# Burnout heat soft-sim - mirrors live CalcTyreWear soft-sats / gates / caps
# Source: tireWearThermals.lua (THERMAL_TOPOLOGY + sport_plus PROFILE_POINTS)
# Fix A: gated high-|lastSlip| longComp boost (slipVelBoost*) so burnout can smoke.
$ErrorActionPreference = 'Stop'
$out = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'output') 'burnout-heat-softsim.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# Live THERMAL_TOPOLOGY
$topo = @{
  patchFracMin = 0.032; patchFracHeatMin = 0.022; patchFracMax = 0.22; patchFracRef = 0.068
  freeBeltCoolMult = 1.32
  drivePropCruiseNm = 650.0; drivePropExcessFullNm = 1100.0
  drivePropSkinCoef = 0.021
  drivePropHystBase = 5e-8; drivePropHystExcess = 1.1e-7
  skinCore = 0.088  # from sport_plus (used below)
  # Fix A knobs
  slipVelBoostStart = 8.0
  slipVelBoostFull = 24.0
  slipVelBoostMax = 9.0
}
$NATIVE_SLIP_VEL_SCALE = 0.0125
$LONG_WEIGHT = 0.55
$LOCKUP_OMEGA_THRESH = 1.0
$LOCKUP_HEAT_FLOOR = 0.22
$ASPHALT_CONDUCTIVITY = 1.35
$THERMAL_BOUNDARY = 0.002
$RUBBER_EMISSIVITY = 0.94
$STEFAN = 5.670374e-8
$CORE_REACTION_RATE = 0.08

# sport_plus (Scintilla / GT-IV-like semi-slick)
$m = @{
  name = 'sport_plus'
  tOpt = 76.0; slipHeat = 8.2; workHeat = 3.8; rollingRes = 0.70
  treadInertia = 0.441; carcassInertia = 0.714; react = 1.3
  skinCore = 0.088; airCool = 0.029; staticCool = 0.095
  coreCool = 0.038; coreVelCool = 0.0095
  trackCondMult = 1.15
}

# Live Fix A: lastSlip -> slipEnergy (gm=1, side=0)
function SlipEnergyFromLastSlip {
  param(
    [double]$lastSlip,
    [double]$sideSlip = 0.0,
    [double]$gm = 1.0,
    [switch]$NoBoost
  )
  $absL = [math]::Abs($lastSlip)
  $longComp = $absL * $NATIVE_SLIP_VEL_SCALE * $gm
  if (-not $NoBoost) {
    $span = [math]::Max(1e-3, [double]$topo.slipVelBoostFull - [double]$topo.slipVelBoostStart)
    $ramp = Clamp (($absL - [double]$topo.slipVelBoostStart) / $span) 0 1
    $ramp = $ramp * $ramp * (3.0 - 2.0 * $ramp) # smoothstep
    $longComp = $longComp * (1.0 + [double]$topo.slipVelBoostMax * $ramp)
  }
  $sideComp = [math]::Abs($sideSlip) * $NATIVE_SLIP_VEL_SCALE * $gm
  return [math]::Max(0.0, $longComp * $LONG_WEIGHT + $sideComp * 0.45)
}

function SimulateBurnout {
  param(
    [hashtable]$knobs,
    [string]$label,
    [double]$dur = 20.0,
    [double]$slip = 1.20,          # longitudinal slip energy (post Fix A if from lastSlip)
    [double]$propNm = 1800.0,      # hard throttle per driven wheel
    [double]$omega = 80.0,         # rad/s spinning (~76 mph peripheral @ 0.34m r)
    [double]$airspeed = 1.5,       # nearly stationary vehicle
    [double]$gMag = 0.08,
    [double]$loadRaw = 4200.0,     # rear drive axle share
    [double]$brakeNm = 0.0,
    [switch]$DisableThermalFric,
    [switch]$DisableSlipSoftSat,
    [switch]$DisablePatchScale,
    [switch]$DisableFreeBeltCool,
    [switch]$DisableSpinConvection,  # ignore ωr mixing into airspeed
    [switch]$DisableAllSoftCaps
  )

  $dt = 0.01
  $env = 26.0
  $trackTemp = 36.0
  $tyreW = 0.95
  $tyreWidthM = 0.275
  $tyreRadius = 0.34
  $surfMu = 1.05
  $jbeamMu = 1.0
  $jbeamSlideMu = 1.0
  $heatMassScale = 1.0
  $flexModifier = 1.0
  $vehNotParked = 1.0
  $wt = 0.46   # center-ish single-zone weight proxy
  $pressurePa = 31.0 * 6894.76

  $skin = Lerp $env ([double]$knobs.tOpt) 0.50
  $core = $skin - 2.0
  $peakSkin = $skin
  $tAt80 = $null; $tAt100 = $null; $tAt120 = $null; $tAt150 = $null

  $loadKg = $loadRaw / 9.81
  $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)

  $adj = [double]$knobs.react / [math]::Max(0.05, [double]$knobs.treadInertia)
  $coreRate = $CORE_REACTION_RATE / [math]::Max(0.05, [double]$knobs.carcassInertia)

  # patchFrac from contact area (live Phase B — soft heat floor)
  $estArea = [math]::Max(0.004, [math]::Min($tyreWidthM * 0.24, $loadRaw / $pressurePa))
  $patchLen = $estArea / $tyreWidthM
  $patchFracRaw = $patchLen / [math]::Max(0.4, 2.0 * [math]::PI * $tyreRadius)
  $patchFrac = Clamp $patchFracRaw ([double]$topo.patchFracMin) ([double]$topo.patchFracMax)
  $patchFracHeat = Clamp $patchFracRaw ([double]$topo.patchFracHeatMin) ([double]$topo.patchFracMax)
  $patchHeatScale = Clamp ($patchFracHeat / [math]::Max(0.05, [double]$topo.patchFracRef)) 0.40 1.20
  $freeBeltCoolBias = 1.0 + (1.0 - $patchFrac) * ([double]$topo.freeBeltCoolMult - 1.0)

  $propAbs = [math]::Abs($propNm)
  $excessPropGate = Clamp (($propAbs - [double]$topo.drivePropCruiseNm) / [math]::Max(1.0, [double]$topo.drivePropExcessFullNm)) 0 1
  $driveHeatGate = [math]::Min(1.0, ($slip * 2.5) + ($gMag * 0.45) + ($(if ($brakeNm -gt 40) { 1.0 } else { 0.0 })))
  if (($slip -lt 0.06) -and ($gMag -lt 0.28) -and ($brakeNm -lt 40)) {
    $driveHeatGate = $driveHeatGate * 0.15
  }
  $driveHeatGate = [math]::Max($driveHeatGate, $excessPropGate)

  $netTorque = $vehNotParked * [math]::Abs($propNm * [double]$topo.drivePropSkinCoef * $driveHeatGate - $brakeNm * 0.025) *
    0.075 * [double]$knobs.rollingRes * $flexModifier

  $rows = New-Object System.Collections.Generic.List[object]
  $n = [int]($dur / $dt)
  $t = 0.0
  $lastGain = 0.0; $lastCool = 0.0; $lastThermFric = 1.0; $lastSeh = 0.0

  for ($i = 0; $i -lt $n; $i++) {
    # --- slip soft-sat ---
    $seh = $slip
    if (-not $DisableSlipSoftSat -and -not $DisableAllSoftCaps) {
      $seh = $slip / (1.0 + $slip * 0.12)
    }

    $loadCoeff = $wt * $loadKg
    $gWork = [math]::Max(0.0, $gMag - 0.22)
    $rel = $gWork * $loadCoeff / 1000.0
    $peakWork = 1.0
    $slideMuScale = Clamp ($jbeamSlideMu / [math]::Max(0.2, $jbeamMu)) 0.5 1.6
    $surfaceMu = ($surfMu) * $jbeamMu

    $raw = ($seh * 0.05 + $netTorque * 0.002) * 3.0 * $wt
    $raw = $raw * ([math]::Max($surfaceMu - 0.5, 0.1) * 2.0)
    $raw = $raw + (((0.0078 * ($seh * $seh) * $loadCoeff) * [double]$knobs.slipHeat * $slideMuScale) +
      (0.145 * $rel * [double]$knobs.workHeat * $peakWork / (1.0 + ($seh * $seh)))) * $surfaceMu / $tyreW

    # thermalFrictionScale - soft heat throttle above 1.1 * tOpt
    $tempDist = $skin / [math]::Max(1.0, [double]$knobs.tOpt)
    $thermFric = 1.0
    if (-not $DisableThermalFric -and -not $DisableAllSoftCaps) {
      if ($tempDist -gt 1.1) {
        $thermFric = [math]::Max(0.30, 1.0 - ($tempDist - 1.1) * 0.6)
      }
    }

    $gain = ($raw / $heatMassScale) * $thermFric

    # lockup floor (only if nearly stopped wheel)
    if (($omega -lt $LOCKUP_OMEGA_THRESH) -and ($slip -gt 0.20)) {
      $lockBlend = Clamp ($omega / $LOCKUP_OMEGA_THRESH) 0 1
      $gain = $gain * (Lerp $LOCKUP_HEAT_FLOOR 1.0 $lockBlend)
    }

    # patch heat scale
    if (-not $DisablePatchScale -and -not $DisableAllSoftCaps) {
      $gain = $gain * $patchHeatScale
    }

    # cooling: freestream + spin mixing (live combinedAirspeed)
    $surfaceRotVel = $omega * $tyreRadius
    $combinedAir = $airspeed
    if (-not $DisableSpinConvection) {
      $combinedAir = $airspeed + $surfaceRotVel * 0.35
    }
    $effAir = $combinedAir / (1.0 + ($combinedAir / 220.0))
    $cornerRetain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $gMag - 0.20) * 0.22))
    $velCool = [math]::Pow([math]::Max(0.01, $effAir), 0.8) * [double]$knobs.airCool * 0.155 * $cornerRetain
    $coolBias = 1.0
    if (-not $DisableFreeBeltCool -and -not $DisableAllSoftCaps) {
      $coolBias = $freeBeltCoolBias
    }
    $tempDelta = $skin - $env
    $conv = $tempDelta * ([double]$knobs.staticCool * 0.04 + $velCool) * $coolBias

    # radiation
    $tK = $skin + 273.15
    $eK = $env + 273.15
    $rad = ($RUBBER_EMISSIVITY * $STEFAN * ([math]::Pow($tK, 4) - [math]::Pow($eK, 4))) * 0.0001

    # surface conduction (soft-sat ±)
    $contactRes = 1.0 / (1.0 + $slip * 0.1)
    $condRate = ($ASPHALT_CONDUCTIVITY * [double]$knobs.trackCondMult * $estArea * ($skin - $trackTemp) / $THERMAL_BOUNDARY) * $contactRes
    $surfCond = (Clamp ($condRate * 0.003) -25 110) * $wt

    $toCore = ($core - $skin) * [double]$knobs.skinCore
    $skinRate = ($gain - $conv - $rad - $surfCond + $toCore) * $adj / $tyreW
    $skin = $skin + $dt * $skinRate
    # NO live absolute temp ceiling - only soft-sim runaway guard for numeric safety
    if ($skin -gt 400) { $skin = 400 }
    if ($skin -lt -20) { $skin = -20 }

    $fromSkin = ($skin - $core) * [double]$knobs.skinCore
    $coreCoolAmt = ($core - $env) * ([double]$knobs.coreCool * 0.12 + 0.18 * [double]$knobs.coreVelCool * [math]::Pow([math]::Max(0.01, $effAir), 0.8) * 0.20)
    # carcass RR/hyst (minor in burnout; cruise soft-cap OFF due to high slip)
    $angHeat = [math]::Abs($omega) / (1.0 + [math]::Abs($omega) / 90.0)
    $hystCoef = [double]$topo.drivePropHystBase + ([double]$topo.drivePropHystExcess - [double]$topo.drivePropHystBase) * $excessPropGate
    $torqueHyst = ($propAbs * $driveHeatGate * $angHeat * $hystCoef * [double]$knobs.rollingRes) / $heatMassScale
    $core = $core + $dt * ($fromSkin + $torqueHyst - $coreCoolAmt) * $coreRate * 8.0

    if ($skin -gt $peakSkin) { $peakSkin = $skin }
    if (($null -eq $tAt80) -and ($skin -ge 80)) { $tAt80 = $t }
    if (($null -eq $tAt100) -and ($skin -ge 100)) { $tAt100 = $t }
    if (($null -eq $tAt120) -and ($skin -ge 120)) { $tAt120 = $t }
    if (($null -eq $tAt150) -and ($skin -ge 150)) { $tAt150 = $t }

    $lastGain = $gain; $lastCool = ($conv + $rad + $surfCond); $lastThermFric = $thermFric; $lastSeh = $seh
    $t += $dt
    if (($i % 100) -eq 0 -or $i -eq ($n - 1)) {
      [void]$rows.Add([pscustomobject]@{
        t = [math]::Round($t, 2)
        skin = [math]::Round($skin, 1)
        core = [math]::Round($core, 1)
        gain = [math]::Round($gain, 2)
        cool = [math]::Round($lastCool, 2)
        thermFric = [math]::Round($thermFric, 3)
        seh = [math]::Round($seh, 3)
        dTdt = [math]::Round($skinRate, 2)
      })
    }
  }

  return [pscustomobject]@{
    label = $label
    peakSkin = [math]::Round($peakSkin, 1)
    endSkin = [math]::Round($skin, 1)
    endCore = [math]::Round($core, 1)
    tAt80 = $tAt80; tAt100 = $tAt100; tAt120 = $tAt120; tAt150 = $tAt150
    patchFrac = [math]::Round($patchFrac, 4)
    patchHeatScale = [math]::Round($patchHeatScale, 3)
    freeBeltCoolBias = [math]::Round($freeBeltCoolBias, 3)
    driveHeatGate = [math]::Round($driveHeatGate, 3)
    netTorque = [math]::Round($netTorque, 3)
    endThermFric = [math]::Round($lastThermFric, 3)
    endSeh = [math]::Round($lastSeh, 3)
    endGain = [math]::Round($lastGain, 2)
    endCool = [math]::Round($lastCool, 2)
    slip = $slip
    rows = $rows
  }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('BURNOUT HEAT SOFT-SIM (20s) - sport_plus / Scintilla-like')
[void]$sb.AppendLine('Mirrors live: Fix A slipVelBoost gate, slipEnergyHeat soft-sat, thermalFrictionScale,')
[void]$sb.AppendLine('patchHeatScale, freeBeltCoolBias, lockup floor, spin-mixing convection, conduction soft-sat.')
[void]$sb.AppendLine('NO live absolute skin/carcass/air ceiling exists (ENV sanitize only -40..60).')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('Fix A knobs: start={0} full={1} maxExtra={2} (smoothstep ramp on |lastSlip|)' -f `
  $topo.slipVelBoostStart, $topo.slipVelBoostFull, $topo.slipVelBoostMax))
[void]$sb.AppendLine('  longComp *= (1 + maxExtra * smoothstep((|ls|-start)/(full-start)))')
[void]$sb.AppendLine('  slipEnergy = max(native, longComp*0.55 + sideComp*0.45)')
[void]$sb.AppendLine('')

# --- Fix A mapping table ---
[void]$sb.AppendLine('=== LIVE lastSlip -> slipEnergy (gm=1, side=0) BEFORE vs AFTER Fix A ===')
[void]$sb.AppendLine((' {0,8} {1,8} {2,10} {3,10} {4,8} {5,8}' -f 'lastSlip', 'omega~', 'slipE_pre', 'slipE_post', 'boost', 'ramp'))
foreach ($ls in @(2, 5, 8, 10, 12, 15, 20, 24, 27, 35, 40, 50, 60)) {
  $pre = SlipEnergyFromLastSlip -lastSlip $ls -NoBoost
  $post = SlipEnergyFromLastSlip -lastSlip $ls
  $span = [math]::Max(1e-3, [double]$topo.slipVelBoostFull - [double]$topo.slipVelBoostStart)
  $ramp = Clamp (([math]::Abs($ls) - [double]$topo.slipVelBoostStart) / $span) 0 1
  $ramp = $ramp * $ramp * (3.0 - 2.0 * $ramp)
  $boost = 1.0 + [double]$topo.slipVelBoostMax * $ramp
  $omegaEst = $ls / 0.34
  [void]$sb.AppendLine((' {0,8:n0} {1,8:n0} {2,10:n3} {3,10:n3} {4,8:n2} {5,8:n3}' -f `
    $ls, $omegaEst, $pre, $post, $boost, $ramp))
}

# Primary burnout from lastSlip via Fix A
$lsBurn = 20.0
$slipBurn = SlipEnergyFromLastSlip -lastSlip $lsBurn
$omegaBurn = $lsBurn / 0.34
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Baseline scenario: stationary rolling burnout via Fix A')
[void]$sb.AppendLine(('  lastSlip={0} m/s -> slipEnergy={1:n3} (was {2:n3} pre-A)  prop=1800Nm  omega={3:n0}  airspeed=1.5' -f `
  $lsBurn, $slipBurn, (SlipEnergyFromLastSlip -lastSlip $lsBurn -NoBoost), $omegaBurn))
[void]$sb.AppendLine('')

$cases = @(
  @{ label = 'BASELINE FixA ls=20'; args = @{}; slip = $slipBurn; omega = $omegaBurn },
  @{ label = 'ablate thermalFrictionScale'; args = @{ DisableThermalFric = $true }; slip = $slipBurn; omega = $omegaBurn },
  @{ label = 'ablate slipEnergyHeat soft-sat'; args = @{ DisableSlipSoftSat = $true }; slip = $slipBurn; omega = $omegaBurn },
  @{ label = 'ablate patchHeatScale'; args = @{ DisablePatchScale = $true }; slip = $slipBurn; omega = $omegaBurn },
  @{ label = 'ablate freeBeltCoolBias'; args = @{ DisableFreeBeltCool = $true }; slip = $slipBurn; omega = $omegaBurn },
  @{ label = 'ablate spin convection (wr)'; args = @{ DisableSpinConvection = $true }; slip = $slipBurn; omega = $omegaBurn },
  @{ label = 'ablate ALL soft-caps'; args = @{ DisableAllSoftCaps = $true }; slip = $slipBurn; omega = $omegaBurn },
  @{ label = 'hard spin FixA ls=27'; args = @{}; slip = (SlipEnergyFromLastSlip -lastSlip 27); omega = (27.0 / 0.34) },
  @{ label = 'upper FixA ls=35'; args = @{}; slip = (SlipEnergyFromLastSlip -lastSlip 35); omega = (35.0 / 0.34) },
  @{ label = 'lockup-ish ls=20 omega=0.5'; args = @{}; slip = $slipBurn; omega = 0.5 },
  @{ label = 'pre-A slipE=0.25 (sanity)'; args = @{}; slip = 0.25; omega = 35.0 },
  @{ label = 'corner-ish ls=5 (low slip)'; args = @{}; slip = (SlipEnergyFromLastSlip -lastSlip 5); omega = 40.0; propNm = 400.0; gMag = 0.85; airspeed = 25.0; loadRaw = 5000.0 }
)

$results = @()
foreach ($c in $cases) {
  $p = @{ knobs = $m; label = $c.label; dur = 20.0 }
  foreach ($k in $c.args.Keys) { $p[$k] = $c.args[$k] }
  if ($c.ContainsKey('slip')) { $p['slip'] = $c.slip }
  if ($c.ContainsKey('omega')) { $p['omega'] = $c.omega }
  if ($c.ContainsKey('propNm')) { $p['propNm'] = $c.propNm }
  if ($c.ContainsKey('gMag')) { $p['gMag'] = $c.gMag }
  if ($c.ContainsKey('airspeed')) { $p['airspeed'] = $c.airspeed }
  if ($c.ContainsKey('loadRaw')) { $p['loadRaw'] = $c.loadRaw }
  $r = SimulateBurnout @p
  $results += $r
}

[void]$sb.AppendLine('=== 20s RESULTS ===')
[void]$sb.AppendLine((' {0,-42} {1,8} {2,8} {3,8} {4,7} {5,7} {6,7} {7,7}' -f `
  'case', 'endSkin', 'peak', 'endCore', 't@80', 't@100', 't@120', 't@150'))
foreach ($r in $results) {
  $f = {
    param($v)
    if ($null -eq $v) { return '-' }
    return ('{0:n1}' -f $v)
  }
  [void]$sb.AppendLine((' {0,-42} {1,8:n1} {2,8:n1} {3,8:n1} {4,7} {5,7} {6,7} {7,7}' -f `
    $r.label, $r.endSkin, $r.peakSkin, $r.endCore,
    (& $f $r.tAt80), (& $f $r.tAt100), (& $f $r.tAt120), (& $f $r.tAt150)))
}

$base = $results[0]
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== BASELINE TIME SERIES (1s) FixA ls=20 ===')
[void]$sb.AppendLine('  t | skin | core | gain | cool | thermFric | seh | dT/dt')
foreach ($row in $base.rows) {
  [void]$sb.AppendLine((' {0,4:n1} | {1,5:n1} | {2,5:n1} | {3,5:n1} | {4,5:n1} | {5,9:n3} | {6,5:n2} | {7,6:n2}' -f `
    $row.t, $row.skin, $row.core, $row.gain, $row.cool, $row.thermFric, $row.seh, $row.dTdt))
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== BASELINE GATE SNAPSHOT ===')
[void]$sb.AppendLine((" patchFrac={0} patchHeatScale={1} freeBeltCoolBias={2}" -f $base.patchFrac, $base.patchHeatScale, $base.freeBeltCoolBias))
[void]$sb.AppendLine((" driveHeatGate={0} netTorque={1} endSeh={2} endThermFric={3} slipE={4:n3}" -f `
  $base.driveHeatGate, $base.netTorque, $base.endSeh, $base.endThermFric, $base.slip))
[void]$sb.AppendLine((" endGain={0} endCool={1}" -f $base.endGain, $base.endCool))

# Rank ablations by peak delta vs baseline
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== ABLATION RANK (peakSkin delta vs BASELINE; higher = more suppression by that mechanism) ===')
$ranked = @()
for ($i = 1; $i -le 6; $i++) {
  $r = $results[$i]
  $delta = $r.peakSkin - $base.peakSkin
  $ranked += [pscustomobject]@{ label = $r.label; delta = $delta; peak = $r.peakSkin }
}
$ranked = $ranked | Sort-Object { -$_.delta }
$rank = 1
foreach ($r in $ranked) {
  [void]$sb.AppendLine((' #{0} {1,-42} deltaPeak={2:+0.0}C  peak={3:n1}C' -f $rank, $r.label, $r.delta, $r.peak))
  $rank++
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== VERDICT HELPERS ===')
[void]$sb.AppendLine((" FixA ls=20 peak @20s = {0}C (pre-A same lastSlip peaked ~51C; smoke zone often 150-250C+)." -f $base.peakSkin))
if ($base.peakSkin -lt 100) {
  [void]$sb.AppendLine(' STILL COLD: Fix A under-boosted; consider higher slipVelBoostMax or earlier full.')
} elseif ($base.peakSkin -lt 120) {
  [void]$sb.AppendLine(' PARTIAL: into hot band but below 120C smoke-ish target; optional B (thermFric) may help.')
} elseif ($base.peakSkin -lt 150) {
  [void]$sb.AppendLine(' GOOD: soft-sim clearly into hot/smoke-ish band (>=120C); ready for in-game burnout recheck.')
} else {
  [void]$sb.AppendLine(' HOT: soft-sim >=150C smoke-zone; ready for in-game burnout recheck (watch thermFric stall).')
}

# Sanity: pre-A slipE=0.25 must not explode (cruise-like injected energy)
$sanity025 = $results | Where-Object { $_.label -like 'pre-A slipE=0.25*' } | Select-Object -First 1
$corner = $results | Where-Object { $_.label -like 'corner-ish*' } | Select-Object -First 1
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== CRUISE / CORNER SAFETY ===')
if ($null -ne $sanity025) {
  [void]$sb.AppendLine((' Injected slipE=0.25 (no high-abs lastSlip): peak {0}C @20s - must stay modest (~51C pre-A).' -f $sanity025.peakSkin))
  if ($sanity025.peakSkin -gt 90) {
    [void]$sb.AppendLine(' FAIL: slipE=0.25 cooked - heat path changed too broadly (not Fix A gate).')
  } else {
    [void]$sb.AppendLine(' OK: moderate slipE without high lastSlip does not explode.')
  }
}
if ($null -ne $corner) {
  [void]$sb.AppendLine((' Corner-ish ls=5 (boost=1): slipE={0:n3} peak {1}C @20s - expect modest rise.' -f $corner.slip, $corner.peakSkin))
  if ($corner.peakSkin -gt 100) {
    [void]$sb.AppendLine(' WARN: corner case got hot; check boost start threshold / g-work.')
  } else {
    [void]$sb.AppendLine(' OK: low-|lastSlip| corner rise stays modest.')
  }
}

# Analytical note on thermalFrictionScale asymptote
$opt = [double]$m.tOpt
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== thermalFrictionScale curve (tOpt=76) ===')
foreach ($T in @(70, 83.6, 90, 100, 110, 120, 140, 160, 183)) {
  $td = $T / $opt
  $tf = 1.0
  if ($td -gt 1.1) { $tf = [math]::Max(0.30, 1.0 - ($td - 1.1) * 0.6) }
  [void]$sb.AppendLine(('  T={0,5:n1}C  tempDist={1:n3}  thermFric={2:n3}' -f $T, $td, $tf))
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== SLIPENERGY SWEEP @20s (post-A lastSlip-mapped + legacy raw slipE) ===')
[void]$sb.AppendLine((' {0,8} {1,8} {2,8} {3,8} {4,8} {5,8} {6,10}' -f 'src', 'slipE', 'omega', 'endSkin', 'peak', 't@100', 'thermFric'))
$sweep = @(
  @{ tag = 'raw'; s = 0.25; w = 35 },
  @{ tag = 'raw'; s = 0.55; w = 65 },
  @{ tag = 'ls=15'; s = (SlipEnergyFromLastSlip -lastSlip 15); w = (15.0 / 0.34) },
  @{ tag = 'ls=20'; s = (SlipEnergyFromLastSlip -lastSlip 20); w = (20.0 / 0.34) },
  @{ tag = 'ls=24'; s = (SlipEnergyFromLastSlip -lastSlip 24); w = (24.0 / 0.34) },
  @{ tag = 'ls=27'; s = (SlipEnergyFromLastSlip -lastSlip 27); w = (27.0 / 0.34) },
  @{ tag = 'ls=35'; s = (SlipEnergyFromLastSlip -lastSlip 35); w = (35.0 / 0.34) },
  @{ tag = 'preA20'; s = (SlipEnergyFromLastSlip -lastSlip 20 -NoBoost); w = (20.0 / 0.34) }
)
foreach ($sw in $sweep) {
  $r = SimulateBurnout -knobs $m -label ('sweep {0}' -f $sw.tag) -dur 20.0 -slip $sw.s -omega $sw.w -propNm 1800.0
  $t100 = if ($null -eq $r.tAt100) { '-' } else { ('{0:n1}' -f $r.tAt100) }
  [void]$sb.AppendLine((' {0,8} {1,8:n3} {2,8:n0} {3,8:n1} {4,8:n1} {5,8} {6,10:n3}' -f `
    $sw.tag, $sw.s, $sw.w, $r.endSkin, $r.peakSkin, $t100, $r.endThermFric))
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== FINAL VERDICT (Fix A) ===')
$rPre = SimulateBurnout -knobs $m -label 'preA' -dur 20.0 -slip (SlipEnergyFromLastSlip -lastSlip 20 -NoBoost) -omega (20.0 / 0.34) -propNm 1800
$r20 = SimulateBurnout -knobs $m -label 'ls20' -dur 20.0 -slip (SlipEnergyFromLastSlip -lastSlip 20) -omega (20.0 / 0.34) -propNm 1800
$r27 = SimulateBurnout -knobs $m -label 'ls27' -dur 20.0 -slip (SlipEnergyFromLastSlip -lastSlip 27) -omega (27.0 / 0.34) -propNm 1800
$r35 = SimulateBurnout -knobs $m -label 'ls35' -dur 20.0 -slip (SlipEnergyFromLastSlip -lastSlip 35) -omega (35.0 / 0.34) -propNm 1800
[void]$sb.AppendLine((" BEFORE Fix A: lastSlip=20 -> slipE={0:n3} -> peak {1}C @20s" -f (SlipEnergyFromLastSlip -lastSlip 20 -NoBoost), $rPre.peakSkin))
[void]$sb.AppendLine((" AFTER  Fix A: lastSlip=20 -> slipE={0:n3} -> peak {1}C @20s" -f (SlipEnergyFromLastSlip -lastSlip 20), $r20.peakSkin))
[void]$sb.AppendLine((" AFTER  Fix A: lastSlip=27 -> slipE={0:n3} -> peak {1}C @20s" -f (SlipEnergyFromLastSlip -lastSlip 27), $r27.peakSkin))
[void]$sb.AppendLine((" AFTER  Fix A: lastSlip=35 -> slipE={0:n3} -> peak {1}C @20s" -f (SlipEnergyFromLastSlip -lastSlip 35), $r35.peakSkin))
[void]$sb.AppendLine(' Formula BEFORE: slipE = |lastSlip| * 0.0125 * 0.55')
[void]$sb.AppendLine(' Formula AFTER:  longComp = |ls|*0.0125*gm*(1 + 9*smoothstep((|ls|-8)/(24-8))); slipE = longComp*0.55')
[void]$sb.AppendLine(' Cruise: |lastSlip|<8 => boost=1 (unchanged). Corner ls=5 unchanged.')
[void]$sb.AppendLine(' Optional B/C (thermFric / patchHeat) NOT applied - Fix A alone first.')
if ($r20.peakSkin -ge 120) {
  [void]$sb.AppendLine(' READY for in-game burnout recheck (soft-sim ls=20 clears ~120C+).')
} else {
  [void]$sb.AppendLine(' NOT YET smoke-ish at ls=20; tune slipVelBoostMax/Full or consider mild B.')
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host $sb.ToString()
Write-Host "WROTE $out"
