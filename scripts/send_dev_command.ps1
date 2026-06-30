param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem",
    [Parameter(Mandatory = $true)]
    [string]$Action,
    [bool]$Value = $true
)

$dataDir = Join-Path $GameDir "reframework\data\re9mp"
if (-not (Test-Path -LiteralPath $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$commandFile = Join-Path $dataDir "dev_command.json"
$id = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$payload = [ordered]@{
    id = $id
    action = $Action
    value = $Value
}

$payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $commandFile -Encoding UTF8
Write-Host "Wrote $commandFile with id $id"
