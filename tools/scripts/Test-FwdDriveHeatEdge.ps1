# FWD drive-slip soft-cap EDGE soft-sim: street baseline vs Race/slick, sport_plus, rally asphalt.
# Mirrors CalcTyreWear: driveHeatGate + excess prop + driveStreetSlip* soft-cap gates.
#
# Soft-cap eligibility (live P1): non-slick, driven prop, rolling freestream, low lateral g.
# sport_plus uses milder HeatMin/PropMin (not full street). Slick still excluded.
#
# Scenarios per compound:
#   FWD hard accel (rolling spin)  --- primary cook path
#   Stationary burnout             --- soft-cap must stay OFF (airspeed below Speed0)
#   Cruise residual                --- low slip; soft-cap blend near zero
#
# Refs: Test-FwdDriveHeat.ps1, tireWearThermals.lua THERMAL_TOPOLOGY
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'fwd-drive-heat-edge.txt'

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
  driveRefWheelNm = 1214.0; driveTireScaleMin = 0.25; driveTireScaleMax = 12.0
  staticLoadFallbackN = 3679.0
  driveStreetSlipCapEnable = $false
  cruiseDriveChokeMin = 1.0
  cruiseRrScaleFull = 1.0; cruiseRrScalePartial = 1.0
  driveLayoutDampEnable = $true
  drivePropAwdExcessScale = 0.62; drivePropDrivenThreshNm = 40.0
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

# ---- Compounds ----
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
  isSlick = $false; isSportPlus = $true; expectSoftCap = $true; mildSoftCap = $true
  purpose = 'street'
  tOpt = 76.0; slipHeat = 7.75; workHeat = 3.6; rollingRes = 0.70
  treadInertia = 0.441; carcassInertia = 0.714; react = 1.3
  skinCore = 0.088; airCool = 0.029; staticCool = 0.095
  coreCool = 0.038; coreVelCool = 0.0095; trackCondMult = 1.15
  treadCoef = 0.30
  tyreWidthM = 0.265; tyreRadius = 0.33; pressurePsi = 30.0
  driveSlipHeatMin = 0.94; driveSlipPropMin = 0.97; driveHighVCarcassScale = 0.82
}
# Race / medium slick (same as Test-FwdDriveHeat / Test-StraightLineSpeedSweep)
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
# Rally asphalt: STANDALONE_MODIFIERS.rally; Phase 5 purpose pack skips street soft-cap
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
  if (-not $topo.driveStreetSlipCapEnable) { return @{ heat = 1.0; prop = 1.0 } }
  if ($comp.isSlick) { return @{ heat = 1.0; prop = 1.0 } }
  $purpose = if ($comp.purpose) { [string]$comp.purpose } else { 'street' }
  $streetPurposes = @{ street = $true; wet = $true; winter = $true; utility = $true; commercial = $true }
  if (-not $streetPurposes[$purpose]) { return @{ heat = 1.0; prop = 1.0 } }
  if ($brakeNm -ge 40.0) { return @{ heat = 1.0; prop = 1.0 } }
  if ($propAbs -le ($cruiseNm * 0.5)) { return @{ heat = 1.0; prop = 1.0 } }

  $speedRamp = Smooth01 (($airspeed - [double]$topo.driveStreetSlipSpeed0) /
    [math]::Max(1.0, [double]$topo.driveStreetSlipSpeed1 - [double]$topo.driveStreetSlipSpeed0))
  $slipRamp = Smooth01 (($slip - [double]$topo.driveStreetSlipCapStart) /
    [math]::Max(1e-3, [double]$topo.driveStreetSlipCapFull - [double]$topo.driveStreetSlipCapStart))
  $blend = $speedRamp * $slipRamp
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
  $staticN = if ($loadRaw -gt 0) { $loadRaw } else { [double]$topo.staticLoadFallbackN }
  $wheelNm = $tyreRadius * $staticN
  $tireScale = Clamp ($wheelNm / [double]$topo.driveRefWheelNm) `
    ([double]$topo.driveTireScaleMin) ([double]$topo.driveTireScaleMax)
  $cruiseNm = [double]$topo.drivePropCruiseNm * $tireScale
  $excessFullNm = [double]$topo.drivePropExcessFullNm * $tireScale
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
    -airspeed $airspeed -gMag $gMag -brakeNm $brakeNm -cruiseNm $cruiseNm -DisableSoftCap:$DisableSoftCap
  $streetHeat = [double]$scales.heat
  $streetProp = [double]$scales.prop

  $driveHeatGate = [math]::Min(1.0, ($slip * 2.5) + ($(if ($brakeNm -gt 40) { 1.0 } else { 0.0 })))
  $chokeMin = [double]$topo.cruiseDriveChokeMin
  if (($slip -lt 0.06) -and ($brakeNm -lt 40) -and ($chokeMin -lt 0.999)) {
    $halfCruise = $cruiseNm * 0.5
    if ($propAbs -gt $halfCruise) {
      $driveHeatGate = $driveHeatGate * (0.15 + 0.85 * (Clamp (($propAbs - $halfCruise) / [math]::Max(1.0, $halfCruise)) 0 1))
    } else {
      $driveHeatGate = $driveHeatGate * 0.15
    }
  }
  $excessPropGate = Clamp (($propAbs - $cruiseNm) /
    [math]::Max(1.0, $excessFullNm)) 0 1
  if ($topo.driveLayoutDampEnable -and ($drivenCount -ge 3)) {
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
  if (($slip -lt 0.08) -and ($brakeNm -lt 50)) { $cruiseRR = [double]$topo.cruiseRrScaleFull }
  elseif ($slip -lt 0.15) { $cruiseRR = [double]$topo.cruiseRrScalePartial }

  $propRrDamp = 1.0
  if (($carcassPropScale -lt 0.999) -and ($excessPropGate -gt 1e-4)) {
    $propRrDamp = 1.0 + ($carcassPropScale - 1.0) * $excessPropGate
  }

  $peakSkin = $skin; $peakCore = $core
  $tAt80 = $null; $tAt100 = $null; $tAt120 = $null; $tAt140 = $null
  $n = [int]($dur / $dt)
  $t = 0.0

  for ($i = 0; $i -lt $n; $i++) {
    $seh = ($slip / (1.0 + $slip * 0.12)) * $streetHeat
    $sehWork = $slip / (1.0 + $slip * 0.12)
    $loadCoeff = $wt * $loadKgTh
    $rel = 0.0

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
    if ($null -eq $tAt140 -and $skin -ge 140.0) { $tAt140 = $t }

    $t += $dt
  }

  $engaged = ($streetHeat -lt 0.995)
  # Plausible: peak within ~2.1x opt or absolute soft ceiling; runaway if still climbing hard past 140
  $overOpt = $peakSkin / [math]::Max(1.0, [double]$comp.tOpt)
  $flag = 'PLAUSIBLE'
  if ($peakSkin -ge 160.0 -or $overOpt -ge 2.4) { $flag = 'RUNAWAY' }
  elseif ($peakSkin -ge 140.0 -or $overOpt -ge 2.0) { $flag = 'HOT' }
  elseif (($null -ne $tAt140) -and (($skin - $skin0) -gt 90.0)) { $flag = 'HOT' }

  return [pscustomobject]@{
    label = $label
    compound = $comp.name
    softCap = -not $DisableSoftCap
    expectSoftCap = [bool]$comp.expectSoftCap
    slip = [math]::Round($slip, 3)
    propNm = [math]::Round($propNm, 0)
    airspeed = [math]::Round($airspeed, 1)
    gMag = [math]::Round($gMag, 2)
    streetHeat = [math]::Round($streetHeat, 3)
    streetProp = [math]::Round($streetProp, 3)
    softCapEngaged = $engaged
    dhgSkin = [math]::Round($dhgSkin, 3)
    netTorque = [math]::Round($netTorque, 2)
    tOpt = [double]$comp.tOpt
    startSkin = [math]::Round($skin0, 1)
    endSkin = [math]::Round($skin, 1)
    peakSkin = [math]::Round($peakSkin, 1)
    endCore = [math]::Round($core, 1)
    peakCore = [math]::Round($peakCore, 1)
    dSkin = [math]::Round($skin - $skin0, 1)
    tAt80 = $tAt80
    tAt100 = $tAt100
    tAt120 = $tAt120
    tAt140 = $tAt140
    flag = $flag
  }
}

# ---- Shared FWD edge kinematics ----
$fwdSlip = SlipEnergyFromLastSlip -lastSlip 20.0
$burnSlip = SlipEnergyFromLastSlip -lastSlip 20.0
$cruiseSlip = 0.08

$scenarios = @(
  @{
    key = 'fwd_hard_accel'
    name = 'FWD hard accel (rolling spin)'
    slip = $fwdSlip; propNm = 1100.0; airspeed = 11.0; gMag = 0.22
    loadRaw = 4400.0; omega = $null; expectEngageEligible = $true
  }
  @{
    key = 'burnout'
    name = 'Stationary burnout'
    slip = $burnSlip; propNm = 1800.0; airspeed = 1.5; gMag = 0.08
    loadRaw = 4200.0; omega = 80.0; expectEngageEligible = $false
  }
  @{
    key = 'cruise'
    name = 'Cruise residual'
    slip = $cruiseSlip; propNm = 350.0; airspeed = 22.0; gMag = 0.10
    loadRaw = 3800.0; omega = $null; expectEngageEligible = $false
  }
)

$compounds = @($street, $sportPlus, $slick, $rallyAsphalt)

$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s) }

Out "=== FWD drive-slip EDGE soft-sim (street / Race slick / sport_plus / rally asphalt) ==="
Out ("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
Out "Live gates: tireScale = radius * static load / 1214. Street slip cap off. Chassis G is not a gate."
Out ("FWD slipE lastSlip=20 -> $([math]::Round($fwdSlip, 3)); cruise slipE=$([math]::Round($cruiseSlip, 3))")
Out "NOTE: sport_plus soft-cap eligible with HeatMin=0.94 PropMin=0.97; slick still excluded."
Out ""

$rows = @()
foreach ($comp in $compounds) {
  foreach ($sc in $scenarios) {
    $pAfter = @{
      comp = $comp; label = "$($comp.name) / $($sc.name)"; dur = 25.0
      slip = $sc.slip; propNm = $sc.propNm; airspeed = $sc.airspeed; gMag = $sc.gMag
      loadRaw = $sc.loadRaw
    }
    if ($null -ne $sc.omega) { $pAfter['omega'] = $sc.omega }
    $after = Simulate-DriveHeat @pAfter

    $pBefore = @{
      comp = $comp; label = "$($comp.name) / $($sc.name) [BEFORE]"; dur = 25.0
      slip = $sc.slip; propNm = $sc.propNm; airspeed = $sc.airspeed; gMag = $sc.gMag
      loadRaw = $sc.loadRaw; DisableSoftCap = $true
    }
    if ($null -ne $sc.omega) { $pBefore['omega'] = $sc.omega }
    $before = Simulate-DriveHeat @pBefore

    $dPeak = $after.peakSkin - $before.peakSkin
    $rows += [pscustomobject]@{
      compound = $comp.name
      scenario = $sc.name
      scenarioKey = $sc.key
      expectSoftCap = [bool]$comp.expectSoftCap
      expectEngageEligible = [bool]$sc.expectEngageEligible
      before = $before
      after = $after
      dPeak = $dPeak
    }
  }
}

function FmtRow([string]$comp, [string]$scen, $pkSk, $pkCo, $enSk, $enCo, $heat, [string]$eng, $dPk, [string]$flag) {
  return (" {0,-14} {1,-30} {2,7:0.0} {3,7:0.0} {4,7:0.0} {5,7:0.0} {6,7:0.000} {7,6} {8,8:0.0} {9,9}" -f `
    $comp, $scen, [double]$pkSk, [double]$pkCo, [double]$enSk, [double]$enCo, [double]$heat, $eng, [double]$dPk, $flag)
}

Out "=== TABLE: compound x scenario (AFTER soft-cap live) ==="
Out (" {0,-14} {1,-30} {2,7} {3,7} {4,7} {5,7} {6,7} {7,6} {8,8} {9,9}" -f `
  "compound", "scenario", "peakSk", "peakCo", "endSk", "endCo", "heatSc", "eng", "dPeak", "flag")
foreach ($r in $rows) {
  $eng = if ($r.after.softCapEngaged) { "YES" } else { "no" }
  Out (FmtRow $r.compound $r.scenario $r.after.peakSkin $r.after.peakCore $r.after.endSkin $r.after.endCore `
    $r.after.streetHeat $eng $r.dPeak $r.after.flag)
}

Out ""
Out "=== BEFORE (scale=1) vs AFTER detail ==="
Out (" {0,-14} {1,-30} {2,8} {3,8} {4,8} {5,8} {6,7} {7,7}" -f `
  "compound", "scenario", "pkB", "pkA", "coB", "coA", "heatSc", "propSc")
foreach ($r in $rows) {
  Out (" {0,-14} {1,-30} {2,8:0.0} {3,8:0.0} {4,8:0.0} {5,8:0.0} {6,7:0.000} {7,7:0.000}" -f `
    $r.compound, $r.scenario,
    [double]$r.before.peakSkin, [double]$r.after.peakSkin,
    [double]$r.before.peakCore, [double]$r.after.peakCore,
    [double]$r.after.streetHeat, [double]$r.after.streetProp)
}

Out ""
Out "=== STREET BASELINE vs EDGE COMPOUNDS (FWD hard accel only) ==="
$streetFwd = $rows | Where-Object { $_.compound -eq "street" -and $_.scenarioKey -eq "fwd_hard_accel" } | Select-Object -First 1
foreach ($name in @("sport_plus", "medium_slick", "rally_asphalt")) {
  $edge = $rows | Where-Object { $_.compound -eq $name -and $_.scenarioKey -eq "fwd_hard_accel" } | Select-Object -First 1
  if ($streetFwd -and $edge) {
    $dVs = $edge.after.peakSkin - $streetFwd.after.peakSkin
    Out (" street peak=$([math]::Round($streetFwd.after.peakSkin,1))C heatSc=$([math]::Round($streetFwd.after.streetHeat,3))  //  $name peak=$([math]::Round($edge.after.peakSkin,1))C heatSc=$([math]::Round($edge.after.streetHeat,3))  (d vs street peak $([math]::Round($dVs,1))C)")
  }
}

Out ""
Out "=== VERDICT CHECKS ==="
$fail = 0

if (-not $streetFwd) {
  Out " FAIL: missing street FWD hard accel row."; $fail++
} elseif ($streetFwd.after.softCapEngaged) {
  Out " FAIL: street FWD hard accel engaged the street slip cap. Live flag is off."; $fail++
} elseif ([math]::Abs($streetFwd.dPeak) -gt 0.05) {
  Out (" FAIL: street FWD peak moved with the cap off ($([math]::Round($streetFwd.dPeak,2))C)."); $fail++
} else {
  Out (" OK: street FWD slip cap off heatSc=$([math]::Round($streetFwd.after.streetHeat,3)) peak=$([math]::Round($streetFwd.after.peakSkin,1))C")
}

$spFwd = $rows | Where-Object { $_.compound -eq "sport_plus" -and $_.scenarioKey -eq "fwd_hard_accel" } | Select-Object -First 1
if (-not $spFwd) {
  Out " FAIL: missing sport_plus FWD hard accel."; $fail++
} elseif ($spFwd.after.softCapEngaged -or ([math]::Abs($spFwd.dPeak) -gt 0.05)) {
  Out " FAIL: sport_plus FWD moved under a cap that is off."; $fail++
} else {
  Out (" OK: sport_plus FWD slip cap off heatSc=$([math]::Round($spFwd.after.streetHeat,3)) peak=$([math]::Round($spFwd.after.peakSkin,1))C")
}
$slSet = $rows | Where-Object { $_.compound -eq "medium_slick" }
$slBad = @($slSet | Where-Object { $_.after.softCapEngaged -or ([math]::Abs($_.dPeak) -gt 0.5) })
if ($slBad.Count -gt 0) {
  $badNames = ($slBad | ForEach-Object { $_.scenario }) -join ", "
  Out " FAIL: medium_slick soft-cap leaked on: $badNames"; $fail++
} else {
  $fwd = $slSet | Where-Object { $_.scenarioKey -eq "fwd_hard_accel" } | Select-Object -First 1
  Out (" OK: medium_slick excluded (FWD peak=$([math]::Round($fwd.after.peakSkin,1))C heatSc=$([math]::Round($fwd.after.streetHeat,3)) flag=$($fwd.after.flag))")
}

# Burnout: no soft-cap on any compound (speed gate)
$burns = $rows | Where-Object { $_.scenarioKey -eq "burnout" }
$burnLeak = @($burns | Where-Object { $_.after.softCapEngaged -or ([math]::Abs($_.dPeak) -gt 2.0) })
if ($burnLeak.Count -gt 0) {
  $leakNames = ($burnLeak | ForEach-Object { $_.compound }) -join ", "
  Out " FAIL: burnout soft-cap leak on: $leakNames"; $fail++
} else {
  Out " OK: stationary burnout unchanged across all compounds (Speed0 gate)"
}

# Cruise: soft-cap should not meaningfully engage (low slip)
$cruises = $rows | Where-Object { $_.scenarioKey -eq "cruise" }
$cruiseBad = @($cruises | Where-Object { $_.after.softCapEngaged })
if ($cruiseBad.Count -gt 0) {
  $cmsg = ($cruiseBad | ForEach-Object { "$($_.compound) heatSc=$([math]::Round($_.after.streetHeat,3))" }) -join "; "
  Out " WARN: cruise soft-cap engaged on: $cmsg"
} else {
  Out " OK: cruise residual soft-cap inactive (low slipEnergy)"
}

# Rally asphalt FWD: Phase 5 purpose pack skips street soft-cap
$rallyFwd = $rows | Where-Object { $_.compound -eq "rally_asphalt" -and $_.scenarioKey -eq "fwd_hard_accel" } | Select-Object -First 1
if ($rallyFwd) {
  if ($rallyFwd.after.softCapEngaged) {
    Out (" FAIL: rally_asphalt FWD soft-cap leaked (Phase 5) heatSc=$([math]::Round($rallyFwd.after.streetHeat,3))"); $fail++
  } else {
    Out (" OK: rally_asphalt FWD soft-cap OFF heatSc=$([math]::Round($rallyFwd.after.streetHeat,3)) peak=$([math]::Round($rallyFwd.after.peakSkin,1))C (purpose=tarmac_rally)")
  }
  if ($rallyFwd.after.flag -eq "RUNAWAY") {
    Out " FAIL: rally_asphalt FWD RUNAWAY."; $fail++
  } elseif ($rallyFwd.after.flag -eq "HOT") {
    Out (" WARN: rally_asphalt FWD still HOT (peak=$([math]::Round($rallyFwd.after.peakSkin,1))C opt=$([math]::Round($rallyFwd.after.tOpt,0))) - review if absurd.")
  } else {
    Out (" OK: rally_asphalt FWD flag=$($rallyFwd.after.flag) peak=$([math]::Round($rallyFwd.after.peakSkin,1))C")
  }
}

# Any RUNAWAY after live soft-cap
$runaways = @($rows | Where-Object { $_.after.flag -eq "RUNAWAY" })
if ($runaways.Count -gt 0) {
  foreach ($x in $runaways) {
    Out (" FAIL: RUNAWAY $($x.compound) / $($x.scenario) peak=$([math]::Round($x.after.peakSkin,1))C")
  }
  $fail += $runaways.Count
}

Out ""
if ($fail -eq 0) {
  Out "OVERALL: PASS - per-tire gates. Street slip cap off. Chassis G is not a heat input."
} else {
  Out "OVERALL: FAIL - $fail check(s) failed."
}

$text = $sb.ToString()
[System.IO.File]::WriteAllText($out, $text)
Write-Host $text
Write-Host "Wrote $out"
if ($fail -gt 0) { exit 1 }
