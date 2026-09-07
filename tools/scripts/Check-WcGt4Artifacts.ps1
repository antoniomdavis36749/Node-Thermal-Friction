$ErrorActionPreference = 'Continue'
$user = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current'
$vs = Join-Path $user 'mods\unpacked\Node-Thermal-Friction-dev\tools'
$modOut = Join-Path $vs 'output'

Write-Host '=== recent logs ==='
Get-ChildItem $user -Filter '*.log' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 8 Name, Length, LastWriteTime |
  Format-Table -AutoSize

$latest = Get-ChildItem $user -Filter 'BeamNG*.log' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) {
  $latest = Get-ChildItem $user -Filter '*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

if ($latest) {
  Write-Host ("=== tail of " + $latest.FullName + " ===")
  Get-Content $latest.FullName -Tail 80
}

$tel = Join-Path $modOut 'wc-gt4-lap-telemetry.csv'
if (Test-Path $tel) {
  $rows = Get-Content $tel
  Write-Host ("telemetryLines=" + $rows.Count)
  $rows | Select-Object -First 2 | ForEach-Object { Write-Host $_ }
  $rows | Select-Object -Last 2 | ForEach-Object { Write-Host $_ }
}
