param(
    [switch]$OpenLogin,
    [string]$AuthKey = ""
)

$ErrorActionPreference = "Stop"

$tailscale = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $tailscale)) {
    winget install --id Tailscale.Tailscale --exact --silent --accept-package-agreements --accept-source-agreements
}

if (-not (Test-Path $tailscale)) {
    throw "Tailscale install finished but tailscale.exe was not found at $tailscale"
}

$service = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne "Running") {
    Start-Service -Name Tailscale
}

& $tailscale version

if ($AuthKey -ne "") {
    & $tailscale logout 2>$null
    & $tailscale up --auth-key $AuthKey --reset
} elseif ($OpenLogin) {
    & $tailscale up
} else {
    & $tailscale status --json
    Write-Host ""
    Write-Host "If BackendState is NeedsLogin, run:"
    Write-Host "  & `"$tailscale`" up"
}
