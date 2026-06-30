param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem",
    [string]$ReleaseUrl = "https://github.com/praydog/REFramework-nightly/releases/download/nightly-01391-a0e9010fb0449dc9d824b5978ee759eeaf50f7c6/REFramework.zip"
)

$ErrorActionPreference = "Stop"

$game = Resolve-Path $GameDir
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $game "_re9mp_backup_$stamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

foreach ($name in @("dinput8.dll", "reframework_revision.txt", "ref_ui.ini")) {
    $path = Join-Path $game $name
    if (Test-Path $path) {
        Copy-Item -LiteralPath $path -Destination $backupDir -Force
    }
}

$existingReframework = Join-Path $game "reframework"
if (Test-Path $existingReframework) {
    Copy-Item -LiteralPath $existingReframework -Destination (Join-Path $backupDir "reframework") -Recurse -Force
}

$zip = Join-Path $env:TEMP "REFramework-nightly-01391.zip"
$extract = Join-Path $env:TEMP "REFramework-nightly-01391"
Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri $ReleaseUrl -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

Copy-Item -LiteralPath (Join-Path $extract "dinput8.dll") -Destination (Join-Path $game "dinput8.dll") -Force
if (Test-Path (Join-Path $extract "reframework_revision.txt")) {
    Copy-Item -LiteralPath (Join-Path $extract "reframework_revision.txt") -Destination (Join-Path $game "reframework_revision.txt") -Force
}
if (Test-Path (Join-Path $extract "reframework")) {
    Copy-Item -LiteralPath (Join-Path $extract "reframework\*") -Destination (Join-Path $game "reframework") -Recurse -Force
}

Write-Host "Backed up existing REFramework files to $backupDir"
Write-Host "Updated REFramework from $ReleaseUrl"
