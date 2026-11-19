output "resource_group_name" {
  description = "Demo resource group."
  value       = azurerm_resource_group.demo.name
}

output "azure_gateway_public_ip" {
  description = "Azure VPN Gateway public peer IP."
  value       = data.azurerm_public_ip.gateway.ip_address
}

output "customer_gateway_public_ip" {
  description = "Simulated customer VPN public peer IP."
  value       = azurerm_public_ip.customer_vpn.ip_address
}

output "connection_name" {
  description = "Azure VPN connection resource name."
  value       = azurerm_virtual_network_gateway_connection.this.name
}

output "customer_test_vm_name" {
  description = "Customer-side private test VM."
  value       = azurerm_linux_virtual_machine.customer_test.name
}

output "azure_test_vm_name" {
  description = "Azure-side private test VM."
  value       = azurerm_linux_virtual_machine.azure_test.name
}
