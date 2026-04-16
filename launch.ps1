# NRR Studio — Vast.ai VM Bootstrap Launcher
# Reads your local .env.studio file and bootstraps a Vast.ai VM via SSH.
#
# Usage:
#   .\launch.ps1 -VmIp 1.2.3.4 -SshPort 12345
#
# The SSH port is the mapped port shown in the Vast.ai console for port 22.

param(
    [Parameter(Mandatory=$true)]
    [string]$VmIp,

    [Parameter(Mandatory=$true)]
    [int]$SshPort
)

# Look for .env.studio in the script directory, then in $HOME\.nrr\
$envFile = Join-Path $PSScriptRoot ".env.studio"
if (-not (Test-Path $envFile)) {
    $envFile = Join-Path $HOME ".nrr\env.studio"
}
if (-not (Test-Path $envFile)) {
    Write-Error "Cannot find .env.studio file. Copy .env.studio.template to .env.studio and fill in your key."
    exit 1
}

# Parse the VPS_SSH_KEY_B64 value from the env file
$key = Get-Content $envFile | Where-Object { $_ -match "^VPS_SSH_KEY_B64=" } | ForEach-Object { $_ -replace "^VPS_SSH_KEY_B64=", "" }
if ([string]::IsNullOrWhiteSpace($key) -or $key -eq "PASTE_YOUR_BASE64_KEY_HERE") {
    Write-Error "VPS_SSH_KEY_B64 is not set in $envFile. Paste your base64-encoded SSH key."
    exit 1
}

$bootstrapUrl = "https://raw.githubusercontent.com/nairoreelproductions-tech/nrr-studio/main/bootstrap.sh"

Write-Host ""
Write-Host "NRR Studio Bootstrap" -ForegroundColor Cyan
Write-Host "  VM:   $VmIp`:$SshPort"
Write-Host "  User: user (default Vast.ai password: password)"
Write-Host ""
Write-Host "Connecting via SSH and running bootstrap..." -ForegroundColor Yellow
Write-Host "(You will be prompted for the VM password — type 'password' and press Enter)" -ForegroundColor Yellow
Write-Host ""

# SSH in, export the key, download and run the bootstrap script
ssh -p $SshPort "user@$VmIp" "export VPS_SSH_KEY_B64='$key' && curl -fsSL $bootstrapUrl | bash"
