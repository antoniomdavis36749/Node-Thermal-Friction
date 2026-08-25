#Requires -Version 5.1
<#
  Soft-sim: high-bank camber vs gravity (BUG) vs vehicle-frame vs road-relative (BEST).
  Live formulas from tireWearThermals.lua camber penalty path.
  No BeamNG launch.
#>
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'banked-camber.txt'

function Lerp([double]$a, [double]$b, [double]$t) { return $a + ($b - $a) * $t }

# Live camber grip penalty (slideFactor=0 = instant bank entry, no slide relief)
function Get-CamberGrip([double]$camberAbs, [double]$compliance, [double]$camberSens, [double]$slideFactor = 0.0) {
  $window = 2.5 + $compliance * 3.5
  $excessive = [math]::Max(0.0, $camberAbs - $window)
  $coef = (0.016 - $compliance * 0.009) * $camberSens
  $penalty = 1.0 / (1.0 + $excessive * $excessive * $coef)
  $applied = Lerp $penalty 1.0 $slideFactor
  return @{ Penalty = $applied; WindowDeg = $window; Excessive = $excessive }
}

# soft_slick-ish (high camberSensitivity) — matches user "slicks ~130%"
$slick = @{ Name = 'soft_slick'; Compliance = 0.25; CamberSens = 1.45; BaseGripPct = 130.0 }
# sport_plus flat-track reference
$sport = @{ Name = 'sport_plus'; Compliance = 0.45; CamberSens = 1.1; BaseGripPct = 112.0 }

# BUG: gravity-frame camber ≈ bank angle when car sits on bank (spindle parallel to road).
function Get-GravityCamber([double]$setupCamberDeg, [double]$bankDeg) {
  return $bankDeg + $setupCamberDeg
}
# Vehicle-frame (invQuat): bank cancels; leftover is geometric / soft-body camber vs chassis.
function Get-ChassisCamber([double]$setupCamberDeg) {
  return $setupCamberDeg
}
# Road-relative (mapmgr.surfaceNormalBelow): camber vs contact normal.
# bodyRollVsSurfaceDeg = chassis lean relative to road (0 when car sits flush on bank).
# When unloaded / no normal → same as vehicle-frame fallback.
function Get-RoadRelativeCamber(
  [double]$setupCamberDeg,
  [double]$bodyRollVsSurfaceDeg,
  [bool]$loaded,
  [bool]$hasNormal
) {
  if (-not $loaded -or -not $hasNormal) {
    return $setupCamberDeg
  }
  return $setupCamberDeg + $bodyRollVsSurfaceDeg
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('Banked-track camber grip soft-sim')
[void]$sb.AppendLine('BUG: calculateWheelAlignment used world-Z (gravity) as camber')
[void]$sb.AppendLine('VEHICLE: invQuat vehicle-frame (Talladega bank cancels when chassis follows bank)')
[void]$sb.AppendLine('ROAD: surfaceNormalBelow at contact patch; falls back to vehicle-frame if airborne/no normal')
[void]$sb.AppendLine('')

$setupCamber = -2.5
$banks = @(0.0, 5.0, 12.0, 18.0, 24.0, 28.0, 31.0)
$fail = 0
$pass = 0

foreach ($cfg in @($slick, $sport)) {
  [void]$sb.AppendLine(('--- {0} compliance={1} camberSens={2} base={3}% setupCamber={4}deg ---' -f `
    $cfg.Name, $cfg.Compliance, $cfg.CamberSens, $cfg.BaseGripPct, $setupCamber))
  [void]$sb.AppendLine('  bank  | gravityCam | chassisCam | roadCam | gripBUG% | gripVEH% | gripROAD% | bugMul | vehMul | roadMul')

  foreach ($bank in $banks) {
    # Chassis aligned with bank → bodyRollVsSurface = 0 → road == vehicle == setup
    $gCam = Get-GravityCamber $setupCamber $bank
    $cCam = Get-ChassisCamber $setupCamber
    $rCam = Get-RoadRelativeCamber $setupCamber 0.0 $true $true
    $g = Get-CamberGrip ([math]::Abs($gCam)) ([double]$cfg.Compliance) ([double]$cfg.CamberSens) 0.0
    $c = Get-CamberGrip ([math]::Abs($cCam)) ([double]$cfg.Compliance) ([double]$cfg.CamberSens) 0.0
    $r = Get-CamberGrip ([math]::Abs($rCam)) ([double]$cfg.Compliance) ([double]$cfg.CamberSens) 0.0
    $gripBug = $cfg.BaseGripPct * $g.Penalty
    $gripVeh = $cfg.BaseGripPct * $c.Penalty
    $gripRoad = $cfg.BaseGripPct * $r.Penalty
    $line = '  {0,5:N1} | {1,9:N1} | {2,9:N1} | {3,7:N1} | {4,7:N1} | {5,7:N1} | {6,8:N1} | {7:N3} | {8:N3} | {9:N3}' -f `
      $bank, $gCam, $cCam, $rCam, $gripBug, $gripVeh, $gripRoad, $g.Penalty, $c.Penalty, $r.Penalty
    [void]$sb.AppendLine($line)

    # Flat: gravity / vehicle / road must agree
    if ($bank -eq 0.0) {
      if ([math]::Abs($gripBug - $gripVeh) -gt 0.5 -or [math]::Abs($gripVeh - $gripRoad) -gt 0.5) {
        [void]$sb.AppendLine('  FAIL flat-track paths diverge')
        $fail++
      } else { $pass++ }
      if ([math]::Abs($rCam - $setupCamber) -gt 0.01) {
        [void]$sb.AppendLine('  FAIL flat road camber != setup')
        $fail++
      } else { $pass++ }
    }
    # High bank BUG must collapse; ROAD/VEHICLE (aligned) must stay sane for slicks
    if ($bank -ge 24.0 -and $cfg.Name -eq 'soft_slick') {
      if ($gripBug -gt 40.0) {
        [void]$sb.AppendLine('  FAIL expected BUG collapse at high bank')
        $fail++
      } else { $pass++ }
      if ($gripRoad -lt 90.0 -or $gripRoad -gt 140.0) {
        [void]$sb.AppendLine(('  FAIL ROAD grip {0:N1}% not in sane band [90,140]' -f $gripRoad))
        $fail++
      } else { $pass++ }
      if ([math]::Abs($rCam - $setupCamber) -gt 0.01) {
        [void]$sb.AppendLine('  FAIL aligned-bank road camber should equal setup')
        $fail++
      } else { $pass++ }
      if ($bank -eq 28.0 -and $gripBug -gt 35.0) {
        [void]$sb.AppendLine('  FAIL BUG at 28deg should be near user 20-25% band')
        $fail++
      } elseif ($bank -eq 28.0) { $pass++ }
    }
  }
  [void]$sb.AppendLine('')
}

# --- Body roll vs surface on high bank (road-relative picks up extra camber) ---
[void]$sb.AppendLine('--- Body roll vs surface (bank=28, setup=-2.5) ---')
[void]$sb.AppendLine('  rollVsSurf | roadCam | chassisCam | gripROAD% | gripVEH% | note')
$bankHi = 28.0
$rolls = @(-4.0, -2.0, 0.0, 2.0, 4.0, 6.0)
foreach ($roll in $rolls) {
  $rCam = Get-RoadRelativeCamber $setupCamber $roll $true $true
  $cCam = Get-ChassisCamber $setupCamber
  $r = Get-CamberGrip ([math]::Abs($rCam)) ([double]$slick.Compliance) ([double]$slick.CamberSens) 0.0
  $c = Get-CamberGrip ([math]::Abs($cCam)) ([double]$slick.Compliance) ([double]$slick.CamberSens) 0.0
  $gripRoad = $slick.BaseGripPct * $r.Penalty
  $gripVeh = $slick.BaseGripPct * $c.Penalty
  $note = if ($roll -eq 0.0) { 'aligned' } else { 'extra road camber' }
  [void]$sb.AppendLine(('  {0,9:N1} | {1,7:N1} | {2,10:N1} | {3,8:N1} | {4,7:N1} | {5}' -f `
    $roll, $rCam, $cCam, $gripRoad, $gripVeh, $note))

  if ($roll -eq 0.0) {
    if ([math]::Abs($rCam - $cCam) -gt 0.01) {
      [void]$sb.AppendLine('  FAIL roll=0 road should match chassis')
      $fail++
    } else { $pass++ }
  } else {
    # Road must move with roll; vehicle-frame stays at setup
    if ([math]::Abs($rCam - ($setupCamber + $roll)) -gt 0.01) {
      [void]$sb.AppendLine('  FAIL road camber != setup+roll')
      $fail++
    } else { $pass++ }
    if ([math]::Abs($cCam - $setupCamber) -gt 0.01) {
      [void]$sb.AppendLine('  FAIL chassis camber should stay at setup under body roll')
      $fail++
    } else { $pass++ }
    if ([math]::Abs($rCam) -le [math]::Abs($cCam) + 0.5 -and [math]::Abs($roll) -ge 2.0) {
      # For |roll|>=2 with same sign as increasing |camber| from -2.5, |road| > |chassis|
      # -2.5+(-4)= -6.5 vs -2.5; -2.5+4=1.5 vs -2.5 — abs may go either way
    }
  }
  # Even with +6° roll, road path must not collapse like gravity bug (bank+setup≈25.5°)
  $gBug = Get-GravityCamber $setupCamber $bankHi
  if ([math]::Abs($rCam) -gt [math]::Abs($gBug) - 5.0) {
    [void]$sb.AppendLine('  FAIL road camber approached gravity-bug magnitude')
    $fail++
  } else { $pass++ }
}
[void]$sb.AppendLine('')

# --- Airborne / no-normal fallback ---
[void]$sb.AppendLine('--- Fallback: airborne / missing normal (bank=28, rollVsSurf=4) ---')
$fallCases = @(
  @{ Name = 'airborne'; Loaded = $false; HasNormal = $true },
  @{ Name = 'no_normal'; Loaded = $true; HasNormal = $false },
  @{ Name = 'both_missing'; Loaded = $false; HasNormal = $false },
  @{ Name = 'loaded_ok'; Loaded = $true; HasNormal = $true }
)
foreach ($fc in $fallCases) {
  $rCam = Get-RoadRelativeCamber $setupCamber 4.0 $fc.Loaded $fc.HasNormal
  $expect = if ($fc.Loaded -and $fc.HasNormal) { $setupCamber + 4.0 } else { $setupCamber }
  $ok = [math]::Abs($rCam - $expect) -lt 0.01
  [void]$sb.AppendLine(('  {0,-12} loaded={1} normal={2} -> camber={3:N1} (expect {4:N1}) {5}' -f `
    $fc.Name, $fc.Loaded, $fc.HasNormal, $rCam, $expect, $(if ($ok) { 'PASS' } else { 'FAIL' })))
  if ($ok) { $pass++ } else { $fail++ }
}
[void]$sb.AppendLine('')

# Instant asphalt path still active: surfaceType unchanged (dry_paved) - camber-only term
[void]$sb.AppendLine('Surface path: asphalt/dry_paved remains active; only camberMul tanks under BUG.')
[void]$sb.AppendLine('combinedBias also used gravity camber (-camber*0.12) - fixed by road/vehicle frame.')
[void]$sb.AppendLine('In-game: Talladega-like bank + flush chassis -> ~setup camber; add body roll -> extra road camber.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('RESULT pass={0} fail={1}' -f $pass, $fail))

$text = $sb.ToString()
Set-Content -Path $outPath -Value $text -Encoding UTF8
Write-Host $text
if ($fail -gt 0) { exit 1 }
exit 0
