[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-s2s-ftd-customer-demo',
    [string]$Prefix = 's2sftdcust'
)

$ErrorActionPreference = 'Stop'

$connectionName = "conn-$Prefix-azure-to-customer"
$swanVmName = "vm-$Prefix-swan"
$customerVmName = "vm-$Prefix-customer-test"
$azureVmName = "vm-$Prefix-azure-test"

az network vpn-connection show `
    --resource-group $ResourceGroup `
    --name $connectionName `
    --query '{status:connectionStatus,ingressBytes:ingressBytesTransferred,egressBytes:egressBytesTransferred}' `
    --output table
if ($LASTEXITCODE -ne 0) {
    throw 'VPN connection status check failed.'
}

az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $swanVmName `
    --command-id RunShellScript `
    --scripts 'sudo ipsec statusall' `
    --query 'value[0].message' `
    --output tsv
if ($LASTEXITCODE -ne 0) {
    throw 'StrongSwan status check failed.'
}

az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $customerVmName `
    --command-id RunShellScript `
    --scripts 'ping -c 4 -W 2 10.20.1.10' `
    --query 'value[0].message' `
    --output tsv
if ($LASTEXITCODE -ne 0) {
    throw 'Customer-to-Azure connectivity test failed.'
}

az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $azureVmName `
    --command-id RunShellScript `
    --scripts 'ping -c 4 -W 2 10.10.1.10' `
    --query 'value[0].message' `
    --output tsv
if ($LASTEXITCODE -ne 0) {
    throw 'Azure-to-customer connectivity test failed.'
}
