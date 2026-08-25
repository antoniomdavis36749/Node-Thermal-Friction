# Thermal oddities soft-sim - reproduces spawn cool/rewarm, elevation env swings,
# and carcass>>skin gap. Mirrors CalcTyreWear / initTyreData / updateGFX env path.
# Source: lua/vehicle/extensions/auto/tireWearThermals.lua
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'thermal-oddities-softsim.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# Street / DEFAULT_MODS-like compound (passenger street, opt ~65C)
$compound = @{
  tOpt = 65.0
  slipHeat = 8.925
  workHeat = 5.1
  rollingRes = 0.8
  treadInertia = 0.46
  carcassInertia = 0.75
  react = 1.35
  skinCore = 0.068
  airCool = 0.0275
  staticCool = 0.08
  coreCool = 0.0385
  coreVelCool = 0.0088
  trackCondMult = 1.0
  treadCoef = 0.5
}

$CORE_REACTION_RATE = 0.08
$ASPHALT_CONDUCTIVITY = 1.35
$THERMAL_BOUNDARY = 0.002
$RUBBER_EMISSIVITY = 0.94
$STEFAN = 5.670374e-8
$FREE_BELT_COOL = 1.32
# Live Phase B THERMAL_TOPOLOGY (was 0.09 / 0.140 preâ€“Phase-B)
$PATCH_FRAC_MIN = 0.032
$PATCH_FRAC_HEAT_MIN = 0.022
$PATCH_FRAC_MAX = 0.22
$PATCH_FRAC_REF = 0.068

# Baseline = live knobs BEFORE thermal-oddity fixes
$baseline = @{
  name = 'BASELINE'
  streetPreheatBlend = 0.50
  skinPreheatFrac = 1.00
  spawnConvGraceS = 0.0
  skinCoreScale = 1.00
  skinCoreFloor = 0.0
  carcassCoolVel = 0.18
  carcassCoolStatic = 0.12
  hystSkinShare = 0.0
  envSmoothRate = 2.0
  envMaxDeltaPerSec = 999.0
}

# Proposed / post-fix knobs (must match Lua after implementation)
$fixed = @{
  name = 'FIXED'
  streetPreheatBlend = 0.34
  skinPreheatFrac = 0.55
  spawnConvGraceS = 14.0
  skinCoreScale = 1.85
  skinCoreFloor = 0.070
  carcassCoolVel = 0.28
  carcassCoolStatic = 0.20
  hystSkinShare = 0.21
  envSmoothRate = 0.40
  envMaxDeltaPerSec = 2.5
}

function Get-EffectiveSkinCore([hashtable]$knobs) {
  $raw = [double]$compound.skinCore
  $scaled = $raw * [double]$knobs.skinCoreScale
  return [math]::Max([double]$knobs.skinCoreFloor, $scaled)
}

function Step-Env {
  param(
    [double]$envTemp,
    [double]$rawEnv,
    [double]$dt,
    [hashtable]$knobs
  )
  $blended = $envTemp + ($rawEnv - $envTemp) * [math]::Min(1.0, $dt * [double]$knobs.envSmoothRate)
  $delta = $blended - $envTemp
  $maxStep = [double]$knobs.envMaxDeltaPerSec * $dt
  $delta = Clamp $delta (-$maxStep) $maxStep
  return $envTemp + $delta
}

function Get-TrackTemp([double]$envTemp, [double]$tod = 0.5, [double]$cloud = 0.2, [bool]$forceWet = $false) {
  $solar = [math]::Max(0.0, [math]::Cos(($tod - 0.5) * 2.0 * [math]::PI))
  $cloudScale = Clamp $cloud 0 1
  $solarGain = $solar * (1.0 - $cloudScale * 0.85) * 32.0
  if ($forceWet) {
    return $envTemp + $solarGain * 0.15 - 1.5
  }
  $nightCool = (1.0 - $solar) * 6.0
  return $envTemp + $solarGain - $nightCool
}

function Simulate-Thermal {
  param(
    [hashtable]$knobs,
    [string]$scenario,
    [double]$dur = 60.0,
    [double]$airspeed = 2.0,
    [double]$omega = 6.0,
    [double]$gMag = 0.05,
    [double]$slip = 0.02,
    [double]$loadRaw = 3800.0,
    [double]$propNm = 80.0,
    [double]$startEnv = 21.0,
    [double]$tod = 0.5,
    [double]$cloud = 0.25,
    [double]$skinCoreOverride = -1.0,
    [double]$rollingResOverride = -1.0,
    [scriptblock]$RawEnvAt = $null,
    [scriptblock]$MotionAt = $null, # optional: t -> @{airspeed;omega;gMag;slip;propNm;loadRaw}
    [switch]$NoPreheat,
    [switch]$EnableFlexWarm
  )

  $dt = 0.01
  $tyreW = 0.95
  $tyreWidthM = 0.225
  $tyreRadius = 0.32
  $heatMassScale = 1.0
  $flexModifier = 1.0
  $wt = 1.0   # single-node average (live zone weights sum to 1)
  $pressurePa = 32.0 * 6894.76
  $rollingRes = if ($rollingResOverride -gt 0) { $rollingResOverride } else { [double]$compound.rollingRes }
  $flexWarmGain = 0.00095
  $flexWarmLoad0 = 120.0; $flexWarmLoad1 = 400.0
  $flexWarmSpeed0 = 2.0; $flexWarmSpeed1 = 20.0
  $flexWarmG0 = 0.28

  $env = $startEnv
  $opt = [double]$compound.tOpt
  $blend = [double]$knobs.streetPreheatBlend
  if ($NoPreheat) {
    $skin = $env
    $core = $env
  } else {
    $core = Lerp $env $opt $blend
    $skin = Lerp $env $opt ($blend * [double]$knobs.skinPreheatFrac)
  }

  $skinCoreRaw = if ($skinCoreOverride -gt 0) { $skinCoreOverride } else { [double]$compound.skinCore }
  $skinCore = [math]::Max([double]$knobs.skinCoreFloor, $skinCoreRaw * [double]$knobs.skinCoreScale)
  $condTread = Lerp 2.0 1.0 ([double]$compound.treadCoef)
  $skinCoreEff = $skinCore * $condTread
  $adj = [double]$compound.react / [math]::Max(0.05, [double]$compound.treadInertia)
  $coreRate = $CORE_REACTION_RATE / [math]::Max(0.05, [double]$compound.carcassInertia)

  $curAir = $airspeed; $curOmega = $omega; $curG = $gMag; $curSlip = $slip; $curProp = $propNm; $curLoad = $loadRaw

  $loadKg = $curLoad / 9.81
  $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)

  $estArea = [math]::Max(0.004, [math]::Min($tyreWidthM * 0.24, $curLoad / $pressurePa))
  $patchLen = $estArea / $tyreWidthM
  $patchFracRaw = $patchLen / [math]::Max(0.4, 2.0 * [math]::PI * $tyreRadius)
  $patchFrac = Clamp $patchFracRaw $PATCH_FRAC_MIN $PATCH_FRAC_MAX
  $patchFracHeat = Clamp $patchFracRaw $PATCH_FRAC_HEAT_MIN $PATCH_FRAC_MAX
  $patchHeatScale = Clamp ($patchFracHeat / [math]::Max(0.05, $PATCH_FRAC_REF)) 0.40 1.20
  $freeBeltBias = 1.0 + (1.0 - $patchFrac) * ($FREE_BELT_COOL - 1.0)

  $skin0 = $skin
  $core0 = $core
  $minSkin = $skin
  $tMinSkin = 0.0
  $maxCoreSkinGap = $core - $skin
  $maxAbsSkinDtEnv = 0.0
  $skinAt5 = $null; $skinAt20 = $null; $skinAt60 = $null
  $coreAt5 = $null; $coreAt20 = $null; $coreAt60 = $null
  $rows = New-Object System.Collections.Generic.List[object]
  $n = [int]($dur / $dt)
  $t = 0.0
  $spawnAge = 0.0
  $prevEnv = $env

  for ($i = 0; $i -lt $n; $i++) {
    if ($null -ne $MotionAt) {
      $m = & $MotionAt $t
      $curAir = [double]$m.airspeed
      $curOmega = [double]$m.omega
      $curG = [double]$m.gMag
      $curSlip = [double]$m.slip
      $curProp = [double]$m.propNm
      $curLoad = [double]$m.loadRaw
      $loadKg = $curLoad / 9.81
      $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)
      $estArea = [math]::Max(0.004, [math]::Min($tyreWidthM * 0.24, $curLoad / $pressurePa))
      $patchLen = $estArea / $tyreWidthM
      $patchFracRaw = $patchLen / [math]::Max(0.4, 2.0 * [math]::PI * $tyreRadius)
      $patchFrac = Clamp $patchFracRaw $PATCH_FRAC_MIN $PATCH_FRAC_MAX
      $patchFracHeat = Clamp $patchFracRaw $PATCH_FRAC_HEAT_MIN $PATCH_FRAC_MAX
      $patchHeatScale = Clamp ($patchFracHeat / [math]::Max(0.05, $PATCH_FRAC_REF)) 0.40 1.20
      $freeBeltBias = 1.0 + (1.0 - $patchFrac) * ($FREE_BELT_COOL - 1.0)
    }

    $rawEnv = $env
    if ($null -ne $RawEnvAt) {
      $rawEnv = [double](& $RawEnvAt $t)
    }
    $env = Step-Env -envTemp $env -rawEnv $rawEnv -dt $dt -knobs $knobs
    $envDelta = [math]::Abs($env - $prevEnv)
    $prevEnv = $env
    $forceWet = [bool]($knobs.ContainsKey('forceWetTrack') -and $knobs.forceWetTrack)
    $trackTemp = Get-TrackTemp $env $tod $cloud $forceWet

    $tempDiff = $env - 21.0
    $heatAdapt = Clamp (1.0 - $tempDiff * 0.008) 0.85 1.25
    $coolAdapt = Clamp (1.0 + $tempDiff * 0.010) 0.75 1.30
    $climateScale = Clamp (1.0 + $tempDiff * 0.012) 0.6 1.4
    $airCool = [double]$compound.airCool * $coolAdapt
    $staticCool = [double]$compound.staticCool * $coolAdapt
    $coreCool = [double]$compound.coreCool * $coolAdapt
    $coreVelCool = [double]$compound.coreVelCool * $coolAdapt
    $slipHeat = [double]$compound.slipHeat * $heatAdapt
    $workHeat = [double]$compound.workHeat * $heatAdapt

    $combinedAir = $curAir + $curOmega * $tyreRadius * 0.35
    $effAir = $combinedAir / (1.0 + $combinedAir / 220.0)
    $cornerRetain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $curG - 0.20) * 0.22))

    $convScale = 1.0
    $grace = [double]$knobs.spawnConvGraceS
    if ($grace -gt 0.0 -and $spawnAge -lt $grace) {
      $u = Clamp ($spawnAge / $grace) 0 1
      $u = $u * $u * (3.0 - 2.0 * $u)
      $convScale = Lerp 0.35 1.0 $u
    }

    # P4: mild solarâ†’skin
    $solarAngle = [math]::Max(0.0, [math]::Cos(($tod - 0.5) * 2.0 * [math]::PI))
    $solarSkin = $solarAngle * (1.0 - (Clamp $cloud 0 1) * 0.85) * 0.026 / (1.0 + $curAir * 0.05)

    $seh = $curSlip / (1.0 + $curSlip * 0.12)
    $loadCoeff = $wt * $loadKg
    $gWork = [math]::Max(0.0, $curG - 0.22)
    $rel = $gWork * $loadCoeff / 1000.0
    $vehNotParked = if (($curAir -lt 1.0) -and ($curOmega -lt 0.4)) { 0.0 } else { 1.0 }
    $driveHeatGate = [math]::Min(1.0, ($curSlip * 2.5) + ($curG * 0.45))
    if (($curSlip -lt 0.06) -and ($curG -lt 0.28)) {
      $driveHeatGate = $driveHeatGate * 0.15
    }
    $netTorque = $vehNotParked * [math]::Abs($curProp * 0.041 * $driveHeatGate) * 0.075 * $rollingRes * $flexModifier

    $raw = ($seh * 0.05 + $netTorque * 0.002) * 3.0 * $wt
    $surfMu = 1.05
    $raw = $raw * ([math]::Max($surfMu - 0.5, 0.1) * 2.0)
    $raw = $raw + (((0.0078 * ($seh * $seh) * $loadCoeff) * $slipHeat) +
      (0.145 * $rel * $workHeat / (1.0 + ($seh * $seh)))) * $surfMu / $tyreW
    $gain = ($raw / $heatMassScale) * $patchHeatScale + $solarSkin

    $velCool = [math]::Pow([math]::Max(0.01, $effAir), 0.8) * $airCool * 0.155 * $cornerRetain
    $tempDelta = $skin - $env
    $wetEvap = 0.0
    if ($knobs.ContainsKey('wetEvap') -and $tempDelta -gt 0) { $wetEvap = [double]$knobs.wetEvap }
    $conv = $tempDelta * ($staticCool * 0.04 + $velCool) * $climateScale * $freeBeltBias * $convScale
    if ($tempDelta -gt 0 -and $wetEvap -gt 0) {
      $conv = $conv + $tempDelta * $climateScale * $wetEvap
    }

    $tK = $skin + 273.15
    $eK = $env + 273.15
    $rad = ($RUBBER_EMISSIVITY * $STEFAN * ([math]::Pow($tK, 4) - [math]::Pow($eK, 4))) * 0.0001

    $contactRes = 1.0 / (1.0 + $curSlip * 0.1)
    $condRate = ($ASPHALT_CONDUCTIVITY * [double]$compound.trackCondMult * $estArea * ($skin - $trackTemp) / $THERMAL_BOUNDARY) * $contactRes
    $surfCond = (Clamp ($condRate * 0.003) -25 110) * $wt

    $angHeat = [math]::Abs($curOmega) / (1.0 + [math]::Abs($curOmega) / 90.0)
    $cruiseRR = 1.0
    if (($curSlip -lt 0.08) -and ($curG -lt 0.35)) { $cruiseRR = 0.48 }
    elseif (($curSlip -lt 0.15) -and ($curG -lt 0.55)) { $cruiseRR = 0.72 }
    $hyst = ($loadKg * $angHeat * 0.0000028 * (0.45 * [math]::Exp(-0.5 * [math]::Pow(($skin / [math]::Max(1.0, $opt) - 1.0), 2)) + 0.15) *
      $rollingRes * $cruiseRR) / $heatMassScale
    $hyst = $hyst + ($curProp * $driveHeatGate * $angHeat * 5e-8 * $rollingRes) / $heatMassScale

    $flexWarm = 0.0
    if ($EnableFlexWarm -and $vehNotParked -gt 0) {
      $fg = (Clamp (($loadKg - $flexWarmLoad0) / [math]::Max(1.0, $flexWarmLoad1 - $flexWarmLoad0)) 0 1) *
        (Clamp (($curAir - $flexWarmSpeed0) / [math]::Max(1.0, $flexWarmSpeed1 - $flexWarmSpeed0)) 0 1) *
        (Clamp (([math]::Max(0.0, $curG - $flexWarmG0) / 0.70) + $curSlip * 1.8) 0 1)
      if ($fg -gt 1e-4) {
        $flexWarm = $fg * $flexWarmGain * $loadKg * $angHeat * $rollingRes * $flexModifier / $heatMassScale
      }
    }

    $carcassWork = $hyst + $flexWarm
    $hystToSkin = $carcassWork * [double]$knobs.hystSkinShare
    $toCore = ($core - $skin) * $skinCoreEff
    $skinRate = ($gain + $hystToSkin - $conv - $rad - $surfCond + $toCore) * $adj / $tyreW
    $skin = $skin + $dt * $skinRate

    $fromSkin = ($skin - $core) * $skinCoreEff
    $carcassCoolCoef = ($knobs.carcassCoolVel * $coreVelCool * ([math]::Pow([math]::Max(0.01, $effAir), 0.8) * 0.20) +
      $knobs.carcassCoolStatic * $coreCool) * $climateScale
    $coreCoolAmt = ($core - $env) * $carcassCoolCoef
    $core = $core + $dt * ($fromSkin + $carcassWork * (1.0 - [double]$knobs.hystSkinShare) - $coreCoolAmt) * $coreRate

    if ($skin -gt 400) { $skin = 400 }
    if ($skin -lt -20) { $skin = -20 }
    if ($core -gt 400) { $core = 400 }
    if ($core -lt -20) { $core = -20 }

    $gap = $core - $skin
    if ($gap -gt $maxCoreSkinGap) { $maxCoreSkinGap = $gap }
    if ($skin -lt $minSkin) { $minSkin = $skin; $tMinSkin = $t }
    $dEnvDt = $envDelta / $dt
    if ($dEnvDt -gt 0.5) {
      $absSkinDt = [math]::Abs($skinRate)
      if ($absSkinDt -gt $maxAbsSkinDtEnv) { $maxAbsSkinDtEnv = $absSkinDt }
    }

    if (($null -eq $skinAt5) -and ($t -ge 5.0)) { $skinAt5 = $skin; $coreAt5 = $core }
    if (($null -eq $skinAt20) -and ($t -ge 20.0)) { $skinAt20 = $skin; $coreAt20 = $core }
    if (($null -eq $skinAt60) -and ($t -ge 60.0)) { $skinAt60 = $skin; $coreAt60 = $core }

    $spawnAge += $dt
    $t += $dt
    if (($i % 100) -eq 0 -or $i -eq ($n - 1)) {
      [void]$rows.Add([pscustomobject]@{
        t = [math]::Round($t, 1)
        skin = [math]::Round($skin, 2)
        core = [math]::Round($core, 2)
        gap = [math]::Round($core - $skin, 2)
        env = [math]::Round($env, 2)
        track = [math]::Round($trackTemp, 2)
        convScale = [math]::Round($convScale, 3)
      })
    }
  }

  return [pscustomobject]@{
    scenario = $scenario
    knobs = $knobs.name
    skin0 = [math]::Round($skin0, 2)
    core0 = [math]::Round($core0, 2)
    endSkin = [math]::Round($skin, 2)
    endCore = [math]::Round($core, 2)
    endGap = [math]::Round($core - $skin, 2)
    minSkin = [math]::Round($minSkin, 2)
    tMinSkin = [math]::Round($tMinSkin, 1)
    coolDip = [math]::Round($skin0 - $minSkin, 2)
    rewarm = [math]::Round($skin - $minSkin, 2)
    maxGap = [math]::Round($maxCoreSkinGap, 2)
    skinAt5 = if ($null -ne $skinAt5) { [math]::Round($skinAt5, 2) } else { $null }
    skinAt20 = if ($null -ne $skinAt20) { [math]::Round($skinAt20, 2) } else { $null }
    skinAt60 = if ($null -ne $skinAt60) { [math]::Round($skinAt60, 2) } else { $null }
    coreAt5 = if ($null -ne $coreAt5) { [math]::Round($coreAt5, 2) } else { $null }
    coreAt20 = if ($null -ne $coreAt20) { [math]::Round($coreAt20, 2) } else { $null }
    coreAt60 = if ($null -ne $coreAt60) { [math]::Round($coreAt60, 2) } else { $null }
    maxAbsSkinDtEnv = [math]::Round($maxAbsSkinDtEnv, 3)
    skinCoreEff = [math]::Round($skinCoreEff, 4)
    rows = $rows
  }
}

$sb = New-Object System.Text.StringBuilder
function Out([string]$s) {
  [void]$sb.AppendLine($s)
  Write-Host $s
}

Out 'THERMAL ODDITIES SOFT-SIM'
Out 'Mirrors: street preheat, skin convection (v^0.8*0.155 + freeBelt), carcass RR/hyst,'
Out 'skinCoreConductance*treadScale, env smooth+clamp, trackTemp=env+solar.'
Out ''

$allResults = @()

# ---- Scenario 1: parked cool-down then crawl rewarm (preheat vs convection fight) ----
Out '=== A) SPAWN: parked 0-18s then drive (night track, street preheat) ==='
$spawnMotion = {
  param($t)
  if ($t -lt 18.0) {
    return @{ airspeed = 0.2; omega = 0.2; gMag = 0.02; slip = 0.0; propNm = 0.0; loadRaw = 3800.0 }
  }
  return @{ airspeed = 16.0; omega = 48.0; gMag = 0.35; slip = 0.08; propNm = 320.0; loadRaw = 4200.0 }
}
foreach ($k in @($baseline, $fixed)) {
  $r = Simulate-Thermal -knobs $k -scenario 'spawn_crawl' -dur 60 -startEnv 21 -tod 0.08 -cloud 0.55 `
    -MotionAt $spawnMotion -EnableFlexWarm
  $allResults += $r
  Out ("  [{0}] start skin={1} core={2} | minSkin={3} @{4}s (dip={5} rewarm={6}) | t20 skin={7} core={8} gap={9} | end skin={10} core={11} gap={12}" -f `
    $r.knobs, $r.skin0, $r.core0, $r.minSkin, $r.tMinSkin, $r.coolDip, $r.rewarm, $r.skinAt20, $r.coreAt20, `
    ([math]::Round($r.coreAt20 - $r.skinAt20, 2)), $r.endSkin, $r.endCore, $r.endGap)
}

# ---- Scenario 2: elevation / env step ----
Out ''
Out '=== B) ENV STEP (elevation): +8C at t=10s, -12C at t=30s (60s crawl) ==='
$envScript = {
  param($t)
  if ($t -lt 10.0) { return 21.0 }
  if ($t -lt 30.0) { return 29.0 }
  return 17.0
}
foreach ($k in @($baseline, $fixed)) {
  $r = Simulate-Thermal -knobs $k -scenario 'env_step' -dur 60 -airspeed 8.0 -omega 25.0 `
    -gMag 0.08 -slip 0.03 -loadRaw 3800 -propNm 120 -startEnv 21 -RawEnvAt $envScript
  $allResults += $r
  # Measure skin swing from t=10..15 and t=30..35 via rows
  $row10 = $r.rows | Where-Object { $_.t -ge 10.0 } | Select-Object -First 1
  $row15 = $r.rows | Where-Object { $_.t -ge 15.0 } | Select-Object -First 1
  $row30 = $r.rows | Where-Object { $_.t -ge 30.0 } | Select-Object -First 1
  $row35 = $r.rows | Where-Object { $_.t -ge 35.0 } | Select-Object -First 1
  $upSwing = if ($row10 -and $row15) { [math]::Round($row15.skin - $row10.skin, 2) } else { $null }
  $dnSwing = if ($row30 -and $row35) { [math]::Round($row35.skin - $row30.skin, 2) } else { $null }
  $env10 = if ($row10) { $row10.env } else { '?' }
  $env15 = if ($row15) { $row15.env } else { '?' }
  Out ("  [{0}] env@10={1} @15={2} | skin dT 10-15={3} | skin dT 30-35={4} | max|dSkin/dt| during env move={5}" -f `
    $r.knobs, $env10, $env15, $upSwing, $dnSwing, $r.maxAbsSkinDtEnv)
  $r | Add-Member -NotePropertyName upSwing -NotePropertyValue $upSwing -Force
  $r | Add-Member -NotePropertyName dnSwing -NotePropertyValue $dnSwing -Force
}

# ---- Scenario 3: sustained cornering - flexWarm into carcass + freestream skin cool ----
Out ''
Out '=== C) LOADED CORNER (90s, 28 m/s, 0.75g) low skinCore=0.032 - carcass vs skin ==='
foreach ($k in @($baseline, $fixed)) {
  $r = Simulate-Thermal -knobs $k -scenario 'loaded_drive' -dur 90 -airspeed 28.0 -omega 85.0 `
    -gMag 0.75 -slip 0.14 -loadRaw 5600 -propNm 450 -startEnv 22 -tod 0.45 -cloud 0.2 `
    -skinCoreOverride 0.032 -rollingResOverride 0.95 -NoPreheat -EnableFlexWarm
  $allResults += $r
  Out ("  [{0}] skinCoreEff={1} | t20 skin={2} core={3} gap={4} | end skin={5} core={6} gap={7} | maxGap={8}" -f `
    $r.knobs, $r.skinCoreEff, $r.skinAt20, $r.coreAt20, `
    $(if ($null -ne $r.skinAt20) { [math]::Round($r.coreAt20 - $r.skinAt20, 2) } else { '?' }), `
    $r.endSkin, $r.endCore, $r.endGap, $r.maxGap)
}

# ---- Pass / fail on FIXED vs targets ----
Out ''
Out '=== PASS / FAIL (FIXED knobs) ==='
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
  $script:pass += $(if ($ok) { 1 } else { 0 })
  $script:fail += $(if ($ok) { 0 } else { 1 })
  Out ("  {0} {1}: {2}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail))
}

$spawnB = $allResults | Where-Object { $_.scenario -eq 'spawn_crawl' -and $_.knobs -eq 'BASELINE' } | Select-Object -First 1
$spawnF = $allResults | Where-Object { $_.scenario -eq 'spawn_crawl' -and $_.knobs -eq 'FIXED' } | Select-Object -First 1
$envB = $allResults | Where-Object { $_.scenario -eq 'env_step' -and $_.knobs -eq 'BASELINE' } | Select-Object -First 1
$envF = $allResults | Where-Object { $_.scenario -eq 'env_step' -and $_.knobs -eq 'FIXED' } | Select-Object -First 1
$drvB = $allResults | Where-Object { $_.scenario -eq 'loaded_drive' -and $_.knobs -eq 'BASELINE' } | Select-Object -First 1
$drvF = $allResults | Where-Object { $_.scenario -eq 'loaded_drive' -and $_.knobs -eq 'FIXED' } | Select-Object -First 1

Check 'spawn_cool_dip_reduced' ($spawnF.coolDip -lt ($spawnB.coolDip * 0.65)) `
  ("FIXED dip={0} vs BASELINE {1} (want <65% of baseline)" -f $spawnF.coolDip, $spawnB.coolDip)
Check 'spawn_baseline_shows_fight' (
  ($spawnB.coolDip -gt 5.0) -and (($spawnB.rewarm -gt 1.0) -or (([double]$spawnB.coreAt20 - [double]$spawnB.skinAt20) -gt 5.0))
) ("BASELINE dip={0}C rewarm={1}C gap@20={2}" -f $spawnB.coolDip, $spawnB.rewarm, ([math]::Round($spawnB.coreAt20 - $spawnB.skinAt20, 2)))
Check 'env_up_swing_damped' (
  ($null -ne $envF.upSwing) -and ($null -ne $envB.upSwing) -and ([math]::Abs([double]$envF.upSwing) -lt [math]::Abs([double]$envB.upSwing) * 0.70)
) ("FIXED dSkin 10-15={0} vs BASELINE {1}" -f $envF.upSwing, $envB.upSwing)
Check 'env_dn_swing_damped' (
  ($null -ne $envF.dnSwing) -and ($null -ne $envB.dnSwing) -and ([math]::Abs([double]$envF.dnSwing) -lt [math]::Abs([double]$envB.dnSwing) * 0.70)
) ("FIXED dSkin 30-35={0} vs BASELINE {1}" -f $envF.dnSwing, $envB.dnSwing)
$gapB20 = if ($null -ne $drvB.coreAt20) { [double]$drvB.coreAt20 - [double]$drvB.skinAt20 } else { 0 }
$gapF20 = if ($null -ne $drvF.coreAt20) { [double]$drvF.coreAt20 - [double]$drvF.skinAt20 } else { 0 }
Check 'loaded_gap_reduced' (
  ($gapB20 -gt 8.0) -and ($gapF20 -lt $gapB20 * 0.60)
) ("FIXED gap@20={0} vs BASELINE {1} (want <60%)" -f ([math]::Round($gapF20, 2)), ([math]::Round($gapB20, 2)))
# Live patchFrac + P2 hystSkinShare can put skin ahead of core at t=20; allow mild skin-lead.
Check 'loaded_gap_bounded' (($gapF20 -gt -8.0) -and ($gapF20 -lt 18.0)) `
  ("FIXED gap@20={0}C (want -8 < gap < 18; live patchFrac/hystSkin may skin-lead)" -f ([math]::Round($gapF20, 2)))

# ---- P4: midday park solarâ†’skin vs night; rain evaporative cool ----
Out ""
Out "=== D) MIDDAY PARK solar->skin (60s parked, FIXED) vs night park ==="
$parkMotion = {
  param($t)
  return @{ airspeed = 0.2; omega = 0.15; gMag = 0.02; slip = 0.0; propNm = 0.0; loadRaw = 3800.0 }
}
$sun = Simulate-Thermal -knobs $fixed -scenario 'sun_park' -dur 60 -startEnv 28 -tod 0.5 -cloud 0.05 `
  -MotionAt $parkMotion -NoPreheat -EnableFlexWarm
$night = Simulate-Thermal -knobs $fixed -scenario 'night_park' -dur 60 -startEnv 28 -tod 0.08 -cloud 0.55 `
  -MotionAt $parkMotion -NoPreheat -EnableFlexWarm
$allResults += $sun; $allResults += $night
Out ("  [sun]   endSkin={0} dSkin={1} | [night] endSkin={2} dSkin={3}" -f `
  $sun.endSkin, ([math]::Round($sun.endSkin - $sun.skin0, 2)), $night.endSkin, ([math]::Round($night.endSkin - $night.skin0, 2)))
$sunRise = $sun.endSkin - $sun.skin0
$nightRise = $night.endSkin - $night.skin0
Check 'sun_park_warmer_than_night' (($sunRise -gt ($nightRise + 1.0)) -and ($sunRise -lt 12.0)) `
  ("sun dSkin={0} vs night {1} (want sun>night+1 and sun<12 mild)" -f ([math]::Round($sunRise, 2)), ([math]::Round($nightRise, 2)))

Out ""
Out "=== E) RAIN evaporative cool (crawl, FIXED) vs dry ==="
$fixedDry = $fixed.Clone()
$fixedDry.name = 'FIXED_DRY'
$fixedWet = $fixed.Clone()
$fixedWet.name = 'FIXED_WET'
$fixedWet['wetEvap'] = 0.014
$fixedWet['forceWetTrack'] = $true
$dry = Simulate-Thermal -knobs $fixedDry -scenario 'dry_crawl' -dur 45 -startEnv 22 -tod 0.45 -cloud 0.2 `
  -airspeed 12 -omega 36 -gMag 0.12 -slip 0.04 -propNm 180 -loadRaw 4000 -NoPreheat
$wet = Simulate-Thermal -knobs $fixedWet -scenario 'rain_crawl' -dur 45 -startEnv 22 -tod 0.45 -cloud 0.2 `
  -airspeed 12 -omega 36 -gMag 0.12 -slip 0.04 -propNm 180 -loadRaw 4000 -NoPreheat
$allResults += $dry; $allResults += $wet
Out ("  [dry] endSkin={0} | [wet] endSkin={1} (d={2})" -f $dry.endSkin, $wet.endSkin, ([math]::Round($wet.endSkin - $dry.endSkin, 2)))
Check 'rain_cooler_than_dry' (
  ($wet.endSkin -lt ($dry.endSkin - 0.8)) -and (($dry.endSkin - $wet.endSkin) -lt 12.0)
) ("wet end={0} dry end={1} (want wet cooler by 0.8-12C, not over-cool)" -f $wet.endSkin, $dry.endSkin)

Out ''
Out ("TOTAL: {0} pass, {1} fail" -f $pass, $fail)
Out ''
Out 'FIXED knobs summary (apply to Lua):'
Out ("  STREET_PREHEAT_BLEND={0}  SKIN_PREHEAT_FRAC={1}  SPAWN_CONV_GRACE_S={2}" -f `
  $fixed.streetPreheatBlend, $fixed.skinPreheatFrac, $fixed.spawnConvGraceS)
Out ("  skinCoreScale={0} skinCoreFloor={1} carcassCoolVel/Static={2}/{3} hystSkinShare={4}" -f `
  $fixed.skinCoreScale, $fixed.skinCoreFloor, $fixed.carcassCoolVel, $fixed.carcassCoolStatic, $fixed.hystSkinShare)
Out ("  ENV_SMOOTH_RATE={0} ENV_MAX_DELTA_PER_SEC={1}" -f $fixed.envSmoothRate, $fixed.envMaxDeltaPerSec)

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host ""
Write-Host "Wrote $out"
if ($fail -gt 0) { exit 1 } else { exit 0 }
