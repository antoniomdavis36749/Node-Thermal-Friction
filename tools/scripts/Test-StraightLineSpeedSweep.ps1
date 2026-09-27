# Straight-line cruise speed sweep soft-sim (25–300 mph).
# Edge-case probe: RR/hyst + residual cruise slip vs v^0.8 convection at high V.
# Mirrors CalcTyreWear post-fix knobs from tireWearThermals.lua
# (spawn grace, skinCore scale/floor, env clamp, cruise RR soft-cap, aero heat discount,
# carcass cool coefs, hystSkinShare).
#
# Refs: Test-ThermalOddities.ps1, Test-AeroEdgeCase.ps1, Test-BurnoutHeat.ps1
param(
  [double]$AeroHeatScale = 0.55,
  [string]$OutSuffix = ''
)
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$suf = if ($OutSuffix) { $OutSuffix } else { ('aero{0}' -f ($AeroHeatScale.ToString('0.00', [cultureinfo]::InvariantCulture))) }
$out = Join-Path $outDir ("straight-line-speed-sweep-{0}.txt" -f $suf)

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# ---- Live THERMAL_TOPOLOGY + post-fix globals ----
$topo = @{
  patchFracMin = 0.09; patchFracMax = 0.22; patchFracRef = 0.140
  freeBeltCoolMult = 1.32
  flexWarmGain = 0.00095
  flexWarmLoad0 = 120.0; flexWarmLoad1 = 400.0
  flexWarmSpeed0 = 2.0; flexWarmSpeed1 = 20.0; flexWarmG0 = 0.28
  drivePropCruiseNm = 340.0; drivePropExcessFullNm = 585.0
  drivePropSkinCoef = 0.041
  drivePropHystBase = 5e-8; drivePropHystExcess = 3.1e-7
  drivePropFlexGateStart = 0.21; drivePropFlexExcess = 0.00034
  drivePropSlipWorkMult = 1.08
  drivePropSlickScale = 0.52; drivePropSlickCarcassScale = 0.29
  drivePropStreetSpeed0 = 78.0; drivePropStreetSpeed1 = 112.0
  aeroHeatScale = $AeroHeatScale; aeroHeatSpeedStart = 15.0; aeroHeatSpeedFull = 52.0; aeroHeatMaxFrac = 0.48
  skinCoreScale = 1.85; skinCoreFloor = 0.070
  carcassCoolVel = 0.28; carcassCoolStatic = 0.20
  hystSkinShare = 0.28
}
$SPAWN_CONV_GRACE_S = 14.0
$STREET_PREHEAT_BLEND = 0.34
$SLICK_PREHEAT_BLEND = 0.25
$SKIN_PREHEAT_FRAC = 0.55
$CORE_REACTION_RATE = 0.08
$ASPHALT_CONDUCTIVITY = 1.35
$THERMAL_BOUNDARY = 0.002
$RUBBER_EMISSIVITY = 0.94
$STEFAN = 5.670374e-8

# Street = DEFAULT_MODS (passenger); slick = medium_slick PROFILE_POINTS
$compounds = @(
  @{
    name = 'street'
    isSlick = $false
    tOpt = 65.0; slipHeat = 7.9; workHeat = 4.8; rollingRes = 0.8
    treadInertia = 0.46; carcassInertia = 0.75; react = 1.35
    skinCore = 0.068; airCool = 0.0275; staticCool = 0.08
    coreCool = 0.0385; coreVelCool = 0.0088; trackCondMult = 1.0
    treadCoef = 0.5
    tyreWidthM = 0.225; tyreRadius = 0.32; pressurePsi = 32.0
    staticLoadN = 3800.0
    # Mild passenger aero: ~0 at low V â†’ ~500 N/wheel @ 300 mph
    aeroPeakN = 500.0
    driveSlipHeatMin = 0.90; driveSlipPropMin = 0.93; driveHighVCarcassScale = 0.80
  }
  @{
    name = 'medium_slick'
    isSlick = $true
    tOpt = 84.0; slipHeat = 10.4; workHeat = 6.1; rollingRes = 1.02
    treadInertia = 0.399; carcassInertia = 0.646; react = 1.42
    skinCore = 0.104; airCool = 0.020; staticCool = 0.076
    coreCool = 0.028; coreVelCool = 0.0064; trackCondMult = 1.15
    treadCoef = 0.0   # slick continuum â†’ conductanceTreadScale â‰ˆ 2.0
    tyreWidthM = 0.275; tyreRadius = 0.33; pressurePsi = 27.0
    staticLoadN = 3400.0
    # Race wing aero: ~0 low â†’ ~2200 N/wheel @ 300 mph
    aeroPeakN = 2200.0
    driveSlipHeatMin = 1.0; driveSlipPropMin = 1.0; driveHighVCarcassScale = 1.0
  }
)

# Ambient / track assumptions (daytime paved, mild cloud)
$ENV_C = 22.0
$TOD = 0.48
$CLOUD = 0.20
function Get-TrackTemp([double]$envTemp) {
  $solar = [math]::Max(0.0, [math]::Cos(($TOD - 0.5) * 2.0 * [math]::PI))
  $cloudScale = Clamp $CLOUD 0 1
  $solarGain = $solar * (1.0 - $cloudScale * 0.85) * 32.0
  $nightCool = (1.0 - $solar) * 6.0
  return $envTemp + $solarGain - $nightCool
}
$TRACK_C = Get-TrackTemp $ENV_C

# Speed points (mph)
$speedsMph = @(25, 40, 60, 80, 100, 120, 150, 180, 200, 250, 300)

# Straight-line residual cruise slip (live soft-sat path still sees tiny longComp)
$CRUISE_SLIP = 0.025
$CRUISE_G = 0.06
# Propulsion to hold speed vs aero/RR (Nm/wheel). Opens excess gate at high V â€” intentional edge case.
function Get-CruisePropNm([double]$vMs) {
  return 40.0 + 0.038 * $vMs * $vMs
}

function Simulate-Cruise {
  param(
    [hashtable]$comp,
    [double]$mph,
    [double]$dur = 210.0,          # 3.5 min settle window
    [double]$eqRate = 0.015,       # |dSkin/dt| + |dCore/dt| threshold
    [double]$eqHold = 4.0          # seconds below threshold â†’ declare settled
  )

  $dt = 0.01
  $vMs = $mph * 0.44704
  $tyreRadius = [double]$comp.tyreRadius
  $tyreWidthM = [double]$comp.tyreWidthM
  $omega = $vMs / [math]::Max(0.05, $tyreRadius)
  $airspeed = $vMs
  $slip = $CRUISE_SLIP
  $gMag = $CRUISE_G
  $propNm = Get-CruisePropNm $vMs
  $propAbs = [math]::Abs($propNm)

  # Aero load ramps with live aeroHeatSpeed* range (fraction of peak)
  $aeroRamp = Clamp (($airspeed - [double]$topo.aeroHeatSpeedStart) /
    [math]::Max(1.0, [double]$topo.aeroHeatSpeedFull - [double]$topo.aeroHeatSpeedStart)) 0 1
  $aeroN = [double]$comp.aeroPeakN * $aeroRamp
  $loadRaw = [double]$comp.staticLoadN + $aeroN

  $tyreW = 0.95
  $wt = 1.0   # single-node average (zone weights sum to 1)
  $heatMassScale = 1.0
  $flexModifier = 1.0
  $surfMu = 1.05
  $pressurePa = [double]$comp.pressurePsi * 6894.76

  $env = $ENV_C
  $trackTemp = $TRACK_C
  $blend = if ($comp.isSlick) { $SLICK_PREHEAT_BLEND } else { $STREET_PREHEAT_BLEND }
  $core = Lerp $env ([double]$comp.tOpt) $blend
  $skin = Lerp $env ([double]$comp.tOpt) ($blend * $SKIN_PREHEAT_FRAC)
  $skin0 = $skin
  $core0 = $core

  $skinCore = [math]::Max([double]$topo.skinCoreFloor, [double]$comp.skinCore * [double]$topo.skinCoreScale)
  $condTread = Lerp 2.0 1.0 ([double]$comp.treadCoef)
  $skinCoreEff = $skinCore * $condTread
  $adj = [double]$comp.react / [math]::Max(0.05, [double]$comp.treadInertia)
  $coreRate = $CORE_REACTION_RATE / [math]::Max(0.05, [double]$comp.carcassInertia)

  $loadKg = $loadRaw / 9.81
  $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)
  # Aero thermal discount (live load_kg_thermal)
  $loadKgTh = $loadKg
  if ($aeroRamp -gt 0.0) {
    $loadKgTh = $loadKg * (1.0 - $aeroRamp * [double]$topo.aeroHeatMaxFrac * (1.0 - [double]$topo.aeroHeatScale))
  }

  $estArea = [math]::Max(0.004, [math]::Min($tyreWidthM * 0.24, $loadRaw / $pressurePa))
  $patchLen = $estArea / $tyreWidthM
  $patchFrac = Clamp ($patchLen / [math]::Max(0.4, 2.0 * [math]::PI * $tyreRadius)) `
    ([double]$topo.patchFracMin) ([double]$topo.patchFracMax)
  $patchHeatScale = Clamp ($patchFrac / [math]::Max(0.05, [double]$topo.patchFracRef)) 0.40 1.20
  $freeBeltBias = 1.0 + (1.0 - $patchFrac) * ([double]$topo.freeBeltCoolMult - 1.0)

  $combinedAir = $airspeed + $omega * $tyreRadius * 0.35
  $effAir = $combinedAir / (1.0 + $combinedAir / 220.0)

  # Climate adapt (env = 22 â†’ mild)
  $tempDiff = $env - 21.0
  $heatAdapt = Clamp (1.0 - $tempDiff * 0.008) 0.85 1.25
  $coolAdapt = Clamp (1.0 + $tempDiff * 0.010) 0.75 1.30
  $climateScale = Clamp (1.0 + $tempDiff * 0.012) 0.6 1.4
  $airCool = [double]$comp.airCool * $coolAdapt
  $staticCool = [double]$comp.staticCool * $coolAdapt
  $coreCool = [double]$comp.coreCool * $coolAdapt
  $coreVelCool = [double]$comp.coreVelCool * $coolAdapt
  $slipHeat = [double]$comp.slipHeat * $heatAdapt
  $workHeat = [double]$comp.workHeat * $heatAdapt

  # Drive gates (straight cruise choke + excess prop)
  $driveHeatGate = [math]::Min(1.0, ($slip * 2.5))
  if (($slip -lt 0.06)) {
    $halfCruise = [double]$topo.drivePropCruiseNm * 0.5
    if ($propAbs -gt $halfCruise) {
      $driveHeatGate = $driveHeatGate * (0.15 + 0.85 * (Clamp (($propAbs - $halfCruise) / [math]::Max(1.0, $halfCruise)) 0 1))
    } else {
      $driveHeatGate = $driveHeatGate * 0.15
    }
  }
  $excessPropGate = Clamp (($propAbs - [double]$topo.drivePropCruiseNm) /
    [math]::Max(1.0, [double]$topo.drivePropExcessFullNm)) 0 1
  $slickDrive = 1.0; $slickCarcass = 1.0
  if ($comp.isSlick) {
    $slickDrive = [double]$topo.drivePropSlickScale
    $slickCarcass = [double]$topo.drivePropSlickCarcassScale
  }
  # Street/non-slick high-V carcass damp (profile driveHighVCarcassScale; topo Speed0/1 enable)
  $streetCarcass = 1.0
  $highVFull = if ($null -ne $comp.driveHighVCarcassScale) { [double]$comp.driveHighVCarcassScale } else { 1.0 }
  if ($highVFull -lt 0.999) {
    $vRamp = Clamp (($airspeed - [double]$topo.drivePropStreetSpeed0) /
      [math]::Max(1.0, [double]$topo.drivePropStreetSpeed1 - [double]$topo.drivePropStreetSpeed0)) 0 1
    $streetCarcass = 1.0 + ($highVFull - 1.0) * $vRamp
  }
  $carcassPropScale = $slickCarcass * $streetCarcass
  $excessSkin = $excessPropGate * $slickDrive
  $excessCarcass = $excessPropGate * $carcassPropScale
  $dhgSkin = [math]::Max($driveHeatGate, $excessSkin)
  $dhgCarcass = [math]::Max($driveHeatGate, $excessCarcass)

  $netTorque = [math]::Abs($propNm * [double]$topo.drivePropSkinCoef * $dhgSkin) *
    0.075 * [double]$comp.rollingRes * $flexModifier

  $cruiseRR = 1.0
  if (($slip -lt 0.08) -and ($gMag -lt 0.35)) { $cruiseRR = 1.0 }
  elseif (($slip -lt 0.15)) { $cruiseRR = 1.0 }

  $propRrDamp = 1.0
  if (($carcassPropScale -lt 0.999) -and ($excessPropGate -gt 1e-4)) {
    $propRrDamp = 1.0 + ($carcassPropScale - 1.0) * $excessPropGate
  }

  $peakSkin = $skin; $peakCore = $core
  $maxGap = $core - $skin
  $minSkin = $skin; $minCore = $core
  $hadNan = $false
  $hitCap = $false
  $settled = $false
  $settleT = $null
  $eqAccum = 0.0
  $prevSkin = $skin; $prevCore = $core

  $n = [int]($dur / $dt)
  $t = 0.0
  $spawnAge = 0.0

  for ($i = 0; $i -lt $n; $i++) {
    $convScale = 1.0
    if ($SPAWN_CONV_GRACE_S -gt 0.0 -and $spawnAge -lt $SPAWN_CONV_GRACE_S) {
      $u = Clamp ($spawnAge / $SPAWN_CONV_GRACE_S) 0 1
      $u = $u * $u * (3.0 - 2.0 * $u)
      $convScale = Lerp 0.35 1.0 $u
    }

    $seh = $slip / (1.0 + $slip * 0.12)
    $loadCoeff = $wt * $loadKgTh
    $gWork = 0.0
    $rel = $gWork * $loadCoeff / 1000.0

    $raw = ($seh * 0.05 + $netTorque * 0.002) * 3.0 * $wt
    $raw = $raw * ([math]::Max($surfMu - 0.5, 0.1) * 2.0)
    $raw = $raw + (((0.0078 * ($seh * $seh) * $loadCoeff) * $slipHeat) +
      (0.145 * $rel * $workHeat / (1.0 + ($seh * $seh)))) * $surfMu / $tyreW

    $tempDist = $skin / [math]::Max(1.0, [double]$comp.tOpt)
    $thermFric = 1.0
    if ($tempDist -gt 1.1) { $thermFric = [math]::Max(0.30, 1.0 - ($tempDist - 1.1) * 0.6) }
    $gain = ($raw / $heatMassScale) * $thermFric * $patchHeatScale *
      (1.0 + ([double]$topo.drivePropSlipWorkMult - 1.0) * $excessSkin)

    $cornerRetain = 1.0
    $velCool = [math]::Pow([math]::Max(0.01, $effAir), 0.8) * $airCool * 0.155 * $cornerRetain
    $tempDelta = $skin - $env
    $conv = $tempDelta * ($staticCool * 0.04 + $velCool) * $climateScale * $freeBeltBias * $convScale

    $tK = $skin + 273.15
    $eK = $env + 273.15
    $rad = ($RUBBER_EMISSIVITY * $STEFAN * ([math]::Pow($tK, 4) - [math]::Pow($eK, 4))) * 0.0001

    $contactRes = 1.0 / (1.0 + $slip * 0.1)
    $condRate = ($ASPHALT_CONDUCTIVITY * [double]$comp.trackCondMult * $estArea *
      ($skin - $trackTemp) / $THERMAL_BOUNDARY) * $contactRes
    $surfCond = (Clamp ($condRate * 0.003) -25 110) * $wt

    $angHeat = [math]::Abs($omega) / (1.0 + [math]::Abs($omega) / 90.0)
    $hyst = ($loadKgTh * $angHeat * 0.0000028 *
      (0.45 * [math]::Exp(-0.5 * [math]::Pow(($skin / [math]::Max(1.0, [double]$comp.tOpt) - 1.0), 2)) + 0.15) *
      [double]$comp.rollingRes * $cruiseRR * $propRrDamp) / $heatMassScale
    $hystCoef = [double]$topo.drivePropHystBase +
      ([double]$topo.drivePropHystExcess - [double]$topo.drivePropHystBase) * $excessCarcass
    $hyst = $hyst + ($propAbs * $dhgCarcass * $angHeat * $hystCoef * [double]$comp.rollingRes) / $heatMassScale

    # Flex warm: cruise g/slip gate â‰ˆ 0 on pure straight (flexWarmG0=0.28, slip*1.8 tiny)
    $flexWarm = 0.0
    $flexGate = (Clamp (($loadKg - [double]$topo.flexWarmLoad0) /
        [math]::Max(1.0, [double]$topo.flexWarmLoad1 - [double]$topo.flexWarmLoad0)) 0 1) *
      (Clamp (($airspeed - [double]$topo.flexWarmSpeed0) /
        [math]::Max(1.0, [double]$topo.flexWarmSpeed1 - [double]$topo.flexWarmSpeed0)) 0 1) *
      (Clamp ($slip * 1.8) 0 1)
    if ($flexGate -gt 1e-4) {
      $flexWarm = $flexGate * [double]$topo.flexWarmGain * $loadKgTh * $angHeat *
        [double]$comp.rollingRes * $flexModifier * $propRrDamp / $heatMassScale
    }
    if ($excessCarcass -gt [double]$topo.drivePropFlexGateStart) {
      $flexWarm = $flexWarm +
        (($excessCarcass - [double]$topo.drivePropFlexGateStart) /
          [math]::Max(1e-3, 1.0 - [double]$topo.drivePropFlexGateStart)) *
        [double]$topo.drivePropFlexExcess * $loadKgTh * $angHeat *
        [double]$comp.rollingRes * $flexModifier / $heatMassScale
    }

    $carcassWork = $hyst + $flexWarm
    $hystToSkin = $carcassWork * [double]$topo.hystSkinShare
    $toCore = ($core - $skin) * $skinCoreEff
    $skinRate = ($gain + $hystToSkin - $conv - $rad - $surfCond + $toCore) * $adj / $tyreW
    $skin = $skin + $dt * $skinRate

    $fromSkin = ($skin - $core) * $skinCoreEff
    $carcassCoolCoef = ([double]$topo.carcassCoolVel * $coreVelCool *
      ([math]::Pow([math]::Max(0.01, $effAir), 0.8) * 0.20) +
      [double]$topo.carcassCoolStatic * $coreCool) * $climateScale
    $coreCoolAmt = ($core - $env) * $carcassCoolCoef
    $core = $core + $dt * ($fromSkin + $carcassWork * (1.0 - [double]$topo.hystSkinShare) - $coreCoolAmt) * $coreRate

    if ([double]::IsNaN($skin) -or [double]::IsInfinity($skin) -or
        [double]::IsNaN($core) -or [double]::IsInfinity($core)) {
      $hadNan = $true
      break
    }
    if ($skin -ge 399.5 -or $core -ge 399.5) { $hitCap = $true }
    if ($skin -gt 400) { $skin = 400 }
    if ($skin -lt -20) { $skin = -20 }
    if ($core -gt 400) { $core = 400 }
    if ($core -lt -20) { $core = -20 }

    if ($skin -gt $peakSkin) { $peakSkin = $skin }
    if ($core -gt $peakCore) { $peakCore = $core }
    if ($skin -lt $minSkin) { $minSkin = $skin }
    if ($core -lt $minCore) { $minCore = $core }
    $gap = $core - $skin
    if ($gap -gt $maxGap) { $maxGap = $gap }

    $dSkin = [math]::Abs(($skin - $prevSkin) / $dt)
    $dCore = [math]::Abs(($core - $prevCore) / $dt)
    $prevSkin = $skin; $prevCore = $core
    if ($t -gt ($SPAWN_CONV_GRACE_S + 5.0)) {
      if (($dSkin + $dCore) -lt $eqRate) {
        $eqAccum += $dt
        if ((-not $settled) -and ($eqAccum -ge $eqHold)) {
          $settled = $true
          $settleT = $t
        }
      } else {
        $eqAccum = 0.0
      }
    }

    $spawnAge += $dt
    $t += $dt
    # Early exit once settled and past 60s (still report full settle temps)
    if ($settled -and $t -ge [math]::Max(60.0, [double]$settleT + 2.0)) { break }
  }

  return [pscustomobject]@{
    compound = [string]$comp.name
    mph = [math]::Round($mph, 0)
    vMs = [math]::Round($vMs, 1)
    propNm = [math]::Round($propNm, 0)
    aeroN = [math]::Round($aeroN, 0)
    loadRaw = [math]::Round($loadRaw, 0)
    loadKgTh = [math]::Round($loadKgTh, 1)
    aeroRamp = [math]::Round($aeroRamp, 3)
    cruiseRR = $cruiseRR
    excessGate = [math]::Round($excessPropGate, 3)
    effAir = [math]::Round($effAir, 1)
    skin0 = [math]::Round($skin0, 2)
    core0 = [math]::Round($core0, 2)
    endSkin = [math]::Round($skin, 2)
    endCore = [math]::Round($core, 2)
    dSkin = [math]::Round($skin - $env, 2)
    dCore = [math]::Round($core - $env, 2)
    gap = [math]::Round($core - $skin, 2)
    maxGap = [math]::Round($maxGap, 2)
    peakSkin = [math]::Round($peakSkin, 2)
    peakCore = [math]::Round($peakCore, 2)
    minSkin = [math]::Round($minSkin, 2)
    settleT = if ($null -ne $settleT) { [math]::Round($settleT, 1) } else { $null }
    settled = $settled
    simT = [math]::Round($t, 1)
    hadNan = $hadNan
    hitCap = $hitCap
  }
}

# ---- Run ----
$sb = New-Object System.Text.StringBuilder
function Out([string]$s) {
  [void]$sb.AppendLine($s)
  Write-Host $s
}

Out 'STRAIGHT-LINE SPEED SWEEP SOFT-SIM'
Out 'Cruise: residual slip=0.025  gMag=0.06  (cruise RR soft-cap=0.48)'
Out ("Ambient={0:n1}C  track={1:n1}C (tod={2} cloud={3})" -f $ENV_C, $TRACK_C, $TOD, $CLOUD)
Out 'Settle: up to 210s or |dT/dt| sum < 0.015 C/s for 4s (after spawn grace)'
Out 'Knobs: skinCoreScale=1.85 floor=0.070  carcassCoolVel/Static=0.28/0.20  hystSkinShare=0.28'
Out ("        aeroHeatScale={0} maxFrac=0.48  vFull=52m/s  spawnGrace=14s" -f $AeroHeatScale)
Out '        streetCarcass damp: 78-112 m/s -> scale 0.65 (non-slick excess-prop carcass)'
Out 'Prop: Nm/wheel = 40 + 0.038*v^2  (aero/RR hold; excess gate opens at high V)'
Out ''

$all = New-Object System.Collections.Generic.List[object]
foreach ($comp in $compounds) {
  Out ('=== {0} (tOpt={1}C  RR={2}  isSlick={3}) ===' -f $comp.name, $comp.tOpt, $comp.rollingRes, $comp.isSlick)
  $hdr = '{0,5} {1,6} {2,6} {3,6} {4,7} {5,7} {6,6} {7,6} {8,6} {9,7} {10,6} {11,5}'
  Out ($hdr -f 'mph', 'v_m/s', 'prop', 'aeroN', 'skin', 'core', 'dSk', 'dCo', 'gap', 'settle', 'simT', 'flags')
  Out ('-' * 96)
  foreach ($mph in $speedsMph) {
    $r = Simulate-Cruise -comp $comp -mph $mph
    [void]$all.Add($r)
    $flags = @()
    if ($r.hadNan) { $flags += 'NAN' }
    if ($r.hitCap) { $flags += 'CAP400' }
    if (-not $r.settled) { $flags += 'UNSETTLED' }
    if ($r.endSkin -le ($ENV_C + 0.8) -and $r.mph -ge 60) { $flags += 'COOL_TO_AMB' }
    if ($r.endSkin -ge 150 -or $r.endCore -ge 150) { $flags += 'HOT150+' }
    if ($r.endSkin -ge 180 -or $r.endCore -ge 180) { $flags += 'RUNAWAY?' }
    if ($r.gap -ge 25) { $flags += 'GAP25+' }
    if ($r.gap -ge 40) { $flags += 'GAP_EXPLODE' }
    $flagStr = if ($flags.Count -gt 0) { ($flags -join ',') } else { 'ok' }
    $st = if ($null -ne $r.settleT) { ('{0}s' -f $r.settleT) } else { '-' }
    Out ($hdr -f $r.mph, $r.vMs, $r.propNm, $r.aeroN, $r.endSkin, $r.endCore,
      $r.dSkin, $r.dCore, $r.gap, $st, $r.simT, $flagStr)
  }
  Out ''
}

# ---- Edge-case analysis ----
Out '=== EDGE-CASE ANALYSIS ==='
foreach ($compName in @('street', 'medium_slick')) {
  $rows = @($all | Where-Object { $_.compound -eq $compName } | Sort-Object mph)
  Out ("--- {0} ---" -f $compName)

  # Monotonicity of endSkin vs mph (allow small noise)
  $nonMono = @()
  for ($i = 1; $i -lt $rows.Count; $i++) {
    $d = [double]$rows[$i].endSkin - [double]$rows[$i - 1].endSkin
    # Expect mild rise or flat; flag sharp drops or huge jumps
    if ($d -lt -3.0) {
      $nonMono += ('skin DROP {0}->{1} mph ({2} -> {3}, d={4})' -f `
        $rows[$i - 1].mph, $rows[$i].mph, $rows[$i - 1].endSkin, $rows[$i].endSkin, [math]::Round($d, 2))
    }
    if ($d -gt 25.0) {
      $nonMono += ('skin JUMP {0}->{1} mph ({2} -> {3}, d={4})' -f `
        $rows[$i - 1].mph, $rows[$i].mph, $rows[$i - 1].endSkin, $rows[$i].endSkin, [math]::Round($d, 2))
    }
  }
  if ($nonMono.Count -eq 0) {
    Out '  monotonicity: OK (no sharp drop >3C or jump >25C between adjacent points)'
  } else {
    foreach ($m in $nonMono) { Out ("  NON-MONO: {0}" -f $m) }
  }

  $r100 = $rows | Where-Object { $_.mph -eq 100 } | Select-Object -First 1
  $r200 = $rows | Where-Object { $_.mph -eq 200 } | Select-Object -First 1
  $r300 = $rows | Where-Object { $_.mph -eq 300 } | Select-Object -First 1
  $r25 = $rows | Where-Object { $_.mph -eq 25 } | Select-Object -First 1

  $nanAny = @($rows | Where-Object { $_.hadNan }).Count -gt 0
  $capAny = @($rows | Where-Object { $_.hitCap }).Count -gt 0
  $coolAmb = @($rows | Where-Object { $_.mph -ge 60 -and $_.endSkin -le ($ENV_C + 0.8) }).Count
  $gapMax = ($rows | Measure-Object -Property gap -Maximum).Maximum
  $skinMax = ($rows | Measure-Object -Property endSkin -Maximum).Maximum
  $coreMax = ($rows | Measure-Object -Property endCore -Maximum).Maximum

  Out ("  NaN/Inf: {0}" -f $(if ($nanAny) { 'YES â€” FAIL' } else { 'none' }))
  Out ("  hit 400C cap: {0}" -f $(if ($capAny) { 'YES â€” RUNAWAY' } else { 'no' }))
  Out ("  cool-to-ambient @>=60mph: {0} points" -f $coolAmb)
  Out ("  max gap (core-skin): {0}C" -f $gapMax)
  Out ("  max end skin/core: {0} / {1} C" -f $skinMax, $coreMax)
  if ($r25 -and $r100 -and $r200 -and $r300) {
    Out ("  25mph  skin={0} core={1} gap={2}" -f $r25.endSkin, $r25.endCore, $r25.gap)
    Out ("  100mph skin={0} core={1} gap={2}  (+{3}/{4} vs 25)" -f `
      $r100.endSkin, $r100.endCore, $r100.gap,
      [math]::Round($r100.endSkin - $r25.endSkin, 1),
      [math]::Round($r100.endCore - $r25.endCore, 1))
    Out ("  200mph skin={0} core={1} gap={2}  (+{3}/{4} vs 100)" -f `
      $r200.endSkin, $r200.endCore, $r200.gap,
      [math]::Round($r200.endSkin - $r100.endSkin, 1),
      [math]::Round($r200.endCore - $r100.endCore, 1))
    Out ("  300mph skin={0} core={1} gap={2}  (+{3}/{4} vs 200)" -f `
      $r300.endSkin, $r300.endCore, $r300.gap,
      [math]::Round($r300.endSkin - $r200.endSkin, 1),
      [math]::Round($r300.endCore - $r200.endCore, 1))
  }

  # Plausibility verdict for 100â€“300 band
  $band = @($rows | Where-Object { $_.mph -ge 100 -and $_.mph -le 300 })
  $runaway = $false
  $overcool = $false
  $gapExplode = $false
  foreach ($b in $band) {
    if ($b.hitCap -or $b.endSkin -ge 180 -or $b.endCore -ge 180) { $runaway = $true }
    if ($b.endSkin -le ($ENV_C + 0.8)) { $overcool = $true }
    if ($b.gap -ge 40) { $gapExplode = $true }
  }
  # Mild rise with speed is expected; huge acceleration of dT/dv is suspicious
  $rise100_300 = if ($r100 -and $r300) { [double]$r300.endSkin - [double]$r100.endSkin } else { 0 }
  $steep = $rise100_300 -gt 60

  $verdict = 'PLAUSIBLE'
  $notes = @()
  if ($nanAny) { $verdict = 'BROKEN'; $notes += 'NaN/Inf' }
  elseif ($runaway) { $verdict = 'RUNAWAY'; $notes += 'temps>=180 or cap' }
  elseif ($steep) { $verdict = 'SUSPECT'; $notes += ("+{0}C skin 100->300mph" -f [math]::Round($rise100_300, 1)) }
  elseif ($overcool) { $verdict = 'OVERCOOL'; $notes += 'skinâ‰ˆambient at cruise' }
  elseif ($gapExplode) { $verdict = 'SUSPECT'; $notes += 'gap>=40C' }
  else {
    $notes += ("skin rise 100->300 = +{0}C (mild/ok)" -f [math]::Round($rise100_300, 1))
  }
  Out ("  VERDICT 100-300mph: {0}  [{1}]" -f $verdict, ($notes -join '; '))
  Out ''
}

# Compact CSV-ish table for parent
Out '=== TABLE (mph -> skin / carcass C) ==='
Out ('{0,5} {1,14} {2,14} {3,14} {4,14}' -f 'mph', 'street_skin', 'street_core', 'slick_skin', 'slick_core')
foreach ($mph in $speedsMph) {
  $st = $all | Where-Object { $_.compound -eq 'street' -and $_.mph -eq $mph } | Select-Object -First 1
  $sk = $all | Where-Object { $_.compound -eq 'medium_slick' -and $_.mph -eq $mph } | Select-Object -First 1
  Out ('{0,5} {1,14} {2,14} {3,14} {4,14}' -f $mph, $st.endSkin, $st.endCore, $sk.endSkin, $sk.endCore)
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host ""
Write-Host "Wrote $out"
