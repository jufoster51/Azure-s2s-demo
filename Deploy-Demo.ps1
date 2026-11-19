[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

function Assert-NativeSuccess {
    param([string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed."
    }
}

$subscriptionId = az account show --query id --output tsv
Assert-NativeSuccess 'Azure subscription lookup'

$sshKeyPath = Join-Path $HOME '.ssh\id_ed25519.pub'
if (-not (Test-Path $sshKeyPath)) {
    throw "SSH public key not found at $sshKeyPath."
}

$env:TF_VAR_subscription_id = $subscriptionId
$env:TF_VAR_admin_ssh_public_key = (Get-Content $sshKeyPath -Raw).Trim()

if (-not $env:TF_VAR_vpn_shared_key) {
    throw 'Set TF_VAR_vpn_shared_key in this PowerShell session. See README.md for a secure generation example.'
}

Push-Location $PSScriptRoot
try {
    terraform init
    Assert-NativeSuccess 'Terraform initialization'

    terraform fmt -check
    Assert-NativeSuccess 'Terraform formatting check'

    terraform validate
    Assert-NativeSuccess 'Terraform validation'

    terraform plan -out=s2s-demo.tfplan
    Assert-NativeSuccess 'Terraform plan'

    if (-not $Apply) {
        Write-Output 'Plan created. No Azure resources were changed. Re-run with -Apply after reviewing the plan.'
        return
    }

    terraform apply -auto-approve s2s-demo.tfplan
    Assert-NativeSuccess 'Terraform apply'
}
finally {
    Pop-Location
    Remove-Item Env:\TF_VAR_subscription_id -ErrorAction SilentlyContinue
    Remove-Item Env:\TF_VAR_admin_ssh_public_key -ErrorAction SilentlyContinue
}
