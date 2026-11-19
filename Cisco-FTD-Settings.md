# Cisco FTD Configuration Worksheet

Use this worksheet to translate the demo into an FMC/FTD site-to-site VPN configuration. Cisco screen names vary by FTD/FMC version, but the values and dependencies remain the same.

## Peer and protected networks

| Setting | Customer / Cisco FTD | Azure |
|---|---|---|
| VPN peer public IP | Demo output `customerGatewayPublicIp` | Demo output `azureGatewayPublicIp` |
| Protected network | `10.10.1.0/24` | `10.20.1.0/24` |
| Inside next hop | FTD/StrongSwan trust IP `10.10.1.4` | Azure VPN Gateway system route |
| Authentication | Customer-generated pre-shared key | Same customer-generated pre-shared key |
| IKE version | IKEv2 | IKEv2 |

## IKE Phase 1

| Parameter | Value |
|---|---|
| Encryption | AES-256 |
| Integrity / PRF | SHA-256 |
| Diffie-Hellman group | Group 14 / MODP 2048 |
| Authentication | Pre-shared key |
| SA lifetime | 28,800 seconds |

Azure fixes the IKE Main Mode lifetime at 28,800 seconds. The FTD proposal must include the same encryption, integrity, and DH combination.

## IPsec Phase 2

| Parameter | Value |
|---|---|
| ESP encryption | AES-256 |
| ESP integrity | SHA-256 |
| Perfect Forward Secrecy | Group 14 / MODP 2048 |
| SA lifetime | 3,600 seconds |
| SA data size | 102,400,000 KB |
| Dead Peer Detection | 45-second timeout |

## Traffic selectors

Configure the crypto domain in both directions:

```text
10.10.1.0/24 <-> 10.20.1.0/24
```

The Azure connection enables policy-based traffic selectors even though the Azure gateway itself is route-based. This supports a common FTD protected-network/crypto-domain design.

## Customer-side build sequence

1. Create network objects for `10.10.1.0/24` and `10.20.1.0/24`.
2. Create an IKEv2 policy with AES-256, SHA-256, and DH14.
3. Create an IPsec proposal with AES-256 and SHA-256.
4. Enable PFS group 14 and set the IPsec lifetime to 3,600 seconds.
5. Create the S2S topology using the Azure gateway public IP as the remote peer.
6. Use the same PSK supplied through `TF_VAR_vpn_shared_key` for the Azure deployment.
7. Define the protected networks as `10.10.1.0/24` and `10.20.1.0/24`.
8. Add a route for `10.20.1.0/24` toward the FTD VPN path or VTI, depending on the selected FTD topology.
9. Add identity NAT exemption for traffic between the two protected networks.
10. Permit the desired application traffic in the FTD access-control policy.
11. Allow outbound UDP 500 and UDP 4500 to the Azure gateway public IP.

## Azure object mapping

| Azure object | What it represents to the customer |
|---|---|
| Virtual Network Gateway | Azure VPN peer |
| Gateway public IP | Remote peer address configured on FTD |
| Local Network Gateway | Azure's model of the customer peer and customer prefixes |
| Connection | PSK, IKE/IPsec policy, DPD, and traffic-selector behavior |
| GatewaySubnet | Dedicated Azure-managed gateway placement subnet |
| Azure VNet address space | Remote protected networks advertised to the customer |

## Troubleshooting map

| Symptom | First checks |
|---|---|
| No IKE SA | Peer public IPs, UDP 500/4500, PSK, IKEv2, AES/SHA/DH proposal |
| IKE up, no IPsec SA | Protected-network selectors, ESP proposal, PFS group, Phase 2 lifetime |
| Tunnel up, no traffic | Customer route, Azure Local Network Gateway prefix, NAT exemption, FTD access policy, NSGs |
| One-way traffic | Return route, asymmetric NAT, selector direction, host firewall |
| Rekey instability | IKE lifetime, IPsec lifetime, DPD settings, proposal ordering |

## Useful demo commands

Azure connection state:

```powershell
az network vpn-connection show -g rg-s2s-ftd-demo -n conn-s2sftd-azure-to-customer -o table
```

StrongSwan equivalent of FTD tunnel diagnostics:

```powershell
az vm run-command invoke -g rg-s2s-ftd-demo -n vm-s2sftd-swan --command-id RunShellScript --scripts "sudo ipsec statusall" -o json
```

Microsoft references:

- https://learn.microsoft.com/azure/vpn-gateway/ipsec-ike-policy-howto
- https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpn-devices
- https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpn-gateway-settings
