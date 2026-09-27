# Player-car wear persistence through the real thermal module.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$py = Join-Path $env:TEMP "ntf-lua-venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }
& $py (Join-Path $PSScriptRoot "Test-CareerWear.py")
exit $LASTEXITCODE
