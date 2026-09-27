# Compare locked-band outputs of the real thermal module to the golden file.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$py = Join-Path $env:TEMP "ntf-lua-venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }
& $py (Join-Path $PSScriptRoot "Test-LockedBandGolden.py")
exit $LASTEXITCODE
