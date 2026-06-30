param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem",
    [string]$BuildDir = "$PSScriptRoot\..\build"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$game = Resolve-Path $GameDir
$pluginSrc = Join-Path $BuildDir "bin\Release\re9mp.dll"
if (-not (Test-Path $pluginSrc)) {
    $pluginSrc = Join-Path $BuildDir "bin\re9mp.dll"
}
if (-not (Test-Path $pluginSrc)) {
    throw "Built plugin not found. Run cmake --build first."
}

$pluginsDir = Join-Path $game "reframework\plugins"
$autorunDir = Join-Path $game "reframework\autorun"
$dataDir = Join-Path $game "reframework\data\re9mp"
New-Item -ItemType Directory -Force -Path $pluginsDir, $autorunDir, $dataDir | Out-Null

Copy-Item -LiteralPath $pluginSrc -Destination (Join-Path $pluginsDir "re9mp.dll") -Force
Copy-Item -LiteralPath (Join-Path $root "reframework\autorun\re9mp.lua") -Destination (Join-Path $autorunDir "re9mp.lua") -Force

Write-Host "Deployed re9mp.dll and re9mp.lua to $game"
