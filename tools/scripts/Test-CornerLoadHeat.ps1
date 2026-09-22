# Corner / load-util heat soft-sim gate (round-3 lateral-G dial-back).
# Mirrors live slip^2 + g-boost, work coef, peakWF/util nudge, verticalCarcassHeat,
# and corner velCool g-penalty (net = patched * (1+pen); cruise pen=0).
# Before = live Round-2 knobs + post-R2 Sport rates; After = R3 table + slip −6% / work −3%.
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
    $g = [double]$c.gMag
    $slip0 = [double]$c.slip
    $dynSlip = $slip0 * (1.0 + [math]::Abs($g) * [double]$k.gBoost)
    $seh = $dynSlip / (1.0 + $dynSlip * 0.12)
    $wt = [double]$c.weight
    $loadRaw = [double]$c.loadRaw
    $loadKg = $loadRaw / 9.81
    $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)
    $loadCoeff = $wt * $loadKg
    $rel = [math]::Max(0.0, $g - [double]$k.workG0) * $loadCoeff / 1000.0

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

    $coolPen = [math]::Min([double]$k.coolCap, [math]::Max(0.0, $g - 0.20) * [double]$k.coolSlope)
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

# Sport rates (live Round-2 reopen: 9.68/4.94 * 0.95 → 9.20/4.69)
$sportSlip = 9.20
$sportWork = 4.69
$sportG0 = 0.16

$before = @{
    gBoost       = 0.11
    workCoef     = 0.135
    utilLo       = 0.82
    utilHi       = 1.28
    utilBlend    = 0.16
    vertScale    = 0.48
    coolCap      = 0.18
    coolSlope    = 0.22
    slipHeatRate = $sportSlip
    workHeatRate = $sportWork
    workG0       = $sportG0
}
$after = @{
    gBoost       = 0.08
    workCoef     = 0.128
    utilLo       = 0.82
    utilHi       = 1.20
    utilBlend    = 0.12
    vertScale    = 0.42
    coolCap      = 0.12
    coolSlope    = 0.14
    slipHeatRate = $sportSlip * 0.94
    workHeatRate = $sportWork * 0.97
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
        metric = 'patched'; minDelta = -12.0; maxDelta = -8.0; gate = $true
    }
    @{
        id = 4; name = 'Near-max util weight-shift'
        gMag = 1.10; slip = 0.255; loadRaw = 7400; weight = 0.52
        peakForce = 9800; loadUtil = 7400; suspVel = 0.55; heldRolling = 0.30
        # UtilHi now binds (peakWF 1.32→1.20); allow a slightly wider cut than case 3.
        metric = 'patched'; minDelta = -16.0; maxDelta = -8.0; gate = $true
    }
)

$isoKeys = @(
    @{ name = 'gBoost';    set = @{ gBoost = 0.08 } }
    @{ name = 'workCoef';  set = @{ workCoef = 0.128 } }
    @{ name = 'utilHi';    set = @{ utilHi = 1.20 } }
    @{ name = 'utilBlend'; set = @{ utilBlend = 0.12 } }
    @{ name = 'vertScale'; set = @{ vertScale = 0.42 } }
    @{ name = 'velCool';   set = @{ coolCap = 0.12; coolSlope = 0.14 } }
    @{ name = 'slipRate';  set = @{ slipHeatRate = $sportSlip * 0.94 } }
    @{ name = 'workRate';  set = @{ workHeatRate = $sportWork * 0.97 } }
)

$sb = New-Object System.Text.StringBuilder
function Out([string]$s) {
    [void]$sb.AppendLine($s)
    Write-Host $s
}

Out '=== Corner / load-util heat soft-sim gate (round-3) ==='
Out 'Live mirrors: slip^2 * g-boost, work coef, peakWF/util nudge, verticalCarcassHeat, velCool g-penalty'
Out ('Before (R2): gBoost={0} workCoef={1} utilHi={2} utilBlend={3} vert={4} cool=min({5},(g-0.20)*{6}) Sport slip/work={7}/{8}' -f `
    $before.gBoost, $before.workCoef, $before.utilHi, $before.utilBlend, $before.vertScale, $before.coolCap, $before.coolSlope, $before.slipHeatRate, $before.workHeatRate)
Out ('After  (R3): gBoost={0} workCoef={1} utilHi={2} utilBlend={3} vert={4} cool=min({5},(g-0.20)*{6}) Sport slip/work={7:N3}/{8:N3} (-6%/-3%)' -f `
    $after.gBoost, $after.workCoef, $after.utilHi, $after.utilBlend, $after.vertScale, $after.coolCap, $after.coolSlope, $after.slipHeatRate, $after.workHeatRate)
Out 'Hold: rollingRes / cruise RR / aeroHeatScale / wear locks / A2 floor / nodeWearScale'
Out ''
Out 'Pass: case1 total |d|<=2%; case3 patched d in [-12,-8]%; case4 patched d in [-16,-8]% (util stacking);'
Out '      no single knob >~7% of that case budget (iso uses net so velCool counts); case2 INFO only'
Out ''

$fail = 0
$results = @()

foreach ($c in $cases) {
    $b = Get-CornerHeat $before $c
    $a = Get-CornerHeat $after $c
    $bVal = [double]$b[$c.metric]
    $aVal = [double]$a[$c.metric]
    $delta = if ($bVal -gt 1e-12) { 100.0 * ($aVal - $bVal) / $bVal } else { 0.0 }
    $dPatched = if ($b.patched -gt 1e-12) { 100.0 * ($a.patched - $b.patched) / $b.patched } else { 0.0 }
    $dNet = if ($b.net -gt 1e-12) { 100.0 * ($a.net - $b.net) / $b.net } else { 0.0 }

    $maxIso = 0.0
    $maxIsoName = ''
    foreach ($iso in $isoKeys) {
        $k = Clone-Knobs $before
        foreach ($key in $iso.set.Keys) { $k[$key] = $iso.set[$key] }
        $one = Get-CornerHeat $k $c
        # Iso against net so velCool g-penalty is visible; cruise pen=0 so net=patched.
        $dIso = [math]::Abs(100.0 * ([double]$one.net - [double]$b.net) / [math]::Max(1e-12, [double]$b.net))
        if ($dIso -gt $maxIso) { $maxIso = $dIso; $maxIsoName = [string]$iso.name }
    }

    $passDelta = ($delta -ge [double]$c.minDelta) -and ($delta -le [double]$c.maxDelta)
    $passIso = $maxIso -le 7.0
    $gated = [bool]$c.gate
    if ($gated) {
        $pass = $passDelta -and $passIso
        if (-not $pass) { $fail++ }
        $flag = if ($pass) { 'PASS' } else { 'FAIL' }
    } else {
        $pass = $true
        $flag = 'INFO'
    }

    Out ("[{0}] {1}" -f $flag, $c.name)
    Out ('  before patched={0:N4} net={1:N4} (slip/work/vert={2:N0}/{3:N0}/{4:N0}%) peakWF={5:N3} phs={6:N3} pen={7:N3}' -f `
        $b.patched, $b.net, $b.slipPct, $b.workPct, $b.vertPct, $b.peakWF, $b.patchHeatScale, $b.coolPen)
    Out ('  after  patched={0:N4} net={1:N4} (slip/work/vert={2:N0}/{3:N0}/{4:N0}%) peakWF={5:N3} phs={6:N3} pen={7:N3}' -f `
        $a.patched, $a.net, $a.slipPct, $a.workPct, $a.vertPct, $a.peakWF, $a.patchHeatScale, $a.coolPen)
    Out ('  metric={0} delta={1:N2}%  (want [{2:N0},{3:N0}])  net d={4:N2}%  maxIso={5:N2}% ({6})' -f `
        $c.metric, $delta, $c.minDelta, $c.maxDelta, $dNet, $maxIso, $maxIsoName)
    if ($c.id -eq 1) {
        Out ('  note: cruise metric includes held rolling={0:N2} (RR held); patched-only d={1:N2}%' -f `
            $c.heldRolling, $dPatched)
    }
    if (-not $gated) {
        Out '  note: informational only (GT3 not the fleet heat verdict car)'
    }
    Out ''

    $results += @{
        id = $c.id; name = $c.name; delta = $delta; dNet = $dNet; pass = $pass; gated = $gated
        flag = $flag
        beforeShare = '{0:N0}/{1:N0}/{2:N0}' -f $b.slipPct, $b.workPct, $b.vertPct
    }
}

Out '--- Summary ---'
foreach ($r in $results) {
    Out ('  case{0}: {1}  d={2:N1}%  net d={3:N1}%  pre slip/work/vert%={4}  {5}' -f `
        $r.id, $r.name, $r.delta, $r.dNet, $r.beforeShare, $r.flag)
}
Out ''
if ($fail -eq 0) {
    Out 'OVERALL: PASS - soft-sim gate green (round-3 lateral-G dial-back sized).'
} else {
    Out ("OVERALL: FAIL - {0} gated case(s) outside pass criteria." -f $fail)
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host ("Wrote {0}" -f $out)
if ($fail -gt 0) { exit 1 } else { exit 0 }
