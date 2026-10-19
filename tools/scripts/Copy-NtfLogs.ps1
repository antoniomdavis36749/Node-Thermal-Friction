# Copy logger CSVs to D:\ntf-logs so the live folder can stay the file BeamNG is writing.
# Dated copies keep each review set. The live file is left in place.
$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
$destRoot = 'D:\ntf-logs'
if (-not (Test-Path 'D:\')) { throw 'Drive D: is not available.' }
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd'
$dest = Join-Path $destRoot $stamp
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Get-ChildItem $src -File -Filter '*.csv' | ForEach-Object {
    $target = Join-Path $dest $_.Name
    if ((Test-Path $target) -and ((Get-Item $target).Length -eq $_.Length)) { return }
    Copy-Item -Force $_.FullName $target
    Write-Host ("copied " + $_.Name)
}
Write-Host $dest
$reader = Join-Path $PSScriptRoot 'Read-NtfRun.py'
if (Get-Command python -ErrorAction SilentlyContinue) {
    python $reader split
}
