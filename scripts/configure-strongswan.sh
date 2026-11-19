#!/usr/bin/env bash
set -euo pipefail

: "${AZURE_GATEWAY_IP:?AZURE_GATEWAY_IP is required}"
: "${CUSTOMER_GATEWAY_IP:?CUSTOMER_GATEWAY_IP is required}"
: "${VPN_PSK_B64:?VPN_PSK_B64 is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends strongswan iproute2 iptables

VPN_PSK="$(printf '%s' "$VPN_PSK_B64" | base64 -d)"
ESCAPED_PSK="${VPN_PSK//\\/\\\\}"
ESCAPED_PSK="${ESCAPED_PSK//\"/\\\"}"
unset VPN_PSK VPN_PSK_B64

cat >/etc/sysctl.d/99-s2s-vpn.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF
sysctl --system

cat >/etc/ipsec.conf <<EOF
config setup
  uniqueids=no

conn azure-s2s
  type=tunnel
  keyexchange=ikev2
  authby=psk
  left=%defaultroute
  leftid=${CUSTOMER_GATEWAY_IP}
  leftsubnet=10.10.1.0/24
  right=${AZURE_GATEWAY_IP}
  rightid=${AZURE_GATEWAY_IP}
  rightsubnet=10.20.1.0/24
  ike=aes256-sha256-modp2048!
  esp=aes256-sha256-modp2048!
  ikelifetime=28800s
  lifetime=3600s
  rekeymargin=3m
  keyingtries=%forever
  dpddelay=30s
  dpdtimeout=45s
  dpdaction=restart
  fragmentation=yes
  forceencaps=yes
  auto=start
EOF

printf '%s %s : PSK "%s"\n' "$CUSTOMER_GATEWAY_IP" "$AZURE_GATEWAY_IP" "$ESCAPED_PSK" >/etc/ipsec.secrets
chmod 600 /etc/ipsec.secrets
unset ESCAPED_PSK

cat >/usr/local/sbin/configure-s2s-firewall.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

iptables -C FORWARD -s 10.10.1.0/24 -d 10.20.1.0/24 -j ACCEPT 2>/dev/null ||
  iptables -I FORWARD 1 -s 10.10.1.0/24 -d 10.20.1.0/24 -j ACCEPT
iptables -C FORWARD -s 10.20.1.0/24 -d 10.10.1.0/24 -j ACCEPT 2>/dev/null ||
  iptables -I FORWARD 1 -s 10.20.1.0/24 -d 10.10.1.0/24 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.10.1.0/24 -d 10.20.1.0/24 -j ACCEPT 2>/dev/null ||
  iptables -t nat -I POSTROUTING 1 -s 10.10.1.0/24 -d 10.20.1.0/24 -j ACCEPT
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1350 2>/dev/null ||
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1350
EOF
chmod 700 /usr/local/sbin/configure-s2s-firewall.sh

cat >/etc/systemd/system/s2s-firewall.service <<'EOF'
[Unit]
Description=Apply S2S VPN forwarding rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/configure-s2s-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now s2s-firewall.service
systemctl enable strongswan-starter.service
systemctl restart strongswan-starter.service

for _ in $(seq 1 12); do
  if systemctl is-active --quiet strongswan-starter.service && ipsec statusall; then
    exit 0
  fi
  sleep 5
done

systemctl status strongswan-starter.service --no-pager -l || true
journalctl -u strongswan-starter.service -n 100 --no-pager || true
exit 1
