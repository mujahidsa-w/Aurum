# Copies the multiplayer / mobile layer from this repository into a full
# PUBG-UNREAL checkout (one that has the real Git LFS assets).
#   powershell -ExecutionPolicy Bypass -File Tools\scripts\apply-to-project.ps1 C:\path\to\PUBG-UNREAL
param([Parameter(Mandatory = $true)][string]$Target)
$ErrorActionPreference = "Stop"
$Src = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "PUBG_BP_Project"
$Dst = Join-Path $Target "PUBG_BP_Project"
if (-not (Test-Path (Join-Path $Dst "Content"))) { throw "$Dst\Content not found (wrong path?)" }
$tiny = Get-ChildItem -Recurse -Filter *.uasset (Join-Path $Dst "Content\Blueprints") | Where-Object { $_.Length -lt 1024 } | Select-Object -First 1
if ($tiny) { Write-Warning "Content contains Git LFS pointer files, not real assets. Run 'git lfs pull' in the target repository first." }
$Backup = Join-Path $Target ".pre-multiplayer-backup"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
foreach ($item in @("Config", "PUBG_Blueprint.uproject", "Source")) {
  $p = Join-Path $Dst $item
  if (Test-Path $p) { Copy-Item -Recurse -Force $p $Backup }
}
Copy-Item -Recurse -Force (Join-Path $Src "Source") $Dst
Copy-Item -Recurse -Force (Join-Path $Src "Config\*") (Join-Path $Dst "Config")
Copy-Item -Force (Join-Path $Src "PUBG_Blueprint.uproject") $Dst
Write-Host "Done. Backup of replaced files: $Backup"
Write-Host "Next: right-click PUBG_Blueprint.uproject > Generate Visual Studio project files, then build."
