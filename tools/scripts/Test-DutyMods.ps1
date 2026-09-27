# Light soft-sim: dutyMods gate eligibility (mirrors CalcTyreWear active-only ids).
# Phase 4: soft-cap magnitudes from profile packs; topo keeps enable ramps only.
# Phase 5: purpose selects soft-cap ENABLE pack (street-like ON; circuit/rally/drag/drift OFF).
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'duty-mods-test.txt'
$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s); Write-Host $s }

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
  drivePropCruiseNm = 340.0; drivePropExcessFullNm = 585.0
  drivePropStreetSpeed0 = 78.0; drivePropStreetSpeed1 = 112.0
  driveStreetSlipSpeed0 = 3.5; driveStreetSlipSpeed1 = 14.0
  driveStreetSlipCapStart = 0.16; driveStreetSlipCapFull = 0.52
  driveStreetSlipG0 = 0.32; driveStreetSlipG1 = 0.58
  driveStreetSlipCapEnable = $false
  drivePropDrivenThreshNm = 40.0; drivePropAwdExcessScale = 0.62
  flexWarmLoad0 = 120.0; flexWarmLoad1 = 400.0
  flexWarmSpeed0 = 2.0; flexWarmSpeed1 = 20.0; flexWarmG0 = 0.24
  flexWarmGain = 0.00125
}
# Profile soft-cap packs (mirror Lua DRIVE_SOFTCAP_*)
$SOFTCAP_STREET = @{ driveSlipHeatMin = 0.90; driveSlipPropMin = 0.93; driveHighVCarcassScale = 0.80 }
$SOFTCAP_SPORT_PLUS = @{ driveSlipHeatMin = 0.94; driveSlipPropMin = 0.97; driveHighVCarcassScale = 0.82 }
$SOFTCAP_OFF = @{ driveSlipHeatMin = 1.0; driveSlipPropMin = 1.0; driveHighVCarcassScale = 1.0 }
$STREET_SOFTCAP_PURPOSES = @{
  street = $true; wet = $true; winter = $true; utility = $true; commercial = $true
}
$DUCT_DEFAULT_PCT = 1

function Test-PurposeAllowsStreetSoftcap([string]$purpose) {
  return [bool]$STREET_SOFTCAP_PURPOSES[$purpose]
}

# Returns comma-joined dutyMod ids (same order as live Lua)
function Get-DutyMods([hashtable]$s) {
  $isSlick = [bool]$s.isSlick
  $isSportPlus = [bool]$s.isSportPlus
  $purpose = if ($s.purpose) { [string]$s.purpose } else { 'street' }
  $safeAirspeed = [double]$s.airspeed
  $slipEnergy = [double]$s.slip
  $gMag = [double]$s.gMag
  $propAbs = [double]$s.propNm
  $brakeNm = [double]$s.brakeNm
  $drivenCount = [int]$s.drivenCount
  $loadKg = [double]$s.loadKg
  $contactDepth = [double]$s.contactDepth
  $rough = [double]$s.rough
  $defaultDepth = if ($null -ne $s.defaultDepth) { [double]$s.defaultDepth } else { 0.0 }
  $fluidDensity = if ($null -ne $s.fluidDensity) { [double]$s.fluidDensity } else { 0.0 }
  $strength = if ($null -ne $s.strength) { [double]$s.strength } else { 1.0 }
  $ductPct = [double]$s.ductPct
  $brakeSurfDelta = [double]$s.brakeSurfDelta
  $brakeSoakPower = [double]$s.brakeSoakPower
  $isAirborne = [bool]$s.isAirborne
  $vehNotParked = [bool]$s.vehNotParked

  $mods = if ($isSlick) { $SOFTCAP_OFF } elseif ($isSportPlus) { $SOFTCAP_SPORT_PLUS } else { $SOFTCAP_STREET }
  $cruiseNm = [double]$topo.drivePropCruiseNm
  $slickDriveScale = if ($isSlick) { 0.52 } else { 1.0 }
  $softcapPurposeOk = Test-PurposeAllowsStreetSoftcap $purpose

  $streetCarcassScale = 1.0
  $highVFull = [double]$mods.driveHighVCarcassScale
  if ($softcapPurposeOk -and $highVFull -lt 0.999) {
    $v0 = [double]$topo.drivePropStreetSpeed0
    $v1 = [double]$topo.drivePropStreetSpeed1
    $vRamp = Clamp (($safeAirspeed - $v0) / [math]::Max(1.0, $v1 - $v0)) 0 1
    $streetCarcassScale = 1.0 + (($highVFull - 1.0) * $vRamp)
  }

  $streetSlipHeatScale = 1.0
  $heatMin = [double]$mods.driveSlipHeatMin
  $propMin = [double]$mods.driveSlipPropMin
  if ($topo.driveStreetSlipCapEnable -and $softcapPurposeOk -and $slickDriveScale -ge 0.999 -and $brakeNm -lt 40 -and $propAbs -gt ($cruiseNm * 0.5) `
      -and ($heatMin -lt 0.999 -or $propMin -lt 0.999)) {
    $v0 = [double]$topo.driveStreetSlipSpeed0
    $v1 = [double]$topo.driveStreetSlipSpeed1
    $speedRamp = Smooth01 (Clamp (($safeAirspeed - $v0) / [math]::Max(1.0, $v1 - $v0)) 0 1)
    $s0 = [double]$topo.driveStreetSlipCapStart
    $s1 = [double]$topo.driveStreetSlipCapFull
    $slipRamp = Smooth01 (Clamp (($slipEnergy - $s0) / [math]::Max(1e-3, $s1 - $s0)) 0 1)
    $blend = $speedRamp * $slipRamp
    if ($blend -gt 1e-4) {
      $streetSlipHeatScale = 1.0 + (($heatMin - 1.0) * $blend)
    }
  }

  $excessPropGate = Clamp (($propAbs - $cruiseNm) / [math]::Max(1.0, [double]$topo.drivePropExcessFullNm)) 0 1
  if ($drivenCount -ge 3) {
    $awdT = Clamp (($drivenCount - 2) / 2.0) 0 1
    $awdScale = 1.0 + (([double]$topo.drivePropAwdExcessScale - 1.0) * $awdT)
    $excessPropGate = $excessPropGate * $awdScale
  }

  $flexWarmHeat = 0.0
  if (-not $isAirborne -and $vehNotParked) {
    $flexGate = (Clamp (($loadKg - [double]$topo.flexWarmLoad0) / [math]::Max(1.0, [double]$topo.flexWarmLoad1 - [double]$topo.flexWarmLoad0)) 0 1) *
      (Clamp (($safeAirspeed - [double]$topo.flexWarmSpeed0) / [math]::Max(1.0, [double]$topo.flexWarmSpeed1 - [double]$topo.flexWarmSpeed0)) 0 1) *
      (Clamp ($slipEnergy * 1.8) 0 1)
    if ($flexGate -gt 1e-4) {
      $flexWarmHeat = $flexGate * [double]$topo.flexWarmGain
    }
  }

  $ids = New-Object System.Collections.Generic.List[string]
  if ($streetSlipHeatScale -lt 0.999) {
    if ($isSportPlus) { $ids.Add('sport_plus_slip_softcap') } else { $ids.Add('fwd_slip_softcap') }
  }
  if ($streetCarcassScale -lt 0.999) { $ids.Add('street_high_v_damp') }
  if ($drivenCount -ge 3 -and $excessPropGate -gt 1e-4 -and $propAbs -gt ($cruiseNm * 0.5)) {
    $ids.Add('awd_prop_gate')
  }
  if ($flexWarmHeat -gt 1e-8 -and $propAbs -lt [double]$topo.drivePropDrivenThreshNm) {
    $ids.Add('undriven_warmup')
  }
  if ($brakeSoakPower -gt 0.015 -and $brakeSurfDelta -gt 10) { $ids.Add('brake_tire_soak') }
  if ($ductPct -gt ($DUCT_DEFAULT_PCT + 4)) { $ids.Add('duct_tire_side') }
  if (-not $isAirborne -and ($contactDepth -gt 0.015 -or $rough -gt 0.15 `
      -or $defaultDepth -gt 0.008 -or $fluidDensity -gt 40 -or $strength -lt 0.88)) {
    $ids.Add('soft_sink_damp')
  }

  return ($ids -join ',')
}

function Assert-Duty([string]$name, [hashtable]$scenario, [string]$expect) {
  $got = Get-DutyMods $scenario
  $ok = ($got -eq $expect)
  if ($ok) {
    Out ("PASS  {0}  ->  {1}" -f $name, $(if ($got -eq '') { '(none)' } else { $got }))
  } else {
    Out ("FAIL  {0}" -f $name)
    Out ("       got    {0}" -f $(if ($got -eq '') { '(none)' } else { $got }))
    Out ("       expect {0}" -f $(if ($expect -eq '') { '(none)' } else { $expect }))
  }
  return $ok
}

$base = @{
  isSlick = $false; isSportPlus = $false; purpose = 'street'
  airspeed = 20.0; slip = 0.05; gMag = 0.15
  propNm = 80.0; brakeNm = 0.0; drivenCount = 2; loadKg = 350.0
  contactDepth = 0.0; rough = 0.0; ductPct = 1.0
  brakeSurfDelta = 0.0; brakeSoakPower = 0.0; isAirborne = $false; vehNotParked = $true
}

Out '=== Duty mods active-gate soft-sim ==='
$pass = 0; $fail = 0

# Parked / idle â€” no topology gates
$s = @{} + $base; $s.airspeed = 0.5; $s.propNm = 0; $s.vehNotParked = $false; $s.loadKg = 400
if (Assert-Duty 'idle parked' $s '') { $pass++ } else { $fail++ }

# FWD street hard accel rolling spin â€” soft-cap on
$s = @{} + $base; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400; $s.drivenCount = 2
if (Assert-Duty 'FWD street hard accel' $s '') { $pass++ } else { $fail++ }

# Sport+ same path â€” milder id
$s = @{} + $base; $s.isSportPlus = $true; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400
if (Assert-Duty 'sport_plus hard accel' $s '') { $pass++ } else { $fail++ }

# Slick â€” soft-cap must stay off (slickDriveScale gate)
$s = @{} + $base; $s.isSlick = $true; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400
if (Assert-Duty 'slick hard accel (no soft-cap)' $s '') { $pass++ } else { $fail++ }

# Stationary burnout â€” below Speed0, soft-cap off
$s = @{} + $base; $s.airspeed = 1.0; $s.slip = 0.55; $s.gMag = 0.10; $s.propNm = 500
if (Assert-Duty 'stationary burnout' $s '') { $pass++ } else { $fail++ }

# High-V street prop-hold â€” carcass damp
$s = @{} + $base; $s.airspeed = 100.0; $s.slip = 0.04; $s.gMag = 0.12; $s.propNm = 300
if (Assert-Duty 'street high-V damp' $s 'street_high_v_damp') { $pass++ } else { $fail++ }

# Undriven axle warm-up (rear on FWD under load/speed/g)
$s = @{} + $base; $s.airspeed = 25.0; $s.slip = 0.08; $s.gMag = 0.45; $s.propNm = 5; $s.loadKg = 380
if (Assert-Duty 'undriven warm-up' $s 'undriven_warmup') { $pass++ } else { $fail++ }

# AWD excess prop gate
$s = @{} + $base; $s.airspeed = 30.0; $s.slip = 0.10; $s.gMag = 0.25; $s.propNm = 400; $s.drivenCount = 4
if (Assert-Duty 'AWD prop gate' $s 'awd_prop_gate') { $pass++ } else { $fail++ }

# Brake soak active
$s = @{} + $base; $s.brakeSurfDelta = 40; $s.brakeSoakPower = 0.05; $s.propNm = 0; $s.loadKg = 50
if (Assert-Duty 'brake tire soak' $s 'brake_tire_soak') { $pass++ } else { $fail++ }

# Ducts open
$s = @{} + $base; $s.ductPct = 40; $s.propNm = 0; $s.loadKg = 50
if (Assert-Duty 'duct tire-side' $s 'duct_tire_side') { $pass++ } else { $fail++ }

# Soft sink / rough
$s = @{} + $base; $s.contactDepth = 0.03; $s.propNm = 0; $s.loadKg = 50
if (Assert-Duty 'soft-sink damp' $s 'soft_sink_damp') { $pass++ } else { $fail++ }

# Path A1: soft GM fields alone (asphalt depth/rough quiet)
$s = @{} + $base; $s.contactDepth = 0.0; $s.rough = 0.0; $s.defaultDepth = 0.04; $s.propNm = 0; $s.loadKg = 50
if (Assert-Duty 'soft-sink via GM defaultDepth' $s 'soft_sink_damp') { $pass++ } else { $fail++ }

$s = @{} + $base; $s.contactDepth = 0.0; $s.rough = 0.0; $s.fluidDensity = 800; $s.propNm = 0; $s.loadKg = 50
if (Assert-Duty 'soft-sink via GM fluidDensity' $s 'soft_sink_damp') { $pass++ } else { $fail++ }

# Combined: FWD soft-cap + soft sink
$s = @{} + $base; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400; $s.contactDepth = 0.025
if (Assert-Duty 'FWD soft-cap + soft-sink' $s 'soft_sink_damp') { $pass++ } else { $fail++ }

# Phase 5: purpose packs â€” same physics state, soft-cap only when purpose allows
$s = @{} + $base; $s.purpose = 'tarmac_rally'; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400
if (Assert-Duty 'tarmac_rally hard accel (no street soft-cap)' $s '') { $pass++ } else { $fail++ }

$s = @{} + $base; $s.purpose = 'gravel'; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400
if (Assert-Duty 'gravel hard accel (no street soft-cap)' $s '') { $pass++ } else { $fail++ }

$s = @{} + $base; $s.purpose = 'circuit'; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400
if (Assert-Duty 'circuit purpose (no street soft-cap)' $s '') { $pass++ } else { $fail++ }

$s = @{} + $base; $s.purpose = 'drag'; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400
if (Assert-Duty 'drag purpose (no street soft-cap)' $s '') { $pass++ } else { $fail++ }

$s = @{} + $base; $s.purpose = 'wet'; $s.airspeed = 18.0; $s.slip = 0.40; $s.gMag = 0.20; $s.propNm = 400
if (Assert-Duty 'wet purpose hard accel' $s '') { $pass++ } else { $fail++ }

$s = @{} + $base; $s.purpose = 'tarmac_rally'; $s.airspeed = 100.0; $s.slip = 0.04; $s.gMag = 0.12; $s.propNm = 300
if (Assert-Duty 'tarmac_rally high-V (no street damp)' $s '') { $pass++ } else { $fail++ }

Out ''
Out ("Result: {0} PASS / {1} FAIL" -f $pass, $fail)
[System.IO.File]::WriteAllText($out, $sb.ToString())
if ($fail -gt 0) { exit 1 }
