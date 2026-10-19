# Compare locked-band outputs of the real thermal module to the golden file.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$venv = Join-Path $env:TEMP "ntf-lua-venv"
$py = Join-Path $venv "Scripts\python.exe"
if (-not ((Test-Path $py) -and (Test-Path (Join-Path $venv "pyvenv.cfg")))) { $py = "python" }
& $py (Join-Path $PSScriptRoot "Test-LockedBandGolden.py")
exit $LASTEXITCODE
