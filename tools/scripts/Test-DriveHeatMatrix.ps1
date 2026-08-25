#Requires -Version 5.1
# P0 gate matrix: street / sport_plus / slick / rally x FWD / RWD / AWD x cruise / hard accel / burnout.
# Mirrors CalcTyreWear driveHeatGate + excess prop + driveStreetSlip* (live THERMAL_TOPOLOGY).
# Refs: Test-FwdDriveHeatEdge.ps1, Test-FwdDriveHeat.ps1, tireWearThermals.lua
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'drive-heat-matrix.txt'

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
  drivePropMassRefKg = 1500.0; drivePropMassScaleMin = 0.78; drivePropMassScaleMax = 1.35
  drivePropAwdExcessScale = 0.62
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
  isSlick = $false; isSportPlus = $false; expectSoftCap = $true
  purpose = 'street'
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
  isSlick = $false; isSportPlus = $true; expectSoftCap = $true
  purpose = 'street'
  tOpt = 76.0; slipHeat = 7.75; workHeat = 3.6; rollingRes = 0.70
  treadInertia = 0.441; carcassInertia = 0.714; react = 1.3
  skinCore = 0.088; airCool = 0.029; staticCool = 0.095
  coreCool = 0.038; coreVelCool = 0.0095; trackCondMult = 1.15
  treadCoef = 0.30
  tyreWidthM = 0.265; tyreRadius = 0.33; pressurePsi = 30.0
  driveSlipHeatMin = 0.94; driveSlipPropMin = 0.97; driveHighVCarcassScale = 0.82
}
$slick = @{
  name = 'medium_slick'
  isSlick = $true; isSportPlus = $false; expectSoftCap = $false
  purpose = 'circuit'
  tOpt = 84.0; slipHeat = 9.1; workHeat = 5.35; rollingRes = 1.02
  treadInertia = 0.399; carcassInertia = 0.646; react = 1.42
  skinCore = 0.104; airCool = 0.024; staticCool = 0.082
  coreCool = 0.031; coreVelCool = 0.0072; trackCondMult = 1.15
  treadCoef = 0.0
  tyreWidthM = 0.275; tyreRadius = 0.33; pressurePsi = 27.0
  driveSlipHeatMin = 1.0; driveSlipPropMin = 1.0; driveHighVCarcassScale = 1.0
}
$rallyAsphalt = @{
  name = 'rally_asphalt'
  isSlick = $false; isSportPlus = $false; expectSoftCap = $false
  purpose = 'tarmac_rally'
  tOpt = 68.0; slipHeat = 9.45; workHeat = 5.1; rollingRes = 1.12
  treadInertia = 0.42; carcassInertia = 0.68; react = 1.65
  skinCore = 0.08; airCool = 0.0275; staticCool = 0.08
  coreCool = 0.035; coreVelCool = 0.008; trackCondMult = 1.0
  treadCoef = 0.35
  tyreWidthM = 0.245; tyreRadius = 0.33; pressurePsi = 28.0
  # Phase 5: rally rubber keeps OFF magnitudes; purpose pack also skips street soft-cap
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
    [double]$cruiseNm = 250.0,
    [switch]$DisableSoftCap
  )
  $heatScale = 1.0
  $propScale = 1.0
  if ($DisableSoftCap) { return @{ heat = 1.0; prop = 1.0 } }
  if ($comp.isSlick) { return @{ heat = 1.0; prop = 1.0 } }
  $purpose = if ($comp.purpose) { [string]$comp.purpose } else { 'street' }
  $streetPurposes = @{ street = $true; wet = $true; winter = $true; utility = $true; commercial = $true }
  if (-not $streetPurposes[$purpose]) { return @{ heat = 1.0; prop = 1.0 } }
  if ($brakeNm -ge 40.0) { return @{ heat = 1.0; prop = 1.0 } }
  if ($propAbs -le ($cruiseNm * 0.5)) { return @{ heat = 1.0; prop = 1.0 } }

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
    [double]$airspeed = 12.0,
    [double]$gMag = 0.18,
    [double]$loadRaw = 4200.0,
    [double]$brakeNm = 0.0,
    [double]$omega = $null,
    [double]$vehicleMassKg = 1500.0,
    [int]$drivenCount = 2,
    [switch]$DisableSoftCap
  )

  $dt = 0.01
  $tyreRadius = [double]$comp.tyreRadius
  $tyreWidthM = [double]$comp.tyreWidthM
  if ($null -eq $omega) {
    $omega = ($airspeed / [math]::Max(0.05, $tyreRadius)) * (1.0 + [math]::Min(1.8, $slip * 1.6))
  }
  $propAbs = [math]::Abs($propNm)
  $massRef = [double]$topo.drivePropMassRefKg
  $massScale = Clamp ([math]::Sqrt([math]::Max(400.0, $vehicleMassKg) / [math]::Max(400.0, $massRef))) `
    ([double]$topo.drivePropMassScaleMin) ([double]$topo.drivePropMassScaleMax)
  $cruiseNm = [double]$topo.drivePropCruiseNm * $massScale
  $excessFullNm = [double]$topo.drivePropExcessFullNm * $massScale
  $tyreW = 0.95
  $wt = 1.0
  $heatMassScale = 1.0
  $flexModifier = 1.0
  $surfMu = 1.05
  $pressurePa = [double]$comp.pressurePsi * 6894.76

  $blend = if ($comp.isSlick) { $SLICK_PREHEAT_BLEND } else { $STREET_PREHEAT_BLEND }
  $core = Lerp $ENV_C ([double]$comp.tOpt) $blend
  $skin = Lerp $ENV_C ([double]$comp.tOpt) ($blend * $SKIN_PREHEAT_FRAC)
  $skin0 = $skin

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
    -airspeed $airspeed -gMag $gMag -brakeNm $brakeNm -cruiseNm $cruiseNm -DisableSoftCap:$DisableSoftCap
  $streetHeat = [double]$scales.heat
  $streetProp = [double]$scales.prop

  $driveHeatGate = [math]::Min(1.0, ($slip * 2.5) + ($gMag * 0.45) + ($(if ($brakeNm -gt 40) { 1.0 } else { 0.0 })))
  if (($slip -lt 0.06) -and ($gMag -lt 0.28) -and ($brakeNm -lt 40)) {
    $halfCruise = $cruiseNm * 0.5
    if ($propAbs -gt $halfCruise) {
      $driveHeatGate = $driveHeatGate * (0.15 + 0.85 * (Clamp (($propAbs - $halfCruise) / [math]::Max(1.0, $halfCruise)) 0 1))
    } else {
      $driveHeatGate = $driveHeatGate * 0.15
    }
  }
  $excessPropGate = Clamp (($propAbs - $cruiseNm) / [math]::Max(1.0, $excessFullNm)) 0 1
  if ($drivenCount -ge 3) {
    $awdT = Clamp (($drivenCount - 2.0) / 2.0) 0 1
    $awdScale = 1.0 + ([double]$topo.drivePropAwdExcessScale - 1.0) * $awdT
    $excessPropGate = $excessPropGate * $awdScale
  }
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
  if (($slip -lt 0.08) -and ($gMag -lt 0.35) -and ($brakeNm -lt 50)) { $cruiseRR = 0.48 }
  elseif (($slip -lt 0.15) -and ($gMag -lt 0.55)) { $cruiseRR = 0.72 }

  $propRrDamp = 1.0
  if (($carcassPropScale -lt 0.999) -and ($excessPropGate -gt 1e-4)) {
    $propRrDamp = 1.0 + ($carcassPropScale - 1.0) * $excessPropGate
  }

  $peakSkin = $skin; $peakCore = $core
  $n = [int]($dur / $dt)
  $t = 0.0

  for ($i = 0; $i -lt $n; $i++) {
    $seh = ($slip / (1.0 + $slip * 0.12)) * $streetHeat
    $sehWork = $slip / (1.0 + $slip * 0.12)
    $loadCoeff = $wt * $loadKgTh
    $gWork = [math]::Max(0.0, $gMag - 0.22)
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

    $cornerRetain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $gMag - 0.20) * 0.22))
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
    $t += $dt
  }

  $engaged = ($streetHeat -lt 0.995)
  $overOpt = $peakSkin / [math]::Max(1.0, [double]$comp.tOpt)
  $flag = 'PLAUSIBLE'
  if ($peakSkin -ge 160.0 -or $overOpt -ge 2.4) { $flag = 'RUNAWAY' }
  elseif ($peakSkin -ge 140.0 -or $overOpt -ge 2.0) { $flag = 'HOT' }

  return [pscustomobject]@{
    label = $label
    compound = $comp.name
    softCapEngaged = $engaged
    streetHeat = [math]::Round($streetHeat, 3)
    streetProp = [math]::Round($streetProp, 3)
    propNm = [math]::Round($propNm, 0)
    slip = [math]::Round($slip, 3)
    endSkin = [math]::Round($skin, 1)
    peakSkin = [math]::Round($peakSkin, 1)
    endCore = [math]::Round($core, 1)
    peakCore = [math]::Round($peakCore, 1)
    dSkin = [math]::Round($skin - $skin0, 1)
    flag = $flag
  }
}

# Layout kinematics (per driven wheel). AWD splits torque ~half of 2WD axle share.
$fwdHardSlip = SlipEnergyFromLastSlip 20.0
$rwdHardSlip = SlipEnergyFromLastSlip 9.0
$awdHardSlip = SlipEnergyFromLastSlip 12.0
$burnSlip = SlipEnergyFromLastSlip 20.0
$cruiseSlip = 0.08

$layouts = @(
  @{
    key = 'FWD'
    hard = @{ slip = $fwdHardSlip; propNm = 1100.0; airspeed = 11.0; gMag = 0.22; loadRaw = 4400.0; omega = $null }
    cruise = @{ slip = $cruiseSlip; propNm = 350.0; airspeed = 22.0; gMag = 0.10; loadRaw = 3800.0; omega = $null }
    burnout = @{ slip = $burnSlip; propNm = 1800.0; airspeed = 1.5; gMag = 0.08; loadRaw = 4200.0; omega = 80.0 }
  }
  @{
    key = 'RWD'
    hard = @{ slip = $rwdHardSlip; propNm = 1100.0; airspeed = 11.0; gMag = 0.22; loadRaw = 4600.0; omega = $null }
    cruise = @{ slip = $cruiseSlip; propNm = 350.0; airspeed = 22.0; gMag = 0.10; loadRaw = 3800.0; omega = $null }
    burnout = @{ slip = $burnSlip; propNm = 1800.0; airspeed = 1.5; gMag = 0.08; loadRaw = 4200.0; omega = 80.0 }
  }
  @{
    key = 'AWD'
    # 4 driven wheels: ~half FWD per-wheel prop; mid residual slip
    hard = @{ slip = $awdHardSlip; propNm = 580.0; airspeed = 11.0; gMag = 0.22; loadRaw = 4200.0; omega = $null }
    cruise = @{ slip = $cruiseSlip; propNm = 200.0; airspeed = 22.0; gMag = 0.10; loadRaw = 3800.0; omega = $null }
    burnout = @{ slip = $burnSlip; propNm = 950.0; airspeed = 1.5; gMag = 0.08; loadRaw = 4200.0; omega = 80.0 }
  }
)

$scenarios = @('cruise', 'hard', 'burnout')
$compounds = @($street, $sportPlus, $slick, $rallyAsphalt)

$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s); Write-Host $s }

Out '=== Drive-heat MATRIX soft-sim (compound x layout x scenario) ==='
Out ("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
Out 'Live knobs: patchFrac 0.032/0.068 heatMin 0.022; driveStreetSlip*; drivePropCruiseNm=310'
Out ''
Out (" {0,-14} {1,-4} {2,-8} {3,7} {4,7} {5,7} {6,7} {7,6} {8,9}" -f `
  'compound', 'lay', 'scen', 'peakSk', 'endSk', 'peakCo', 'heatSc', 'eng', 'flag')

$rows = @()
foreach ($comp in $compounds) {
  foreach ($lay in $layouts) {
    $drivenN = if ($lay.key -eq 'AWD') { 4 } elseif ($lay.key -eq 'FWD' -or $lay.key -eq 'RWD') { 2 } else { 2 }
    foreach ($sk in $scenarios) {
      $sc = $lay[$sk]
      $p = @{
        comp = $comp
        label = "$($comp.name)/$($lay.key)/$sk"
        dur = 25.0
        slip = [double]$sc.slip
        propNm = [double]$sc.propNm
        airspeed = [double]$sc.airspeed
        gMag = [double]$sc.gMag
        loadRaw = [double]$sc.loadRaw
        drivenCount = $drivenN
        vehicleMassKg = 1500.0
      }
      if ($null -ne $sc.omega) { $p['omega'] = [double]$sc.omega }
      $r = Simulate-DriveHeat @p
      $eng = if ($r.softCapEngaged) { 'YES' } else { 'no' }
      Out (" {0,-14} {1,-4} {2,-8} {3,7:0.0} {4,7:0.0} {5,7:0.0} {6,7:0.000} {7,6} {8,9}" -f `
        $comp.name, $lay.key, $sk, $r.peakSkin, $r.endSkin, $r.peakCore, $r.streetHeat, $eng, $r.flag)
      $rows += [pscustomobject]@{
        compound = $comp.name
        layout = $lay.key
        scenario = $sk
        expectSoftCap = [bool]$comp.expectSoftCap
        isSlick = [bool]$comp.isSlick
        isSportPlus = [bool]$comp.isSportPlus
        r = $r
      }
    }
  }
}

Out ''
Out '=== VERDICT CHECKS ==='
$fail = 0

# slick: soft-cap never engages
$slBad = @($rows | Where-Object { $_.compound -eq 'medium_slick' -and $_.r.softCapEngaged })
if ($slBad.Count -gt 0) {
  Out (" FAIL: medium_slick soft-cap leaked on $($slBad.Count) cell(s)."); $fail++
} else {
  Out ' OK: medium_slick excluded from soft-cap across matrix'
}

# sport_plus FWD hard: milder soft-cap engages
$spFwd = $rows | Where-Object { $_.compound -eq 'sport_plus' -and $_.layout -eq 'FWD' -and $_.scenario -eq 'hard' } | Select-Object -First 1
if (-not $spFwd) {
  Out ' FAIL: missing sport_plus/FWD/hard.'; $fail++
} elseif (-not $spFwd.r.softCapEngaged) {
  Out ' FAIL: sport_plus FWD hard soft-cap did not engage.'; $fail++
} elseif ($spFwd.r.streetHeat -lt 0.88 -or $spFwd.r.streetHeat -gt 0.995) {
  Out (" FAIL: sport_plus heatSc=$($spFwd.r.streetHeat) want ~0.88-0.995"); $fail++
} else {
  Out (" OK: sport_plus milder soft-cap heatSc=$($spFwd.r.streetHeat) peak=$($spFwd.r.peakSkin)C")
}

# Burnout: soft-cap off for all
$burnBad = @($rows | Where-Object { $_.scenario -eq 'burnout' -and $_.r.softCapEngaged })
if ($burnBad.Count -gt 0) {
  $bn = ($burnBad | ForEach-Object { "$($_.compound)/$($_.layout)" }) -join ', '
  Out " FAIL: burnout soft-cap leak on: $bn"; $fail++
} else {
  Out ' OK: burnout soft-cap inactive (Speed0) across layouts'
}

# Cruise: soft-cap should stay inactive (low slip)
$cruiseBad = @($rows | Where-Object { $_.scenario -eq 'cruise' -and $_.r.softCapEngaged })
if ($cruiseBad.Count -gt 0) {
  $cn = ($cruiseBad | ForEach-Object { "$($_.compound)/$($_.layout)" }) -join ', '
  Out " WARN: cruise soft-cap engaged on: $cn"
} else {
  Out ' OK: cruise residual soft-cap inactive'
}

# Street FWD hard: soft-cap engages + no RUNAWAY
$stFwd = $rows | Where-Object { $_.compound -eq 'street' -and $_.layout -eq 'FWD' -and $_.scenario -eq 'hard' } | Select-Object -First 1
if (-not $stFwd) {
  Out ' FAIL: missing street/FWD/hard cell.'; $fail++
} elseif (-not $stFwd.r.softCapEngaged) {
  Out ' FAIL: street FWD hard soft-cap did not engage.'; $fail++
} elseif ($stFwd.r.flag -eq 'RUNAWAY') {
  Out (" FAIL: street FWD hard RUNAWAY peak=$($stFwd.r.peakSkin)C"); $fail++
} else {
  Out (" OK: street FWD hard soft-cap heatSc=$($stFwd.r.streetHeat) peak=$($stFwd.r.peakSkin)C flag=$($stFwd.r.flag)")
}

# Street AWD hard cooler than FWD (torque split) â€” soft expect
$stAwd = $rows | Where-Object { $_.compound -eq 'street' -and $_.layout -eq 'AWD' -and $_.scenario -eq 'hard' } | Select-Object -First 1
if ($stFwd -and $stAwd) {
  if ($stAwd.r.peakSkin -ge $stFwd.r.peakSkin) {
    Out (" WARN: street AWD hard peak $($stAwd.r.peakSkin)C not below FWD $($stFwd.r.peakSkin)C (torque-split expectation)")
  } else {
    Out (" OK: street AWD hard cooler than FWD ($($stAwd.r.peakSkin) < $($stFwd.r.peakSkin)C)")
  }
}

# Rally FWD hard: Phase 5 purpose pack skips street soft-cap; must not RUNAWAY
$ryFwd = $rows | Where-Object { $_.compound -eq 'rally_asphalt' -and $_.layout -eq 'FWD' -and $_.scenario -eq 'hard' } | Select-Object -First 1
if ($ryFwd) {
  if ($ryFwd.r.softCapEngaged) {
    Out (" FAIL: rally FWD hard soft-cap leaked (Phase 5 purpose gate) heatSc=$($ryFwd.r.streetHeat)"); $fail++
  } elseif ($ryFwd.r.flag -eq 'RUNAWAY') {
    Out (" FAIL: rally FWD hard RUNAWAY peak=$($ryFwd.r.peakSkin)C"); $fail++
  } else {
    Out (" OK: rally FWD hard soft-cap OFF peak=$($ryFwd.r.peakSkin)C eng=$($ryFwd.r.softCapEngaged) flag=$($ryFwd.r.flag)")
  }
}

# Soft-cap compounds must not RUNAWAY on hard accel
$badRun = @($rows | Where-Object {
  $_.r.flag -eq 'RUNAWAY' -and $_.scenario -eq 'hard' -and $_.expectSoftCap
})
if ($badRun.Count -gt 0) {
  foreach ($x in $badRun) {
    Out (" FAIL: RUNAWAY $($x.compound)/$($x.layout)/$($x.scenario) peak=$($x.r.peakSkin)C")
  }
  $fail += $badRun.Count
}

# PatchFrac live parity smoke: street cruise peak must stay below absurd (parity regression)
$stCruise = $rows | Where-Object { $_.compound -eq 'street' -and $_.layout -eq 'RWD' -and $_.scenario -eq 'cruise' } | Select-Object -First 1
if ($stCruise -and ($stCruise.r.peakSkin -gt 95.0 -or $stCruise.r.peakSkin -lt 25.0)) {
  Out (" FAIL: street cruise peak absurd $($stCruise.r.peakSkin)C (patchFrac parity?)"); $fail++
} elseif ($stCruise) {
  Out (" OK: street RWD cruise peak=$($stCruise.r.peakSkin)C (patchFrac live band)")
}

Out ''
if ($fail -eq 0) {
  Out 'OVERALL: PASS - matrix gate green (soft-cap spectrum + layouts).'
} else {
  Out "OVERALL: FAIL - $fail check(s) failed."
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host "Wrote $out"
if ($fail -gt 0) { exit 1 } else { exit 0 }
