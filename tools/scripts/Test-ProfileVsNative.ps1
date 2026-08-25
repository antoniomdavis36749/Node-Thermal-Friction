#Requires -Version 5.1
<#
  Soft-sim: each tire profile / spectrum anchor vs native BeamNG baseline.

  Native reference (soft-sim only — not in-game telemetry):
    - Mod disables native thermal curve via setFrictionThermalSensitivity(-300, 1e7, …).
    - Soft frictionCoef coupling at μ=1 → 0.55+0.45*1 = 1.0 (clamp 0.88–1.12).
    - Therefore native peak product ≈ 1.0 and native thermal ≈ flat 1.0 in operating band.
    - Condition-poly is mod-only; native column is μ≈1 / thermal-off, not stock poly.

  Metrics (dry paved, frictionCoef=1, load=1×):
    peakProd   = gripMultiplier × dryGripScale
    peakLat    = peakProd × latGripMult
    peakLong   = peakProd × longGripMult
    coldProd   = shapedThermal(20°C) × peakProd
    hotProd    = shapedThermal(opt+40°C) × peakProd
    polyPeak   = conditionPoly(1) × peakProd   (mod effective peak vs native 1.0)

  Source: lua/vehicle/extensions/auto/tireWearThermals.lua (mirrored).
#>
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'profile-vs-native.txt'
$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s); Write-Host $s }

# --- Soft-cap packs (live DRIVE_SOFTCAP_*) ---
$SOFTCAP_STREET     = @{ heatMin = 0.90; propMin = 0.93; highV = 0.80; label = 'street' }
$SOFTCAP_SPORT      = @{ heatMin = 0.92; propMin = 0.95; highV = 0.87; label = 'sport' }
$SOFTCAP_SPORT_PLUS = @{ heatMin = 0.94; propMin = 0.97; highV = 0.82; label = 'sport+' }
$SOFTCAP_TRACK_DAY  = @{ heatMin = 0.97; propMin = 0.985; highV = 0.91; label = 'trackDay' }
$SOFTCAP_VINTAGE    = @{ heatMin = 0.95; propMin = 0.97; highV = 0.88; label = 'vintage' }
$SOFTCAP_OFF        = @{ heatMin = 1.00; propMin = 1.00; highV = 1.00; label = 'OFF' }

# Character cold/hot grip powers (live CHARACTER_*)
$CHAR_NEUTRAL     = @{ coldP = 1.35; hotP = 2.00 }
$CHAR_SPORT       = @{ coldP = 1.33; hotP = 2.20 }
$CHAR_SPORT_PLUS  = @{ coldP = 1.32; hotP = 2.28 }
$CHAR_TRACK_DAY   = @{ coldP = 1.36; hotP = 2.22 }
$CHAR_SLICK_HARD  = @{ coldP = 1.40; hotP = 2.15 }
$CHAR_SLICK_MED   = @{ coldP = 1.38; hotP = 2.20 }
$CHAR_SLICK_SOFT  = @{ coldP = 1.36; hotP = 2.28 }
$CHAR_DRAG        = @{ coldP = 1.32; hotP = 2.10 }
$CHAR_DRIFT       = @{ coldP = 1.35; hotP = 2.05 }

# GRIP_COEFFS tag → poly (first match wins; order matches Lua)
$GRIP_COEFFS = @(
  @{ tag = 'sport_plus';   c = @(1.12, 0.22, -0.08) },
  @{ tag = 'soft_slick';   c = @(1.42, 0.34, -0.12) },
  @{ tag = 'medium_slick'; c = @(1.38, 0.32, -0.12) },
  @{ tag = 'hard_slick';   c = @(1.34, 0.30, -0.11) },
  @{ tag = 'slick';        c = @(1.38, 0.32, -0.12) },
  @{ tag = 'sport';        c = @(1.02, 0.16, -0.06) },
  @{ tag = 'drag';         c = @(1.28, 0.28, -0.10) },
  @{ tag = 'drift';        c = @(0.88, 0.12, -0.05) },
  @{ tag = 'rain';         c = @(0.96, 0.14, -0.05) },
  @{ tag = 'rally';        c = @(0.98, 0.14, -0.05) },
  @{ tag = 'winter';       c = @(0.90, 0.12, -0.04) },
  @{ tag = 'paddle';       c = @(0.70, 0.08, -0.02) },
  @{ tag = 'donut';        c = @(0.68, 0.08, -0.03) },
  @{ tag = 'mudterrain';   c = @(0.76, 0.08, -0.02) },
  @{ tag = 'allterrain';   c = @(0.82, 0.10, -0.03) },
  @{ tag = 'crawler';      c = @(0.72, 0.06, -0.02) },
  @{ tag = 'vintage';      c = @(0.88, 0.11, -0.04) },
  @{ tag = 'utility';      c = @(0.84, 0.08, -0.02) },
  @{ tag = 'truck';        c = @(0.86, 0.08, -0.02) },
  @{ tag = 'heavy';        c = @(0.84, 0.08, -0.02) },
  @{ tag = 'standard';     c = @(0.92, 0.12, -0.04) },
  @{ tag = 'utv';          c = @(0.78, 0.08, -0.02) }
)

function Get-PolyPeak([string]$profileName) {
  $pl = $profileName.ToLowerInvariant()
  foreach ($row in $GRIP_COEFFS) {
    if ($pl.Contains($row.tag)) {
      $c = $row.c
      $x = 1.0
      return $c[0] + $x * ($c[1] + $x * ($c[2] + $x * $(if ($c.Length -gt 3) { $c[3] } else { 0.0 })))
    }
  }
  return 0.85 + 1.0 * (0.10 + 1.0 * (-0.05))
}

function Get-Thermal(
  [double]$temp, [double]$tOpt, [double]$plateau, [double]$wCold, [double]$wHot,
  [double]$floor, [double]$coldP, [double]$hotP,
  [double]$compliance = 0.5, [double]$softness = 0.5
) {
  $plateau = $plateau * (0.8 + 0.4 * $softness)
  $wCold = $wCold * (0.8 + 0.4 * $softness) * (1.0 + ($compliance - 0.5) * 0.15)
  $wHot = $wHot * (0.8 + 0.4 * $softness)
  $diff = [math]::Abs($temp - $tOpt)
  $excess = [math]::Max(0.0, $diff - $plateau)
  $width = if ($temp -lt $tOpt) { $wCold } else { $wHot }
  $power = if ($temp -lt $tOpt) { $coldP } else { $hotP }
  $decay = [math]::Exp(-[math]::Pow($excess / [math]::Max(1.0, $width), $power))
  return $floor + (1.0 - $floor) * $decay
}

function Soften-Thermal([double]$tm, [double]$tread = 0.5, [bool]$isRaceCold = $false) {
  if ($tm -ge 1.0) { return $tm }
  if ($isRaceCold) {
    return [math]::Max(0.42, [math]::Pow($tm, 1.12))
  }
  $tol = 1.18 + (1.08 - 1.18) * $tread
  return [math]::Max(0.50, [math]::Pow($tm, 1.0 / $tol))
}

function Shape-Thermal([double]$tTherm, [double]$adhesion) {
  $adhesionWeight = [math]::Max(0.15, [math]::Min(0.75, $adhesion))
  $shaped = $tTherm * (0.62 + 0.38 * $tTherm)
  return $tTherm + ($shaped - $tTherm) * ($adhesionWeight * 0.55)
}

function Band-VsNative([double]$ratio) {
  # ratio of peakProd to native 1.0
  if ($ratio -lt 0.95) { return 'UNDER' }
  if ($ratio -le 1.05) { return 'NEAR' }
  return 'ABOVE'
}

# Helper to build a profile row
function New-Prof {
  param(
    [string]$Family, [string]$Id, [string]$Profile,
    [double]$Anchor, [string]$AnchorKey,
    [double]$gm, [double]$dry, [double]$lat, [double]$long,
    [double]$tOpt, [double]$plat, [double]$wc, [double]$wh, [double]$fl,
    [double]$ad, [double]$comp, [double]$slip, [double]$work,
    [hashtable]$Softcap, [hashtable]$Char,
    [double]$softness = 0.5, [double]$tread = 0.5,
    [bool]$isRaceCold = $false
  )
  return [pscustomobject]@{
    Family = $Family; Id = $Id; Profile = $Profile
    Anchor = $Anchor; AnchorKey = $AnchorKey
    gm = $gm; dry = $dry; lat = $lat; long = $long
    tOpt = $tOpt; plat = $plat; wc = $wc; wh = $wh; fl = $fl
    ad = $ad; comp = $comp; slip = $slip; work = $work
    Softcap = $Softcap; Char = $Char
    softness = $softness; tread = $tread; isRaceCold = $isRaceCold
  }
}

$profiles = New-Object System.Collections.Generic.List[object]

# ===== PROFILE_POINTS (street continuum) =====
$pp = @(
  @{ a=0.30; p='sport_plus';  gm=1.04; dry=1.04; lat=1.02; long=1.05; tOpt=76; plat=14; wc=52; wh=32; fl=0.24; ad=0.52; comp=0.45; slip=16.6; work=10.2; sc=$SOFTCAP_SPORT_PLUS; ch=$CHAR_SPORT_PLUS },
  @{ a=0.40; p='track_day';    gm=1.04; dry=1.04; lat=1.0; long=1.08; tOpt=76; plat=16; wc=64; wh=52; fl=0.28; ad=0.444; comp=0.42; slip=10.9; work=6.20; sc=$SOFTCAP_TRACK_DAY; ch=$CHAR_TRACK_DAY },
  @{ a=0.50; p='sport';       gm=1.00; dry=1.02; lat=1.0; long=1.0; tOpt=66; plat=18; wc=74; wh=55; fl=0.34; ad=0.42; comp=0.50; slip=9.68; work=5.61; sc=$SOFTCAP_SPORT; ch=$CHAR_SPORT },
  @{ a=0.60; p='standard';    gm=1.00; dry=1.01; lat=1.0; long=1.0; tOpt=63; plat=17; wc=66; wh=55; fl=0.30; ad=0.41; comp=0.55; slip=8.25; work=4.85; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ a=0.70; p='standard';    gm=1.00; dry=1.00; lat=1.0; long=1.0; tOpt=60; plat=16; wc=58; wh=55; fl=0.26; ad=0.40; comp=0.60; slip=7.9; work=4.8; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ a=0.80; p='allterrain';  gm=0.86; dry=1.00; lat=1.0; long=1.0; tOpt=56; plat=18; wc=58; wh=50; fl=0.26; ad=0.36; comp=0.75; slip=7.2; work=4.5; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ a=0.85; p='allterrain';  gm=0.84; dry=0.97; lat=1.0; long=1.0; tOpt=54; plat=18; wc=58; wh=50; fl=0.26; ad=0.34; comp=0.775; slip=6.75; work=4.2; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ a=0.90; p='mudterrain';  gm=0.82; dry=0.94; lat=1.0; long=1.0; tOpt=52; plat=18; wc=58; wh=50; fl=0.26; ad=0.32; comp=0.80; slip=6.3; work=3.9; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ a=1.00; p='crawler';     gm=0.78; dry=0.94; lat=1.0; long=1.0; tOpt=48; plat=18; wc=58; wh=50; fl=0.26; ad=0.28; comp=0.85; slip=5.775; work=3.3; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL }
)
foreach ($r in $pp) {
  $profiles.Add((New-Prof -Family 'PROFILE' -Id ("PP_t{0:n2}_{1}" -f $r.a, $r.p) -Profile $r.p `
    -Anchor $r.a -AnchorKey 'tread' -gm $r.gm -dry $r.dry -lat $r.lat -long $r.long `
    -tOpt $r.tOpt -plat $r.plat -wc $r.wc -wh $r.wh -fl $r.fl -ad $r.ad -comp $r.comp `
    -slip $r.slip -work $r.work -Softcap $r.sc -Char $r.ch -tread $r.a -softness 0.5))
}

# ===== SLICK_SPECTRUM_POINTS =====
$sk = @(
  @{ a=0.50;  p='hard_slick';   gm=0.96; dry=0.98; lat=0.74; long=1.0; tOpt=90; plat=14; wc=48; wh=48; fl=0.20; ad=0.48; comp=0.30; slip=8.5; work=5.1; ch=$CHAR_SLICK_HARD },
  @{ a=0.575; p='hard_slick';   gm=0.99; dry=0.98; lat=0.73; long=1.0; tOpt=87; plat=14; wc=47; wh=47; fl=0.20; ad=0.50; comp=0.275; slip=8.8; work=5.225; ch=$CHAR_SLICK_HARD },
  @{ a=0.65;  p='medium_slick'; gm=1.02; dry=0.98; lat=0.72; long=1.0; tOpt=84; plat=14; wc=46; wh=46; fl=0.20; ad=0.52; comp=0.25; slip=9.1; work=5.35; ch=$CHAR_SLICK_MED },
  @{ a=0.725; p='medium_slick'; gm=1.05; dry=0.98; lat=0.71; long=1.0; tOpt=83; plat=14; wc=45; wh=45; fl=0.19; ad=0.535; comp=0.235; slip=9.55; work=5.45; ch=$CHAR_SLICK_MED },
  @{ a=0.80;  p='soft_slick';   gm=1.08; dry=0.98; lat=0.70; long=1.0; tOpt=82; plat=14; wc=44; wh=44; fl=0.18; ad=0.55; comp=0.22; slip=10.0; work=5.55; ch=$CHAR_SLICK_SOFT }
)
foreach ($r in $sk) {
  $profiles.Add((New-Prof -Family 'SLICK' -Id ("SL_s{0:n3}_{1}" -f $r.a, $r.p) -Profile $r.p `
    -Anchor $r.a -AnchorKey 'softness' -gm $r.gm -dry $r.dry -lat $r.lat -long $r.long `
    -tOpt $r.tOpt -plat $r.plat -wc $r.wc -wh $r.wh -fl $r.fl -ad $r.ad -comp $r.comp `
    -slip $r.slip -work $r.work -Softcap $SOFTCAP_OFF -Char $r.ch -softness $r.a -tread 0.12 -isRaceCold $true))
}

# ===== UTILITY_SPECTRUM =====
$ut = @(
  @{ a=0.50; p='highway_utility_utility';    gm=0.90; dry=1.00; lat=1; long=1; tOpt=60; plat=16; wc=58; wh=55; fl=0.26; ad=0.40; comp=0.30; slip=7.875; work=4.2 },
  @{ a=0.60; p='highway_utility_utility';    gm=0.87; dry=1.00; lat=1; long=1; tOpt=58; plat=17; wc=58; wh=52.5; fl=0.26; ad=0.38; comp=0.325; slip=7.612; work=4.05 },
  @{ a=0.70; p='allterrain_utility_utility'; gm=0.84; dry=1.00; lat=1; long=1; tOpt=56; plat=18; wc=58; wh=50; fl=0.26; ad=0.36; comp=0.35; slip=7.35; work=3.9 },
  @{ a=0.85; p='mudterrain_utility_utility'; gm=0.80; dry=0.94; lat=1; long=1; tOpt=52; plat=18; wc=58; wh=50; fl=0.26; ad=0.32; comp=0.40; slip=6.51; work=3.6 },
  @{ a=0.95; p='logger_utility_utility';     gm=0.76; dry=0.94; lat=1; long=1; tOpt=50; plat=18; wc=58; wh=50; fl=0.26; ad=0.30; comp=0.45; slip=6.09; work=3.3 }
)
foreach ($r in $ut) {
  $profiles.Add((New-Prof -Family 'UTILITY' -Id ("UT_t{0:n2}" -f $r.a) -Profile $r.p `
    -Anchor $r.a -AnchorKey 'tread' -gm $r.gm -dry $r.dry -lat $r.lat -long $r.long `
    -tOpt $r.tOpt -plat $r.plat -wc $r.wc -wh $r.wh -fl $r.fl -ad $r.ad -comp $r.comp `
    -slip $r.slip -work $r.work -Softcap $SOFTCAP_STREET -Char $CHAR_NEUTRAL -tread $r.a))
}

# ===== COMMERCIAL_SPECTRUM =====
$cm = @(
  @{ a=0.50; p='highway_steer_truck';  gm=0.84; dry=1.00; lat=1; long=1; tOpt=62; plat=16; wc=58; wh=55; fl=0.26; ad=0.35; comp=0.12; slip=7.35; work=2.4 },
  @{ a=0.60; p='highway_trailer_truck'; gm=0.78; dry=1.00; lat=1; long=1; tOpt=62; plat=16; wc=58; wh=55; fl=0.26; ad=0.30; comp=0.10; slip=6.825; work=2.16 },
  @{ a=0.70; p='traction_drive_truck';  gm=0.82; dry=1.00; lat=1; long=1; tOpt=62; plat=16; wc=58; wh=55; fl=0.26; ad=0.35; comp=0.15; slip=7.875; work=2.7 },
  @{ a=0.80; p='traction_drive_truck';  gm=0.77; dry=0.97; lat=1; long=1; tOpt=59; plat=17; wc=58; wh=52.5; fl=0.26; ad=0.325; comp=0.165; slip=7.087; work=3.0 },
  @{ a=0.90; p='heavy_offroad_truck';   gm=0.72; dry=0.94; lat=1; long=1; tOpt=56; plat=18; wc=58; wh=50; fl=0.26; ad=0.30; comp=0.18; slip=6.3; work=3.3 }
)
foreach ($r in $cm) {
  $profiles.Add((New-Prof -Family 'COMMERCIAL' -Id ("CM_t{0:n2}" -f $r.a) -Profile $r.p `
    -Anchor $r.a -AnchorKey 'tread' -gm $r.gm -dry $r.dry -lat $r.lat -long $r.long `
    -tOpt $r.tOpt -plat $r.plat -wc $r.wc -wh $r.wh -fl $r.fl -ad $r.ad -comp $r.comp `
    -slip $r.slip -work $r.work -Softcap $SOFTCAP_STREET -Char $CHAR_NEUTRAL -tread $r.a))
}

# ===== ATV_UTV_SPECTRUM =====
$at = @(
  @{ a=0.50; p='hardpack_utv_utv';    gm=0.84; dry=1.00; lat=1; long=1; tOpt=55; plat=16; wc=58; wh=55; fl=0.26; ad=0.35; comp=0.80; slip=6.825; work=3.6 },
  @{ a=0.60; p='hardpack_utv_utv';    gm=0.82; dry=1.00; lat=1; long=1; tOpt=52.5; plat=17; wc=58; wh=52.5; fl=0.26; ad=0.325; comp=0.825; slip=6.562; work=3.45 },
  @{ a=0.70; p='allterrain_utv_utv';  gm=0.80; dry=1.00; lat=1; long=1; tOpt=50; plat=18; wc=58; wh=50; fl=0.26; ad=0.30; comp=0.85; slip=6.3; work=3.3 },
  @{ a=0.85; p='mud_utv_utv';         gm=0.76; dry=0.94; lat=1; long=1; tOpt=48; plat=18; wc=58; wh=50; fl=0.26; ad=0.28; comp=0.90; slip=5.775; work=3.0 }
)
foreach ($r in $at) {
  $profiles.Add((New-Prof -Family 'ATV_UTV' -Id ("AT_t{0:n2}" -f $r.a) -Profile $r.p `
    -Anchor $r.a -AnchorKey 'tread' -gm $r.gm -dry $r.dry -lat $r.lat -long $r.long `
    -tOpt $r.tOpt -plat $r.plat -wc $r.wc -wh $r.wh -fl $r.fl -ad $r.ad -comp $r.comp `
    -slip $r.slip -work $r.work -Softcap $SOFTCAP_STREET -Char $CHAR_NEUTRAL -tread $r.a))
}

# ===== VINTAGE_SPECTRUM =====
$vn = @(
  @{ a=0.50;  p='vintage_biasply_vintage'; gm=0.92; dry=1.00; lat=1; long=1; tOpt=56; plat=16; wc=58; wh=55; fl=0.26; ad=0.28; comp=0.65; slip=6.5; work=5.7 },
  @{ a=0.575; p='vintage_biasply_vintage'; gm=0.945; dry=1.00; lat=1; long=1; tOpt=58; plat=16; wc=58; wh=55; fl=0.26; ad=0.315; comp=0.60; slip=6.9; work=5.45 },
  @{ a=0.65;  p='classic_radial_vintage';  gm=0.97; dry=1.00; lat=1; long=1; tOpt=60; plat=16; wc=58; wh=55; fl=0.26; ad=0.35; comp=0.55; slip=7.4; work=5.05 }
)
foreach ($r in $vn) {
  $profiles.Add((New-Prof -Family 'VINTAGE' -Id ("VN_t{0:n3}" -f $r.a) -Profile $r.p `
    -Anchor $r.a -AnchorKey 'tread' -gm $r.gm -dry $r.dry -lat $r.lat -long $r.long `
    -tOpt $r.tOpt -plat $r.plat -wc $r.wc -wh $r.wh -fl $r.fl -ad $r.ad -comp $r.comp `
    -slip $r.slip -work $r.work -Softcap $SOFTCAP_VINTAGE -Char $CHAR_NEUTRAL -tread $r.a))
}

# ===== STANDALONE_MODIFIERS (key purpose tires) =====
$sa = @(
  @{ id='drag';           p='drag';           gm=1.18; dry=1.08; lat=0.92; long=1.12; tOpt=72; plat=12; wc=62; wh=55; fl=0.28; ad=0.58; comp=0.85; slip=16.2; work=6.6; sc=$SOFTCAP_OFF; ch=$CHAR_DRAG },
  @{ id='drift';          p='drift';          gm=0.88; dry=1.00; lat=0.92; long=0.95; tOpt=75; plat=14; wc=65; wh=65; fl=0.28; ad=0.48; comp=0.40; slip=10.0; work=3.6; sc=$SOFTCAP_OFF; ch=$CHAR_DRIFT },
  @{ id='vintage';        p='vintage';        gm=0.94; dry=1.00; lat=1.00; long=1.00; tOpt=58; plat=16; wc=58; wh=55; fl=0.26; ad=0.28; comp=0.60; slip=6.6; work=5.6; sc=$SOFTCAP_VINTAGE; ch=$CHAR_NEUTRAL },
  @{ id='crawler';        p='crawler';        gm=0.78; dry=0.94; lat=1.00; long=1.00; tOpt=48; plat=18; wc=58; wh=50; fl=0.26; ad=0.28; comp=0.85; slip=5.775; work=3.3; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='paddle';         p='paddle';         gm=0.74; dry=1.00; lat=1.00; long=1.00; tOpt=48; plat=18; wc=58; wh=50; fl=0.26; ad=0.25; comp=0.80; slip=6.3; work=3.6; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='truck';          p='truck';          gm=0.90; dry=1.00; lat=1.00; long=1.00; tOpt=65; plat=16; wc=58; wh=55; fl=0.26; ad=0.35; comp=0.12; slip=7.875; work=2.7; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='truck_offroad';  p='truck_offroad';  gm=0.82; dry=0.94; lat=1.00; long=1.00; tOpt=60; plat=16; wc=58; wh=55; fl=0.26; ad=0.32; comp=0.18; slip=6.3; work=3.3; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='heavy_duty';     p='heavy_duty';     gm=0.90; dry=1.00; lat=1.00; long=1.00; tOpt=65; plat=16; wc=58; wh=55; fl=0.26; ad=0.38; comp=0.15; slip=6.825; work=3.3; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='light_truck_std'; p='light_truck_std'; gm=0.90; dry=1.00; lat=1.00; long=1.00; tOpt=62; plat=16; wc=58; wh=55; fl=0.26; ad=0.42; comp=0.35; slip=8.4; work=4.8; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='light_truck_hd';  p='light_truck_hd';  gm=0.88; dry=1.00; lat=1.00; long=1.00; tOpt=65; plat=16; wc=58; wh=55; fl=0.26; ad=0.40; comp=0.25; slip=7.35; work=4.2; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='winter';         p='winter';         gm=0.86; dry=0.90; lat=1.00; long=1.00; tOpt=38; plat=16; wc=42; wh=40; fl=0.28; ad=0.40; comp=0.65; slip=7.875; work=4.2; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='donut';          p='donut';          gm=0.68; dry=1.00; lat=0.88; long=0.95; tOpt=60; plat=14; wc=55; wh=55; fl=0.22; ad=0.30; comp=0.45; slip=11.5; work=6.6; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL },
  @{ id='rally';          p='rally';          gm=0.96; dry=1.00; lat=1.06; long=1.00; tOpt=68; plat=16; wc=62; wh=55; fl=0.28; ad=0.45; comp=0.55; slip=9.45; work=5.1; sc=$SOFTCAP_OFF; ch=$CHAR_NEUTRAL },
  @{ id='rain';           p='rain';           gm=0.90; dry=0.92; lat=1.05; long=1.02; tOpt=58; plat=15; wc=62; wh=55; fl=0.28; ad=0.50; comp=0.50; slip=9.9; work=5.4; sc=$SOFTCAP_STREET; ch=$CHAR_NEUTRAL }
)
foreach ($r in $sa) {
  $profiles.Add((New-Prof -Family 'STANDALONE' -Id ("SA_{0}" -f $r.id) -Profile $r.p `
    -Anchor 0 -AnchorKey 'n/a' -gm $r.gm -dry $r.dry -lat $r.lat -long $r.long `
    -tOpt $r.tOpt -plat $r.plat -wc $r.wc -wh $r.wh -fl $r.fl -ad $r.ad -comp $r.comp `
    -slip $r.slip -work $r.work -Softcap $r.sc -Char $r.ch -tread 0.5 -softness 0.5))
}

# Native reference row
$NATIVE_PEAK = 1.0
$NATIVE_THERM = 1.0

Out '================================================================'
Out 'PROFILE vs NATIVE soft-sim (frictionCoef=1, dry paved, load=1x)'
Out 'Native ref: peakProd=1.00, thermal=1.00 (mod disables native thermal)'
Out 'Limitation: soft-sim math only — not in-game native telemetry'
Out '================================================================'
Out ''
Out ('{0,-28} {1,7} {2,7} {3,7} {4,7} {5,7} {6,7} {7,6} {8,6} {9,8} {10,6}' -f `
  'profile', 'peak', 'lat', 'long', 'cold20', 'hot+40', 'polyPk', 'slipH', 'workH', 'softcap', 'band')
Out ('{0,-28} {1,7} {2,7} {3,7} {4,7} {5,7} {6,7} {7,6} {8,6} {9,8} {10,6}' -f `
  '----------------------------', '------', '------', '------', '------', '------', '------', '-----', '-----', '-------', '----')
Out ('{0,-28} {1,7:n3} {2,7:n3} {3,7:n3} {4,7:n3} {5,7:n3} {6,7:n3} {7,6} {8,6} {9,8} {10,6}' -f `
  'NATIVE_REF', $NATIVE_PEAK, $NATIVE_PEAK, $NATIVE_PEAK, $NATIVE_THERM, $NATIVE_THERM, $NATIVE_PEAK, '-', '-', 'n/a', 'REF')

$rows = New-Object System.Collections.Generic.List[object]
foreach ($p in $profiles) {
  $peak = $p.gm * $p.dry
  $peakLat = $peak * $p.lat
  $peakLong = $peak * $p.long
  $poly = Get-PolyPeak $p.Profile
  $polyPeak = $poly * $peak

  $rawCold = Get-Thermal 20.0 $p.tOpt $p.plat $p.wc $p.wh $p.fl $p.Char.coldP $p.Char.hotP $p.comp $p.softness
  $tmCold = Soften-Thermal $rawCold $p.tread $p.isRaceCold
  $ctCold = Shape-Thermal $tmCold $p.ad
  $coldProd = $ctCold * $peak

  $hotT = $p.tOpt + 40.0
  $rawHot = Get-Thermal $hotT $p.tOpt $p.plat $p.wc $p.wh $p.fl $p.Char.coldP $p.Char.hotP $p.comp $p.softness
  $tmHot = Soften-Thermal $rawHot $p.tread $p.isRaceCold
  $ctHot = Shape-Thermal $tmHot $p.ad
  $hotProd = $ctHot * $peak

  # At optimal: thermal should be ~1 after soften/shape of plateau
  $rawOpt = Get-Thermal $p.tOpt $p.tOpt $p.plat $p.wc $p.wh $p.fl $p.Char.coldP $p.Char.hotP $p.comp $p.softness
  $tmOpt = Soften-Thermal $rawOpt $p.tread $false
  $ctOpt = Shape-Thermal $tmOpt $p.ad

  $band = Band-VsNative $peak
  $scLabel = '{0}/{1:n2}' -f $p.Softcap.label, $p.Softcap.heatMin

  $row = [pscustomobject]@{
    Family = $p.Family; Id = $p.Id; Profile = $p.Profile
    peak = $peak; peakLat = $peakLat; peakLong = $peakLong
    cold = $coldProd; hot = $hotProd; polyPeak = $polyPeak
    ctCold = $ctCold; ctHot = $ctHot; ctOpt = $ctOpt
    slip = $p.slip; work = $p.work
    softcap = $scLabel; band = $band
    gm = $p.gm; dry = $p.dry; lat = $p.lat; long = $p.long
    tOpt = $p.tOpt
  }
  $rows.Add($row)

  Out ('{0,-28} {1,7:n3} {2,7:n3} {3,7:n3} {4,7:n3} {5,7:n3} {6,7:n3} {7,6:n2} {8,6:n2} {9,8} {10,6}' -f `
    $p.Id, $peak, $peakLat, $peakLong, $coldProd, $hotProd, $polyPeak, $p.slip, $p.work, $scLabel, $band)
}

# ---- Family summaries ----
Out ''
Out '--- BAND COUNTS (peakProd = gm*dry vs native 1.0) ---'
$under = @($rows | Where-Object { $_.band -eq 'UNDER' }).Count
$near  = @($rows | Where-Object { $_.band -eq 'NEAR' }).Count
$above = @($rows | Where-Object { $_.band -eq 'ABOVE' }).Count
Out ("UNDER (<0.95): {0}   NEAR (0.95-1.05): {1}   ABOVE (>1.05): {2}   total={3}" -f $under, $near, $above, $rows.Count)

Out ''
Out '--- FAMILY PEAK PRODUCT RANGES vs native 1.0 ---'
foreach ($fam in @('PROFILE','SLICK','UTILITY','COMMERCIAL','ATV_UTV','VINTAGE','STANDALONE')) {
  $frows = @($rows | Where-Object { $_.Family -eq $fam })
  if ($frows.Count -eq 0) { continue }
  $mins = ($frows | Measure-Object -Property peak -Minimum).Minimum
  $maxs = ($frows | Measure-Object -Property peak -Maximum).Maximum
  $avgs = ($frows | Measure-Object -Property peak -Average).Average
  Out ("{0,-12} n={1}  peak [{2:n3} .. {3:n3}]  avg={4:n3}" -f $fam, $frows.Count, $mins, $maxs, $avgs)
}

# ---- Special callouts ----
Out ''
Out '--- SPECIAL: STREET CONTINUUM vs native ---'
foreach ($id in @('PP_t0.70_standard','PP_t0.50_sport','PP_t0.40_track_day','PP_t0.30_sport_plus')) {
  $r = $rows | Where-Object { $_.Id -eq $id } | Select-Object -First 1
  if ($r) {
    Out ("  {0}: peak={1:n3} ({2}) cold20={3:n3} polyPk={4:n3} slip/work={5:n2}/{6:n2}" -f `
      $r.Id, $r.peak, $r.band, $r.cold, $r.polyPeak, $r.slip, $r.work)
  }
}

Out ''
Out '--- SPECIAL: SLICKS (overall peak vs lat; cold cliff) ---'
foreach ($r in ($rows | Where-Object { $_.Family -eq 'SLICK' })) {
  Out ("  {0}: peak={1:n3} lat={2:n3} long={3:n3} cold20={4:n3} (therm={5:n3}) hot+40={6:n3} polyPk={7:n3}" -f `
    $r.Id, $r.peak, $r.peakLat, $r.peakLong, $r.cold, $r.ctCold, $r.hot, $r.polyPeak)
}
$medSlick = $rows | Where-Object { $_.Id -eq 'SL_s0.650_medium_slick' } | Select-Object -First 1
$std = $rows | Where-Object { $_.Id -eq 'PP_t0.70_standard' } | Select-Object -First 1
if ($medSlick -and $std) {
  Out ("  NOTE: medium_slick overall peak {0:n3} vs standard {1:n3}; lat product {2:n3} is UNDER native (anti-trip)." -f `
    $medSlick.peak, $std.peak, $medSlick.peakLat)
}

Out ''
Out '--- SPECIAL: VINTAGE / BIAS-PLY ---'
foreach ($r in ($rows | Where-Object { $_.Family -eq 'VINTAGE' -or $_.Id -eq 'SA_vintage' })) {
  Out ("  {0}: peak={1:n3} ({2}) cold20={3:n3} polyPk={4:n3} slip/work={5:n2}/{6:n2} softcap={7}" -f `
    $r.Id, $r.peak, $r.band, $r.cold, $r.polyPeak, $r.slip, $r.work, $r.softcap)
}
$bias = $rows | Where-Object { $_.Id -eq 'VN_t0.500' } | Select-Object -First 1
if ($bias -and $std) {
  Out ("  NOTE: bias-ply peak {0:n0}% of native / {1:n0}% of standard; workHeat {2:n2} elevated vs street (flex), softcap gentler than street." -f `
    (100.0 * $bias.peak), (100.0 * $bias.peak / $std.peak), $bias.work)
}

Out ''
Out '--- SPECIAL: PURPOSE STANDALONES ---'
foreach ($id in @('SA_drag','SA_drift','SA_rally','SA_rain','SA_winter','SA_crawler','SA_donut')) {
  $r = $rows | Where-Object { $_.Id -eq $id } | Select-Object -First 1
  if ($r) {
    Out ("  {0}: peak={1:n3} lat={2:n3} long={3:n3} ({4}) cold20={5:n3} slip/work={6:n2}/{7:n2}" -f `
      $r.Id, $r.peak, $r.peakLat, $r.peakLong, $r.band, $r.cold, $r.slip, $r.work)
  }
}

# ---- Asserts ----
$fail = 0
function Expect([bool]$ok, [string]$msg) {
  if ($ok) {
    Out "PASS $msg"
  } else {
    $script:fail++
    Out "FAIL $msg"
  }
}

Out ''
Out '--- ASSERTS ---'
Expect ($rows.Count -ge 40) ('inventory size >= 40 anchors (got {0})' -f $rows.Count)
Expect ($std.peak -ge 0.95 -and $std.peak -le 1.05) ('standard peak near native ({0:n3})' -f $std.peak)
$sp = $rows | Where-Object { $_.Id -eq 'PP_t0.30_sport_plus' } | Select-Object -First 1
Expect ($sp.peak -gt $std.peak) ('sport_plus peak above standard ({0:n3} vs {1:n3})' -f $sp.peak, $std.peak)
Expect ($medSlick.polyPeak -gt $std.polyPeak) ('medium_slick polyPeak above standard ({0:n3} vs {1:n3})' -f $medSlick.polyPeak, $std.polyPeak)
Expect ($medSlick.peakLat -lt $NATIVE_PEAK) ('slick lat product UNDER native ({0:n3})' -f $medSlick.peakLat)
Expect ($medSlick.ctCold -lt 0.85) ('slick cold cliff at 20C (therm={0:n3})' -f $medSlick.ctCold)
Expect ($bias.peak -lt 0.95) ('bias-ply peak UNDER native ({0:n3})' -f $bias.peak)
Expect ($bias.work -gt $std.work) ('bias-ply workHeat above standard ({0:n2} vs {1:n2})' -f $bias.work, $std.work)
$drag = $rows | Where-Object { $_.Id -eq 'SA_drag' } | Select-Object -First 1
Expect ($drag.peak -gt 1.05) ('drag ABOVE native peak ({0:n3})' -f $drag.peak)
Expect ($drag.slip -gt 12) ('drag high slipHeat ({0:n2})' -f $drag.slip)
$donut = $rows | Where-Object { $_.Id -eq 'SA_donut' } | Select-Object -First 1
Expect ($donut.peak -lt 0.75) ('donut well UNDER native ({0:n3})' -f $donut.peak)
$winter = $rows | Where-Object { $_.Id -eq 'SA_winter' } | Select-Object -First 1
Expect ($winter.peak -lt 0.95) ('winter dry peak UNDER native ({0:n3})' -f $winter.peak)
# Softcap stamps
$slickSc = $rows | Where-Object { $_.Family -eq 'SLICK' } | Select-Object -First 1
Expect ($slickSc.softcap -like 'OFF*') ('slick softcap OFF ({0})' -f $slickSc.softcap)
Expect ($bias.softcap -like 'vintage*') ('vintage softcap pack ({0})' -f $bias.softcap)
Expect ($std.softcap -like 'street*') ('standard street softcap ({0})' -f $std.softcap)

Out ''
if ($fail -gt 0) {
  Out "ASSERTS: $fail failed"
  Out "VERDICT: FAIL"
  $sb.ToString() | Set-Content -LiteralPath $outPath -Encoding UTF8
  Write-Host "Wrote $outPath"
  exit 1
}
Out 'ASSERTS: all passed'
Out 'VERDICT: PASS'
$sb.ToString() | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "Wrote $outPath"
exit 0
