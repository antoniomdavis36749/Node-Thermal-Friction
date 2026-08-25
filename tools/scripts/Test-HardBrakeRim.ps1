#Requires -Version 5.1
<#
  Soft-sim: hard-brake → rim rise (tire-side soak only).
  Mirrors live tireWearThermals.lua rim node:
    brakeSurfSoak 0.016 / brakeCoreSoak 0.0025 / brakeRadiantCoef 2.2e-11
    ductAirCoolFactor / ductSoakCondFactor / brakeAreaScale / rotorSoakMult
  Rotor temps are a soft-proxy INPUT (native owns real rotors — not reimplemented).
  Sweeps: duct closed vs open; steel vs carbon; high vs low brakeGainRate.
#>
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'hard-brake-rim.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# Live THERMAL_TOPOLOGY + rim constants (P3 trail-brake bump)
$BRAKE_SURF_SOAK = 0.022
$BRAKE_CORE_SOAK = 0.0032
$BRAKE_RADIANT_COEF = 2.8e-11
$BRAKE_EFF_SOAK = 1.0
$RIM_THERMAL_INERTIA = 1.35
$RIM_REACTION_RATE = 0.10
$RIM_CARCASS_CONDUCTANCE = 0.042
$RIM_AIR_CONDUCTANCE = 0.028
$MAX_DUCT_AIR = 1.45
$CORE_REACTION_RATE = 0.08

function Get-DuctFactors([double]$ductPct) {
  $open = Clamp (($ductPct - 1.0) / 99.0) 0.0 1.0
  return @{
    Air = (Lerp 1.0 $MAX_DUCT_AIR $open)
    Soak = (Lerp 1.15 0.85 $open)
    Open = $open
  }
}

function Get-RotorMults([string]$mat) {
  $m = $mat.ToLowerInvariant()
  $cool = 1.0; $soak = 1.0
  if ($m -eq 'aluminum' -or $m -eq 'aluminium') { $cool = 1.15; $soak = 1.08 }
  elseif ($m -like '*carbon*') { $cool = 0.90; $soak = 0.82 }
  return @{ Cool = $cool; Soak = $soak }
}

function Simulate-HardBrakeRim {
  param(
    [string]$Name,
    [double]$BrakeGain = 1.05,
    [double]$DuctPct = 1.0,
    [string]$RotorMaterial = 'steel',
    [double]$BrakeArea = 0.12,
    [double]$BrakeMass = 8.0,
    [double]$BrakeDiameter = 0.30,
    [double]$Env = 22.0,
    [double]$CarcassInertia = 0.68,
    [double]$BrakeS = 8.0,
    [double]$SoakS = 12.0,
    [double]$BrakeNm = 1400.0
  )

  $duct = Get-DuctFactors $DuctPct
  $rotor = Get-RotorMults $RotorMaterial
  $brakeAreaScale = Clamp (($BrakeArea / 0.12)) 0.6 1.8
  $rimInertia = $RIM_THERMAL_INERTIA * (Clamp ($BrakeMass / 8.0) 0.6 2.5) * (Clamp ($BrakeDiameter / 0.30) 0.75 1.4)
  $rimRate = $RIM_REACTION_RATE / [math]::Max(0.05, $rimInertia)
  $coreRate = $CORE_REACTION_RATE / [math]::Max(0.05, $CarcassInertia)

  $dt = 0.05
  $preS = 5.0
  $t = 0.0
  $phase = 'cruise'

  $rim = $Env + 2.0
  $core = $Env + 2.5
  $airCav = $Env + 2.0
  $brakeSurf = $Env + 30.0
  $brakeCoreT = $Env + 22.0
  $rimPre = $rim
  $peakRim = $rim
  $peakSurf = $brakeSurf
  $peakSoakRate = 0.0
  $effAir = 35.0
  $brakeElapsed = 0.0
  $soakEnd = 0.0
  $rimAtBrakeEnd = $null
  $rimAtSoakMid = $null

  $omega = 110.0  # ~ high-speed approach

  while ($t -lt ($preS + $BrakeS + $SoakS + 0.5)) {
    if ($phase -eq 'cruise' -and $t -ge $preS) {
      $phase = 'brake'
      $rimPre = $rim
      $brakeElapsed = 0.0
    } elseif ($phase -eq 'brake' -and $brakeElapsed -ge $BrakeS) {
      $phase = 'soak'
      $rimAtBrakeEnd = $rim
      $soakEnd = $t + $SoakS
    } elseif ($phase -eq 'soak' -and $t -ge $soakEnd) {
      break
    }

    if ($phase -eq 'cruise') {
      $effAir = 35.0
      $omega = 110.0
      $brakeSurf = $brakeSurf + $dt * (-($brakeSurf - ($Env + 28.0)) * 0.05)
      $brakeCoreT = $brakeCoreT + $dt * (0.03 * ($brakeSurf - $brakeCoreT) - ($brakeCoreT - $Env) * 0.02)
    } elseif ($phase -eq 'brake') {
      $brakeElapsed += $dt
      $frac = Clamp ($brakeElapsed / $BrakeS) 0 1
      $effAir = Lerp 35.0 1.5 $frac
      $omega = Lerp 110.0 0.2 $frac
      # Soft-proxy rotor heat (INPUT only). Mid-stop surf targets ~160-220C (RallyLooseBraking band).
      $brakePower = $BrakeNm * [math]::Max(0.0, $omega) * 0.00042
      $brakeSurf = $brakeSurf + $dt * ($brakePower - ($brakeSurf - $Env) * 0.04)
      if ($brakeSurf -gt 260) { $brakeSurf = 260 }
      $brakeCoreT = $brakeCoreT + $dt * (0.055 * ($brakeSurf - $brakeCoreT) - ($brakeCoreT - $Env) * 0.014)
      if ($brakeCoreT -gt 220) { $brakeCoreT = 220 }
    } else {
      $effAir = 0.5
      $omega = 0.0
      $brakeSurf = $brakeSurf + $dt * (-($brakeSurf - $Env) * 0.05)
      $brakeCoreT = $brakeCoreT + $dt * (0.02 * ($brakeSurf - $brakeCoreT) - ($brakeCoreT - $Env) * 0.025)
      if (($null -eq $rimAtSoakMid) -and (($t - ($soakEnd - $SoakS)) -ge ($SoakS * 0.5))) {
        $rimAtSoakMid = $rim
      }
    }

    $soakCommon = $BrakeGain * [double]$duct.Soak * $brakeAreaScale * $BRAKE_EFF_SOAK * [double]$rotor.Soak
    $radiant = $BRAKE_RADIANT_COEF * ([math]::Pow($brakeSurf + 273.15, 4) - [math]::Pow($rim + 273.15, 4)) *
      $BrakeGain * [double]$duct.Soak * $brakeAreaScale * [double]$rotor.Soak
    $surfTerm = ($BRAKE_SURF_SOAK * ($brakeSurf - $rim)) * $soakCommon
    $coreTerm = ($BRAKE_CORE_SOAK * ($brakeCoreT - $rim)) * $soakCommon
    $brakeSoakPower = $surfTerm + $coreTerm + $radiant
    $soakRateCs = $brakeSoakPower * $rimRate
    if ($soakRateCs -gt $peakSoakRate) { $peakSoakRate = $soakRateCs }

    $rimCarcassNet = ($core - $rim) * $RIM_CARCASS_CONDUCTANCE * [double]$duct.Soak
    $rimCool = ($rim - $Env) * (0.22 * ([math]::Pow([math]::Max(0.01, $effAir), 0.8) * 0.28) *
      [double]$duct.Air * [double]$rotor.Cool + 0.08) * $brakeAreaScale

    $rim = $rim + ($brakeSoakPower + $rimCarcassNet + ($airCav - $rim) * $RIM_AIR_CONDUCTANCE - $rimCool) * $rimRate * $dt
    $core = $core + (($rim - $core) * $RIM_CARCASS_CONDUCTANCE * [double]$duct.Soak -
      ($core - $Env) * 0.02) * $coreRate * $dt
    $airCav = $airCav + (
      ($core - $airCav) * 0.015 * 4.0 +
      ($rim - $airCav) * $RIM_AIR_CONDUCTANCE * 2.0 -
      ($airCav - $Env) * 0.01
    ) * (1.0 / 0.22) * $dt

    if ($rim -gt $peakRim) { $peakRim = $rim }
    if ($brakeSurf -gt $peakSurf) { $peakSurf = $brakeSurf }
    $t += $dt
  }

  $dRim = $peakRim - $rimPre
  $surfShare = [math]::Abs($BRAKE_SURF_SOAK)
  $coreShare = [math]::Abs($BRAKE_CORE_SOAK)
  return [pscustomobject]@{
    Name = $Name
    DuctPct = $DuctPct
    Rotor = $RotorMaterial
    BrakeGain = $BrakeGain
    BrakeS = $BrakeS
    AirFactor = [math]::Round([double]$duct.Air, 3)
    SoakFactor = [math]::Round([double]$duct.Soak, 3)
    RimPre = [math]::Round($rimPre, 2)
    PeakRim = [math]::Round($peakRim, 2)
    DeltaRim = [math]::Round($dRim, 2)
    FinalRim = [math]::Round($rim, 2)
    FinalCore = [math]::Round($core, 2)
    RimAtBrakeEnd = if ($null -ne $rimAtBrakeEnd) { [math]::Round($rimAtBrakeEnd, 2) } else { $null }
    RimAtSoakMid = if ($null -ne $rimAtSoakMid) { [math]::Round($rimAtSoakMid, 2) } else { $null }
    PeakBrakeSurf = [math]::Round($peakSurf, 1)
    PeakSoakRate = [math]::Round($peakSoakRate, 2)
    SurfOverCore = [math]::Round($surfShare / [math]::Max(1e-9, $coreShare), 1)
  }
}

$cases = @(
  (Simulate-HardBrakeRim -Name 'steel_ductClosed' -BrakeGain 1.05 -DuctPct 1 -RotorMaterial 'steel')
  (Simulate-HardBrakeRim -Name 'steel_ductOpen' -BrakeGain 1.05 -DuctPct 100 -RotorMaterial 'steel')
  (Simulate-HardBrakeRim -Name 'carbon_ductClosed' -BrakeGain 1.05 -DuctPct 1 -RotorMaterial 'carbon-ceramic')
  (Simulate-HardBrakeRim -Name 'carbon_ductOpen' -BrakeGain 1.05 -DuctPct 100 -RotorMaterial 'carbon-ceramic')
  (Simulate-HardBrakeRim -Name 'highGain_steel' -BrakeGain 1.5 -DuctPct 1 -RotorMaterial 'steel')
  (Simulate-HardBrakeRim -Name 'lowGain_steel' -BrakeGain 0.45 -DuctPct 1 -RotorMaterial 'steel')
  # P3 extended: long trail-brake + hot park soak
  (Simulate-HardBrakeRim -Name 'trail_steel_18s' -BrakeGain 1.05 -DuctPct 1 -RotorMaterial 'steel' -BrakeS 18.0 -SoakS 20.0 -BrakeNm 900.0)
  (Simulate-HardBrakeRim -Name 'trail_steel_open' -BrakeGain 1.05 -DuctPct 100 -RotorMaterial 'steel' -BrakeS 18.0 -SoakS 20.0 -BrakeNm 900.0)
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== Soft-sim: Hard-brake -> rim rise (tire-side soak) ===')
[void]$sb.AppendLine(('Live coeffs P3: surf={0} core={1} radiant={2} MAX_DUCT_AIR={3}' -f `
  $BRAKE_SURF_SOAK, $BRAKE_CORE_SOAK, $BRAKE_RADIANT_COEF, $MAX_DUCT_AIR))
[void]$sb.AppendLine('Scenario: 5s cruise -> 8s hard brake (1400 Nm) -> 12s park soak; + trail 18s @900 Nm')
[void]$sb.AppendLine('')

$pass = 0; $fail = 0
$byName = @{}
foreach ($r in $cases) {
  $byName[$r.Name] = $r
  [void]$sb.AppendLine(('{0,-22} duct={1,3}% {2,-14} gain={3:N2} brakeS={4:N0} | dRim={5:N1}C peakRim={6:N1} core={7:N1} soakRate={8:N2}C/s brakeSurf={9:N0}' -f `
    $r.Name, $r.DuctPct, $r.Rotor, $r.BrakeGain, $r.BrakeS, `
    $r.DeltaRim, $r.PeakRim, $r.FinalCore, $r.PeakSoakRate, $r.PeakBrakeSurf))
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Gates ---')

# 1) Hard brake raises rim (P3: more readable trail feel)
$base = $byName['steel_ductClosed']
if ($base.DeltaRim -ge 5.0 -and $base.PeakBrakeSurf -ge 140.0) {
  [void]$sb.AppendLine(('PASS: steel closed-duct dRim={0:N1}C peakBrakeSurf={1:N0}C' -f $base.DeltaRim, $base.PeakBrakeSurf)); $pass++
} else {
  [void]$sb.AppendLine(('FAIL: steel closed-duct dRim={0:N1}C surf={1:N0}C (want dRim>=5, surf>=140)' -f $base.DeltaRim, $base.PeakBrakeSurf)); $fail++
}

# 2) Open duct lowers soak / peak rim vs closed (same steel)
$open = $byName['steel_ductOpen']
if ($open.PeakRim -lt $base.PeakRim -and $open.SoakFactor -lt $base.SoakFactor -and $open.AirFactor -gt $base.AirFactor) {
  [void]$sb.AppendLine(('PASS: open duct cooler rim ({0:N1} vs {1:N1}) + air up / soak down' -f $open.PeakRim, $base.PeakRim)); $pass++
} else {
  [void]$sb.AppendLine(('FAIL: open duct did not reduce rim soak (open={0:N1} closed={1:N1})' -f $open.PeakRim, $base.PeakRim)); $fail++
}

# 3) Carbon soaks less than steel (closed duct)
$carb = $byName['carbon_ductClosed']
if ($carb.DeltaRim -lt $base.DeltaRim * 0.95) {
  [void]$sb.AppendLine(('PASS: carbon dRim={0:N1} less than steel {1:N1} (rotorSoakMult)' -f $carb.DeltaRim, $base.DeltaRim)); $pass++
} else {
  [void]$sb.AppendLine(('FAIL: carbon vs steel soak (carbon={0:N1} steel={1:N1})' -f $carb.DeltaRim, $base.DeltaRim)); $fail++
}

# 4) High gain > low gain
$hi = $byName['highGain_steel']; $lo = $byName['lowGain_steel']
if ($hi.DeltaRim -gt $lo.DeltaRim * 1.3) {
  [void]$sb.AppendLine(('PASS: high gain dRim={0:N1} much greater than low {1:N1}' -f $hi.DeltaRim, $lo.DeltaRim)); $pass++
} else {
  [void]$sb.AppendLine(('FAIL: gain sweep (hi={0:N1} lo={1:N1})' -f $hi.DeltaRim, $lo.DeltaRim)); $fail++
}

# 5) Surface >> core constants
if ($BRAKE_SURF_SOAK -gt $BRAKE_CORE_SOAK * 3.0) {
  [void]$sb.AppendLine(('PASS: surf/core ratio {0:N1}x (>= 3)' -f ($BRAKE_SURF_SOAK / $BRAKE_CORE_SOAK))); $pass++
} else {
  [void]$sb.AppendLine('FAIL: surf should dominate core'); $fail++
}

# 6) Peak rim exceeds pre-brake rim; carcass trails peak rim at end of brake-led heat
#    (finalCore may catch during park soak — compare peakRim vs rimPre + modest carcass lag)
if (($base.PeakRim - $base.RimPre) -ge 2.5 -and $base.FinalCore -le ($base.PeakRim + 3.0)) {
  [void]$sb.AppendLine(('PASS: rim rose and carcass not runaway (peakRim={0:N1} finalCore={1:N1})' -f $base.PeakRim, $base.FinalCore)); $pass++
} else {
  [void]$sb.AppendLine(('FAIL: rim/carcass coupling (peakRim={0:N1} finalCore={1:N1} rimPre={2:N1})' -f $base.PeakRim, $base.FinalCore, $base.RimPre)); $fail++
}

# 7) P3: long trail-brake readable (> hard 8s) and open duct cooler on trail
$trail = $byName['trail_steel_18s']
$trailOpen = $byName['trail_steel_open']
if ($trail -and ($trail.DeltaRim -gt $base.DeltaRim) -and ($trail.DeltaRim -ge 7.0) -and ($trail.DeltaRim -lt 35.0)) {
  [void]$sb.AppendLine(('PASS: trail 18s dRim={0:N1}C > hard 8s {1:N1}C (readable, bounded)' -f $trail.DeltaRim, $base.DeltaRim)); $pass++
} else {
  $td = if ($trail) { $trail.DeltaRim } else { 'missing' }
  [void]$sb.AppendLine(("FAIL: trail soak ($td vs hard $($base.DeltaRim))")); $fail++
}
if ($trail -and $trailOpen -and ($trailOpen.PeakRim -lt $trail.PeakRim)) {
  [void]$sb.AppendLine(('PASS: trail open-duct cooler ({0:N1} vs closed {1:N1})' -f $trailOpen.PeakRim, $trail.PeakRim)); $pass++
} else {
  [void]$sb.AppendLine('FAIL: trail open duct not cooler'); $fail++
}
# Hot park: rim should still be elevated mid-soak (not instantly dump)
if ($trail -and ($null -ne $trail.RimAtSoakMid) -and ($trail.RimAtSoakMid -gt ($trail.RimPre + 3.0))) {
  [void]$sb.AppendLine(('PASS: hot park mid-soak rim still up ({0:N1}C vs pre {1:N1})' -f $trail.RimAtSoakMid, $trail.RimPre)); $pass++
} else {
  [void]$sb.AppendLine('FAIL: hot park mid-soak rim cooled too fast'); $fail++
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine(('RESULT: {0} pass / {1} fail' -f $pass, $fail))
if ($fail -gt 0) { [void]$sb.AppendLine('VERDICT: FAIL') } else { [void]$sb.AppendLine('VERDICT: PASS') }

$text = $sb.ToString()
[System.IO.File]::WriteAllText($outPath, $text)
Write-Host $text
if ($fail -gt 0) { exit 1 }
exit 0
