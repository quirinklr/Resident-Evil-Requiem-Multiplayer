param(
    [int]$Port = 27777
)

$ErrorActionPreference = "Stop"

$ruleName = "RE9MP UDP $Port"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Firewall rule already exists: $ruleName"
    return
}

New-NetFirewallRule `
    -DisplayName $ruleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol UDP `
    -LocalPort $Port `
    -Profile Any `
    -ErrorAction Stop | Out-Null

Write-Host "Created inbound UDP firewall rule: $ruleName"
