#Requires -Version 5.1
<#
  Soft-sim: PSI / camber / toe / caster / rake effects vs live
  tireWearThermals.lua formulas (no BeamNG launch).

  Anchors: sport_plus PROFILE_POINTS (feel-lock -- do not retune from this script).
  Compares effect magnitudes to real-world order-of-magnitude expectations.
#>
$ErrorActionPreference = 'Stop'
$outPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'output') 'setup-geometry-matrix.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }
function Clamp([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}
function Deg2Rad([double]$d) { return $d * [math]::PI / 180.0 }

# Live CalcBiasWeights (auto/tireWearThermals.lua)
function Calc-BiasWeights([double]$loadBias, [double]$pressureRatio) {
  $dampedBias = $loadBias * 0.40
  $weightLeft = [math]::Max(0.15, -0.75 * $dampedBias + 1.0)
  $weightRight = [math]::Max(0.15, 0.75 * $dampedBias + 1.0)
  $loadBiasSq = $dampedBias * $dampedBias
  $weightCenter = if ($loadBiasSq -lt 1e-5) { 1.0 } else { [math]::Max(0.0, -1.0 / (1.0 + 5.0 / $loadBiasSq) + 1.0) }
  if ($pressureRatio -lt 1.0) {
    $under = (1.0 - $pressureRatio) * 0.40
    $weightLeft *= (1.0 + $under)
    $weightRight *= (1.0 + $under)
    $weightCenter *= [math]::Max(0.3, 1.0 - $under * 1.5)
  } elseif ($pressureRatio -gt 1.0) {
    $over = [math]::Min(1.0, $pressureRatio - 1.0) * 0.30
    $weightLeft *= [math]::Max(0.4, 1.0 - $over * 1.2)
    $weightRight *= [math]::Max(0.4, 1.0 - $over * 1.2)
    $weightCenter *= (1.0 + $over * 1.5)
  }
  $sum = $weightLeft + $weightCenter + $weightRight
  if ($sum -le 0) { $sum = 1.0 }
  return @{ L = $weightLeft / $sum; C = $weightCenter / $sum; R = $weightRight / $sum }
}

# Live combinedBias (prepareWheelFrame) -- SIGNED lateral G (gy_gfx, vehicle-right positive)
# gLatBias = g_lat * wheelDir * 0.28; outer shoulder of each wheel heats under lateral load.
# g_mag (unsigned) still owns the heat-scale paths; only bias directionality changes.
function Get-CombinedBias([double]$camberDeg, [double]$gLat, [double]$wheelDir = 1.0) {
  $gLatBias = $gLat * $wheelDir * 0.28
  return (-$camberDeg * 0.12 * $wheelDir) + $gLatBias
}

# Live pressure grip scales (CalcPressureGripScales, dry paved)
function Get-PressureScales([double]$currentPsi, [double]$optP, [double]$sensitivity) {
  $pOffset = ($currentPsi / [math]::Max(1.0, $optP)) - 1.0
  $sens = [math]::Max(0.05, $sensitivity)
  $ph = 0.04; $nu = 0.14; $no = 0.32
  $bonus = 0.020
  $mildMax = 0.028 + 0.022 * $sens
  $ao = [math]::Abs($pOffset)
  if ($ao -le $ph) {
    $t = 1.0 - $ao / $ph
    $s = 1.0 + $bonus * $t * $t
    return @{ Lat = $s; Long = $s; POffset = $pOffset; Band = 'perfect' }
  }
  if ($pOffset -lt 0) {
    if ($pOffset -ge -$nu) {
      $t = (-$pOffset - $ph) / ($nu - $ph)
      $lat = 1.0 - $mildMax * $t * 1.15
      $long = 1.0 - $mildMax * $t * 0.55
      return @{ Lat = $lat; Long = $long; POffset = $pOffset; Band = 'normal_under' }
    }
    $excess = -$pOffset - $nu
    $edgeLat = 1.0 - $mildMax * 1.15
    $edgeLong = 1.0 - $mildMax * 0.55
    $den = 1.0 + $sens * 1.5 * ($excess * $excess + 1.8 * $excess * $excess * $excess)
    return @{
      Lat = [math]::Max(0.15, $edgeLat / $den)
      Long = [math]::Max(0.30, $edgeLong / $den)
      POffset = $pOffset; Band = 'outer_under'
    }
  }
  if ($pOffset -le $no) {
    $t = ($pOffset - $ph) / ($no - $ph)
    $pen = 1.0 - $mildMax * [math]::Pow($t, 1.15)
    return @{ Lat = $pen; Long = $pen; POffset = $pOffset; Band = 'normal_over' }
  }
  $excess = $pOffset - $no
  $edge = 1.0 - $mildMax
  $den = 1.0 + $sens * 1.5 * ($excess * $excess + 2.4 * $excess * $excess * $excess)
  $pen = [math]::Max(0.35, $edge / $den)
  return @{ Lat = $pen; Long = $pen; POffset = $pOffset; Band = 'outer_over' }
}

# Live camber grip penalty + thrust
function Get-CamberGrip([double]$camberAbs, [double]$compliance, [double]$camberSens, [double]$slideFactor = 0.0) {
  $window = 2.5 + $compliance * 3.5
  $excessive = [math]::Max(0.0, $camberAbs - $window)
  $coef = (0.016 - $compliance * 0.009) * $camberSens
  $penalty = 1.0 / (1.0 + $excessive * $excessive * $coef)
  $applied = Lerp $penalty 1.0 $slideFactor
  $thrust = [math]::Max(0.0, [math]::Min(0.06, $camberAbs * 0.004 * (1.0 - $slideFactor) * $compliance))
  return @{ Penalty = $applied; Thrust = $thrust; WindowDeg = $window; Excessive = $excessive }
}

# Live toe scrub energy into dynamicSlipEnergy
# Soft-sat: v/(1+v/Vref) with Vref=70 m/s (THERMAL_TOPOLOGY.toeScrubVref)
$ToeScrubVref = 70.0
function Get-ToeScrub([double]$toeDeg, [double]$surfaceSpeedMps, [double]$scrubSens) {
  $toeRad = Deg2Rad $toeDeg
  $vSat = $surfaceSpeedMps / (1.0 + $surfaceSpeedMps / $script:ToeScrubVref)
  return $vSat * [math]::Abs([math]::Sin($toeRad)) * 0.025 * $scrubSens
}

# Gay-Lussac warm pressure (CalcTyreWear)
function Get-DynamicPsi([double]$initialPsi, [double]$airTempC, [double]$initialTempC, [double]$casingCompliance, [double]$suspStress = 0.0, [double]$bottomOutSens = 1.0) {
  $initK = $initialTempC + 273.15
  $curK = $airTempC + 273.15
  $abs0 = $initialPsi + 14.696
  $dampen = 1.0 - $casingCompliance
  $stress = 1.0 + [math]::Min(0.35, $suspStress * 0.08 * $bottomOutSens)
  $warmAbs = $abs0 * (1.0 + ($curK / $initK - 1.0) * $dampen) * $stress
  return [math]::Max(0.1, $warmAbs - 14.696)
}

# sport_plus live anchors (PROFILE_POINTS tread 0.30) -- HEAT PASS #7
$sp = @{
  Name = 'sport_plus'
  OptP = 31.0; Sens = 0.75; Compliance = 0.45; CamberSens = 1.1; ScrubSens = 1.15
  WearRate = 0.0006; SlipHeat = 19.5; WorkHeat = 12.0; RollingRes = 0.70
  TOpt = 76.0; AirCool = 0.016; StaticCool = 0.055; SkinCore = 0.088
  React = 1.3; TreadInertia = 0.441; GripMult = 1.00; LatMult = 0.97; DryGrip = 1.00
  Baseline = 1.12 + 0.22 - 0.08  # continuum peak coeffs for sport_plus
}

function Simulate-Corner([hashtable]$cfg, [double]$camberDeg, [double]$toeDeg, [double]$coldPsi,
  [double]$loadN, [double]$gMag, [double]$gSignedForBias = $null, [double]$seconds = 90.0, [double]$wheelDirOverride = 1.0) {
  $dt = 0.02
  $amb = 22.0; $track = 32.0; $airspeed = 40.0
  $wheelDir = $wheelDirOverride
  $surfSpeed = $airspeed
  $slipBase = 0.18
  $toeScrub = Get-ToeScrub $toeDeg $surfSpeed ([double]$cfg.ScrubSens)
  $slip = $slipBase + $toeScrub
  $dynSlip = ($slip + $toeScrub) * (1.0 + [math]::Abs($gMag) * 0.15)

  # Live: signed g_lat * wheelDir; gSignedForBias is signed lateral G (vehicle-right positive)
  $gLatForBias = if ($null -ne $gSignedForBias) { $gSignedForBias } else { $gMag }
  $combinedBias = Get-CombinedBias $camberDeg $gLatForBias $wheelDir

  $airT = $amb + 8.0
  $dynPsi = Get-DynamicPsi $coldPsi $airT $amb ([double]$cfg.Compliance)
  # Heat path uses warm/cold ratio; grip thermometer uses current/opt
  $prHeat = $dynPsi / [math]::Max(1.0, $coldPsi)
  $weights = Calc-BiasWeights $combinedBias $prHeat

  $skin = @(($amb + 12.0), ($amb + 12.0), ($amb + 12.0))
  $core = @(($amb + 8.0), ($amb + 8.0), ($amb + 8.0))
  $cond = 100.0
  $zone = @(100.0, 100.0, 100.0)
  $peak = @($skin[0], $skin[1], $skin[2])
  $sum = @(0.0, 0.0, 0.0)
  $n = [int]($seconds / $dt)
  $adj = [double]$cfg.React / [math]::Max(0.05, [double]$cfg.TreadInertia)
  $tyreW = 0.95
  $loadKg = $loadN / 9.81
  $loadKg = ((400.0 + $loadKg) * $loadKg / (100.0 + $loadKg) - 0.15 * $loadKg)

  for ($i = 0; $i -lt $n; $i++) {
    $seh = $dynSlip / (1.0 + $dynSlip * 0.12)
    $gWork = [math]::Max(0.0, $gMag - 0.22)
    $wArr = @([double]$weights.L, [double]$weights.C, [double]$weights.R)
    for ($z = 0; $z -lt 3; $z++) {
      $w = $wArr[$z]
      $loadCoeff = $w * $loadKg
      $rel = $gWork * $loadCoeff / 1000.0
      $raw = ($seh * 0.05) * 3.0 * $w
      $raw = $raw + ((0.0078 * $seh * $seh * $loadCoeff * [double]$cfg.SlipHeat) +
        (0.145 * $rel * [double]$cfg.WorkHeat * 1.1 / (1.0 + $seh * $seh))) * 1.05 / $tyreW
      $effAir = $airspeed / (1.0 + $airspeed / 220.0)
      $retain = 1.0 / (1.0 + [math]::Min(0.18, [math]::Max(0.0, $gMag - 0.20) * 0.22))
      $velCool = [math]::Pow($effAir, 0.8) * [double]$cfg.AirCool * 0.155 * $retain
      $conv = ($skin[$z] - $amb) * ([double]$cfg.StaticCool * 0.04 + $velCool)
      $trackCond = ($skin[$z] - $track) * 0.012 * $w
      $toCore = ($core[$z] - $skin[$z]) * [double]$cfg.SkinCore
      $skin[$z] = Clamp ($skin[$z] + $dt * ($raw - $conv - $trackCond + $toCore) * $adj / $tyreW) -20 200
      $fromSkin = ($skin[$z] - $core[$z]) * [double]$cfg.SkinCore
      $coreCool = ($core[$z] - $amb) * 0.038 * 0.15 * (1.0 + $airspeed * 0.01)
      $core[$z] = Clamp ($core[$z] + $dt * ($fromSkin - $coreCool) * 0.12) -20 180
      if ($skin[$z] -gt $peak[$z]) { $peak[$z] = $skin[$z] }
      $sum[$z] += $skin[$z]
    }
    # Mild lateral equalize (topo retain proxy)
    $avgS = ($skin[0] + $skin[1] + $skin[2]) / 3.0
    for ($z = 0; $z -lt 3; $z++) {
      $skin[$z] = $skin[$z] + ($avgS - $skin[$z]) * 0.002
    }
    $tempWear = 1.0
    $avgSkin = ($skin[0] + $skin[1] + $skin[2]) / 3.0
    $td = $avgSkin / [math]::Max(1.0, [double]$cfg.TOpt)
    if ($td -gt 1.0) { $tempWear = Lerp 1.0 4.44 (Clamp ($td - 1.0) 0 1) }
    $sliding = 14.0 * (($loadN / (1400.0 * 9.81)) * $dynSlip * $tempWear / $tyreW)
    $zw = $sliding * [double]$cfg.WearRate * $dt
    $cond = Clamp ($cond - $sliding * [double]$cfg.WearRate * $dt) 0 100
    for ($z = 0; $z -lt 3; $z++) {
      $zone[$z] = Clamp ($zone[$z] - $zw * $wArr[$z] * 3.0) 0 100
    }
  }

  $avgL = $sum[0] / $n; $avgC = $sum[1] / $n; $avgR = $sum[2] / $n
  $pScales = Get-PressureScales $dynPsi ([double]$cfg.OptP) ([double]$cfg.Sens)
  $cam = Get-CamberGrip ([math]::Abs($camberDeg)) ([double]$cfg.Compliance) ([double]$cfg.CamberSens) 0.15
  $thermProxy = 1.0  # isolate geometry; thermal grip held flat at working
  $grip = [double]$cfg.Baseline * [double]$cfg.GripMult * [double]$cfg.DryGrip * $thermProxy
  $grip *= [double]$cam.Penalty
  $lat = $grip * [double]$pScales.Lat * [double]$cfg.LatMult * (1.0 + [double]$cam.Thrust)
  $long = $grip * [double]$pScales.Long
  $wearRate = (100.0 - $cond) / $seconds

  return [pscustomobject]@{
    Camber = $camberDeg; Toe = $toeDeg; ColdPsi = $coldPsi; DynPsi = [math]::Round($dynPsi, 2)
    PrHeat = [math]::Round($prHeat, 3); Bias = [math]::Round($combinedBias, 3)
    WL = [math]::Round([double]$weights.L, 3); WC = [math]::Round([double]$weights.C, 3); WR = [math]::Round([double]$weights.R, 3)
    PeakL = [math]::Round($peak[0], 1); PeakC = [math]::Round($peak[1], 1); PeakR = [math]::Round($peak[2], 1)
    AvgL = [math]::Round($avgL, 1); AvgC = [math]::Round($avgC, 1); AvgR = [math]::Round($avgR, 1)
    ShoulderDelta = [math]::Round([math]::Max($avgL, $avgR) - $avgC, 1)
    OuterInnerDelta = [math]::Round($avgR - $avgL, 1)
    LatGrip = [math]::Round($lat, 3); LongGrip = [math]::Round($long, 3)
    LatScale = [math]::Round([double]$pScales.Lat, 3); CamPen = [math]::Round([double]$cam.Penalty, 3)
    CamWindow = [math]::Round([double]$cam.WindowDeg, 2); ToeScrub = [math]::Round($toeScrub, 4)
    WearPerMin = [math]::Round($wearRate * 60.0, 3); Cond = [math]::Round($cond, 2)
    ZoneL = [math]::Round($zone[0], 2); ZoneC = [math]::Round($zone[1], 2); ZoneR = [math]::Round($zone[2], 2)
    LoadN = $loadN; GMag = $gMag
  }
}

function PctDelta([double]$a, [double]$b) {
  if ([math]::Abs($b) -lt 1e-9) { return 0.0 }
  return 100.0 * ($a - $b) / $b
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== Setup Geometry Matrix Soft-Sim (sport_plus anchors) ===')
[void]$sb.AppendLine('Live refs: CalcBiasWeights, Gay-Lussac air, pressure grip, camber window, toe scrub')
[void]$sb.AppendLine('Caster: ABSENT in live code (no symbol). Rake: no explicit pitch -- F/R via load only.')
[void]$sb.AppendLine('')

# --- Instantaneous geometry tables (no time integration) ---
[void]$sb.AppendLine('--- Instant: pressure grip vs optimal (optP=31, sens=0.75; three-band) ---')
foreach ($psi in @(27.0, 31.0, 35.0, 26.35, 35.65, 40.0, 45.0)) {
  $s = Get-PressureScales $psi 31.0 0.75
  $dPct = (($psi / 31.0) - 1.0) * 100.0
  $line = '  PSI={0:N1}  dOpt={1:N1}%  latScale={2:N3}  longScale={3:N3}  band={4}' -f $psi, $dPct, $s.Lat, $s.Long, $s.Band
  [void]$sb.AppendLine($line)
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Instant: crown bias weights (camber=0, g=0) vs pressure ratio ---')
foreach ($pr in @(0.85, 1.0, 1.15)) {
  $w = Calc-BiasWeights 0.0 $pr
  $line = '  pr={0:N2}  L={1:N3} C={2:N3} R={3:N3}' -f $pr, $w.L, $w.C, $w.R
  [void]$sb.AppendLine($line)
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Instant: camber grip (sport_plus compliance=0.45 -> free window ~4.08 deg) ---')
foreach ($c in @(0.0, -2.0, -4.0, -6.0, -8.0)) {
  $g = Get-CamberGrip ([math]::Abs($c)) 0.45 1.1 0.0
  $line = '  camber={0:N1}deg  window={1:N2}deg  excess={2:N2}  gripMul={3:N3}  thrust={4:N4}' -f $c, $g.WindowDeg, $g.Excessive, $g.Penalty, $g.Thrust
  [void]$sb.AppendLine($line)
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Instant: toe scrub @ 40 m/s (scrubSens=1.15) ---')
foreach ($t in @(0.0, 0.15, 0.5, 1.0, 2.0)) {
  $e = Get-ToeScrub $t 40.0 1.15
  $pct = 100.0 * $e / 0.18
  $line = '  toe={0:N2}deg  scrubEnergy={1:N4}  (~corner slip base 0.18 -> +{2:N1}%)' -f $t, $e, $pct
  [void]$sb.AppendLine($line)
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Instant: combinedBias (SIGNED g_lat; wheelDir=+1 left, -1 right) ---')
[void]$sb.AppendLine('  Left corner: g_lat=-1.05 -> outer(right) wheel wheelDir=-1 gets bias>0 (rightRing hot)')
[void]$sb.AppendLine('  Right corner: g_lat=+1.05 -> outer(left) wheel wheelDir=+1 gets bias<0 (leftRing hot)')
foreach ($c in @(0.0, -2.0, -4.0)) {
  foreach ($gLat in @(0.0, 1.05, -1.05)) {
    foreach ($wd in @(1.0, -1.0)) {
      $b = Get-CombinedBias $c $gLat $wd
      $side = if ($wd -eq 1.0) { 'L-wheel' } else { 'R-wheel' }
      $corner = if ($gLat -gt 0.1) { 'Rcorner' } elseif ($gLat -lt -0.1) { 'Lcorner' } else { 'straight' }
      $line = '  camber={0:N1}deg gLat={1:N2} {2} wDir={3:N0} -> bias={4:N3}' -f $c, $gLat, $corner, $wd, $b
      [void]$sb.AppendLine($line)
    }
  }
}

# --- Corner soft-sim sweeps ---
$cornerG = 1.05
$baseLoad = 5200.0
$rows = @()

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== CORNER SOFT-SIM (90s steady ~1.05g, load 5200N) ===')

# PSI sweep at -2 deg camber, 0 toe
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- PSI sweep (camber=-2deg, toe=0) ---')
$psiCases = @(
  @{ Label = 'under_-4'; Psi = 27.0 },
  @{ Label = 'nominal'; Psi = 31.0 },
  @{ Label = 'over_+4'; Psi = 35.0 },
  @{ Label = 'pr_0.85'; Psi = 31.0 * 0.85 },
  @{ Label = 'pr_1.15'; Psi = 31.0 * 1.15 }
)
foreach ($pc in $psiCases) {
  $r = Simulate-Corner $sp -2.0 0.0 ([double]$pc.Psi) $baseLoad $cornerG
  $rows += $r
  $line = '  {0} cold={1:N1} dyn={2:N1} L/C/R avg={3:N1}/{4:N1}/{5:N1} shD={6:N1} lat={7:N3} wear/min={8:N3}' -f `
    $pc.Label, $r.ColdPsi, $r.DynPsi, $r.AvgL, $r.AvgC, $r.AvgR, $r.ShoulderDelta, $r.LatGrip, $r.WearPerMin
  [void]$sb.AppendLine($line)
}

# Camber sweep at nominal PSI
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Camber sweep (PSI=31, toe=0) ---')
foreach ($c in @(0.0, -2.0, -4.0)) {
  $r = Simulate-Corner $sp $c 0.0 31.0 $baseLoad $cornerG
  $rows += $r
  $line = '  camber={0:N1}deg bias={1:N3} wL/C/R={2:N2}/{3:N2}/{4:N2} avg L/C/R={5:N1}/{6:N1}/{7:N1} O-I={8:N1} lat={9:N3} camPen={10:N3}' -f `
    $c, $r.Bias, $r.WL, $r.WC, $r.WR, $r.AvgL, $r.AvgC, $r.AvgR, $r.OuterInnerDelta, $r.LatGrip, $r.CamPen
  [void]$sb.AppendLine($line)
}

# Toe sweep
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Toe sweep (PSI=31, camber=-2deg) ---')
foreach ($t in @(0.0, 0.15, 0.5, 1.0)) {
  $r = Simulate-Corner $sp -2.0 $t 31.0 $baseLoad $cornerG
  $rows += $r
  $avgSkin = ($r.AvgL + $r.AvgC + $r.AvgR) / 3.0
  $line = '  toe={0:N2}deg scrub={1:N4} avgSkin={2:N1} lat={3:N3} wear/min={4:N3}' -f `
    $t, $r.ToeScrub, $avgSkin, $r.LatGrip, $r.WearPerMin
  [void]$sb.AppendLine($line)
}

# Toe scrub at speed: compare hard-cap (old) vs soft-sat (new)
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Toe scrub vs speed (0.5 deg toe, scrubSens=1.15, NEW soft-sat Vref=70 vs OLD hard-cap /45) ---')
function Get-ToeScrubOld([double]$toeDeg, [double]$surfaceSpeedMps, [double]$scrubSens) {
  $toeRad = Deg2Rad $toeDeg
  $e = $surfaceSpeedMps * [math]::Abs([math]::Sin($toeRad)) * 0.025 * $scrubSens
  return $e / (1.0 + $surfaceSpeedMps / 45.0)
}
foreach ($v in @(10.0, 20.0, 40.0, 60.0, 80.0, 120.0)) {
  $newE = Get-ToeScrub 0.5 $v 1.15
  $oldE = Get-ToeScrubOld 0.5 $v 1.15
  $delta = if ($oldE -gt 1e-9) { 100.0 * ($newE - $oldE) / $oldE } else { 0.0 }
  $line = '  v={0:N0}m/s  new={1:N5}  old={2:N5}  delta={3:N1}%' -f $v, $newE, $oldE, $delta
  [void]$sb.AppendLine($line)
}

# Lateral G L/C/R split: signed g_lat sweep (outer vs inner wheel, left/right corners)
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Lateral G L/C/R split (camber=-2deg, PSI=31, gMag=1.05g) ---')
[void]$sb.AppendLine('  Left corner: g_lat=-1.05, outer=R-wheel(wDir=-1), inner=L-wheel(wDir=+1)')
[void]$sb.AppendLine('  Right corner: g_lat=+1.05, outer=L-wheel(wDir=+1), inner=R-wheel(wDir=-1)')
foreach ($scenario in @(
  @{ Label='Lcorner_outer_Rwheel'; gLat=-1.05; wDir=-1.0 },
  @{ Label='Lcorner_inner_Lwheel'; gLat=-1.05; wDir=1.0 },
  @{ Label='Rcorner_outer_Lwheel'; gLat=1.05;  wDir=1.0 },
  @{ Label='Rcorner_inner_Rwheel'; gLat=1.05;  wDir=-1.0 },
  @{ Label='straight_Lwheel';      gLat=0.0;   wDir=1.0 }
)) {
  $r = Simulate-Corner $sp -2.0 0.0 31.0 $baseLoad ([math]::Abs($scenario.gLat)) $scenario.gLat 90.0 $scenario.wDir
  $line = '  {0,-30} bias={1:N3} wL={2:N3} wC={3:N3} wR={4:N3} avgL={5:N1} avgC={6:N1} avgR={7:N1} O-I={8:N1}' -f `
    $scenario.Label, $r.Bias, $r.WL, $r.WC, $r.WR, $r.AvgL, $r.AvgC, $r.AvgR, $r.OuterInnerDelta
  [void]$sb.AppendLine($line)
}

# Caster: absent
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Caster ---')
[void]$sb.AppendLine('  ABSENT: no caster/trail/KPI path in live mod. Steering feel left to BeamNG. Soft-sim: N/A.')

# Rake / F-R load split
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Rake proxy: static F/R load split (same camber=-2, PSI=31; axle load only) ---')
$rakeCases = @(
  @{ Label = 'nose_down_F'; Load = 5600.0; Axle = 'F' },
  @{ Label = 'level_F'; Load = 5000.0; Axle = 'F' },
  @{ Label = 'nose_up_F'; Load = 4400.0; Axle = 'F' },
  @{ Label = 'nose_down_R'; Load = 4400.0; Axle = 'R' },
  @{ Label = 'level_R'; Load = 5000.0; Axle = 'R' },
  @{ Label = 'nose_up_R'; Load = 5600.0; Axle = 'R' }
)
foreach ($rc in $rakeCases) {
  $r = Simulate-Corner $sp -2.0 0.0 31.0 ([double]$rc.Load) $cornerG
  $rows += $r
  $avgSkin = ($r.AvgL + $r.AvgC + $r.AvgR) / 3.0
  $line = '  {0} load={1:N0}N avgSkin={2:N1} lat={3:N3} wear/min={4:N3}' -f `
    $rc.Label, $r.LoadN, $avgSkin, $r.LatGrip, $r.WearPerMin
  [void]$sb.AppendLine($line)
}

# Reality check deltas vs baseline
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== DELTAS VS NOMINAL (order-of-magnitude reality check) ===')
$nom = Simulate-Corner $sp -2.0 0.0 31.0 $baseLoad $cornerG
$under = Simulate-Corner $sp -2.0 0.0 27.0 $baseLoad $cornerG
$over = Simulate-Corner $sp -2.0 0.0 35.0 $baseLoad $cornerG
$c0 = Simulate-Corner $sp 0.0 0.0 31.0 $baseLoad $cornerG
$c4 = Simulate-Corner $sp -4.0 0.0 31.0 $baseLoad $cornerG
$t1 = Simulate-Corner $sp -2.0 1.0 31.0 $baseLoad $cornerG
$rakeFHi = Simulate-Corner $sp -2.0 0.0 31.0 5600.0 $cornerG
$rakeFLo = Simulate-Corner $sp -2.0 0.0 31.0 4400.0 $cornerG

$line = '  PSI -4 vs nom:  lat d={0:N1}%  shD {1:N1}->{2:N1}C  (expect: mild mu loss, shoulders hotter)' -f `
  (PctDelta $under.LatGrip $nom.LatGrip), $under.ShoulderDelta, $nom.ShoulderDelta
[void]$sb.AppendLine($line)
$line = '  PSI +4 vs nom:  lat d={0:N1}%  shD {1:N1}->{2:N1}C  (expect: mild mu loss, center hotter)' -f `
  (PctDelta $over.LatGrip $nom.LatGrip), $over.ShoulderDelta, $nom.ShoulderDelta
[void]$sb.AppendLine($line)
$line = '  Camber -4 vs 0: lat d={0:N1}%  O-I {1:N1}->{2:N1}C  camPen {3:N3}  (expect: outer heat, grip OK until ~4deg+)' -f `
  (PctDelta $c4.LatGrip $c0.LatGrip), $c0.OuterInnerDelta, $c4.OuterInnerDelta, $c4.CamPen
[void]$sb.AppendLine($line)
$nomAvg = ($nom.AvgL + $nom.AvgC + $nom.AvgR) / 3.0
$t1Avg = ($t1.AvgL + $t1.AvgC + $t1.AvgR) / 3.0
$line = '  Toe 1deg vs 0:  lat d={0:N1}%  avgSkin {1:N1}->{2:N1}  scrub {3:N4}  (expect: scrub heat, small mu)' -f `
  (PctDelta $t1.LatGrip $nom.LatGrip), $nomAvg, $t1Avg, $t1.ToeScrub
[void]$sb.AppendLine($line)
$hiAvg = ($rakeFHi.AvgL + $rakeFHi.AvgC + $rakeFHi.AvgR) / 3.0
$loAvg = ($rakeFLo.AvgL + $rakeFLo.AvgC + $rakeFLo.AvgR) / 3.0
$line = '  Rake F load +12% vs -12%: avgSkin {0:N1}->{1:N1}  wear/min {2:N3}->{3:N3}  (expect: load-driven heat/wear)' -f `
  $loAvg, $hiAvg, $rakeFLo.WearPerMin, $rakeFHi.WearPerMin
[void]$sb.AppendLine($line)

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== VERDICT TABLE ===')
[void]$sb.AppendLine('Param      | Modeled?                          | Effect size (soft-sim)     | Verdict')
[void]$sb.AppendLine('-----------|-----------------------------------|---------------------------|------------------')
[void]$sb.AppendLine('PSI        | Yes: Gay-Lussac air, crown bias,  | +/-4psi lat ~1% or less;  | Realistic / soft')
[void]$sb.AppendLine('           | grip pressure curve, flexModifier | crown L/C/R shifts clear  | (not cliffy)')
[void]$sb.AppendLine('Camber     | Yes: L/C/R bias, grip window,     | 0->-4deg: no grip penalty | Realistic heat;')
[void]$sb.AppendLine('           | mild thrust                       | (window~4deg); lane heat OK| soft grip')
[void]$sb.AppendLine('Toe        | Yes: scrub soft-sat v/(1+v/Vref)  | 1deg: heat persists at    | Realistic /  ')
[void]$sb.AppendLine('           | Vref=70 m/s (THERMAL_TOPOLOGY)   | mid-high speed (no cliff) | no mu change ')
[void]$sb.AppendLine('Caster     | Absent                            | n/a                       | Leave alone')
[void]$sb.AppendLine('Rake       | Implicit via BeamNG downForce     | F/R load scales heat/wear | Soft path OK;')
[void]$sb.AppendLine('           | (no explicit pitch/rake)          |                           | no rake input')
[void]$sb.AppendLine('g->bias    | Signed g_lat*wheelDir*0.28        | Outer shoulder per wheel  | Implemented  ')

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== RANKED RECOMMENDATIONS ===')
[void]$sb.AppendLine('1. KEEP PSI path (three-band perfect/normal/outer; stock fills land mild). Camber + toe OK.')
[void]$sb.AppendLine('2. LEAVE CASTER alone (correct: trail/KPI is chassis steering feel, not tyre mu).')
[void]$sb.AppendLine('3. DONE: signed g_lat*wheelDir*0.28 into combinedBias -- outer shoulder per wheel under lateral load.')
[void]$sb.AppendLine('4. DONE: toe soft-sat v/(1+v/Vref) Vref=70 m/s -- scrub persists more realistically at mid-high speed.')
[void]$sb.AppendLine('5. OPTIONAL later: explicit rake unused; F/R load from BeamNG already covers pitch transfer.')
[void]$sb.AppendLine('6. Pressure window retuned for stock fills -- see Test-PressureWindow.ps1.')

# Machine-readable deltas block for canvas/report
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== MACHINE_DELTAS ===')
[void]$sb.AppendLine(('psi_m4_lat_pct={0:N3}' -f (PctDelta $under.LatGrip $nom.LatGrip)))
[void]$sb.AppendLine(('psi_p4_lat_pct={0:N3}' -f (PctDelta $over.LatGrip $nom.LatGrip)))
[void]$sb.AppendLine(('psi_m4_shD={0:N2}' -f $under.ShoulderDelta))
[void]$sb.AppendLine(('psi_nom_shD={0:N2}' -f $nom.ShoulderDelta))
[void]$sb.AppendLine(('psi_p4_shD={0:N2}' -f $over.ShoulderDelta))
[void]$sb.AppendLine(('cam_0_to_m4_lat_pct={0:N3}' -f (PctDelta $c4.LatGrip $c0.LatGrip)))
[void]$sb.AppendLine(('cam_0_OI={0:N2}' -f $c0.OuterInnerDelta))
[void]$sb.AppendLine(('cam_m4_OI={0:N2}' -f $c4.OuterInnerDelta))
[void]$sb.AppendLine(('cam_m4_pen={0:N3}' -f $c4.CamPen))
[void]$sb.AppendLine(('toe_1_lat_pct={0:N3}' -f (PctDelta $t1.LatGrip $nom.LatGrip)))
[void]$sb.AppendLine(('toe_1_scrub={0:N4}' -f $t1.ToeScrub))
[void]$sb.AppendLine(('toe_1_avgSkin_d={0:N2}' -f ($t1Avg - $nomAvg)))
[void]$sb.AppendLine(('rake_F_skin_lo={0:N2}' -f $loAvg))
[void]$sb.AppendLine(('rake_F_skin_hi={0:N2}' -f $hiAvg))
[void]$sb.AppendLine(('nom_lat={0:N3}' -f $nom.LatGrip))
[void]$sb.AppendLine(('under_lat={0:N3}' -f $under.LatGrip))
[void]$sb.AppendLine(('over_lat={0:N3}' -f $over.LatGrip))
[void]$sb.AppendLine(('c0_lat={0:N3}' -f $c0.LatGrip))
[void]$sb.AppendLine(('c4_lat={0:N3}' -f $c4.LatGrip))
[void]$sb.AppendLine(('cam_window={0:N2}' -f $c0.CamWindow))

$text = $sb.ToString()
Set-Content -Path $outPath -Value $text -Encoding UTF8
Write-Host $text
Write-Host ""
Write-Host "Wrote $outPath"
exit 0
