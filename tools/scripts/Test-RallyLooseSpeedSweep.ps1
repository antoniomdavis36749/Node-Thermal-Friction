# Rally / gravel compound × loose-surface straight cruise speed sweep (25–200 mph).
# Reuses CalcTyreWear post-fix knobs from Test-StraightLineSpeedSweep.ps1
# (skinCore scale/floor, cruise RR soft-cap, street high-V propRrDamp, aero discount,
# carcass cool, hystSkinShare) + rally STANDALONE mods / loose surface params from
# Test-RallySurfaces.ps1 + live tireWearThermals.lua surface conduction.
#
# Loose surfaces imply higher residual cruise slip/g than asphalt (grip soft-sim /
# RallySurfaces only models μ — thermal soft-sim uses elevated residual slip).
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'rally-loose-speed-sweep.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# ---- Live THERMAL_TOPOLOGY + post-fix globals (match StraightLineSpeedSweep) ----
$topo = @{
  patchFracMin = 0.032; patchFracHeatMin = 0.022; patchFracMax = 0.22; patchFracRef = 0.068
  freeBeltCoolMult = 1.32
  flexWarmGain = 0.00095
  flexWarmLoad0 = 120.0; flexWarmLoad1 = 400.0
  flexWarmSpeed0 = 2.0; flexWarmSpeed1 = 20.0; flexWarmG0 = 0.28
  drivePropCruiseNm = 250.0; drivePropExcessFullNm = 520.0
  drivePropSkinCoef = 0.066
  drivePropHystBase = 5e-8; drivePropHystExcess = 6e-7
  drivePropFlexGateStart = 0.12; drivePropFlexExcess = 0.00054
  drivePropSlipWorkMult = 1.28
  drivePropSlickScale = 0.50; drivePropSlickCarcassScale = 0.30
  drivePropStreetSpeed0 = 78.0; drivePropStreetSpeed1 = 112.0
  aeroHeatScale = 0.55; aeroHeatSpeedStart = 15.0; aeroHeatSpeedFull = 52.0; aeroHeatMaxFrac = 0.48
  skinCoreScale = 1.85; skinCoreFloor = 0.070
  carcassCoolVel = 0.28; carcassCoolStatic = 0.20
  hystSkinShare = 0.18
  softSinkHeatCoef = 1.2; softSinkRoughCoef = 0.35; softSinkHeatFloor = 0.72
  softSinkDefaultDepthCoef = 2.2; softSinkStrengthRef = 1.0; softSinkStrengthCoef = 0.40
  softSinkFluidCoef = 0.0007; softSinkStribeckRef = 1.0; softSinkStribeckCoef = 0.035
  gmConductionDefaultDepthCoef = 2.5; gmConductionStrengthCoef = 0.30; gmConductionFluidCoef = 0.0005
}
$SPAWN_CONV_GRACE_S = 14.0
$STREET_PREHEAT_BLEND = 0.34
$SKIN_PREHEAT_FRAC = 0.55
$CORE_REACTION_RATE = 0.08
$ASPHALT_CONDUCTIVITY = 1.35
$THERMAL_BOUNDARY = 0.002
$RUBBER_EMISSIVITY = 0.94
$STEFAN = 5.670374e-8

# STANDALONE_MODIFIERS.rally (live) — tread spans soft→medium gravel from Test-RallySurfaces
$compounds = @(
  @{
    name = 'rally_gravel_soft'
    isSlick = $false
    tOpt = 68.0; slipHeat = 9.45; workHeat = 5.1; rollingRes = 1.12
    treadInertia = 0.42; carcassInertia = 0.68; react = 1.65
    skinCore = 0.08; airCool = 0.0275; staticCool = 0.08
    coreCool = 0.035; coreVelCool = 0.008; trackCondMult = 1.0
    treadCoef = 0.55
    tyreWidthM = 0.235; tyreRadius = 0.33; pressurePsi = 28.0
    staticLoadN = 3600.0
    aeroPeakN = 400.0   # mild rally aero / body
    driveSlipHeatMin = 0.40; driveSlipPropMin = 0.62; driveHighVCarcassScale = 0.28
  }
  @{
    name = 'rally_gravel_medium'
    isSlick = $false
    tOpt = 68.0; slipHeat = 9.45; workHeat = 5.1; rollingRes = 1.12
    treadInertia = 0.42; carcassInertia = 0.68; react = 1.65
    skinCore = 0.08; airCool = 0.0275; staticCool = 0.08
    coreCool = 0.035; coreVelCool = 0.008; trackCondMult = 1.0
    treadCoef = 0.70
    tyreWidthM = 0.235; tyreRadius = 0.33; pressurePsi = 28.0
    staticLoadN = 3600.0
    aeroPeakN = 400.0
    driveSlipHeatMin = 0.40; driveSlipPropMin = 0.62; driveHighVCarcassScale = 0.28
  }
)

# Loose surfaces: live fillSurfaceFlags.loose + conduction branches in CalcTyreWear
# residual slip/g: elevated vs asphalt cruise (0.025 / 0.06) — loose needs more slip to hold speed
$surfaces = @(
  @{
    name = 'gravel'
    beamMu = 0.75
    # live: gravel → conductivity 0.55, surfaceTemp = env + (track-env)*0.55
    condFactor = 0.55; surfTempBlend = 0.55
    contactDepth = 0.025; rough = 0.30
    cruiseSlip = 0.065; cruiseG = 0.12
  }
  @{
    name = 'dirt'
    beamMu = 0.70
    # live: dirtGrass → same 0.55 branch as gravel
    condFactor = 0.55; surfTempBlend = 0.55
    contactDepth = 0.035; rough = 0.40
    cruiseSlip = 0.075; cruiseG = 0.14
  }
  @{
    name = 'mud'
    beamMu = 0.50
    # live: mud → conductivity 0.45, surfaceTemp = env
    condFactor = 0.45; surfTempBlend = 0.0
    contactDepth = 0.060; rough = 0.50
    cruiseSlip = 0.110; cruiseG = 0.16
  }
)

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

$speedsMph = @(25, 40, 60, 80, 100, 120, 150, 180, 200)

function Get-CruisePropNm([double]$vMs) {
  # Same aero/RR hold as asphalt sweep; loose may need a bit more — mild bump via slip path not prop
  return 40.0 + 0.038 * $vMs * $vMs
}

function Simulate-Cruise {
  param(
    [hashtable]$comp,
    [hashtable]$surf,
    [double]$mph,
    [double]$dur = 210.0,
    [double]$eqRate = 0.015,
    [double]$eqHold = 4.0
  )

  $dt = 0.01
  $vMs = $mph * 0.44704
  $tyreRadius = [double]$comp.tyreRadius
  $tyreWidthM = [double]$comp.tyreWidthM
  $omega = $vMs / [math]::Max(0.05, $tyreRadius)
  $airspeed = $vMs
  $slip = [double]$surf.cruiseSlip
  $gMag = [double]$surf.cruiseG
  $propNm = Get-CruisePropNm $vMs
  $propAbs = [math]::Abs($propNm)

  $aeroRamp = Clamp (($airspeed - [double]$topo.aeroHeatSpeedStart) /
    [math]::Max(1.0, [double]$topo.aeroHeatSpeedFull - [double]$topo.aeroHeatSpeedStart)) 0 1
  $aeroN = [double]$comp.aeroPeakN * $aeroRamp
  $loadRaw = [double]$comp.staticLoadN + $aeroN

  $tyreW = 0.95
  $wt = 1.0
  $heatMassScale = 1.0
  $flexModifier = 1.0
  $surfMu = [double]$surf.beamMu
  $pressurePa = [double]$comp.pressurePsi * 6894.76
  $contactDepth = [double]$surf.contactDepth
  $rough = [double]$surf.rough

  $env = $ENV_C
  $trackTempSolar = $TRACK_C
  # Live surfaceTemp blend for loose
  $surfTemp = $env + ($trackTempSolar - $env) * [double]$surf.surfTempBlend
  $blend = $STREET_PREHEAT_BLEND
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
  $loadKgTh = $loadKg
  if ($aeroRamp -gt 0.0) {
    $loadKgTh = $loadKg * (1.0 - $aeroRamp * [double]$topo.aeroHeatMaxFrac * (1.0 - [double]$topo.aeroHeatScale))
  }

  $estArea = [math]::Max(0.004, [math]::Min($tyreWidthM * 0.24, $loadRaw / $pressurePa))
  # Soft sink: conduction denom only — no area-shrink (live parity)
  $patchLen = $estArea / $tyreWidthM
  $patchFracRaw = $patchLen / [math]::Max(0.4, 2.0 * [math]::PI * $tyreRadius)
  $patchFrac = Clamp $patchFracRaw ([double]$topo.patchFracMin) ([double]$topo.patchFracMax)
  $patchFracHeat = Clamp $patchFracRaw ([double]$topo.patchFracHeatMin) ([double]$topo.patchFracMax)
  $patchHeatScale = Clamp ($patchFracHeat / [math]::Max(0.05, [double]$topo.patchFracRef)) 0.40 1.20
  $freeBeltBias = 1.0 + (1.0 - $patchFrac) * ([double]$topo.freeBeltCoolMult - 1.0)

  $combinedAir = $airspeed + $omega * $tyreRadius * 0.35
  $effAir = $combinedAir / (1.0 + $combinedAir / 220.0)

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

  # Drive gates (straight cruise choke + excess prop) — match live / asphalt sweep
  $driveHeatGate = [math]::Min(1.0, ($slip * 2.5) + ($gMag * 0.45))
  if (($slip -lt 0.06) -and ($gMag -lt 0.28)) {
    $halfCruise = [double]$topo.drivePropCruiseNm * 0.5
    if ($propAbs -gt $halfCruise) {
      $driveHeatGate = $driveHeatGate * (0.15 + 0.85 * (Clamp (($propAbs - $halfCruise) / [math]::Max(1.0, $halfCruise)) 0 1))
    } else {
      $driveHeatGate = $driveHeatGate * 0.15
    }
  }
  # Loose residual slip often >= 0.06 → cruise choke may not fully apply (intentional)

  $excessPropGate = Clamp (($propAbs - [double]$topo.drivePropCruiseNm) /
    [math]::Max(1.0, [double]$topo.drivePropExcessFullNm)) 0 1
  $slickDrive = 1.0; $slickCarcass = 1.0
  # Rally is non-slick → street high-V carcass damp from profile pack
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
  if (($slip -lt 0.08) -and ($gMag -lt 0.35)) { $cruiseRR = 0.48 }
  elseif (($slip -lt 0.15) -and ($gMag -lt 0.55)) { $cruiseRR = 0.72 }
  # mud/dirt often land in 0.72 soft-cap band (slip 0.08–0.15)

  $propRrDamp = 1.0
  if (($carcassPropScale -lt 0.999) -and ($excessPropGate -gt 1e-4)) {
    $propRrDamp = 1.0 + ($carcassPropScale - 1.0) * $excessPropGate
  }

  $surfaceConductivity = [double]$surf.condFactor * [double]$comp.trackCondMult
  # Note: live uses ASPHALT_CONDUCTIVITY * mult for paved; loose replaces with absolute factors
  # (0.55 etc. are absolute W-scale, not * ASPHALT_CONDUCTIVITY)

  $peakSkin = $skin; $peakCore = $core
  $maxGap = $core - $skin
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
    $gWork = [math]::Max(0.0, $gMag - 0.22)
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

    $cornerRetain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $gMag - 0.20) * 0.22))
    $velCool = [math]::Pow([math]::Max(0.01, $effAir), 0.8) * $airCool * 0.155 * $cornerRetain
    $tempDelta = $skin - $env
    $conv = $tempDelta * ($staticCool * 0.04 + $velCool) * $climateScale * $freeBeltBias * $convScale

    $tK = $skin + 273.15
    $eK = $env + 273.15
    $rad = ($RUBBER_EMISSIVITY * $STEFAN * ([math]::Pow($tK, 4) - [math]::Pow($eK, 4))) * 0.0001

    $contactRes = 1.0 / (1.0 + $slip * 0.1)
    $depthRoughDenom = 1.0 + [math]::Max(0.0, $contactDepth) * 4.0 + $rough * 0.5
    $condRate = ($surfaceConductivity * $estArea * ($skin - $surfTemp) / $THERMAL_BOUNDARY) *
      $contactRes / $depthRoughDenom
    $surfCond = (Clamp ($condRate * 0.003) -25 110) * $wt

    $angHeat = [math]::Abs($omega) / (1.0 + [math]::Abs($omega) / 90.0)
    $hyst = ($loadKgTh * $angHeat * 0.0000028 *
      (0.45 * [math]::Exp(-0.5 * [math]::Pow(($skin / [math]::Max(1.0, [double]$comp.tOpt) - 1.0), 2)) + 0.15) *
      [double]$comp.rollingRes * $cruiseRR * $propRrDamp) / $heatMassScale
    $hystCoef = [double]$topo.drivePropHystBase +
      ([double]$topo.drivePropHystExcess - [double]$topo.drivePropHystBase) * $excessCarcass
    $hyst = $hyst + ($propAbs * $dhgCarcass * $angHeat * $hystCoef * [double]$comp.rollingRes) / $heatMassScale

    $flexWarm = 0.0
    $flexGate = (Clamp (($loadKg - [double]$topo.flexWarmLoad0) /
        [math]::Max(1.0, [double]$topo.flexWarmLoad1 - [double]$topo.flexWarmLoad0)) 0 1) *
      (Clamp (($airspeed - [double]$topo.flexWarmSpeed0) /
        [math]::Max(1.0, [double]$topo.flexWarmSpeed1 - [double]$topo.flexWarmSpeed0)) 0 1) *
      (Clamp (([math]::Max(0.0, $gMag - [double]$topo.flexWarmG0) / 0.70) + $slip * 1.8) 0 1)
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
    if ($settled -and $t -ge [math]::Max(60.0, [double]$settleT + 2.0)) { break }
  }

  return [pscustomobject]@{
    compound = [string]$comp.name
    surface = [string]$surf.name
    mph = [math]::Round($mph, 0)
    vMs = [math]::Round($vMs, 1)
    slip = $slip
    gMag = $gMag
    cruiseRR = $cruiseRR
    propNm = [math]::Round($propNm, 0)
    excessGate = [math]::Round($excessPropGate, 3)
    surfMu = $surfMu
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

Out 'RALLY LOOSE-SURFACE SPEED SWEEP SOFT-SIM'
Out 'Compound: STANDALONE_MODIFIERS.rally (soft/medium tread from Test-RallySurfaces)'
Out 'Surfaces: gravel / dirt / mud (live loose flags + conduction factors)'
Out ("Ambient={0:n1}C  solarTrack={1:n1}C (tod={2} cloud={3})" -f $ENV_C, $TRACK_C, $TOD, $CLOUD)
Out 'Residual cruise slip/g (elevated vs asphalt 0.025/0.06):'
foreach ($s in $surfaces) {
  Out ('  {0,-8} slip={1:n3}  g={2:n2}  beamMu={3:n2}  cond={4:n2}  depth={5:n3}  RR soft-cap band via slip' -f `
    $s.name, $s.cruiseSlip, $s.cruiseG, $s.beamMu, $s.condFactor, $s.contactDepth)
}
Out 'Settle: up to 210s or |dT/dt| sum < 0.015 C/s for 4s (after spawn grace)'
Out 'Knobs: skinCoreScale=1.85 floor=0.070  carcassCoolVel/Static=0.28/0.20  hystSkinShare=0.18'
Out '        streetCarcass damp: 78-112 m/s -> scale 0.28 (non-slick excess-prop / propRrDamp)'
Out 'Prop: Nm/wheel = 40 + 0.038*v^2'
Out ''

$all = New-Object System.Collections.Generic.List[object]
$total = $compounds.Count * $surfaces.Count * $speedsMph.Count
$done = 0

foreach ($comp in $compounds) {
  foreach ($surf in $surfaces) {
    Out ('=== {0} @ {1} (tOpt={2}C RR={3} tread={4} slip={5} g={6}) ===' -f `
      $comp.name, $surf.name, $comp.tOpt, $comp.rollingRes, $comp.treadCoef,
      $surf.cruiseSlip, $surf.cruiseG)
    $hdr = '{0,5} {1,6} {2,6} {3,5} {4,7} {5,7} {6,6} {7,6} {8,6} {9,7} {10,6} {11,5}'
    Out ($hdr -f 'mph', 'v_m/s', 'prop', 'exG', 'skin', 'core', 'dSk', 'dCo', 'gap', 'settle', 'simT', 'flags')
    Out ('-' * 98)
    foreach ($mph in $speedsMph) {
      $r = Simulate-Cruise -comp $comp -surf $surf -mph $mph
      [void]$all.Add($r)
      $done++
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
      Out ($hdr -f $r.mph, $r.vMs, $r.propNm, $r.excessGate, $r.endSkin, $r.endCore,
        $r.dSkin, $r.dCore, $r.gap, $st, $r.simT, $flagStr)
      Write-Host ("  [{0}/{1}]" -f $done, $total) -ForegroundColor DarkGray
    }
    Out ''
  }
}

# ---- Edge-case analysis ----
Out '=== EDGE-CASE ANALYSIS ==='
foreach ($comp in $compounds) {
  foreach ($surf in $surfaces) {
    $rows = @($all | Where-Object { $_.compound -eq $comp.name -and $_.surface -eq $surf.name } | Sort-Object mph)
    $key = '{0}@{1}' -f $comp.name, $surf.name
    Out ("--- {0} ---" -f $key)

    $nonMono = @()
    for ($i = 1; $i -lt $rows.Count; $i++) {
      $d = [double]$rows[$i].endSkin - [double]$rows[$i - 1].endSkin
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
      Out '  monotonicity: OK (no sharp drop >3C or jump >25C)'
    } else {
      foreach ($m in $nonMono) { Out ("  NON-MONO: {0}" -f $m) }
    }

    $nanAny = @($rows | Where-Object { $_.hadNan }).Count -gt 0
    $capAny = @($rows | Where-Object { $_.hitCap }).Count -gt 0
    $coolAmb = @($rows | Where-Object { $_.mph -ge 60 -and $_.endSkin -le ($ENV_C + 0.8) }).Count
    $gapMax = ($rows | Measure-Object -Property gap -Maximum).Maximum
    $skinMax = ($rows | Measure-Object -Property endSkin -Maximum).Maximum
    $coreMax = ($rows | Measure-Object -Property endCore -Maximum).Maximum
    $r25 = $rows | Where-Object { $_.mph -eq 25 } | Select-Object -First 1
    $r100 = $rows | Where-Object { $_.mph -eq 100 } | Select-Object -First 1
    $r200 = $rows | Where-Object { $_.mph -eq 200 } | Select-Object -First 1

    Out ("  NaN/Inf: {0}" -f $(if ($nanAny) { 'YES — FAIL' } else { 'none' }))
    Out ("  hit 400C cap: {0}" -f $(if ($capAny) { 'YES — RUNAWAY' } else { 'no' }))
    Out ("  cool-to-ambient @>=60mph: {0} points" -f $coolAmb)
    Out ("  max gap (core-skin): {0}C" -f $gapMax)
    Out ("  max end skin/core: {0} / {1} C" -f $skinMax, $coreMax)
    if ($r25 -and $r100 -and $r200) {
      Out ("  25mph  skin={0} core={1} gap={2}" -f $r25.endSkin, $r25.endCore, $r25.gap)
      Out ("  100mph skin={0} core={1} gap={2}  (+{3}/{4} vs 25)" -f `
        $r100.endSkin, $r100.endCore, $r100.gap,
        [math]::Round($r100.endSkin - $r25.endSkin, 1),
        [math]::Round($r100.endCore - $r25.endCore, 1))
      Out ("  200mph skin={0} core={1} gap={2}  (+{3}/{4} vs 100)" -f `
        $r200.endSkin, $r200.endCore, $r200.gap,
        [math]::Round($r200.endSkin - $r100.endSkin, 1),
        [math]::Round($r200.endCore - $r100.endCore, 1))
    }

    $runaway = $false; $overcool = $false; $gapExplode = $false
    foreach ($b in $rows) {
      if ($b.hitCap -or $b.endSkin -ge 180 -or $b.endCore -ge 180) { $runaway = $true }
      if ($b.mph -ge 60 -and $b.endSkin -le ($ENV_C + 0.8)) { $overcool = $true }
      if ($b.gap -ge 40) { $gapExplode = $true }
    }
    $rise = if ($r25 -and $r200) { [double]$r200.endSkin - [double]$r25.endSkin } else { 0 }
    $steep = $rise -gt 50
    $verdict = 'PLAUSIBLE'
    $notes = @()
    if ($nanAny) { $verdict = 'BROKEN'; $notes += 'NaN/Inf' }
    elseif ($runaway) { $verdict = 'RUNAWAY'; $notes += 'temps>=180 or cap' }
    elseif ($steep) { $verdict = 'SUSPECT'; $notes += ("+{0}C skin 25->200" -f [math]::Round($rise, 1)) }
    elseif ($overcool) { $verdict = 'OVERCOOL'; $notes += 'skin≈ambient at cruise' }
    elseif ($gapExplode) { $verdict = 'SUSPECT'; $notes += 'gap>=40C' }
    else { $notes += ("skin 25->200 = +{0}C" -f [math]::Round($rise, 1)) }
    Out ("  VERDICT: {0}  [{1}]" -f $verdict, ($notes -join '; '))
    Out ''
  }
}

# ---- Compact cross tables ----
Out '=== TABLE: surface x mph -> skin / carcass (rally_gravel_medium) ==='
$med = 'rally_gravel_medium'
Out ('{0,5} {1,16} {2,16} {3,16}' -f 'mph', 'gravel', 'dirt', 'mud')
foreach ($mph in $speedsMph) {
  $cells = @()
  foreach ($sn in @('gravel', 'dirt', 'mud')) {
    $r = $all | Where-Object { $_.compound -eq $med -and $_.surface -eq $sn -and $_.mph -eq $mph } | Select-Object -First 1
    $cells += ('{0}/{1}' -f $r.endSkin, $r.endCore)
  }
  Out ('{0,5} {1,16} {2,16} {3,16}' -f $mph, $cells[0], $cells[1], $cells[2])
}
Out ''

Out '=== TABLE: surface x mph -> skin / carcass (rally_gravel_soft) ==='
$soft = 'rally_gravel_soft'
Out ('{0,5} {1,16} {2,16} {3,16}' -f 'mph', 'gravel', 'dirt', 'mud')
foreach ($mph in $speedsMph) {
  $cells = @()
  foreach ($sn in @('gravel', 'dirt', 'mud')) {
    $r = $all | Where-Object { $_.compound -eq $soft -and $_.surface -eq $sn -and $_.mph -eq $mph } | Select-Object -First 1
    $cells += ('{0}/{1}' -f $r.endSkin, $r.endCore)
  }
  Out ('{0,5} {1,16} {2,16} {3,16}' -f $mph, $cells[0], $cells[1], $cells[2])
}
Out ''

# Verdict vs asphalt street sweep (from tools/output/straight-line-speed-sweep.txt reference)
Out '=== vs ASPHALT STREET SWEEP (street compound, slip=0.025 g=0.06) ==='
Out 'Reference street asphalt (prior soft-sim): ~31-35C skin / ~34-36C core across 25-200 mph'
Out 'Rally loose: warmer from residual slip + weaker surface conduction (0.45-0.55 vs asphalt 1.35),'
Out '  tempered by lower beamMu on friction heat; RR soft-cap still partially active (0.48-0.72).'
Out 'Note: many loose cases flag UNSETTLED at 210s (slow carcass asymptote); end temps are still usable.'
$ref = $all | Where-Object { $_.compound -eq $med -and $_.surface -eq 'gravel' -and $_.mph -eq 100 } | Select-Object -First 1
$ref200 = $all | Where-Object { $_.compound -eq $med -and $_.surface -eq 'gravel' -and $_.mph -eq 200 } | Select-Object -First 1
if ($ref -and $ref200) {
  Out ('Rally medium @ gravel 100mph: skin={0} core={1} (street asphalt ~32.9/36.1)' -f $ref.endSkin, $ref.endCore)
  Out ('Rally medium @ gravel 200mph: skin={0} core={1} (street asphalt ~31.5/36.1)' -f $ref200.endSkin, $ref200.endCore)
  $d100 = [math]::Round($ref.endSkin - 32.86, 1)
  $d200 = [math]::Round($ref200.endSkin - 31.53, 1)
  Out ('Delta skin vs street asphalt: 100mph {0:+0.0;-0.0}C  200mph {1:+0.0;-0.0}C' -f $d100, $d200)
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host ""
Write-Host "Wrote $out"
