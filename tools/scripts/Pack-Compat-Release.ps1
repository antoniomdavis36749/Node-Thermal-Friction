#Requires -Version 5.1
# Pack Compat Tires zip from an unpacked (or git) tires root. Core Pack-Release stays vehicles-free.
param(
    [string]$TiresRoot = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Node-Thermal-Friction-Tires-dev',
    [string]$OutDir = '',
    [string]$ZipName = 'NodeThermalFriction_CompatTires.zip'
)

$ErrorActionPreference = 'Stop'
$CoreRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path $TiresRoot)) { throw "TiresRoot not found: $TiresRoot" }
$vehicles = Join-Path $TiresRoot 'vehicles'
if (-not (Test-Path $vehicles)) { throw "Missing vehicles/ under $TiresRoot" }

function New-ZipFromStage {
    param([string]$StageDir, [string]$DestZip)
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
    $tmpPy = Join-Path $env:TEMP ('ntf-compat-zip-' + [guid]::NewGuid().ToString('N') + '.py')
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
        if ($roots -notcontains 'vehicles') { throw 'Compat zip missing vehicles/ root' }
        if ($roots -contains 'ui' -or $roots -contains 'lua') {
            throw 'Compat zip must not contain ui/ or lua/ (those belong in core)'
        }
    } finally {
        $zip.Dispose()
    }
}

if ($ZipName -notmatch '\.zip$') { $ZipName = "$ZipName.zip" }
$zipPath = Join-Path $OutDir $ZipName
$stage = Join-Path $env:TEMP ("ntf-compat-pack-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
    Copy-Item -Recurse -Force $vehicles (Join-Path $stage 'vehicles')

    $miSrc = Join-Path $TiresRoot 'mod_info'
    if (Test-Path $miSrc) {
        Copy-Item -Recurse -Force $miSrc (Join-Path $stage 'mod_info')
    }

    foreach ($f in @('README.md', 'INVENTORY.md', 'LISTING.md', 'license', 'CREDITS.md', 'NOTICE', 'COMPAT_TIRES.md')) {
        $src = Join-Path $TiresRoot $f
        if (-not (Test-Path $src) -and $f -eq 'COMPAT_TIRES.md') {
            $src = Join-Path $CoreRoot 'COMPAT_TIRES.md'
        }
        if (Test-Path $src) { Copy-Item -Force $src (Join-Path $stage $f) }
    }

    New-ZipFromStage -StageDir $stage -DestZip $zipPath
    Write-Host 'NOTE: Compat pack is vehicles-only. Core Pack-Release.ps1 stays separate.'
}
finally {
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
}
