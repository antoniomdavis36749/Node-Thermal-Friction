#Requires -Version 5.1
<#
.SYNOPSIS
  Toggle clean-zip smoke: use packed zip only (park unpacked outside mods/).

.EXAMPLE
  Close BeamNG first.
  .\Toggle-CleanZipSmoke.ps1 -Enable
  .\Toggle-CleanZipSmoke.ps1 -Restore
#>
param(
    [switch]$Enable,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$mods = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods'
$unpacked = Join-Path $mods 'unpacked\Node-Thermal-Friction-dev'
$park = 'C:\Users\anton\AppData\Local\Temp\Node-Thermal-Friction-dev.__smoke_off'
$zipName = 'NodeThermalFriction.zip'
$zipDst = Join-Path $mods $zipName

if (Get-Process -Name 'BeamNG.drive*' -ErrorAction SilentlyContinue) {
    throw 'Close BeamNG.drive completely before toggling.'
}

function Get-PackZip {
    $candidates = @(
        (Join-Path $unpacked "tools\output\$zipName"),
        (Join-Path $park "tools\output\$zipName"),
        (Join-Path 'C:\Users\anton\AppData\Local\Temp\ntf-clone-smoke\tools\output' $zipName)
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

if ($Enable) {
    $src = Get-PackZip
    if (-not $src) { throw 'Missing packed zip. Run Pack-Release.ps1 first.' }
    Copy-Item -Force $src $zipDst

    if (Test-Path $unpacked) {
        if (Test-Path $park) { Remove-Item -Recurse -Force $park }
        Move-Item -Path $unpacked -Destination $park
    }

    # BeamNG recursively mounts zips under unpacked/ — never leave a release zip there.
    $nested = Join-Path $park "tools\output\$zipName"
    if (Test-Path $nested) {
        Remove-Item -Force $nested
        Write-Host "Removed nested tools/output zip (prevents double-mount)."
    }

    Write-Host 'Clean zip smoke ENABLED.'
    Write-Host "  zip: $zipDst"
    Write-Host "  unpacked parked at: $park"
    Write-Host 'Restart BeamNG → Repository/Mods: ensure NodeThermalFriction is ON.'
    Write-Host 'Apps menu → add Tire Wear Thermals Node-Thermal Friction (Pitwall/Classic/Crew). Apps do not auto-open.'
}
elseif ($Restore) {
    if (Test-Path $park) {
        if (Test-Path $unpacked) { throw "Cannot restore: $unpacked already exists" }
        # Restore pack zip into tools/output if missing
        $outDir = Join-Path $park 'tools\output'
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        if ((Test-Path $zipDst) -and -not (Test-Path (Join-Path $outDir $zipName))) {
            Copy-Item -Force $zipDst (Join-Path $outDir $zipName)
        }
        Move-Item -Path $park -Destination $unpacked
    }
    if (Test-Path $zipDst) { Remove-Item -Force $zipDst }
    Write-Host 'Restored unpacked Node-Thermal Friction; removed smoke zip from mods/.'
}
else {
    Write-Host 'Use -Enable or -Restore'
}
