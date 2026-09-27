#Requires -Version 5.1
param(
    [string]$OutDir = '',
    [string]$ZipName = 'NodeThermalFriction.zip'
)

$ErrorActionPreference = 'Stop'
$ModRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function New-ZipFromStage {
    param([string]$StageDir, [string]$DestZip)
    # BeamNG zipFS requires forward-slash entry names. .NET CreateFromDirectory on
    # Windows writes backslashes, which mounts the zip but hides ui/lua/scripts.
    $py = @'
import sys, zipfile
from pathlib import Path
stage = Path(sys.argv[1])
dest = Path(sys.argv[2])
if dest.exists():
    dest.unlink()
with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    dirs = set()
    files = []
    for p in stage.rglob("*"):
        rel = p.relative_to(stage).as_posix()
        if p.is_dir():
            dirs.add(rel.rstrip("/") + "/")
            parts = rel.split("/")
            for i in range(1, len(parts)):
                dirs.add("/".join(parts[:i]) + "/")
        else:
            files.append(p)
            parts = rel.split("/")
            for i in range(1, len(parts)):
                dirs.add("/".join(parts[:i]) + "/")
    for d in sorted(dirs):
        zf.writestr(zipfile.ZipInfo(d), b"")
    for p in files:
        arc = p.relative_to(stage).as_posix()
        zf.write(p, arcname=arc)
print(dest)
'@
    $tmpPy = Join-Path $env:TEMP ('ntf-zip-' + [guid]::NewGuid().ToString('N') + '.py')
    Set-Content -Path $tmpPy -Value $py -Encoding UTF8
    try {
        python $tmpPy $StageDir $DestZip
        if ($LASTEXITCODE -ne 0) { throw "Python zip failed ($LASTEXITCODE)" }
    } finally {
        Remove-Item -Force $tmpPy -ErrorAction SilentlyContinue
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($DestZip)
    try {
        $roots = $zip.Entries | ForEach-Object {
            ($_.FullName -replace '\\', '/').Split('/')[0]
        } | Select-Object -Unique | Sort-Object
        Write-Host ("Wrote $DestZip")
        Write-Host ("Zip root entries: " + ($roots -join ', '))
    } finally {
        $zip.Dispose()
    }
}

if ($ZipName -notmatch '\.zip$') { $ZipName = "$ZipName.zip" }
$zipPath = Join-Path $OutDir $ZipName

$stage = Join-Path $env:TEMP ("ntf-pack-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
    # Core only. Never include vehicles/ in the main zip: BeamNG sets mountPoint=vehicles/
    # for vehicle-classified zips, which hides ui/lua/scripts (Apps vanish).
    foreach ($d in @('lua', 'ui', 'scripts')) {
        $src = Join-Path $ModRoot $d
        if (-not (Test-Path $src)) { throw "Missing required folder: $src" }
        Copy-Item -Recurse -Force $src (Join-Path $stage $d)
    }

    foreach ($f in @('license', 'CREDITS.md', 'NOTICE', 'README.md', 'LISTING.md', 'COMPAT_TIRES.md')) {
        $src = Join-Path $ModRoot $f
        if (Test-Path $src) { Copy-Item -Force $src (Join-Path $stage $f) }
    }

    $mi = Join-Path $ModRoot 'mod_info'
    if (Test-Path $mi) {
        Copy-Item -Recurse -Force $mi (Join-Path $stage 'mod_info')
        # Core identity only. Companion tires live in Node-Thermal-Friction-Tires.
        $compatMi = Join-Path $stage 'mod_info\TWTRS_COMPAT'
        if (Test-Path $compatMi) { Remove-Item -Recurse -Force $compatMi }
        Get-ChildItem (Join-Path $stage 'mod_info') -Recurse -Filter 'icon-redux-reference.jpg' -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    $pitwall = Join-Path $stage 'ui\modules\apps\tireWearThermalsHeavy'
    if (Test-Path $pitwall) {
        Remove-Item -Recurse -Force $pitwall
        Write-Host 'Excluded tireWearThermalsHeavy (dev Pitwall) from public package'
    }

    foreach ($driverApp in @(
        'ui\modules\apps\tireWearThermalsDriver',
        'ui\modules\apps\tyreWearThermalsDriver'
    )) {
        $driverPath = Join-Path $stage $driverApp
        if (Test-Path $driverPath) {
            Remove-Item -Recurse -Force $driverPath
            Write-Host "Excluded $driverApp (Driver UI removed) from public package"
        }
    }

    $lap = Join-Path $stage 'lua\ge\extensions\tireWestCoastLapTest.lua'
    if (Test-Path $lap) {
        Remove-Item -Force $lap
        Write-Host 'Excluded tireWestCoastLapTest.lua from package'
    }

    foreach ($probe in @(
        'lua\vehicle\extensions\tireWearThermalsNodeProbe.lua',
        'lua\vehicle\extensions\tireWearThermalsNodeProbeState.lua',
        'lua\vehicle\controller\tireWearThermalsNodeProbe.lua'
    )) {
        $probePath = Join-Path $stage $probe
        if (Test-Path $probePath) {
            Remove-Item -Force $probePath
            Write-Host "Excluded $probe from package"
        }
    }

    New-ZipFromStage -StageDir $stage -DestZip $zipPath
    Write-Host 'NOTE: this packer is core-only (no vehicles/). Companion tires: Node-Thermal-Friction-Tires'
    Write-Host 'NOTE: zip entries use forward slashes (required by BeamNG zipFS).'
}
finally {
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
}
