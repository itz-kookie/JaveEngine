param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Preset = if ($Configuration -eq 'Release') { 'windows-x64-release' } else { 'windows-x64-debug' }
$BuildPreset = if ($Configuration -eq 'Release') { 'release' } else { 'debug' }

cmake --preset $Preset
cmake --build --preset $BuildPreset

$Runtime = Join-Path $ProjectRoot "build\$($Configuration.ToLower())\$Configuration"
$PackageRoot = Join-Path $ProjectRoot 'dist'
$Zip = Join-Path $PackageRoot "JaveEngine-$Configuration-x64.zip"
New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip }
Compress-Archive -Path (Join-Path $Runtime '*') -DestinationPath $Zip
Write-Host "Created $Zip"

