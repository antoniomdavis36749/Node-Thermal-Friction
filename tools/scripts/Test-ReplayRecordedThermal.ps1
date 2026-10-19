# Run the real thermal module outside BeamNG on the recorded slip-ratio log.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$venv = Join-Path $env:TEMP "ntf-lua-venv"
$py = Join-Path $venv "Scripts\python.exe"
if (-not ((Test-Path $py) -and (Test-Path (Join-Path $venv "pyvenv.cfg")))) { $py = "python" }
& $py (Join-Path $PSScriptRoot "Replay-RecordedThermal.py")
exit $LASTEXITCODE
