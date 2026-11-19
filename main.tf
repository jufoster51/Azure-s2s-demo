locals {
  image = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  configure_strongswan_script = replace(
    file("${path.module}/scripts/configure-strongswan.sh"),
    "\r\n",
    "\n",
  )

  configure_strongswan_command = "echo ${base64encode(local.configure_strongswan_script)} | base64 -d > /tmp/configure-strongswan.sh && chmod 700 /tmp/configure-strongswan.sh && AZURE_GATEWAY_IP=${data.azurerm_public_ip.gateway.ip_address} CUSTOMER_GATEWAY_IP=${azurerm_public_ip.customer_vpn.ip_address} VPN_PSK_B64=${base64encode(var.vpn_shared_key)} /tmp/configure-strongswan.sh"
}

resource "azurerm_resource_group" "demo" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_network_security_group" "customer_untrust" {
  name                = "nsg-${var.prefix}-customer-untrust"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "customer_trust" {
  name                = "nsg-${var.prefix}-customer-trust"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-Icmp-From-Azure"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.20.1.0/24"
    destination_address_prefix = "10.10.1.0/24"
  }
}

resource "azurerm_network_security_group" "azure_workload" {
  name                = "nsg-${var.prefix}-azure-workload"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-Icmp-From-Customer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.10.1.0/24"
    destination_address_prefix = "10.20.1.0/24"
  }
}

resource "azurerm_route_table" "customer" {
  name                          = "rt-${var.prefix}-customer"
  location                      = azurerm_resource_group.demo.location
  resource_group_name           = azurerm_resource_group.demo.name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

resource "azurerm_route" "to_azure" {
  name                   = "To-Azure-Via-StrongSwan"
  resource_group_name    = azurerm_resource_group.demo.name
  route_table_name       = azurerm_route_table.customer.name
  address_prefix         = "10.20.0.0/16"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "10.10.1.4"
}

resource "azurerm_public_ip" "customer_vpn" {
  name                    = "pip-${var.prefix}-customer-vpn"
  location                = azurerm_resource_group.demo.location
  resource_group_name     = azurerm_resource_group.demo.name
  allocation_method       = "Static"
  sku                     = "Standard"
  ip_version              = "IPv4"
  idle_timeout_in_minutes = 30
  tags                    = var.tags

  lifecycle {
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

resource "azurerm_public_ip" "azure_vpn_gateway" {
  name                    = "pip-${var.prefix}-azure-vpng"
  location                = azurerm_resource_group.demo.location
  resource_group_name     = azurerm_resource_group.demo.name
  allocation_method       = "Static"
  sku                     = "Standard"
  ip_version              = "IPv4"
  idle_timeout_in_minutes = 30
  tags                    = var.tags

  lifecycle {
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

resource "azurerm_virtual_network" "customer" {
  name                = "vnet-${var.prefix}-customer"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  address_space       = ["10.10.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "customer_untrust" {
  name                 = "snet-customer-untrust"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.customer.name
  address_prefixes     = ["10.10.0.0/24"]
}

resource "azurerm_subnet" "customer_trust" {
  name                 = "snet-customer-trust"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.customer.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "customer_untrust" {
  subnet_id                 = azurerm_subnet.customer_untrust.id
  network_security_group_id = azurerm_network_security_group.customer_untrust.id
}

resource "azurerm_subnet_network_security_group_association" "customer_trust" {
  subnet_id                 = azurerm_subnet.customer_trust.id
  network_security_group_id = azurerm_network_security_group.customer_trust.id
}

resource "azurerm_subnet_route_table_association" "customer_trust" {
  subnet_id      = azurerm_subnet.customer_trust.id
  route_table_id = azurerm_route_table.customer.id
}

resource "azurerm_virtual_network" "azure" {
  name                = "vnet-${var.prefix}-azure"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "azure_workload" {
  name                 = "snet-azure-workload"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.azure.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.azure.name
  address_prefixes     = ["10.20.255.0/27"]
}

resource "azurerm_subnet_network_security_group_association" "azure_workload" {
  subnet_id                 = azurerm_subnet.azure_workload.id
  network_security_group_id = azurerm_network_security_group.azure_workload.id
}

resource "azurerm_network_interface" "swan_untrust" {
  #checkov:skip=CKV_AZURE_119:A public IP is required for the simulated customer VPN peer; inbound access is restricted to IKE/NAT-T from the Azure gateway IP.
  name                  = "nic-${var.prefix}-swan-untrust"
  location              = azurerm_resource_group.demo.location
  resource_group_name   = azurerm_resource_group.demo.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "ipconfig-untrust"
    subnet_id                     = azurerm_subnet.customer_untrust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.0.4"
    public_ip_address_id          = azurerm_public_ip.customer_vpn.id
    primary                       = true
  }
}

resource "azurerm_network_interface" "swan_trust" {
  name                  = "nic-${var.prefix}-swan-trust"
  location              = azurerm_resource_group.demo.location
  resource_group_name   = azurerm_resource_group.demo.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "ipconfig-trust"
    subnet_id                     = azurerm_subnet.customer_trust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.1.4"
    primary                       = true
  }
}

resource "azurerm_network_interface" "customer_test" {
  name                = "nic-${var.prefix}-customer-test"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.customer_trust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.1.10"
    primary                       = true
  }
}

resource "azurerm_network_interface" "azure_test" {
  name                = "nic-${var.prefix}-azure-test"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.azure_workload.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.20.1.10"
    primary                       = true
  }
}

resource "azurerm_linux_virtual_machine" "swan" {
  #checkov:skip=CKV_AZURE_50:Protected VM extension configuration is required; no inbound management ports are exposed.
  #checkov:skip=CKV_AZURE_97:Host encryption requires an unregistered subscription feature; Trusted Launch and platform-managed disk encryption remain enabled.
  name                            = "vm-${var.prefix}-swan"
  resource_group_name             = azurerm_resource_group.demo.name
  location                        = azurerm_resource_group.demo.location
  size                            = "Standard_B1s"
  admin_username                  = var.admin_username
  computer_name                   = "swanftdsim"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.swan_untrust.id, azurerm_network_interface.swan_trust.id]
  patch_assessment_mode           = "AutomaticByPlatform"
  patch_mode                      = "AutomaticByPlatform"
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  boot_diagnostics {}
}

resource "azurerm_linux_virtual_machine" "customer_test" {
  #checkov:skip=CKV_AZURE_50:Azure Run Command is the private management path; the VM has no public IP or inbound management rule.
  #checkov:skip=CKV_AZURE_97:Host encryption requires an unregistered subscription feature; Trusted Launch and platform-managed disk encryption remain enabled.
  name                            = "vm-${var.prefix}-customer-test"
  resource_group_name             = azurerm_resource_group.demo.name
  location                        = azurerm_resource_group.demo.location
  size                            = "Standard_B1s"
  admin_username                  = var.admin_username
  computer_name                   = "customertest"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.customer_test.id]
  patch_assessment_mode           = "AutomaticByPlatform"
  patch_mode                      = "AutomaticByPlatform"
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  boot_diagnostics {}
}

resource "azurerm_linux_virtual_machine" "azure_test" {
  #checkov:skip=CKV_AZURE_50:Azure Run Command is the private management path; the VM has no public IP or inbound management rule.
  #checkov:skip=CKV_AZURE_97:Host encryption requires an unregistered subscription feature; Trusted Launch and platform-managed disk encryption remain enabled.
  name                            = "vm-${var.prefix}-azure-test"
  resource_group_name             = azurerm_resource_group.demo.name
  location                        = azurerm_resource_group.demo.location
  size                            = "Standard_B1s"
  admin_username                  = var.admin_username
  computer_name                   = "azuretest"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.azure_test.id]
  patch_assessment_mode           = "AutomaticByPlatform"
  patch_mode                      = "AutomaticByPlatform"
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  boot_diagnostics {}
}

resource "azurerm_virtual_network_gateway" "this" {
  name                = "vpng-${var.prefix}-azure"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  bgp_enabled         = false
  generation          = "Generation1"
  sku                 = "VpnGw1AZ"
  tags                = var.tags

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.azure_vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}

data "azurerm_public_ip" "gateway" {
  name                = azurerm_public_ip.azure_vpn_gateway.name
  resource_group_name = azurerm_resource_group.demo.name

  depends_on = [azurerm_virtual_network_gateway.this]
}

resource "azurerm_local_network_gateway" "customer" {
  name                = "lng-${var.prefix}-customer-ftd"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  gateway_address     = azurerm_public_ip.customer_vpn.ip_address
  address_space       = ["10.10.1.0/24"]
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "this" {
  name                               = "conn-${var.prefix}-azure-to-customer"
  location                           = azurerm_resource_group.demo.location
  resource_group_name                = azurerm_resource_group.demo.name
  type                               = "IPsec"
  virtual_network_gateway_id         = azurerm_virtual_network_gateway.this.id
  local_network_gateway_id           = azurerm_local_network_gateway.customer.id
  shared_key                         = var.vpn_shared_key
  connection_protocol                = "IKEv2"
  dpd_timeout_seconds                = 45
  bgp_enabled                        = false
  routing_weight                     = 10
  use_policy_based_traffic_selectors = true
  tags                               = var.tags

  ipsec_policy {
    dh_group         = "DHGroup14"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"
    sa_datasize      = 102400000
    sa_lifetime      = 3600
  }
}

resource "azurerm_network_security_rule" "allow_ike" {
  name                        = "Allow-IKE-From-Azure-Gateway"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "500"
  source_address_prefix       = data.azurerm_public_ip.gateway.ip_address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.demo.name
  network_security_group_name = azurerm_network_security_group.customer_untrust.name
}

resource "azurerm_network_security_rule" "allow_nat_traversal" {
  name                        = "Allow-NAT-T-From-Azure-Gateway"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "4500"
  source_address_prefix       = data.azurerm_public_ip.gateway.ip_address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.demo.name
  network_security_group_name = azurerm_network_security_group.customer_untrust.name
}

resource "azurerm_virtual_machine_extension" "configure_strongswan" {
  #checkov:skip=CKV_AZURE_50:Protected Custom Script configuration is required for the VPN appliance.
  name                       = "configure-strongswan"
  virtual_machine_id         = azurerm_linux_virtual_machine.swan.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = local.configure_strongswan_command
  })

  depends_on = [
    azurerm_network_security_rule.allow_ike,
    azurerm_network_security_rule.allow_nat_traversal,
    azurerm_virtual_network_gateway_connection.this,
  ]
}
