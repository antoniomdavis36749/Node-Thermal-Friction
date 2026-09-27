# FWD vs RWD drive-slip heat soft-sim (street residual spin cook).
# Mirrors CalcTyreWear: driveHeatGate + excess prop + street driven-slip soft-cap
# (driveStreetSlip*). Compares BEFORE (scale=1) vs AFTER (live soft-cap).
#
# Scenarios:
#   FWD street hard accel   --- driven front, high long slip, rolling 15---40 mph
#   RWD street hard accel   --- driven rear, milder residual slip (typical)
#   Stationary burnout      --- airspeed---1.5, must still cook (soft-cap off)
#   RWD drift               --- high g + side slip, soft-cap off
#   Slick                    --- soft-cap off (floors 1.0)
#   sport_plus               --- milder profile floors (0.88/0.92)
#
# Refs: Test-StraightLineSpeedSweep.ps1, Test-BurnoutHeat.ps1
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'fwd-drive-heat-softsim.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}
function Smooth01([double]$t) {
  $t = Clamp $t 0 1
  return $t * $t * (3.0 - 2.0 * $t)
}

# ---- Live THERMAL_TOPOLOGY (post street-slip soft-cap) ----
$topo = @{
  patchFracMin = 0.032; patchFracHeatMin = 0.022; patchFracMax = 0.22; patchFracRef = 0.068
  freeBeltCoolMult = 1.32
  drivePropCruiseNm = 340.0; drivePropExcessFullNm = 585.0
  drivePropSkinCoef = 0.041
  drivePropHystBase = 5e-8; drivePropHystExcess = 3.1e-7
  drivePropFlexGateStart = 0.21; drivePropFlexExcess = 0.00034
  drivePropSlipWorkMult = 1.08
  drivePropSlickScale = 0.52; drivePropSlickCarcassScale = 0.29
  drivePropStreetSpeed0 = 78.0; drivePropStreetSpeed1 = 112.0
  driveStreetSlipSpeed0 = 3.5; driveStreetSlipSpeed1 = 14.0
  driveStreetSlipCapStart = 0.16; driveStreetSlipCapFull = 0.52
  driveStreetSlipG0 = 0.32; driveStreetSlipG1 = 0.58
  skinCoreScale = 1.85; skinCoreFloor = 0.070
  carcassCoolVel = 0.28; carcassCoolStatic = 0.20
  hystSkinShare = 0.18
  slipVelBoostStart = 8.0; slipVelBoostFull = 24.0; slipVelBoostMax = 9.0
}
$STREET_PREHEAT_BLEND = 0.34
$SLICK_PREHEAT_BLEND = 0.25
$SKIN_PREHEAT_FRAC = 0.55
$CORE_REACTION_RATE = 0.08
$ASPHALT_CONDUCTIVITY = 1.35
$THERMAL_BOUNDARY = 0.002
$RUBBER_EMISSIVITY = 0.94
$STEFAN = 5.670374e-8
$NATIVE_SLIP_VEL_SCALE = 0.0125
$LONG_WEIGHT = 0.55
$ENV_C = 22.0
$TRACK_C = 36.0

$street = @{
  name = 'street'
  isSlick = $false; isSportPlus = $false
  tOpt = 65.0; slipHeat = 7.9; workHeat = 4.8; rollingRes = 0.8
  treadInertia = 0.46; carcassInertia = 0.75; react = 1.35
  skinCore = 0.068; airCool = 0.0275; staticCool = 0.08
  coreCool = 0.0385; coreVelCool = 0.0088; trackCondMult = 1.0
  treadCoef = 0.5
  tyreWidthM = 0.225; tyreRadius = 0.32; pressurePsi = 32.0
  driveSlipHeatMin = 0.90; driveSlipPropMin = 0.93; driveHighVCarcassScale = 0.80
}
$sportPlus = @{
  name = 'sport_plus'
  isSlick = $false; isSportPlus = $true
  tOpt = 76.0; slipHeat = 7.75; workHeat = 3.6; rollingRes = 0.70
  treadInertia = 0.441; carcassInertia = 0.714; react = 1.3
  skinCore = 0.088; airCool = 0.029; staticCool = 0.095
  coreCool = 0.038; coreVelCool = 0.0095; trackCondMult = 1.15
  treadCoef = 0.30
  driveSlipHeatMin = 0.94; driveSlipPropMin = 0.97; driveHighVCarcassScale = 0.82
  tyreWidthM = 0.265; tyreRadius = 0.33; pressurePsi = 30.0
}
$slick = @{
  name = 'medium_slick'
  isSlick = $true; isSportPlus = $false
  tOpt = 84.0; slipHeat = 9.1; workHeat = 5.35; rollingRes = 1.02
  treadInertia = 0.399; carcassInertia = 0.646; react = 1.42
  skinCore = 0.104; airCool = 0.024; staticCool = 0.082
  coreCool = 0.031; coreVelCool = 0.0072; trackCondMult = 1.15
  treadCoef = 0.0
  tyreWidthM = 0.275; tyreRadius = 0.33; pressurePsi = 27.0
  driveSlipHeatMin = 1.0; driveSlipPropMin = 1.0; driveHighVCarcassScale = 1.0
}

function SlipEnergyFromLastSlip([double]$lastSlip, [double]$sideSlip = 0.0) {
  $absL = [math]::Abs($lastSlip)
  $longComp = $absL * $NATIVE_SLIP_VEL_SCALE
  $span = [math]::Max(1e-3, [double]$topo.slipVelBoostFull - [double]$topo.slipVelBoostStart)
  $ramp = Smooth01 (($absL - [double]$topo.slipVelBoostStart) / $span)
  $longComp = $longComp * (1.0 + [double]$topo.slipVelBoostMax * $ramp)
  $sideComp = [math]::Abs($sideSlip) * $NATIVE_SLIP_VEL_SCALE
  return [math]::Max(0.0, $longComp * $LONG_WEIGHT + $sideComp * 0.45)
}

function Get-StreetSlipScales {
  param(
    [hashtable]$comp,
    [double]$slip,
    [double]$propAbs,
    [double]$airspeed,
    [double]$gMag,
    [double]$brakeNm = 0.0,
    [switch]$DisableSoftCap
  )
  $heatScale = 1.0
  $propScale = 1.0
  if ($DisableSoftCap) { return @{ heat = 1.0; prop = 1.0 } }
  if ($comp.isSlick) { return @{ heat = 1.0; prop = 1.0 } }
  if ($brakeNm -ge 40.0) { return @{ heat = 1.0; prop = 1.0 } }
  if ($propAbs -le ([double]$topo.drivePropCruiseNm * 0.5)) { return @{ heat = 1.0; prop = 1.0 } }

  $speedRamp = Smooth01 (($airspeed - [double]$topo.driveStreetSlipSpeed0) /
    [math]::Max(1.0, [double]$topo.driveStreetSlipSpeed1 - [double]$topo.driveStreetSlipSpeed0))
  $gGate = 1.0 - (Clamp (($gMag - [double]$topo.driveStreetSlipG0) /
    [math]::Max(1e-3, [double]$topo.driveStreetSlipG1 - [double]$topo.driveStreetSlipG0)) 0 1)
  $slipRamp = Smooth01 (($slip - [double]$topo.driveStreetSlipCapStart) /
    [math]::Max(1e-3, [double]$topo.driveStreetSlipCapFull - [double]$topo.driveStreetSlipCapStart))
  $blend = $speedRamp * $gGate * $slipRamp
  if ($blend -gt 1e-4) {
    $heatMin = if ($null -ne $comp.driveSlipHeatMin) { [double]$comp.driveSlipHeatMin } else { 1.0 }
    $propMin = if ($null -ne $comp.driveSlipPropMin) { [double]$comp.driveSlipPropMin } else { 1.0 }
    if ($heatMin -ge 0.999 -and $propMin -ge 0.999) { return @{ heat = 1.0; prop = 1.0 } }
    $heatScale = 1.0 + ($heatMin - 1.0) * $blend
    $propScale = 1.0 + ($propMin - 1.0) * $blend
  }
  return @{ heat = $heatScale; prop = $propScale }
}

function Simulate-DriveHeat {
  param(
    [hashtable]$comp,
    [string]$label,
    [double]$dur = 25.0,
    [double]$slip = 0.45,
    [double]$propNm = 900.0,
    [double]$airspeed = 12.0,   # freestream m/s (safeAirspeed)
    [double]$gMag = 0.18,
    [double]$loadRaw = 4200.0,
    [double]$brakeNm = 0.0,
    [double]$omega = $null,     # default from airspeed / r if null; burnout overrides
    [switch]$DisableSoftCap
  )

  $dt = 0.01
  $tyreRadius = [double]$comp.tyreRadius
  $tyreWidthM = [double]$comp.tyreWidthM
  if ($null -eq $omega) {
    # Residual spin: wheel faster than vehicle (typical FWD accel slip)
    $omega = ($airspeed / [math]::Max(0.05, $tyreRadius)) * (1.0 + [math]::Min(1.8, $slip * 1.6))
  }
  $propAbs = [math]::Abs($propNm)
  $tyreW = 0.95
  $wt = 1.0
  $heatMassScale = 1.0
  $flexModifier = 1.0
  $surfMu = 1.05
  $pressurePa = [double]$comp.pressurePsi * 6894.76

  $blend = if ($comp.isSlick) { $SLICK_PREHEAT_BLEND } else { $STREET_PREHEAT_BLEND }
  $core = Lerp $ENV_C ([double]$comp.tOpt) $blend
  $skin = Lerp $ENV_C ([double]$comp.tOpt) ($blend * $SKIN_PREHEAT_FRAC)
  $skin0 = $skin; $core0 = $core

  $skinCore = [math]::Max([double]$topo.skinCoreFloor, [double]$comp.skinCore * [double]$topo.skinCoreScale)
  $condTread = Lerp 2.0 1.0 ([double]$comp.treadCoef)
  $skinCoreEff = $skinCore * $condTread
  $adj = [double]$comp.react / [math]::Max(0.05, [double]$comp.treadInertia)
  $coreRate = $CORE_REACTION_RATE / [math]::Max(0.05, [double]$comp.carcassInertia)

  $loadKg = $loadRaw / 9.81
  $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)
  $loadKgTh = $loadKg

  $estArea = [math]::Max(0.004, [math]::Min($tyreWidthM * 0.24, $loadRaw / $pressurePa))
  $patchLen = $estArea / $tyreWidthM
  $patchFracRaw = $patchLen / [math]::Max(0.4, 2.0 * [math]::PI * $tyreRadius)
  $patchFrac = Clamp $patchFracRaw ([double]$topo.patchFracMin) ([double]$topo.patchFracMax)
  $patchFracHeat = Clamp $patchFracRaw ([double]$topo.patchFracHeatMin) ([double]$topo.patchFracMax)
  $patchHeatScale = Clamp ($patchFracHeat / [math]::Max(0.05, [double]$topo.patchFracRef)) 0.40 1.20
  $freeBeltBias = 1.0 + (1.0 - $patchFrac) * ([double]$topo.freeBeltCoolMult - 1.0)

  $combinedAir = $airspeed + $omega * $tyreRadius * 0.35
  $effAir = $combinedAir / (1.0 + $combinedAir / 220.0)

  $tempDiff = $ENV_C - 21.0
  $heatAdapt = Clamp (1.0 - $tempDiff * 0.008) 0.85 1.25
  $coolAdapt = Clamp (1.0 + $tempDiff * 0.010) 0.75 1.30
  $climateScale = Clamp (1.0 + $tempDiff * 0.012) 0.6 1.4
  $airCool = [double]$comp.airCool * $coolAdapt
  $staticCool = [double]$comp.staticCool * $coolAdapt
  $coreCool = [double]$comp.coreCool * $coolAdapt
  $coreVelCool = [double]$comp.coreVelCool * $coolAdapt
  $slipHeat = [double]$comp.slipHeat * $heatAdapt
  $workHeat = [double]$comp.workHeat * $heatAdapt

  $scales = Get-StreetSlipScales -comp $comp -slip $slip -propAbs $propAbs `
    -airspeed $airspeed -gMag $gMag -brakeNm $brakeNm -DisableSoftCap:$DisableSoftCap
  $streetHeat = [double]$scales.heat
  $streetProp = [double]$scales.prop

  $driveHeatGate = [math]::Min(1.0, ($slip * 2.5) + ($(if ($brakeNm -gt 40) { 1.0 } else { 0.0 })))
  if (($slip -lt 0.06) -and ($brakeNm -lt 40)) {
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

  $netTorque = [math]::Abs($propNm * [double]$topo.drivePropSkinCoef * $dhgSkin * $streetProp - $brakeNm * 0.025) *
    0.075 * [double]$comp.rollingRes * $flexModifier

  $cruiseRR = 1.0
  if (($slip -lt 0.08) -and ($brakeNm -lt 50)) { $cruiseRR = 1.0 }
  elseif (($slip -lt 0.15)) { $cruiseRR = 1.0 }

  $propRrDamp = 1.0
  if (($carcassPropScale -lt 0.999) -and ($excessPropGate -gt 1e-4)) {
    $propRrDamp = 1.0 + ($carcassPropScale - 1.0) * $excessPropGate
  }

  $peakSkin = $skin; $peakCore = $core
  $tAt80 = $null; $tAt100 = $null; $tAt120 = $null
  $n = [int]($dur / $dt)
  $t = 0.0

  for ($i = 0; $i -lt $n; $i++) {
    $seh = ($slip / (1.0 + $slip * 0.12)) * $streetHeat
    $sehWork = $slip / (1.0 + $slip * 0.12)
    $loadCoeff = $wt * $loadKgTh
    $gWork = 0.0
    $rel = $gWork * $loadCoeff / 1000.0

    $raw = ($seh * 0.05 + $netTorque * 0.002) * 3.0 * $wt
    $raw = $raw * ([math]::Max($surfMu - 0.5, 0.1) * 2.0)
    $raw = $raw + (((0.0078 * ($seh * $seh) * $loadCoeff) * $slipHeat) +
      (0.145 * $rel * $workHeat / (1.0 + ($sehWork * $sehWork)))) * $surfMu / $tyreW

    $tempDist = $skin / [math]::Max(1.0, [double]$comp.tOpt)
    $thermFric = 1.0
    if ($tempDist -gt 1.1) { $thermFric = [math]::Max(0.30, 1.0 - ($tempDist - 1.1) * 0.6) }
    $gain = ($raw / $heatMassScale) * $thermFric * $patchHeatScale *
      (1.0 + ([double]$topo.drivePropSlipWorkMult - 1.0) * $excessSkin * $streetHeat)

    $cornerRetain = 1.0
    $velCool = [math]::Pow([math]::Max(0.01, $effAir), 0.8) * $airCool * 0.155 * $cornerRetain
    $tempDelta = $skin - $ENV_C
    $conv = $tempDelta * ($staticCool * 0.04 + $velCool) * $climateScale * $freeBeltBias

    $tK = $skin + 273.15
    $eK = $ENV_C + 273.15
    $rad = ($RUBBER_EMISSIVITY * $STEFAN * ([math]::Pow($tK, 4) - [math]::Pow($eK, 4))) * 0.0001

    $contactRes = 1.0 / (1.0 + $slip * 0.1)
    $condRate = ($ASPHALT_CONDUCTIVITY * [double]$comp.trackCondMult * $estArea *
      ($skin - $TRACK_C) / $THERMAL_BOUNDARY) * $contactRes
    $surfCond = (Clamp ($condRate * 0.003) -25 110) * $wt

    $angHeat = [math]::Abs($omega) / (1.0 + [math]::Abs($omega) / 90.0)
    $hyst = ($loadKgTh * $angHeat * 0.0000028 *
      (0.45 * [math]::Exp(-0.5 * [math]::Pow(($skin / [math]::Max(1.0, [double]$comp.tOpt) - 1.0), 2)) + 0.15) *
      [double]$comp.rollingRes * $cruiseRR * $propRrDamp) / $heatMassScale
    $hystCoef = [double]$topo.drivePropHystBase +
      ([double]$topo.drivePropHystExcess - [double]$topo.drivePropHystBase) * $excessCarcass
    $hyst = $hyst + ($propAbs * $dhgCarcass * $angHeat * $hystCoef * [double]$comp.rollingRes) / $heatMassScale

    $carcassWork = $hyst
    $hystToSkin = $carcassWork * [double]$topo.hystSkinShare
    $toCore = ($core - $skin) * $skinCoreEff
    $skinRate = ($gain + $hystToSkin - $conv - $rad - $surfCond + $toCore) * $adj / $tyreW
    $skin = $skin + $dt * $skinRate

    $fromSkin = ($skin - $core) * $skinCoreEff
    $carcassCoolCoef = ([double]$topo.carcassCoolVel * $coreVelCool *
      ([math]::Pow([math]::Max(0.01, $effAir), 0.8) * 0.20) +
      [double]$topo.carcassCoolStatic * $coreCool) * $climateScale
    $coreCoolAmt = ($core - $ENV_C) * $carcassCoolCoef
    $core = $core + $dt * ($fromSkin + $carcassWork * (1.0 - [double]$topo.hystSkinShare) - $coreCoolAmt) * $coreRate

    if ($skin -gt $peakSkin) { $peakSkin = $skin }
    if ($core -gt $peakCore) { $peakCore = $core }
    if ($null -eq $tAt80 -and $skin -ge 80.0) { $tAt80 = $t }
    if ($null -eq $tAt100 -and $skin -ge 100.0) { $tAt100 = $t }
    if ($null -eq $tAt120 -and $skin -ge 120.0) { $tAt120 = $t }

    $t += $dt
  }

  return [pscustomobject]@{
    label = $label
    compound = $comp.name
    softCap = -not $DisableSoftCap
    slip = [math]::Round($slip, 3)
    propNm = [math]::Round($propNm, 0)
    airspeed = [math]::Round($airspeed, 1)
    gMag = [math]::Round($gMag, 2)
    streetHeat = [math]::Round($streetHeat, 3)
    streetProp = [math]::Round($streetProp, 3)
    dhgSkin = [math]::Round($dhgSkin, 3)
    netTorque = [math]::Round($netTorque, 2)
    startSkin = [math]::Round($skin0, 1)
    endSkin = [math]::Round($skin, 1)
    peakSkin = [math]::Round($peakSkin, 1)
    endCore = [math]::Round($core, 1)
    peakCore = [math]::Round($peakCore, 1)
    dSkin = [math]::Round($skin - $skin0, 1)
    tAt80 = $tAt80
    tAt100 = $tAt100
    tAt120 = $tAt120
  }
}

# ---- Cases ----
# FWD street: high residual long slip while rolling (lastSlip ~18---22 --- slipE ~0.4---0.7)
$fwdSlip = SlipEnergyFromLastSlip -lastSlip 20.0
$rwdSlip = SlipEnergyFromLastSlip -lastSlip 9.0   # milder driven residual
$burnSlip = SlipEnergyFromLastSlip -lastSlip 20.0
$driftSlip = SlipEnergyFromLastSlip -lastSlip 8.0 -sideSlip 12.0

$cases = @(
  @{
    name = 'FWD street hard accel (rolling spin)'
    comp = $street; slip = $fwdSlip; propNm = 1100.0; airspeed = 11.0; gMag = 0.22
    loadRaw = 4400.0; omega = $null
  }
  @{
    name = 'FWD street launch mid (25 mph)'
    comp = $street; slip = $fwdSlip; propNm = 1000.0; airspeed = 11.2; gMag = 0.25
    loadRaw = 4300.0; omega = $null
  }
  @{
    name = 'FWD street cruise residual'
    comp = $street; slip = 0.08; propNm = 350.0; airspeed = 22.0; gMag = 0.10
    loadRaw = 3800.0; omega = $null
  }
  @{
    name = 'RWD street hard accel (milder slip)'
    comp = $street; slip = $rwdSlip; propNm = 1100.0; airspeed = 11.0; gMag = 0.22
    loadRaw = 4600.0; omega = $null
  }
  @{
    name = 'Stationary burnout (must stay hot)'
    comp = $street; slip = $burnSlip; propNm = 1800.0; airspeed = 1.5; gMag = 0.08
    loadRaw = 4200.0; omega = 80.0
  }
  @{
    name = 'RWD drift (high g --- soft-cap off)'
    comp = $street; slip = $driftSlip; propNm = 900.0; airspeed = 20.0; gMag = 0.85
    loadRaw = 4800.0; omega = $null
  }
  @{
    name = 'sport_plus FWD-like spin (milder soft-cap)'
    comp = $sportPlus; slip = $fwdSlip; propNm = 1100.0; airspeed = 11.0; gMag = 0.22
    loadRaw = 4400.0; omega = $null
  }
  @{
    name = 'medium_slick driven spin (excluded)'
    comp = $slick; slip = $fwdSlip; propNm = 1100.0; airspeed = 11.0; gMag = 0.22
    loadRaw = 4400.0; omega = $null
  }
)

$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s) }

Out '=== FWD / RWD drive-slip heat soft-sim ==='
Out ('Generated: {0:yyyy-MM-dd HH:mm}' -f (Get-Date))
Out 'Live knobs: topo enable ramps + profile driveSlipHeatMin/PropMin (street 0.90/0.93, sport+ 0.94/0.97)'
Out ('FWD slipE from lastSlip=20 -> {0:n3}; RWD lastSlip=9 -> {1:n3}; burnout lastSlip=20 -> {2:n3}' -f `
  $fwdSlip, $rwdSlip, $burnSlip)
Out ''
Out (' {0,-42} {1,7} {2,7} {3,6} {4,6} {5,7} {6,7} {7,7} {8,7}' -f `
  'case', 'mode', 'heatSc', 'endSk', 'peak', 'dSkin', 'endCo', 't@100', 't@120')

$paired = @()
foreach ($c in $cases) {
  $pAfter = @{
    comp = $c.comp; label = $c.name; dur = 25.0
    slip = $c.slip; propNm = $c.propNm; airspeed = $c.airspeed; gMag = $c.gMag
    loadRaw = $c.loadRaw
  }
  if ($null -ne $c.omega) { $pAfter['omega'] = $c.omega }
  $after = Simulate-DriveHeat @pAfter

  $pBefore = @{
    comp = $c.comp; label = ($c.name + ' [BEFORE]'); dur = 25.0
    slip = $c.slip; propNm = $c.propNm; airspeed = $c.airspeed; gMag = $c.gMag
    loadRaw = $c.loadRaw; DisableSoftCap = $true
  }
  if ($null -ne $c.omega) { $pBefore['omega'] = $c.omega }
  $before = Simulate-DriveHeat @pBefore

  $paired += [pscustomobject]@{ name = $c.name; before = $before; after = $after }

  foreach ($r in @($before, $after)) {
    $mode = if ($r.softCap) { 'AFTER' } else { 'BEFORE' }
    $f100 = if ($null -eq $r.tAt100) { '-' } else { ('{0:n1}' -f $r.tAt100) }
    $f120 = if ($null -eq $r.tAt120) { '-' } else { ('{0:n1}' -f $r.tAt120) }
    Out (' {0,-42} {1,7} {2,7:n3} {3,6:n1} {4,6:n1} {5,7:n1} {6,7:n1} {7,7} {8,7}' -f `
      $c.name, $mode, $r.streetHeat, $r.endSkin, $r.peakSkin, $r.dSkin, $r.endCore, $f100, $f120)
  }
  Out ''
}

Out '=== BEFORE -> AFTER deltas (peakSkin; negative = cooler = soft-cap working) ==='
foreach ($p in $paired) {
  $dPeak = $p.after.peakSkin - $p.before.peakSkin
  $dEnd = $p.after.endSkin - $p.before.endSkin
  Out (' {0,-42} dPeak={1:n1}C  dEnd={2:n1}C  heatScale={3:n3}' -f `
    $p.name, $dPeak, $dEnd, $p.after.streetHeat)
}

Out ''
Out '=== VERDICT CHECKS ==='
$fwd = $paired | Where-Object { $_.name -like 'FWD street hard accel*' } | Select-Object -First 1
$burn = $paired | Where-Object { $_.name -like 'Stationary burnout*' } | Select-Object -First 1
$drift = $paired | Where-Object { $_.name -like 'RWD drift*' } | Select-Object -First 1
$sp = $paired | Where-Object { $_.name -like 'sport_plus*' } | Select-Object -First 1
$sl = $paired | Where-Object { $_.name -like 'medium_slick*' } | Select-Object -First 1
$rwd = $paired | Where-Object { $_.name -like 'RWD street hard accel*' } | Select-Object -First 1

$fail = 0
if ($fwd -and (($fwd.before.peakSkin - $fwd.after.peakSkin) -lt 1.0)) {
  Out ' FAIL: FWD rolling spin not cooled enough (expect >=1.0C peak relief after Pass 6 milder soft-cap).'; $fail++
} else {
  Out (' OK: FWD rolling spin peak {0:n1} -> {1:n1}C (relief {2:n1}C)' -f `
    $fwd.before.peakSkin, $fwd.after.peakSkin, ($fwd.before.peakSkin - $fwd.after.peakSkin))
}
if ($burn -and ([math]::Abs($burn.after.peakSkin - $burn.before.peakSkin) -gt 2.0)) {
  Out ' FAIL: burnout peak changed - soft-cap leaked into stationary spin.'; $fail++
} else {
  Out (' OK: burnout unchanged (peak {0:n1}C, heatScale={1:n3})' -f $burn.after.peakSkin, $burn.after.streetHeat)
}
if ($drift -and ([math]::Abs($drift.after.peakSkin - $drift.before.peakSkin) -gt 2.0)) {
  Out ' FAIL: drift heat changed - g-gate not protecting high-g.'; $fail++
} else {
  Out (' OK: drift unchanged (peak {0:n1}C, heatScale={1:n3})' -f $drift.after.peakSkin, $drift.after.streetHeat)
}
if ($sp -and ($sp.after.streetHeat -ge 0.999 -or $sp.after.streetHeat -lt 0.88 -or $sp.after.streetHeat -gt 0.995)) {
  Out ' FAIL: sport_plus should use milder soft-cap (heatSc ~0.88-0.995).'; $fail++
} else {
  Out (" OK: sport_plus milder soft-cap heatSc={0:n3}" -f $sp.after.streetHeat)
}
if ($sl -and ([math]::Abs($sl.after.peakSkin - $sl.before.peakSkin) -gt 0.5)) {
  Out ' FAIL: slick should be excluded from soft-cap.'; $fail++
} else {
  Out ' OK: slick excluded'
}
if ($fwd -and ($fwd.after.peakSkin -gt 120.0)) {
  Out ' WARN: FWD after peak still >120C - consider further root heat cut.'
} elseif ($fwd -and $rwd) {
  Out (' OK: FWD after peak {0:n1}C (street opt~65); RWD mild-slip {1:n1}C' -f `
    $fwd.after.peakSkin, $rwd.after.peakSkin)
}

Out ''
if ($fail -eq 0) {
  Out 'OVERALL: PASS --- street FWD residual spin softened; burnout/drift/race paths intact.'
} else {
  Out ("OVERALL: FAIL --- $fail check(s) failed.")
}

$text = $sb.ToString()
[System.IO.File]::WriteAllText($out, $text)
Write-Host $text
Write-Host ("Wrote $out")
if ($fail -gt 0) { exit 1 }
