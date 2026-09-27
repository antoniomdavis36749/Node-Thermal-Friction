# Run the real thermal module outside BeamNG on the recorded slip-ratio log.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$py = Join-Path $env:TEMP "ntf-lua-venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }
& $py (Join-Path $PSScriptRoot "Replay-RecordedThermal.py")
exit $LASTEXITCODE
