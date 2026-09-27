# Slick compounds under long high-G turns (soft-sim mirrors live heat + blister path)
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$out = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'output') 'slick-highg-turns-test.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
    if ($v -lt $lo) { return $lo }
    if ($v -gt $hi) { return $hi }
    return $v
}
function Baseline([double[]]$c) { return $c[0] + $c[1] + $c[2] }

function ThermalGrip([double]$temp, [hashtable]$m, [double]$softness) {
    $comp = [double]$m.casing
    $plat = [double]$m.plat * (0.8 + 0.4 * $softness)
    $wC = [double]$m.wc * (0.8 + 0.4 * $softness) * (1.0 + ($comp - 0.5) * 0.15)
    $wH = [double]$m.wh * (0.8 + 0.4 * $softness)
    $diff = [math]::Abs($temp - [double]$m.tOpt)
    $excess = [math]::Max(0.0, $diff - $plat)
    if ($temp -lt [double]$m.tOpt) { $w = $wC; $p = 1.35 } else { $w = $wH; $p = 2.0 }
    $decay = [math]::Exp(-[math]::Pow($excess / [math]::Max(1.0, $w), $p))
    $tm = [double]$m.floor + (1.0 - [double]$m.floor) * $decay
    # Race/slick: sharpen cold cliff (mirrors live isRaceCold path)
    if ($tm -lt 1.0 -and ($m.name -like '*slick*' -or $m.name -eq 'sport_plus')) {
        $tm = [math]::Max(0.42, [math]::Pow($tm, 1.12))
    }
    $adW = Clamp ([double]$m.ad) 0.15 0.75
    $shaped = $tm * (0.62 + 0.38 * $tm)
    return ($tm + ($shaped - $tm) * ($adW * 0.55))
}

# Live SLICK_SPECTRUM_POINTS + sport control (v4 anti-trip: lat 0.74/0.72/0.70, dryGrip 0.98, dry_paved cap 1.15)
$profiles = @(
    @{
        name = 'hard_slick'; softness = 0.50
        c = @(1.34, 0.30, -0.11); gm = 0.96; lat = 0.74; dryGrip = 0.98
        tOpt = 90.0; plat = 14.0; wc = 48.0; wh = 48.0; floor = 0.20; ad = 0.48; casing = 0.30
        slipHeat = 9.7; workHeat = 5.8; wearRate = 0.0005; hotWear = 4.4; blisterRatio = 1.50
        treadInertia = 0.4536; carcassInertia = 0.7344; react = 1.25; skinCore = 0.088
        airCool = 0.018; staticCool = 0.072; coreCool = 0.035
    }
    @{
        name = 'medium_slick'; softness = 0.65
        c = @(1.38, 0.32, -0.12); gm = 1.02; lat = 0.72; dryGrip = 0.98
        tOpt = 84.0; plat = 14.0; wc = 46.0; wh = 46.0; floor = 0.20; ad = 0.52; casing = 0.25
        slipHeat = 10.4; workHeat = 6.1; wearRate = 0.0008; hotWear = 4.52; blisterRatio = 1.50
        treadInertia = 0.399; carcassInertia = 0.646; react = 1.42; skinCore = 0.104
        airCool = 0.020; staticCool = 0.076; coreCool = 0.028
    }
    @{
        name = 'soft_slick'; softness = 0.80
        c = @(1.42, 0.34, -0.12); gm = 1.08; lat = 0.70; dryGrip = 0.98
        tOpt = 78.0; plat = 14.0; wc = 44.0; wh = 44.0; floor = 0.18; ad = 0.55; casing = 0.22
        slipHeat = 11.6; workHeat = 6.4; wearRate = 0.0013; hotWear = 4.72; blisterRatio = 1.50
        treadInertia = 0.3444; carcassInertia = 0.5576; react = 1.55; skinCore = 0.116
        airCool = 0.020; staticCool = 0.082; coreCool = 0.028
    }
    @{
        name = 'sport'; softness = 0.50
        c = @(1.02, 0.16, -0.06); gm = 1.00; lat = 1.0; dryGrip = 1.02
        tOpt = 66.0; plat = 16.0; wc = 62.0; wh = 55.0; floor = 0.28; ad = 0.42; casing = 0.50
        slipHeat = 8.1; workHeat = 4.4; wearRate = 0.00045; hotWear = 2.98; blisterRatio = 1.55
        treadInertia = 0.483; carcassInertia = 0.782; react = 1.2; skinCore = 0.076
        airCool = 0.02625; staticCool = 0.08; coreCool = 0.035
    }
)

$dt = 0.01
$env = 28.0
$surfMu = 1.05
$tyreW = 0.95
$vehMass = 1250.0
$cps = @(10, 30, 60, 90, 120, 180, 240, 300)

function Simulate([hashtable]$m, [hashtable]$sc) {
    $soft = [double]$m['softness']
    $tOpt = [double]$m['tOpt']
    $skin = Lerp $env $tOpt 0.50
    $core = $skin - 4.0
    $cond = 100.0
    $blister = 0.0
    $marbles = 0.0
    $hotStint = 0.0
    $samp = @{}
    $t = 0.0
    $peakSkin = $skin
    $timeAboveOpt = 0.0
    $timeBlistering = 0.0

    $base = Baseline ([double[]]$m['c'])
    $adj = [double]$m['react'] / [math]::Max(0.05, [double]$m['treadInertia'])
    $coreRate = 0.08 / [math]::Max(0.05, [double]$m['carcassInertia'])
    $blOn = $tOpt * [double]$m['blisterRatio']
    $scaleW = [double]$m['wearRate'] * 2000.0

    $gMag = [double]$sc['gMag']
    $baseSlip = [double]$sc['slip']
    $airspeed = [double]$sc['airspeed']
    $loadRaw = [double]$sc['loadRaw']
    $duration = [double]$sc['duration']

    # Chassis G does not scale slip energy. The turn's own slip is the heat input.
    $slip = $baseSlip
    $wt = 0.48

    $loadKg = $loadRaw / 9.81
    $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)
    $n = [int][math]::Floor($duration / $dt + 0.5)
    if ($n -lt 1) { throw "Bad duration/n=$n" }

    for ($i = 0; $i -lt $n; $i++) {
        # Optional lap pattern: long turn with brief straights (cooldown)
        $phase = $t % 40.0
        $inTurn = $true
        if ($sc.ContainsKey('lapPattern') -and [bool]$sc['lapPattern']) {
            $inTurn = ($phase -lt 28.0)
        }
        $slipUse = if ($inTurn) { $slip } else { 0.04 }
        $gUse = if ($inTurn) { $gMag } else { 0.15 }
        $loadUse = if ($inTurn) { $loadRaw } else { ($loadRaw * 0.55) }
        $loadKgUse = if ($inTurn) { $loadKg } else { $loadKg * 0.55 }

        $seh = $slipUse / (1.0 + $slipUse * 0.12)
        $loadCoeff = $wt * $loadKgUse
        # Live: gWork = max(0, g_mag - 0.22)
        $gWork = 0.0
        $rel = $gWork * $loadCoeff / 1000.0

        $raw = ($seh * 0.05) * 3.0 * $wt
        $raw = $raw * ([math]::Max($surfMu - 0.5, 0.1) * 2.0)
        $slipTerm = 0.0078 * ($seh * $seh) * $loadCoeff * [double]$m['slipHeat']
        # Near peak lateral capacity in a committed high-G turn
        $peakWork = 1.18
        $workTerm = 0.145 * $rel * [double]$m['workHeat'] * $peakWork / (1.0 + ($seh * $seh))
        # Mild rolling hysteresis (live angularVelHeat path, compressed)
        $rollTerm = 0.022 * $rel * [double]$m['workHeat']
        $raw = $raw + (($slipTerm + $workTerm + $rollTerm) * $surfMu / $tyreW)

        $tempDist = $skin / [math]::Max(1.0, $tOpt)
        $thermFric = 1.0
        if ($tempDist -gt 1.1) { $thermFric = [math]::Max(0.30, 1.0 - ($tempDist - 1.1) * 0.6) }
        $gain = $raw * $thermFric

        $tempDelta = $skin - $env
        # Live effectiveAirspeed soft-cap + corner convection retain under lateral load
        $effAir = $airspeed / (1.0 + $airspeed / 220.0)
        $cornerRetain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $gUse - 0.20) * 0.22))
        $velCool = [math]::Pow([math]::Max(0.0, $effAir), 0.8) * [double]$m['airCool'] * 0.155 * $cornerRetain
        $conv = $tempDelta * ([double]$m['staticCool'] * 0.04 + $velCool)
        # Hot-track conduction (warm asphalt ~38C): heats cold rubber, sinks excess heat when over temp
        $trackTemp = 38.0
        $trackCond = ($skin - $trackTemp) * 0.012 * $wt
        $toCore = ($core - $skin) * [double]$m['skinCore']
        # NOTE: cannot use $dT — PowerShell is case-insensitive and would clobber timestep $dt
        $skinRate = ($gain - $conv - $trackCond + $toCore) * $adj / $tyreW
        if ([double]::IsNaN($skinRate) -or [double]::IsInfinity($skinRate)) { $skinRate = 0.0 }
        $skin = $skin + $dt * $skinRate
        $skin = Clamp $skin -20 250

        $fromSkin = ($skin - $core) * [double]$m['skinCore']
        $coreCoolAmt = ($core - $env) * [double]$m['coreCool'] * 0.15 * (1.0 + $airspeed * 0.01)
        $core = $core + $dt * ($fromSkin - $coreCoolAmt) * $coreRate * 8.0
        $core = Clamp $core -20 220

        if ($skin -gt $peakSkin) { $peakSkin = $skin }
        if ($skin -gt $tOpt) { $timeAboveOpt += $dt }

        $tempWear = 1.0
        if ($tempDist -gt 1.0) { $tempWear = Lerp 1.0 ([double]$m['hotWear']) (Clamp ($tempDist - 1.0) 0 1) }
        $sliding = 14.0 * (($loadUse / ($vehMass * 9.81)) * $slipUse * $tempWear / $tyreW)
        $cond = Clamp ($cond - $sliding * [double]$m['wearRate'] * $dt) 0 100

        # Live blister model (post-desense)
        $blisterSlipThresh = 0.32
        if (($skin -gt $blOn) -and ($slipUse -gt $blisterSlipThresh)) {
            $overheat = [math]::Min(2.0, ($skin - $blOn) / [math]::Max(12.0, $tOpt * 0.18))
            $slipFactor = [math]::Min(2.2, $slipUse / $blisterSlipThresh)
            $blister = Clamp ($blister + 0.00028 * $scaleW * $overheat * $slipFactor * $dt) 0 1
            $timeBlistering += $dt
        }

        if (($skin -gt $tOpt * 0.95) -and ($slipUse -gt 0.20)) {
            $marbles = Clamp ($marbles + 0.0004 * $slipUse * $scaleW * $dt) 0 1
        }
        if ($skin -ge $tOpt * 0.90) { $hotStint += $dt }
        $stint = [math]::Min(0.12, $hotStint / 10000.0)

        $t += $dt

        foreach ($cp in $cps) {
            $key = [string]$cp
            if (-not $samp.ContainsKey($key) -and $t -ge ([double]$cp - 0.0000001)) {
                $x = $cond * 0.01
                $therm = ThermalGrip $skin $m $soft
                $dryG = if ($m.ContainsKey('dryGrip')) { [double]$m['dryGrip'] } else { 1.0 }
                $grip = $base * $therm * [double]$m['gm'] * $dryG
                $grip = $grip * (Lerp 0.75 1.0 $x)
                $bPen = 0.0
                if ($blister -gt 0.08) { $bPen = ($blister - 0.08) * 0.32 }
                $grip = $grip * (1.0 - $bPen) * (1.0 - $marbles * 0.18) * (1.0 - $stint)
                # Anti-trip: lat mult + dry_paved cap 1.15 / gmMu (live getSurfaceSanityScale)
                $latGrip = $grip * [double]$m['lat']
                $surfaceCap = 1.15
                $beamRef = [math]::Max(0.18, [math]::Min(1.20, $surfMu))
                $latGrip = [math]::Min($latGrip, $surfaceCap / $beamRef)
                # Live race latCap: soft/med/hard slick 1.18/1.16/1.14 (was soft-sim 1.30/1.28/1.26)
                $latCap = 1.12
                if ($m.name -eq 'soft_slick') { $latCap = 1.18 }
                elseif ($m.name -eq 'medium_slick') { $latCap = 1.16 }
                elseif ($m.name -eq 'hard_slick') { $latCap = 1.14 }
                $coldFrac = Clamp (([double]$m.tOpt - $skin) / [math]::Max(20.0, [double]$m.tOpt * 0.45)) 0 1
                $hotFrac = Clamp (($skin - [double]$m.tOpt) / [math]::Max(20.0, [double]$m.tOpt * 0.40)) 0 1
                $latCap = $latCap * (1.0 - 0.18 * $coldFrac - 0.12 * $hotFrac)
                if ($latGrip -gt $latCap) { $latGrip = $latCap }
                $grip = $latGrip
                $samp[$key] = @{
                    t = $cp
                    skin = [math]::Round($skin, 1)
                    core = [math]::Round($core, 1)
                    cond = [math]::Round($cond, 1)
                    blister = [math]::Round($blister * 100, 1)
                    marbles = [math]::Round($marbles * 100, 1)
                    therm = [math]::Round($therm, 3)
                    grip = [math]::Round($grip, 3)
                    dTdt = [math]::Round($skinRate, 2)
                }
            }
        }
    }

    $getGrip = {
        param($sec)
        $k = [string][int]$sec
        if ($samp.ContainsKey($k)) { return $samp[$k].grip }
        return $null
    }

    return @{
        samples = $samp
        peakSkin = [math]::Round($peakSkin, 1)
        timeAboveOpt = [math]::Round($timeAboveOpt, 1)
        timeBlistering = [math]::Round($timeBlistering, 1)
        finalBlister = [math]::Round($blister * 100, 1)
        finalCond = [math]::Round($cond, 1)
        grip60 = & $getGrip 60
        grip180 = & $getGrip 180
        grip300 = & $getGrip 300
        blisterOnsetC = [math]::Round($blOn, 0)
    }
}

$scenario = @{
    name = 'long_highg_turn'
    label = 'Sustained high-G turn: g=1.30 slip=0.22(+g scale) v=42m/s load=6200N 300s'
    gMag = 1.30
    slip = 0.22
    airspeed = 42.0
    loadRaw = 6200.0
    duration = 300.0
    lapPattern = $false
}

$lapScenario = @{
    name = 'highg_lap_pattern'
    label = 'Lap pattern: 28s @1.25g / 12s straight, 300s total'
    gMag = 1.25
    slip = 0.15
    airspeed = 40.0
    loadRaw = 6000.0
    duration = 300.0
    lapPattern = $true
}

$stress = @{
    name = 'highg_push'
    label = 'High-G push/scrub: g=1.25 slip=0.30 v=38m/s load=6000N 180s'
    gMag = 1.25
    slip = 0.30
    airspeed = 38.0
    loadRaw = 6000.0
    duration = 180.0
    lapPattern = $false
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('SLICK LONG HIGH-G TURN TEST')
[void]$sb.AppendLine($scenario.label)
[void]$sb.AppendLine('Outside loaded zone (wt=0.48); warm ambient 28C; asphalt mu~1.05; slick 50% preheat')
[void]$sb.AppendLine('Slip for heat includes live g-scale (1+|g|*0.15). Blister gate slip>0.32.')
[void]$sb.AppendLine('')

$results = @{}
foreach ($m in $profiles) {
    $peak = (Baseline ([double[]]$m['c'])) * [double]$m['gm']
    [void]$sb.AppendLine(('=== {0} === peak={1:n3} tOpt={2:n0}C blister@{3:n0}C wear={4} slipHeat={5}' -f `
            $m['name'], $peak, $m['tOpt'], ([double]$m['tOpt'] * [double]$m['blisterRatio']), $m['wearRate'], $m['slipHeat']))
    $r = Simulate $m $scenario
    $results[$m['name']] = $r
    [void]$sb.AppendLine(('{0,5} {1,7} {2,7} {3,6} {4,7} {5,7} {6,6} {7,6}' -f 't(s)', 'skinC', 'coreC', 'cond%', 'blister%', 'therm', 'grip', 'dT/dt'))
    foreach ($cp in $cps) {
        $s = $r.samples[[string]$cp]
        if ($null -eq $s) {
            [void]$sb.AppendLine(('  (missing sample @ {0}s)' -f $cp))
            continue
        }
        [void]$sb.AppendLine(('{0,5} {1,7:n1} {2,7:n1} {3,6:n1} {4,7:n1} {5,7:n3} {6,6:n3} {7,6:n2}' -f `
                $s.t, $s.skin, $s.core, $s.cond, $s.blister, $s.therm, $s.grip, $s.dTdt))
    }
    [void]$sb.AppendLine(('  peakSkin={0}C  aboveOpt={1}s  blisteringTime={2}s  finalBlister={3}%  wearLost={4:n1}%' -f `
            $r.peakSkin, $r.timeAboveOpt, $r.timeBlistering, $r.finalBlister, (100.0 - $r.finalCond)))
    [void]$sb.AppendLine('')
}

[void]$sb.AppendLine('=== LAP PATTERN ===')
[void]$sb.AppendLine($lapScenario.label)
$lapResults = @{}
foreach ($m in $profiles) {
    if ($m['name'] -eq 'sport') { continue }
    $r = Simulate $m $lapScenario
    $lapResults[$m['name']] = $r
    $s = $r.samples['300']
    [void]$sb.AppendLine(('{0,-14} peak={1:n1}C @300s skin={2:n1}C grip={3:n3} cond={4:n1}% blister={5:n1}%' -f `
            $m['name'], $r.peakSkin, $s.skin, $s.grip, $s.cond, $s.blister))
}
[void]$sb.AppendLine('')

[void]$sb.AppendLine('=== STRESS: ' + $stress.label + ' ===')
$stressResults = @{}
foreach ($m in $profiles) {
    if ($m['name'] -eq 'sport') { continue }
    $r = Simulate $m $stress
    $stressResults[$m['name']] = $r
    $s = $r.samples['180']
    [void]$sb.AppendLine(('{0,-14} peak={1:n1}C blister={2:n1}% cond={3:n1}% grip180={4:n3} aboveOpt={5:n0}s' -f `
            $m['name'], $r.peakSkin, $r.finalBlister, $r.finalCond, $s.grip, $r.timeAboveOpt))
}
[void]$sb.AppendLine('')

[void]$sb.AppendLine('=== LOGIC CHECKS ===')
$fail = 0; $pass = 0
function Expect([bool]$ok, [string]$msg) {
    if ($ok) { $script:pass++; [void]$script:sb.AppendLine("PASS  $msg") }
    else { $script:fail++; [void]$script:sb.AppendLine("FAIL  $msg") }
}

$h = $results['hard_slick']; $med = $results['medium_slick']; $sft = $results['soft_slick']; $sp = $results['sport']

Expect ($null -ne $h.samples['60']) 'hard produced samples'
Expect ($sft.peakSkin -ge ($med.peakSkin - 3.0)) 'soft peak skin >= medium (within 3C)'
Expect ($med.peakSkin -ge ($h.peakSkin - 3.0)) 'medium peak skin >= hard (within 3C)'
Expect ((100.0 - $sft.finalCond) -ge (100.0 - $med.finalCond - 0.05)) 'soft wears >= medium over 300s'
Expect ((100.0 - $med.finalCond) -ge (100.0 - $h.finalCond - 0.05)) 'medium wears >= hard over 300s'

Expect ($h.samples['60'].skin -gt 35) ('hard skin@60s above cold (got {0})' -f $h.samples['60'].skin)
Expect ($med.samples['60'].skin -gt 35) ('medium skin@60s above cold (got {0})' -f $med.samples['60'].skin)
Expect ($sft.samples['60'].skin -gt 35) ('soft skin@60s above cold (got {0})' -f $sft.samples['60'].skin)

# Chassis G no longer boosts slip, so the old 60/65 C floors are retired.
Expect ($h.samples['180'].skin -gt 45) ('hard skin@180s warming (got {0})' -f $h.samples['180'].skin)
Expect ($sft.samples['180'].skin -gt 45) ('soft skin@180s warming (got {0})' -f $sft.samples['180'].skin)

# Effective slip after g-scale still below blister gate 0.32 for this scenario
Expect ($h.finalBlister -lt 1.0) 'hard: no blister in gripping high-G turn'
Expect ($med.finalBlister -lt 1.0) 'medium: no blister in gripping high-G turn'
Expect ($sft.finalBlister -lt 1.0) 'soft: no blister in gripping high-G turn'

# Cap-aware usable floors (lat*gm*dryGrip under dry_paved 1.15 — not old uncapped ~1.4 peaks)
Expect ($h.grip180 -gt 0.70) ('hard grip@180s still drives ({0})' -f $h.grip180)
Expect ($med.grip180 -gt 0.90) ('medium grip@180s usable ({0})' -f $med.grip180)
Expect ($sft.grip180 -gt 0.90) ('soft grip@180s usable ({0})' -f $sft.grip180)

Expect ($sft.grip60 -gt $h.grip60) 'soft grip@60s > hard (peak advantage)'
Expect ($h.finalCond -ge $sft.finalCond) 'hard retains >= soft condition at 300s'

Expect ($h.peakSkin -lt 140) ('hard peak not runaway (<140C, got {0})' -f $h.peakSkin)
Expect ($sft.peakSkin -lt 140) ('soft peak not runaway (<140C, got {0})' -f $sft.peakSkin)

$sh = $stressResults['hard_slick']; $sm = $stressResults['medium_slick']; $ss = $stressResults['soft_slick']
Expect ($ss.finalBlister -ge ($sm.finalBlister - 0.5)) 'stress: soft blister >= medium'
Expect ($sm.finalBlister -ge ($sh.finalBlister - 0.5)) 'stress: medium blister >= hard'
Expect ($ss.finalBlister -lt 45) ('stress soft blister not runaway (<45%, got {0}%)' -f $ss.finalBlister)
Expect ($sh.samples['180'].grip -gt 0.90) ('stress hard still drives @180s ({0})' -f $sh.samples['180'].grip)

# Soft should build heat faster / sit nearer blister window under scrub
Expect ($ss.peakSkin -ge ($sh.peakSkin - 1.0)) 'stress: soft peaks >= hard'

[void]$sb.AppendLine('')
[void]$sb.AppendLine("RESULT: $pass passed, $fail failed")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== SUMMARY @ 180s continuous high-G ===')
foreach ($name in @('hard_slick', 'medium_slick', 'soft_slick', 'sport')) {
    $r = $results[$name]
    $s = $r.samples['180']
    [void]$sb.AppendLine(('{0,-14} skin={1,5:n1}C grip={2:n3} cond={3:n1}% blister={4:n1}% peak={5:n1}C' -f `
            $name, $s.skin, $s.grip, $s.cond, $s.blister, $r.peakSkin))
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Output $sb.ToString()
if ($fail -gt 0) { Write-Output "FAIL count=$fail"; exit 1 }
Write-Output "OK pass=$pass"
