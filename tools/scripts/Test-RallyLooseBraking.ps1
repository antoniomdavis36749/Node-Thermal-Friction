# Rally / gravel compound x loose-surface HARD BRAKING soft-sim (60/80/100 mph -> 0).
# Reuses CalcTyreWear post-fix knobs from Test-StraightLineSpeedSweep.ps1 /
# Test-RallyLooseSpeedSweep.ps1 + brake/rim/clog/wear gates from live
# tireWearThermals.lua (driveHeatGate brake open, brake*0.025 netTorque,
# cruiseRR off when |brake|>50, LOCKUP_HEAT_FLOOR, rim soak via brakeGainRate,
# loose surfaceWearScale, rally clog pack*0.55 / clogCoef 0.16).
#
# Scenario: ABS-ish residual brake slip (wheel still rolling) on gravel/dirt/mud;
# elevated long g demand; optional short pre-brake cruise settle then hard stop + soak.
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'rally-loose-braking.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# ---- Live THERMAL_TOPOLOGY + post-fix globals (match RallyLooseSpeedSweep) ----
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
  softVelBoostStart = 8.0; slipVelBoostFull = 24.0; slipVelBoostMax = 9.0
  softSinkHeatCoef = 1.2; softSinkRoughCoef = 0.35; softSinkHeatFloor = 0.72
  softSinkDefaultDepthCoef = 2.2; softSinkStrengthRef = 1.0; softSinkStrengthCoef = 0.40
  softSinkFluidCoef = 0.0007; softSinkStribeckRef = 1.0; softSinkStribeckCoef = 0.035
  gmConductionDefaultDepthCoef = 2.5; gmConductionStrengthCoef = 0.30; gmConductionFluidCoef = 0.0005
}
$SPAWN_CONV_GRACE_S = 14.0
$STREET_PREHEAT_BLEND = 0.34
$SKIN_PREHEAT_FRAC = 0.55
$CORE_REACTION_RATE = 0.08
$THERMAL_BOUNDARY = 0.002
$RUBBER_EMISSIVITY = 0.94
$STEFAN = 5.670374e-8
$LOCKUP_OMEGA_THRESH = 1.0
$LOCKUP_HEAT_FLOOR = 0.22
$TORQUE_ENERGY_MULTIPLIER = 0.25
$RIM_THERMAL_INERTIA = 1.35
$RIM_REACTION_RATE = 0.10
$RIM_CARCASS_CONDUCTANCE = 0.042
$RIM_AIR_CONDUCTANCE = 0.028
$NATIVE_SLIP_VEL_SCALE = 0.0125
$LONG_WEIGHT = 0.55

# STANDALONE_MODIFIERS.rally — soft/medium gravel tread (Test-RallySurfaces / LooseSpeedSweep)
$compounds = @(
  @{
    name = 'rally_gravel_soft'
    isSlick = $false; isRally = $true
    tOpt = 68.0; slipHeat = 9.45; workHeat = 5.1; rollingRes = 1.12
    treadInertia = 0.42; carcassInertia = 0.68; react = 1.65
    skinCore = 0.08; airCool = 0.0275; staticCool = 0.08
    coreCool = 0.035; coreVelCool = 0.008; trackCondMult = 1.0
    airCond = 0.015; brakeGain = 1.05
    wearRate = 0.0006; coldWearMult = 1.83; hotWearMult = 3.04
    treadCoef = 0.55
    tyreWidthM = 0.235; tyreRadius = 0.33; pressurePsi = 28.0
    staticLoadN = 3600.0
    aeroPeakN = 400.0
  }
  @{
    name = 'rally_gravel_medium'
    isSlick = $false; isRally = $true
    tOpt = 68.0; slipHeat = 9.45; workHeat = 5.1; rollingRes = 1.12
    treadInertia = 0.42; carcassInertia = 0.68; react = 1.65
    skinCore = 0.08; airCool = 0.0275; staticCool = 0.08
    coreCool = 0.035; coreVelCool = 0.008; trackCondMult = 1.0
    airCond = 0.015; brakeGain = 1.05
    wearRate = 0.0006; coldWearMult = 1.83; hotWearMult = 3.04
    treadCoef = 0.70
    tyreWidthM = 0.235; tyreRadius = 0.33; pressurePsi = 28.0
    staticLoadN = 3600.0
    aeroPeakN = 400.0
  }
)

# Loose surfaces: same cond/slip residuals as RallyLooseSpeedSweep + brake-specific fields
# brakeSlip = ABS-ish residual slipEnergy during hard stop (wheel rolling, not locked)
# brakeG = long deceleration demand (g); brakeNm = torque/wheel; lastSlipMs for Fix A note
$surfaces = @(
  @{
    name = 'gravel'
    beamMu = 0.75
    condFactor = 0.55; surfTempBlend = 0.55
    contactDepth = 0.025; rough = 0.30
    defaultDepth = 0.020; strength = 0.85; fluidDensity = 0.0
    cruiseSlip = 0.065; cruiseG = 0.12
    brakeSlip = 0.22; brakeG = 0.62; brakeNm = 1100.0; lastSlipMs = 6.5
    # dry gravel: self-clean path (not wet pack)
    packsClog = $false; isMud = $false; isGravel = $true; isDirt = $false
    wearLooseKind = 'gravel'
  }
  @{
    name = 'dirt'
    beamMu = 0.70
    condFactor = 0.55; surfTempBlend = 0.55
    contactDepth = 0.035; rough = 0.40
    defaultDepth = 0.030; strength = 0.75; fluidDensity = 0.0
    cruiseSlip = 0.075; cruiseG = 0.14
    brakeSlip = 0.28; brakeG = 0.55; brakeNm = 980.0; lastSlipMs = 8.5
    packsClog = $true; isMud = $false; isGravel = $false; isDirt = $true
    wearLooseKind = 'dirt'
  }
  @{
    name = 'mud'
    beamMu = 0.50
    condFactor = 0.45; surfTempBlend = 0.0
    contactDepth = 0.060; rough = 0.50
    defaultDepth = 0.050; strength = 0.55; fluidDensity = 900.0
    cruiseSlip = 0.110; cruiseG = 0.16
    brakeSlip = 0.38; brakeG = 0.38; brakeNm = 720.0; lastSlipMs = 12.0
    packsClog = $true; isMud = $true; isGravel = $false; isDirt = $false
    wearLooseKind = 'mud'
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

$speedsMph = @(60, 80, 100)
$PRE_BRAKE_CRUISE_S = 45.0   # short settle before threshold (not full 210s asymptote)
$POST_STOP_SOAK_S = 8.0

function Get-CruisePropNm([double]$vMs) {
  return 40.0 + 0.038 * $vMs * $vMs
}

function SlipEnergyFromLastSlip([double]$lastSlip) {
  $absL = [math]::Abs($lastSlip)
  $longComp = $absL * $NATIVE_SLIP_VEL_SCALE
  $span = [math]::Max(1e-3, [double]$topo.slipVelBoostFull - [double]$topo.slipVelBoostStart)
  $ramp = Clamp (($absL - [double]$topo.slipVelBoostStart) / $span) 0 1
  $ramp = $ramp * $ramp * (3.0 - 2.0 * $ramp)
  $longComp = $longComp * (1.0 + [double]$topo.slipVelBoostMax * $ramp)
  return [math]::Max(0.0, $longComp * $LONG_WEIGHT)
}

function Get-SurfaceWearScale([hashtable]$surf, [double]$tread) {
  $kind = [string]$surf.wearLooseKind
  if ($kind -eq 'mud') { return (Lerp 0.35 0.15 $tread) }
  if ($kind -eq 'gravel') { return (Lerp 1.15 0.70 $tread) }
  # dirt / other loose
  return (Lerp 0.85 0.50 $tread)
}

function Simulate-BrakeStop {
  param(
    [hashtable]$comp,
    [hashtable]$surf,
    [double]$mphStart
  )

  $dt = 0.01
  $tyreRadius = [double]$comp.tyreRadius
  $tyreWidthM = [double]$comp.tyreWidthM
  $tyreW = 0.95
  $wt = 1.0
  $heatMassScale = 1.0
  $flexModifier = 1.0
  $surfMu = [double]$surf.beamMu
  $pressurePa = [double]$comp.pressurePsi * 6894.76
  $contactDepth = [double]$surf.contactDepth
  $rough = [double]$surf.rough
  $gmDefaultDepth = if ($null -ne $surf.defaultDepth) { [double]$surf.defaultDepth } else { 0.0 }
  $gmStrength = if ($null -ne $surf.strength) { [double]$surf.strength } else { 1.0 }
  $gmFluid = if ($null -ne $surf.fluidDensity) { [double]$surf.fluidDensity } else { 0.0 }
  $brakeGain = [double]$comp.brakeGain
  $wearRate = [double]$comp.wearRate
  $tread = [double]$comp.treadCoef
  $surfaceWearScale = Get-SurfaceWearScale $surf $tread

  $env = $ENV_C
  $trackTempSolar = $TRACK_C
  $surfTemp = $env + ($trackTempSolar - $env) * [double]$surf.surfTempBlend
  $blend = $STREET_PREHEAT_BLEND
  $core = Lerp $env ([double]$comp.tOpt) $blend
  $skin = Lerp $env ([double]$comp.tOpt) ($blend * $SKIN_PREHEAT_FRAC)
  $rim = $env + 4.0
  $airCav = $core - 1.0
  $brakeSurf = $env + 18.0
  $brakeCoreT = $env + 12.0
  $clog = 0.0
  $condition = 100.0

  $skinCore = [math]::Max([double]$topo.skinCoreFloor, [double]$comp.skinCore * [double]$topo.skinCoreScale)
  $condTread = Lerp 2.0 1.0 $tread
  $skinCoreEff = $skinCore * $condTread
  $adj = [double]$comp.react / [math]::Max(0.05, [double]$comp.treadInertia)
  $coreRate = $CORE_REACTION_RATE / [math]::Max(0.05, [double]$comp.carcassInertia)
  $rimInertia = $heatMassScale * $RIM_THERMAL_INERTIA * 1.0
  $rimRate = $RIM_REACTION_RATE / [math]::Max(0.05, $rimInertia)

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
  $airCond = [double]$comp.airCond

  $vMs = $mphStart * 0.44704
  $phase = 'cruise'
  $t = 0.0
  $spawnAge = 0.0
  $brakeElapsed = 0.0
  $stopT = $null
  $soakEnd = $null

  $skin0 = $skin; $core0 = $core
  $skinPre = $null; $corePre = $null; $rimPre = $null
  $peakSkin = $skin; $peakCore = $core; $peakRim = $rim
  $peakSkinBrake = -999.0; $peakCoreBrake = -999.0
  $peakBrakeSurf = $brakeSurf
  $maxGap = $core - $skin
  $hadNan = $false; $hitCap = $false
  $wearAccum = 0.0
  $peakClog = 0.0
  $gripAtEnd = 1.0
  $fixEFromLs = SlipEnergyFromLastSlip ([double]$surf.lastSlipMs)

  # Integrate until post-stop soak completes
  $maxT = $PRE_BRAKE_CRUISE_S + 40.0 + $POST_STOP_SOAK_S
  $nMax = [int]($maxT / $dt) + 10

  for ($i = 0; $i -lt $nMax; $i++) {
    # ---- motion state by phase ----
    $slip = 0.0; $gMag = 0.0; $propNm = 0.0; $brakeNm = 0.0
    $airspeed = [math]::Max(0.0, $vMs)
    $omega = if ($tyreRadius -gt 0.05) { $vMs / $tyreRadius } else { 0.0 }

    if ($phase -eq 'cruise') {
      $slip = [double]$surf.cruiseSlip
      $gMag = [double]$surf.cruiseG
      $propNm = Get-CruisePropNm $vMs
      $brakeNm = 0.0
      # idle rotor cool toward ambient during cruise settle
      $brakeSurf = $brakeSurf + $dt * (-($brakeSurf - ($env + 8.0)) * 0.06)
      $brakeCoreT = $brakeCoreT + $dt * (0.03 * ($brakeSurf - $brakeCoreT) - ($brakeCoreT - $env) * 0.02)
      if ($t -ge $PRE_BRAKE_CRUISE_S) {
        $skinPre = $skin; $corePre = $core; $rimPre = $rim
        $phase = 'brake'
        $brakeElapsed = 0.0
      }
    }
    elseif ($phase -eq 'brake') {
      $slip = [double]$surf.brakeSlip
      $gMag = [double]$surf.brakeG
      $propNm = 0.0
      $brakeNm = [double]$surf.brakeNm
      # speed under constant long decel; omega tracks (ABS — not locked)
      $a = -[double]$surf.brakeG * 9.80665
      $vMs = [math]::Max(0.0, $vMs + $a * $dt)
      $airspeed = $vMs
      $omega = if ($tyreRadius -gt 0.05) { $vMs / $tyreRadius } else { 0.0 }
      # slight ABS omega lag at low V (residual slip without full lock)
      if ($vMs -lt 4.0 -and $vMs -gt 0.15) {
        $omega = $omega * 0.92
      }
      $brakeElapsed += $dt
      # Rotor heat soft-proxy (native BeamNG brake thermals not reimplemented).
      # Scale so hard stage stops land ~140–220C surface mid-stop (before soak cool).
      $brakePower = $brakeNm * [math]::Max(0.0, $omega) * 0.00032
      $brakeSurf = $brakeSurf + $dt * ($brakePower - ($brakeSurf - $env) * 0.04)
      if ($brakeSurf -gt 260) { $brakeSurf = 260 }
      $brakeCoreT = $brakeCoreT + $dt * (0.05 * ($brakeSurf - $brakeCoreT) - ($brakeCoreT - $env) * 0.015)
      if ($brakeCoreT -gt 220) { $brakeCoreT = 220 }
      if ($brakeSurf -gt $peakBrakeSurf) { $peakBrakeSurf = $brakeSurf }
      if ($vMs -le 0.25) {
        $vMs = 0.0
        $stopT = $t
        $phase = 'soak'
        $soakEnd = $t + $POST_STOP_SOAK_S
      }
    }
    else {
      # soak: parked, residual heat redistribution
      $slip = 0.02
      $gMag = 0.02
      $propNm = 0.0
      $brakeNm = 0.0
      $vMs = 0.0
      $airspeed = 0.0
      $omega = 0.0
      $brakeSurf = $brakeSurf + $dt * (-($brakeSurf - $env) * 0.05)
      $brakeCoreT = $brakeCoreT + $dt * (0.02 * ($brakeSurf - $brakeCoreT) - ($brakeCoreT - $env) * 0.025)
      if ($null -ne $soakEnd -and $t -ge $soakEnd) { break }
    }

    $propAbs = [math]::Abs($propNm)
    $aeroRamp = Clamp (($airspeed - [double]$topo.aeroHeatSpeedStart) /
      [math]::Max(1.0, [double]$topo.aeroHeatSpeedFull - [double]$topo.aeroHeatSpeedStart)) 0 1
    $aeroN = [double]$comp.aeroPeakN * $aeroRamp
    $loadRaw = [double]$comp.staticLoadN + $aeroN
    # brake transfer bump (~front bias soft-sim): +12% load while braking
    if ($phase -eq 'brake') { $loadRaw = $loadRaw * 1.12 }

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

    # Drive gates — live: brakeTorque > 40 opens gate fully
    $driveHeatGate = [math]::Min(1.0, ($slip * 2.5) + ($gMag * 0.45) + ($(if ($brakeNm -gt 40) { 1.0 } else { 0.0 })))
    if (($slip -lt 0.06) -and ($gMag -lt 0.28) -and ($brakeNm -lt 40)) {
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
    $streetCarcass = 1.0
    $highVFull = if ($null -ne $comp.driveHighVCarcassScale) { [double]$comp.driveHighVCarcassScale } else { 0.28 }
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

    # Live: |prop*skinCoef*gate - brake*0.025|
    $netTorque = [math]::Abs($propNm * [double]$topo.drivePropSkinCoef * $dhgSkin - $brakeNm * 0.025) *
      0.075 * [double]$comp.rollingRes * $flexModifier

    # cruise RR soft-cap OFF when |brake| >= 50 (live)
    $cruiseRR = 1.0
    if (($slip -lt 0.08) -and ($gMag -lt 0.35) -and ($brakeNm -lt 50)) { $cruiseRR = 0.48 }
    elseif (($slip -lt 0.15) -and ($gMag -lt 0.55)) { $cruiseRR = 0.72 }

    $propRrDamp = 1.0
    if (($carcassPropScale -lt 0.999) -and ($excessPropGate -gt 1e-4)) {
      $propRrDamp = 1.0 + ($carcassPropScale - 1.0) * $excessPropGate
    }

    $surfaceConductivity = [double]$surf.condFactor * [double]$comp.trackCondMult

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
    # Phase D + Path A1 soft-sink frictional damp (conduction has separate denom)
    $softExtra = [math]::Max(0.0, $gmDefaultDepth) * [double]$topo.softSinkDefaultDepthCoef `
      + [math]::Max(0.0, 1.0 - $gmStrength / [math]::Max(0.2, [double]$topo.softSinkStrengthRef)) * [double]$topo.softSinkStrengthCoef `
      + [math]::Max(0.0, $gmFluid) * [double]$topo.softSinkFluidCoef
    $sinkDamp = 1.0 / (1.0 + [math]::Max(0.0, $contactDepth) * [double]$topo.softSinkHeatCoef +
      $rough * [double]$topo.softSinkRoughCoef + $softExtra)
    $gain = $gain * [math]::Max([double]$topo.softSinkHeatFloor, $sinkDamp)

    # lockup floor (ABS keeps omega mostly above thresh; near-stop may dip)
    if (($omega -lt $LOCKUP_OMEGA_THRESH) -and ($slip -gt 0.20)) {
      $lockBlend = Clamp ($omega / $LOCKUP_OMEGA_THRESH) 0 1
      $gain = $gain * (Lerp $LOCKUP_HEAT_FLOOR 1.0 $lockBlend)
    }

    $cornerRetain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $gMag - 0.20) * 0.22))
    $velCool = [math]::Pow([math]::Max(0.01, $effAir), 0.8) * $airCool * 0.155 * $cornerRetain
    $tempDelta = $skin - $env
    $conv = $tempDelta * ($staticCool * 0.04 + $velCool) * $climateScale * $freeBeltBias * $convScale

    $tK = $skin + 273.15
    $eK = $env + 273.15
    $rad = ($RUBBER_EMISSIVITY * $STEFAN * ([math]::Pow($tK, 4) - [math]::Pow($eK, 4))) * 0.0001

    $contactRes = 1.0 / (1.0 + $slip * 0.1)
    $condExtra = [math]::Max(0.0, $gmDefaultDepth) * [double]$topo.gmConductionDefaultDepthCoef `
      + [math]::Max(0.0, 1.0 - $gmStrength / [math]::Max(0.2, [double]$topo.softSinkStrengthRef)) * [double]$topo.gmConductionStrengthCoef `
      + [math]::Max(0.0, $gmFluid) * [double]$topo.gmConductionFluidCoef
    $depthRoughDenom = 1.0 + [math]::Max(0.0, $contactDepth) * 4.0 + $rough * 0.5 + $condExtra
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
    # rim -> carcass conduction (live RIM_CARCASS)
    $rimToCarcass = ($rim - $core) * $RIM_CARCASS_CONDUCTANCE
    $toCore = ($core - $skin) * $skinCoreEff
    $skinRate = ($gain + $hystToSkin - $conv - $rad - $surfCond + $toCore) * $adj / $tyreW
    $skin = $skin + $dt * $skinRate

    $fromSkin = ($skin - $core) * $skinCoreEff
    $carcassCoolCoef = ([double]$topo.carcassCoolVel * $coreVelCool *
      ([math]::Pow([math]::Max(0.01, $effAir), 0.8) * 0.20) +
      [double]$topo.carcassCoolStatic * $coreCool) * $climateScale
    $coreCoolAmt = ($core - $env) * $carcassCoolCoef
    $core = $core + $dt * ($fromSkin + $carcassWork * (1.0 - [double]$topo.hystSkinShare) +
      $rimToCarcass - $coreCoolAmt) * $coreRate

    # Rim soak from native brake temps (live: brakeSurfSoak 0.016 / brakeCoreSoak 0.0025,
    # brakeRadiantCoef 2.2e-11, ductSoakCondFactor, brakeAreaScale on BOTH surf+core, rotorSoakMult)
    $brakeAreaScale = 1.0
    $ductSoakCond = 1.15  # ducts closed (stock) → closed conduction factor
    $brakeEffSoak = 1.0
    $rotorSoakMult = 1.0  # steel
    $brakeSurfSoak = 0.016
    $brakeCoreSoak = 0.0025
    $brakeRadiantCoef = 2.2e-11
    $soakCommon = $brakeGain * $ductSoakCond * $brakeAreaScale * $brakeEffSoak * $rotorSoakMult
    $radiantToRim = $brakeRadiantCoef * ([math]::Pow($brakeSurf + 273.15, 4) - [math]::Pow($rim + 273.15, 4)) *
      $brakeGain * $ductSoakCond * $brakeAreaScale * $rotorSoakMult
    $rimCarcassNet = ($core - $rim) * $RIM_CARCASS_CONDUCTANCE * $ductSoakCond
    $rimCool = ($rim - $env) * (0.22 * ([math]::Pow([math]::Max(0.01, $effAir), 0.8) * 0.28) + 0.08) *
      $climateScale * $brakeAreaScale
    $rim = $rim + (
      ($brakeSurfSoak * ($brakeSurf - $rim)) * $soakCommon +
      ($brakeCoreSoak * ($brakeCoreT - $rim)) * $soakCommon +
      $radiantToRim + $rimCarcassNet +
      ($airCav - $rim) * $RIM_AIR_CONDUCTANCE -
      $rimCool
    ) * $rimRate * $dt

    $airCav = $airCav + (
      ($core - $airCav) * $airCond * 4.0 +
      ($rim - $airCav) * $RIM_AIR_CONDUCTANCE * 2.0 -
      ($airCav - $env) * ($airCond * 0.08 * (([double]$comp.pressurePsi + 14.696) / 14.696) *
        (1.0 + [math]::Abs($omega) * 0.006)) * $climateScale
    ) * (1.0 / 0.22) * $dt

    # Wear (simplified single-zone; live slidingWear + brake torque term)
    if ($phase -ne 'soak' -or $slip -gt 0.05) {
      $tempDistW = $skin / [math]::Max(1.0, [double]$comp.tOpt)
      $tempWearPenalty = 1.0
      if ($tempDistW -gt 1.0) {
        $tempWearPenalty = Lerp 1.0 ([double]$comp.hotWearMult) (Clamp ($tempDistW - 1.0) 0 1)
      } elseif ($tempDistW -lt 0.80) {
        $tempWearPenalty = Lerp 1.0 ([double]$comp.coldWearMult) (Clamp ((0.80 - $tempDistW) / 0.50) 0 1)
      }
      $vehMass = 1450.0
      $slidingWear = 20.0 * (($loadRaw / ($vehMass * 9.81)) * $slip * $tempWearPenalty / ($tyreWidthM / 0.2))
      $torqueWear = [math]::Abs($propNm * 0.008 - $brakeNm * 0.025) * 0.3 * $TORQUE_ENERGY_MULTIPLIER * 0.08
      $wear = ($slidingWear + $torqueWear + $omega * 0.0005) * $wearRate * $surfaceWearScale * $dt
      $wearAccum += $wear
      $condition = [math]::Max(0.0, $condition - $wear)
    }

    # Clog pack / clean (live rally *0.55 pack; dry gravel self-cleans)
    $depthPack = [math]::Min(1.5, [math]::Max(0.0, $contactDepth) * 3.0)
    if ([bool]$surf.packsClog) {
      $packRate = (0.35 + $slip * 0.25 + $depthPack) * [math]::Max(0.05, 1.15 - $tread)
      if ([bool]$surf.isMud) { $packRate = $packRate * 1.4 }
      if ([bool]$comp.isRally) { $packRate = $packRate * 0.55 }
      $clog = $clog + $packRate * $dt
    } else {
      $cleanBoost = 2.5  # gravel
      if ([bool]$comp.isRally) { $cleanBoost = $cleanBoost * 1.45 }
      $selfClean = (0.015 + ($omega * $omega) * 0.000004 + $slip * 0.02) *
        (Lerp 0.4 2.5 $tread) * $cleanBoost
      $clog = $clog - $selfClean * $dt * [math]::Max(0.35, 1.0 - $depthPack * 0.4)
    }
    $clog = Clamp $clog 0 1
    if ($clog -gt $peakClog) { $peakClog = $clog }

    # Grip penalty from clog (rally clogCoef 0.16)
    $clogCoef = if ([bool]$comp.isRally) { 0.16 } else { 0.28 }
    $gripAtEnd = 1.0
    if ($clog -gt 0.01) {
      $gripAtEnd = 1.0 - $clog * $clogCoef * (Lerp 1.2 0.6 $tread)
    }

    if ([double]::IsNaN($skin) -or [double]::IsInfinity($skin) -or
        [double]::IsNaN($core) -or [double]::IsInfinity($core) -or
        [double]::IsNaN($rim) -or [double]::IsInfinity($rim)) {
      $hadNan = $true
      break
    }
    if ($skin -ge 399.5 -or $core -ge 399.5 -or $rim -ge 399.5) { $hitCap = $true }
    if ($skin -gt 400) { $skin = 400 }
    if ($skin -lt -20) { $skin = -20 }
    if ($core -gt 400) { $core = 400 }
    if ($core -lt -20) { $core = -20 }
    if ($rim -gt 400) { $rim = 400 }
    if ($rim -lt -20) { $rim = -20 }

    if ($skin -gt $peakSkin) { $peakSkin = $skin }
    if ($core -gt $peakCore) { $peakCore = $core }
    if ($rim -gt $peakRim) { $peakRim = $rim }
    if ($phase -eq 'brake' -or $phase -eq 'soak') {
      if ($skin -gt $peakSkinBrake) { $peakSkinBrake = $skin }
      if ($core -gt $peakCoreBrake) { $peakCoreBrake = $core }
    }
    $gap = $core - $skin
    if ($gap -gt $maxGap) { $maxGap = $gap }

    $spawnAge += $dt
    $t += $dt
  }

  if ($null -eq $skinPre) { $skinPre = $skin0; $corePre = $core0; $rimPre = $rim }
  if ($peakSkinBrake -lt -900) { $peakSkinBrake = $skin; $peakCoreBrake = $core }

  $stopDur = if ($null -ne $stopT) { $stopT - $PRE_BRAKE_CRUISE_S } else { $null }
  $dSkinStop = $peakSkinBrake - $skinPre
  $dCoreStop = $peakCoreBrake - $corePre
  $dRimStop = $peakRim - $rimPre

  return [pscustomobject]@{
    compound = [string]$comp.name
    surface = [string]$surf.name
    mph = [math]::Round($mphStart, 0)
    brakeSlip = [double]$surf.brakeSlip
    brakeG = [double]$surf.brakeG
    brakeNm = [math]::Round([double]$surf.brakeNm, 0)
    lastSlipMs = [double]$surf.lastSlipMs
    slipEFromLs = [math]::Round($fixEFromLs, 3)
    cruiseRROff = $true
    stopDur = if ($null -ne $stopDur) { [math]::Round($stopDur, 2) } else { $null }
    skinPre = [math]::Round($skinPre, 2)
    corePre = [math]::Round($corePre, 2)
    rimPre = [math]::Round($rimPre, 2)
    peakSkin = [math]::Round($peakSkinBrake, 2)
    peakCore = [math]::Round($peakCoreBrake, 2)
    peakRim = [math]::Round($peakRim, 2)
    endSkin = [math]::Round($skin, 2)
    endCore = [math]::Round($core, 2)
    endRim = [math]::Round($rim, 2)
    endBrakeSurf = [math]::Round($brakeSurf, 1)
    peakBrakeSurf = [math]::Round($peakBrakeSurf, 1)
    dSkin = [math]::Round($dSkinStop, 2)
    dCore = [math]::Round($dCoreStop, 2)
    dRim = [math]::Round($dRimStop, 2)
    gapEnd = [math]::Round($core - $skin, 2)
    maxGap = [math]::Round($maxGap, 2)
    wearDelta = [math]::Round($wearAccum, 4)
    condEnd = [math]::Round($condition, 3)
    peakClog = [math]::Round($peakClog * 100, 1)
    endClog = [math]::Round($clog * 100, 1)
    gripMult = [math]::Round($gripAtEnd, 3)
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

Out 'RALLY LOOSE-SURFACE HARD BRAKING SOFT-SIM'
Out 'Compound: STANDALONE_MODIFIERS.rally (soft/medium tread from Test-RallySurfaces)'
Out 'Surfaces: gravel / dirt / mud (cond + cruise residuals from RallyLooseSpeedSweep)'
Out ("Ambient={0:n1}C  solarTrack={1:n1}C (tod={2} cloud={3})" -f $ENV_C, $TRACK_C, $TOD, $CLOUD)
Out ("Pre-brake cruise settle: {0}s @ stage speed  |  Post-stop soak: {1}s" -f $PRE_BRAKE_CRUISE_S, $POST_STOP_SOAK_S)
Out 'Brake scenario: ABS-ish residual slip (omega tracks v; lock floor only if omega<1)'
Out '  live gates: driveHeatGate +=1 if |brake|>40; cruiseRR soft-cap OFF if |brake|>=50;'
Out '  netTorque = |prop*0.066*gate - brake*0.025| * 0.075 * RR; rim soak via brakeGainRate'
Out ''
Out 'Per-surface brake / ABS residuals:'
foreach ($s in $surfaces) {
  $lsE = SlipEnergyFromLastSlip ([double]$s.lastSlipMs)
  Out ('  {0,-8} brakeSlip={1:n3}  g={2:n2}  Nm={3:n0}  lastSlip={4:n1}m/s -> slipE~{5:n3} (Fix A note)' -f `
    $s.name, $s.brakeSlip, $s.brakeG, $s.brakeNm, $s.lastSlipMs, $lsE)
  Out ('           cruise residual slip/g={0:n3}/{1:n2}  cond={2:n2}  depth={3:n3}  packsClog={4}' -f `
    $s.cruiseSlip, $s.cruiseG, $s.condFactor, $s.contactDepth, $s.packsClog)
}
Out 'Knobs: skinCoreScale=1.85 floor=0.070  carcassCoolVel/Static=0.28/0.20  hystSkinShare=0.18'
Out '        rally clog pack*0.55  clogCoef=0.16  brakeGain=1.05'
Out ''

$all = New-Object System.Collections.Generic.List[object]
$total = $compounds.Count * $surfaces.Count * $speedsMph.Count
$done = 0

foreach ($comp in $compounds) {
  foreach ($surf in $surfaces) {
    Out ('=== {0} @ {1} (tOpt={2}C tread={3} brakeSlip={4} g={5} Nm={6}) ===' -f `
      $comp.name, $surf.name, $comp.tOpt, $comp.treadCoef,
      $surf.brakeSlip, $surf.brakeG, $surf.brakeNm)
    $hdr = '{0,5} {1,6} {2,7} {3,7} {4,7} {5,7} {6,6} {7,6} {8,6} {9,7} {10,6} {11,5} {12,6}'
    Out ($hdr -f 'mph', 'tStop', 'skPre', 'pkSkin', 'pkCore', 'endSk', 'dSk', 'dCo', 'dRim', 'wear', 'clog%', 'grip', 'flags')
    Out ('-' * 110)
    foreach ($mph in $speedsMph) {
      $r = Simulate-BrakeStop -comp $comp -surf $surf -mphStart $mph
      [void]$all.Add($r)
      $done++
      $flags = @()
      if ($r.hadNan) { $flags += 'NAN' }
      if ($r.hitCap) { $flags += 'CAP400' }
      if ($r.peakSkin -ge 150 -or $r.peakCore -ge 150) { $flags += 'HOT150+' }
      if ($r.peakSkin -ge 180 -or $r.peakCore -ge 180) { $flags += 'RUNAWAY?' }
      if ($r.maxGap -ge 25) { $flags += 'GAP25+' }
      if ($r.maxGap -ge 40) { $flags += 'CARCASS>>SKIN' }
      if ($r.dSkin -ge 25) { $flags += 'SPIKE25+' }
      if ($r.dSkin -ge 40) { $flags += 'SPIKE40+' }
      if ($r.wearDelta -ge 0.15) { $flags += 'WEAR_SPIKE' }
      if ($r.peakClog -ge 15) { $flags += 'CLOG15+' }
      if ($null -eq $r.stopDur) { $flags += 'NO_STOP' }
      $flagStr = if ($flags.Count -gt 0) { ($flags -join ',') } else { 'ok' }
      $ts = if ($null -ne $r.stopDur) { ('{0:n2}s' -f $r.stopDur) } else { '-' }
      Out ($hdr -f $r.mph, $ts, $r.skinPre, $r.peakSkin, $r.peakCore, $r.endSkin,
        $r.dSkin, $r.dCore, $r.dRim, $r.wearDelta, $r.peakClog, $r.gripMult, $flagStr)
      Write-Host ("  [{0}/{1}]" -f $done, $total) -ForegroundColor DarkGray
    }
    Out ''
  }
}

# ---- Compact tables: surface x speed -> peak skin/core / dSkin / flags ----
Out '=== TABLE: surface x mph -> peakSkin/peakCore (dSkin)  [rally_gravel_medium] ==='
$med = 'rally_gravel_medium'
Out ('{0,5} {1,28} {2,28} {3,28}' -f 'mph', 'gravel', 'dirt', 'mud')
foreach ($mph in $speedsMph) {
  $cells = @()
  foreach ($sn in @('gravel', 'dirt', 'mud')) {
    $r = $all | Where-Object { $_.compound -eq $med -and $_.surface -eq $sn -and $_.mph -eq $mph } | Select-Object -First 1
    $cells += ('{0}/{1} (+{2})' -f $r.peakSkin, $r.peakCore, $r.dSkin)
  }
  Out ('{0,5} {1,28} {2,28} {3,28}' -f $mph, $cells[0], $cells[1], $cells[2])
}
Out ''

Out '=== TABLE: surface x mph -> peakSkin/peakCore (dSkin)  [rally_gravel_soft] ==='
$soft = 'rally_gravel_soft'
Out ('{0,5} {1,28} {2,28} {3,28}' -f 'mph', 'gravel', 'dirt', 'mud')
foreach ($mph in $speedsMph) {
  $cells = @()
  foreach ($sn in @('gravel', 'dirt', 'mud')) {
    $r = $all | Where-Object { $_.compound -eq $soft -and $_.surface -eq $sn -and $_.mph -eq $mph } | Select-Object -First 1
    $cells += ('{0}/{1} (+{2})' -f $r.peakSkin, $r.peakCore, $r.dSkin)
  }
  Out ('{0,5} {1,28} {2,28} {3,28}' -f $mph, $cells[0], $cells[1], $cells[2])
}
Out ''

Out '=== TABLE: surface x mph -> rim peak / dRim / peakBrakeSurf / wear / clog%  [medium] ==='
Out ('{0,5} {1,34} {2,34} {3,34}' -f 'mph', 'gravel', 'dirt', 'mud')
foreach ($mph in $speedsMph) {
  $cells = @()
  foreach ($sn in @('gravel', 'dirt', 'mud')) {
    $r = $all | Where-Object { $_.compound -eq $med -and $_.surface -eq $sn -and $_.mph -eq $mph } | Select-Object -First 1
    $cells += ('rim{0}(+{1}) brk{2} w{3} c{4}' -f $r.peakRim, $r.dRim, $r.peakBrakeSurf, $r.wearDelta, $r.peakClog)
  }
  Out ('{0,5} {1,34} {2,34} {3,34}' -f $mph, $cells[0], $cells[1], $cells[2])
}
Out ''

# ---- Edge analysis + vs cruise ----
Out '=== EDGE-CASE / VERDICT ==='
$nanAny = @($all | Where-Object { $_.hadNan }).Count -gt 0
$capAny = @($all | Where-Object { $_.hitCap }).Count -gt 0
$runaway = @($all | Where-Object { $_.peakSkin -ge 180 -or $_.peakCore -ge 180 }).Count -gt 0
$gapBig = @($all | Where-Object { $_.maxGap -ge 40 }).Count -gt 0
$spike = ($all | Measure-Object -Property dSkin -Maximum).Maximum
$wearMax = ($all | Measure-Object -Property wearDelta -Maximum).Maximum
$clogMax = ($all | Measure-Object -Property peakClog -Maximum).Maximum
Out ("NaN/Inf: {0}" -f $(if ($nanAny) { 'YES — FAIL' } else { 'none' }))
Out ("hit 400C cap: {0}" -f $(if ($capAny) { 'YES' } else { 'no' }))
Out ("temps>=180: {0}" -f $(if ($runaway) { 'YES — RUNAWAY' } else { 'no' }))
Out ("maxGap>=40 (carcass>>skin): {0}" -f $(if ($gapBig) { 'YES' } else { 'no' }))
Out ("max dSkin (brake spike): {0}C" -f $spike)
Out ("max wear delta / peak clog%: {0} / {1}" -f $wearMax, $clogMax)

$verdict = 'PLAUSIBLE'
$notes = @()
if ($nanAny) { $verdict = 'BROKEN'; $notes += 'NaN' }
elseif ($runaway -or $capAny) { $verdict = 'RUNAWAY'; $notes += 'hot>=180 or cap' }
elseif ($spike -ge 40) { $verdict = 'SUSPECT'; $notes += ("skin spike +{0}C" -f $spike) }
elseif ($gapBig) { $verdict = 'SUSPECT'; $notes += 'gap>=40' }
else { $notes += ("max brake dSkin +{0}C; wear max {1}" -f $spike, $wearMax) }
Out ("VERDICT: {0}  [{1}]" -f $verdict, ($notes -join '; '))
Out ''

Out '=== vs RALLY LOOSE CRUISE SWEEP ==='
Out 'Cruise soft-sim (same compounds/surfaces): residual slip warms skin modestly over minutes;'
Out '  RR soft-cap still partially active (0.48-0.72); street high-V carcass damp at extreme mph.'
Out 'Hard braking: cruiseRR OFF (|brake|>=50), driveHeatGate=1, elevated slip + long g,'
Out '  short duration (few seconds) - expect brief skin spike vs cruise asymptote, then soak cool.'
Out '  Rim rises from brake soak (brakeGain=1.05); mud/dirt pack clog (rally*0.55); gravel self-cleans.'
Out '  Note: live dirtGrass/mud pack rates can saturate clog in <10s of continuous contact - expected.'
$ref = $all | Where-Object { $_.compound -eq $med -and $_.surface -eq 'gravel' -and $_.mph -eq 100 } | Select-Object -First 1
$refMud = $all | Where-Object { $_.compound -eq $med -and $_.surface -eq 'mud' -and $_.mph -eq 100 } | Select-Object -First 1
if ($ref) {
  Out ('Medium@gravel 100->0: pre={0}/{1} peak={2}/{3} dSk={4} rimPeak={5}(+{6}) wear={7} stop={8}s' -f `
    $ref.skinPre, $ref.corePre, $ref.peakSkin, $ref.peakCore, $ref.dSkin,
    $ref.peakRim, $ref.dRim, $ref.wearDelta, $ref.stopDur)
}
if ($refMud) {
  Out ('Medium@mud    100->0: pre={0}/{1} peak={2}/{3} dSk={4} clog%={5} grip={6} stop={7}s' -f `
    $refMud.skinPre, $refMud.corePre, $refMud.peakSkin, $refMud.peakCore, $refMud.dSkin,
    $refMud.peakClog, $refMud.gripMult, $refMud.stopDur)
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host ""
Write-Host "Wrote $out"
