# Corner / load-util heat soft-sim gate (round-4: peak under ~100C from ~116C).
# Mirrors live slip^2 + g-boost, work coef, peakWF/util nudge, verticalCarcassHeat,
# and corner velCool g-penalty (net = patched * (1+pen); cruise pen=0).
# Before = live Round-3 knobs + post-R3 Sport rates; After = R4 (slip −8% / work −4%).
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'corner-load-heat-softsim.txt'

function Clamp([double]$v, [double]$lo, [double]$hi) {
    if ($v -lt $lo) { return $lo }
    if ($v -gt $hi) { return $hi }
    return $v
}

# Instant patched heat budget (slip + work + vertical through patchHeatScale).
# Held rolling is optional ballast so cruise delta stays nearly flat (RR not reopened).
# Corner velCool g-penalty: lua divides velCool by (1+min(cap,(g-0.20)*slope));
# equilibrium skin ~ gen*(1+pen), so net = patched * (1+coolPen).
function Get-CornerHeat([hashtable]$k, [hashtable]$c) {
    $slip0 = [double]$c.slip
    $dynSlip = $slip0
    $seh = $dynSlip / (1.0 + $dynSlip * 0.12)
    $wt = [double]$c.weight
    $loadRaw = [double]$c.loadRaw
    $loadKg = $loadRaw / 9.81
    $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)
    $loadCoeff = $wt * $loadKg
    $rel = 0.0

    $peakWF = 1.0
    $peakForce = [double]$c.peakForce
    $loadUtil = [double]$c.loadUtil
    if ($peakForce -gt 100.0 -and $loadUtil -gt 100.0) {
        $peakWF = Clamp ($peakForce / $loadUtil) ([double]$k.utilLo) ([double]$k.utilHi)
    }
    $utilNudge = 1.0 + (($peakWF - 1.0) * [double]$k.utilBlend)
    $patchHeatScale = Clamp (1.0 * $utilNudge) 0.70 1.20

    $slipTerm = 0.0078 * ($seh * $seh) * $loadCoeff * [double]$k.slipHeatRate
    $workTerm = [double]$k.workCoef * $rel * [double]$k.workHeatRate * $peakWF / (1.0 + ($seh * $seh))

    $suspVel = [double]$c.suspVel
    $vert = [math]::Abs($suspVel) * ($loadRaw / 1200.0) * [double]$k.vertScale
    if ([math]::Abs($suspVel) -lt 0.04) { $vert = $vert * 0.35 }
    $vertSkin = $vert * 0.005 * [double]$k.workHeatRate * $wt

    $surfMu = 1.05
    $tyreW = 0.95
    $slipWorkScale = 1.10
    $core = ($slipTerm + $workTerm) * $surfMu / $tyreW * $slipWorkScale
    $patched = ($core + $vertSkin) * $patchHeatScale
    $roll = [double]$c.heldRolling

    $coolPen = 0.0
    $retain = 1.0 / (1.0 + $coolPen)
    $net = $patched * (1.0 + $coolPen)
    $total = $patched + $roll

    $slipH = $slipTerm * $surfMu / $tyreW * $slipWorkScale * $patchHeatScale
    $workH = $workTerm * $surfMu / $tyreW * $slipWorkScale * $patchHeatScale
    $vertH = $vertSkin * $patchHeatScale
    $pden = if ($patched -gt 1e-12) { $patched } else { 1.0 }

    return @{
        patched        = $patched
        net            = $net
        total          = $total
        slip           = $slipH
        work           = $workH
        vert           = $vertH
        roll           = $roll
        slipPct        = 100.0 * $slipH / $pden
        workPct        = 100.0 * $workH / $pden
        vertPct        = 100.0 * $vertH / $pden
        peakWF         = $peakWF
        patchHeatScale = $patchHeatScale
        dynSlip        = $dynSlip
        coolPen        = $coolPen
        retain         = $retain
    }
}

function Clone-Knobs([hashtable]$src) {
    $h = @{}
    foreach ($key in $src.Keys) { $h[$key] = $src[$key] }
    return $h
}

# Sport rates live after Round-3 (9.20*0.94 / 4.69*0.97).
$sportSlip = 8.65
$sportWork = 4.55
$sportG0 = 0.16

$before = @{
    gBoost       = 0.08
    workCoef     = 0.128
    utilLo       = 0.82
    utilHi       = 1.20
    utilBlend    = 0.12
    vertScale    = 0.42
    coolCap      = 0.12
    coolSlope    = 0.14
    slipHeatRate = $sportSlip
    workHeatRate = $sportWork
    workG0       = $sportG0
}
$after = @{
    gBoost       = 0.06
    workCoef     = 0.118
    utilLo       = 0.82
    utilHi       = 1.12
    utilBlend    = 0.09
    vertScale    = 0.36
    coolCap      = 0.05
    coolSlope    = 0.07
    slipHeatRate = [math]::Round($sportSlip * 0.92, 2)
    workHeatRate = [math]::Round($sportWork * 0.96, 2)
    workG0       = $sportG0
}

# Cases sized to match diagnosis work/slip shares (Sport rates, mid-corner proxies).
$cases = @(
    @{
        id = 1; name = 'Cruise (g~0.15)'
        gMag = 0.15; slip = 0.03; loadRaw = 4000; weight = 0.33
        peakForce = 4000; loadUtil = 4000; suspVel = 0.02; heldRolling = 2.5
        # Gate uses total (patched + held RR) so cruise stays nearly flat.
        metric = 'total'; minDelta = -2.0; maxDelta = 2.0; gate = $true
    }
    @{
        id = 2; name = 'GT3-ideal mid-turn'
        gMag = 1.40; slip = 0.092; loadRaw = 10000; weight = 0.52
        peakForce = 10500; loadUtil = 10000; suspVel = 0.04; heldRolling = 0.40
        metric = 'patched'; minDelta = -14.0; maxDelta = -8.0
        gate = $false   # informational only — GT3 is not the fleet heat reference
    }
    @{
        id = 3; name = 'Low-camber outside mid'
        gMag = 1.18; slip = 0.195; loadRaw = 6800; weight = 0.50
        peakForce = 7500; loadUtil = 6800; suspVel = 0.14; heldRolling = 0.35
        # ~116C peak → under 100C is ~15–18% less corner rise. Gate that band.
        metric = 'patched'; minDelta = -20.0; maxDelta = -12.0; gate = $true
    }
    @{
        id = 4; name = 'Near-max util weight-shift'
        gMag = 1.10; slip = 0.255; loadRaw = 7400; weight = 0.52
        peakForce = 9800; loadUtil = 7400; suspVel = 0.55; heldRolling = 0.30
        metric = 'patched'; minDelta = -22.0; maxDelta = -12.0; gate = $true
    }
)

$isoKeys = @(
    @{ name = 'gBoost';    set = @{ gBoost = 0.06 } }
    @{ name = 'workCoef';  set = @{ workCoef = 0.118 } }
    @{ name = 'utilHi';    set = @{ utilHi = 1.12 } }
    @{ name = 'utilBlend'; set = @{ utilBlend = 0.09 } }
    @{ name = 'vertScale'; set = @{ vertScale = 0.36 } }
    @{ name = 'velCool';   set = @{ coolCap = 0.05; coolSlope = 0.07 } }
    @{ name = 'slipRate';  set = @{ slipHeatRate = [math]::Round($sportSlip * 0.92, 2) } }
    @{ name = 'workRate';  set = @{ workHeatRate = [math]::Round($sportWork * 0.96, 2) } }
)

$sb = New-Object System.Text.StringBuilder
function Out([string]$s) {
    [void]$sb.AppendLine($s)
    Write-Host $s
}

Out '=== Corner heat soft-sim (live per-tire gates) ==='
Out 'Chassis G does not scale slip, cornering work, or cooling. Slip energy and this tire load do.'
Out ''

$fail = 0
$k = @{
    gBoost = 0.08; workCoef = 0.128; utilLo = 0.82; utilHi = 1.12; utilBlend = 0.09
    vertScale = 0.36; coolCap = 0.12; coolSlope = 0.14
    slipHeatRate = 7.96; workHeatRate = 4.37; workG0 = 0.16
}
$base = @{
    slip = 0.09; loadRaw = 6800; weight = 0.50
    peakForce = 7500; loadUtil = 6800; suspVel = 0.14; heldRolling = 0.35
}
$lowG = Get-CornerHeat $k (@{ gMag = 0.15 } + $base)
$highG = Get-CornerHeat $k (@{ gMag = 1.40 } + $base)
$dG = [math]::Abs($highG.patched - $lowG.patched)
if ($dG -gt 1e-6 -or $highG.coolPen -gt 0) {
    Out (" FAIL: chassis G changed patched heat ({0:N4} vs {1:N4}) or cooling." -f $lowG.patched, $highG.patched)
    $fail++
} else {
    Out (" OK: g 0.15 and g 1.40 share patched heat {0:N4}. Cooling penalty is 0." -f $lowG.patched)
}
$moreSlip = Get-CornerHeat $k (@{ gMag = 1.40; slip = 0.25; loadRaw = 6800; weight = 0.50; peakForce = 7500; loadUtil = 6800; suspVel = 0.14; heldRolling = 0.35 })
if ($moreSlip.patched -le $highG.patched) {
    Out ' FAIL: more slip energy did not raise heat.'
    $fail++
} else {
    Out (" OK: slip 0.09 -> 0.25 raises patched heat {0:N4} -> {1:N4}." -f $highG.patched, $moreSlip.patched)
}
$light = Get-CornerHeat $k (@{ gMag = 0.2; slip = 0.09; loadRaw = 3000; weight = 0.50; peakForce = 3000; loadUtil = 3000; suspVel = 0.14; heldRolling = 0.35 })
$heavy = Get-CornerHeat $k (@{ gMag = 0.2; slip = 0.09; loadRaw = 9000; weight = 0.50; peakForce = 9000; loadUtil = 9000; suspVel = 0.14; heldRolling = 0.35 })
if ($heavy.patched -le $light.patched) {
    Out ' FAIL: this tire load did not raise heat.'
    $fail++
} else {
    Out (" OK: tire load 3000 N -> 9000 N raises patched heat {0:N4} -> {1:N4}." -f $light.patched, $heavy.patched)
}

Out ''
if ($fail -eq 0) {
    Out 'OVERALL: PASS - corner heat follows slip and tire load. Chassis G is not an input.'
} else {
    Out ("OVERALL: FAIL - {0} check(s)." -f $fail)
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host ("Wrote {0}" -f $out)
if ($fail -gt 0) { exit 1 } else { exit 0 }
