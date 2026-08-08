# Builds QuickForge.pak at the repo root using LSLib's divine.exe, then
# deploys it to the game's Mods folder (skip with -NoDeploy).
param([string]$DivinePath, [switch]$NoDeploy)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$modFolder = "QuickForge_1993d511-b789-4edc-9e0a-cf15ea5ffd80"
$out = Join-Path $repo "QuickForge.pak"

# Locate divine.exe: -DivinePath, then LSLIB_PATH, then common spots.
$candidates = @()
if ($DivinePath) { $candidates += @($DivinePath, (Join-Path $DivinePath "divine.exe")) }
if ($env:LSLIB_PATH) { $candidates += @($env:LSLIB_PATH, (Join-Path $env:LSLIB_PATH "divine.exe")) }
$candidates += @(
    "$env:LOCALAPPDATA\LSLib\Tools\divine.exe",
    "C:\Tools\LSLib\divine.exe",
    "C:\LSLib\divine.exe"
)
$divine = $candidates | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) } | Select-Object -First 1

if (-not $divine) {
    Write-Host "divine.exe not found."
    Write-Host "Download LSLib (ExportTool) from https://github.com/Norbyte/lslib/releases, then either:"
    Write-Host "  - rerun with:  tools\pack.ps1 -DivinePath <path\to\divine.exe>"
    Write-Host "  - or set LSLIB_PATH to the folder containing divine.exe"
    Write-Host "  - or run it yourself against a folder containing only Mods\$modFolder :"
    Write-Host "      divine.exe -g dos2de -a create-package -c lz4 -s <staging folder> -d `"$out`""
    exit 1
}

# Stage: the pak root must contain Mods\<folder> and nothing else from the repo.
$stage = Join-Path ([IO.Path]::GetTempPath()) "QuickForge-pak"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory (Join-Path $stage "Mods") -Force | Out-Null
Copy-Item (Join-Path $repo "Mods\$modFolder") (Join-Path $stage "Mods\$modFolder") -Recurse

& $divine -g dos2de -a create-package -c lz4 -s $stage -d $out
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Remove-Item $stage -Recurse -Force
Write-Host "Built $out"

$gameMods = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Larian Studios\Divinity Original Sin 2 Definitive Edition\Mods"
if (-not $NoDeploy -and (Test-Path $gameMods)) {
    Copy-Item $out $gameMods -Force
    Write-Host "Deployed to $gameMods"
}
