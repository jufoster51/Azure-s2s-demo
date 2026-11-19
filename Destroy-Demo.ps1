[CmdletBinding()]
param(
    [switch]$ConfirmDestroy
)

$ErrorActionPreference = 'Stop'

if (-not $ConfirmDestroy) {
    throw 'Re-run with -ConfirmDestroy to delete the demo resources and local state.'
}

$subscriptionId = az account show --query id --output tsv
if ($LASTEXITCODE -ne 0) {
    throw 'Azure subscription lookup failed.'
}

$sshKeyPath = Join-Path $HOME '.ssh\id_ed25519.pub'
if (-not (Test-Path $sshKeyPath)) {
    throw "SSH public key not found at $sshKeyPath."
}

$env:TF_VAR_subscription_id = $subscriptionId
$env:TF_VAR_admin_ssh_public_key = (Get-Content $sshKeyPath -Raw).Trim()
if (-not $env:TF_VAR_vpn_shared_key) {
    $env:TF_VAR_vpn_shared_key = 'DestroyOnlyPlaceholderValue123456'
}

Push-Location $PSScriptRoot
try {
    terraform destroy -auto-approve
    if ($LASTEXITCODE -ne 0) {
        throw 'Terraform destroy failed. Local state was retained for recovery.'
    }

    Get-ChildItem -LiteralPath $PSScriptRoot -File |
        Where-Object { $_.Name -match '^terraform\.tfstate(\..+)?$|\.tfplan$' } |
        Remove-Item -Force

    Write-Output 'Demo resources destroyed and local state/plan files removed.'
}
finally {
    Pop-Location
    Remove-Item Env:\TF_VAR_subscription_id -ErrorAction SilentlyContinue
    Remove-Item Env:\TF_VAR_admin_ssh_public_key -ErrorAction SilentlyContinue
    Remove-Item Env:\TF_VAR_vpn_shared_key -ErrorAction SilentlyContinue
}
