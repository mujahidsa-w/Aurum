# Rebuilds PUBG_BP_Project/Content from the split archive (Windows 10+, built-in tar).
#   powershell -ExecutionPolicy Bypass -File AssetParts\restore.ps1
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot; $Root = Resolve-Path (Join-Path $Here "..")
$Out = Join-Path $Here "Content.tar.gz"
$parts = Get-ChildItem $Here -Filter "Content.tar.gz.part*" | Sort-Object Name
$fs = [IO.File]::Create($Out)
foreach ($p in $parts) { $b = [IO.File]::ReadAllBytes($p.FullName); $fs.Write($b, 0, $b.Length) }
$fs.Close()
$want = (Get-Content (Join-Path $Here "Content.tar.gz.sha256")).Split(" ")[0]
$got = (Get-FileHash $Out -Algorithm SHA256).Hash.ToLower()
if ($got -ne $want) { throw "Checksum mismatch: archive is incomplete or corrupted" }
tar -xzf $Out -C $Root
Remove-Item $Out
Write-Host "Done: PUBG_BP_Project\Content restored and verified."
