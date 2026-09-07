# Light + medium duty truck tires x ALL surfaces
$ErrorActionPreference = 'Stop'
$out = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Node-Thermal-Friction-dev\tools\output\light-medium-truck-surface-test.txt'

function Lerp([double]$a,[double]$b,[double]$t){ return $a+($b-$a)*$t }
function Clamp([double]$v,[double]$lo,[double]$hi){ if($v -lt $lo){return $lo}; if($v -gt $hi){return $hi}; return $v }

$gripCoeffs = @(
  @{tag='mudterrain'; c=@(0.76,0.08,-0.02)},
  @{tag='allterrain'; c=@(0.82,0.10,-0.03)},
  @{tag='crawler'; c=@(0.72,0.06,-0.02)},
  @{tag='utility'; c=@(0.84,0.08,-0.02)},
  @{tag='truck'; c=@(0.86,0.08,-0.02)},
  @{tag='heavy'; c=@(0.84,0.08,-0.02)},
  @{tag='standard'; c=@(0.92,0.12,-0.04)}
)
function Baseline([string]$profile) {
  $p = $profile.ToLowerInvariant()
  foreach ($row in $gripCoeffs) {
    if ($p.Contains($row.tag)) { $c=$row.c; return $c[0]+$c[1]+$c[2] }
  }
  return 0.90
}

function SurfaceScale([string]$surface, [double]$tread, [double]$drainage) {
  switch ($surface) {
    'dry_paved'   { $a = Lerp 1.04 0.90 $tread; return ,@($a, 1.15) }
    'hard_smooth' { $a = Lerp 0.96 0.90 $tread; return ,@($a, 1.10) }
    'wet_paved'   {
      $wet = (Lerp 0.82 0.98 $drainage) * (Lerp 0.94 1.02 $tread)
      $dry = Lerp 1.06 0.90 $tread
      $a = [math]::Min($wet, $dry * 0.92)
      return ,@($a, 1.15)
    }
    'gravel'      { $a = Lerp 0.55 1.05 $tread; return ,@($a, 1.00) }
    'gravel_wet'  { $a = Lerp 0.48 0.95 $tread; return ,@($a, 0.88) }
    'dirt'        { $a = Lerp 0.62 1.02 $tread; return ,@($a, 0.95) }
    'mud'         { $a = Lerp 0.34 1.08 $tread; return ,@($a, 0.85) }
    'sand'        { $a = Lerp 0.42 1.04 $tread; return ,@($a, 0.90) }
    'snow'        { $a = Lerp 0.36 1.00 $tread; return ,@($a, 0.60) }
    'ice'         { $a = Lerp 0.42 0.78 $tread; return ,@($a, 0.30) }
    'rock'        { $a = Lerp 0.88 1.05 $tread; return ,@($a, 1.40) }
    'generic'     { return ,@(1.0, 1.30) }
    default       { return ,@(1.0, 1.30) }
  }
}

# Live applyProfileSurfaceBias (post truck fix)
function ProfileBias([double]$g, [string]$surface, [string]$profile) {
  $p = $profile.ToLowerInvariant()
  $isPaddle=$p.Contains('paddle'); $isWinter=$p.Contains('winter'); $isRally=$p.Contains('rally')
  $isCrawler=$p.Contains('crawler'); $isMT=$p.Contains('mudterrain'); $isAT=$p.Contains('allterrain')
  $isSlick=$p.Contains('slick'); $isRain=($p -eq 'rain'); $isDrift=$p.Contains('drift'); $isDrag=$p.Contains('drag')
  $isTruckOffroad=$p.Contains('offroad') -or $p.Contains('logger')
  $isTruckDrive=$p.Contains('traction') -and $p.Contains('drive')
  $isTruckHighway=$p.Contains('highway') -or $p.Contains('trailer') -or ($p.Contains('steer') -and $p.Contains('truck'))
  $isLightTruckHd=$p.Contains('light_truck_hd') -or $p.Contains('heavy_duty')
  $isLightTruck=$p.Contains('light_truck') -and -not $isLightTruckHd

  switch ($surface) {
    'sand' {
      if($isPaddle){return $g*1.35} elseif($isMT){return $g*1.10} elseif($isAT -or $isCrawler){return $g*1.06}
      elseif($isTruckOffroad){return $g*1.08} elseif($isTruckDrive){return $g*1.04}
      elseif($isTruckHighway){return $g*0.90} elseif($isSlick -or $isDrag){return $g*0.88}
    }
    'mud' {
      if($isPaddle){return $g*1.25} elseif($isMT -or $isCrawler){return $g*1.14} elseif($isAT){return $g*1.08}
      elseif($isTruckOffroad){return $g*1.12} elseif($isTruckDrive){return $g*1.06}
      elseif($isLightTruckHd -or $isLightTruck){return $g*1.04} elseif($isTruckHighway){return $g*0.88}
      elseif($isSlick -or $isDrag){return $g*0.82}
    }
    'rock' {
      if($isCrawler){return $g*1.18} elseif($isTruckOffroad){return $g*1.14}
      elseif($isAT -or $isTruckDrive){return $g*1.06} elseif($isTruckHighway){return $g*0.96}
      elseif($isPaddle){return $g*0.80} elseif($isSlick){return $g*0.94}
    }
    { $_ -in @('gravel','dirt') } {
      if($isRally){return $g*1.12} elseif($isAT){return $g*1.10} elseif($isTruckOffroad){return $g*1.10}
      elseif($isMT){return $g*1.06} elseif($isTruckDrive){return $g*1.05}
      elseif($isLightTruckHd -or $isLightTruck){return $g*1.04} elseif($isTruckHighway){return $g*0.94}
      elseif($isSlick -or $isDrag){return $g*0.90} elseif($isDrift){return $g*0.95}
    }
    'gravel_wet' {
      if($isRally -or $isAT){return $g*1.08} elseif($isMT -or $isCrawler -or $isTruckOffroad){return $g*1.10}
      elseif($isTruckDrive){return $g*1.04} elseif($isRain){return $g*1.06}
      elseif($isTruckHighway){return $g*0.90} elseif($isSlick){return $g*0.85}
    }
    { $_ -in @('snow','ice') } {
      if($isWinter){return $g*1.22} elseif($isRain){return $g*1.08}
      elseif($isAT -or $isTruckOffroad){return $g*1.05} elseif($isTruckDrive){return $g*1.03}
      elseif($isTruckHighway){return $g*0.92} elseif($isSlick -or $isDrag){return $g*0.82}
    }
    'wet_paved' {
      if($isRain){return $g*1.06} elseif($isWinter){return $g*1.04}
      elseif($isSlick -or $isDrag){return $g*0.92}
    }
    { $_ -in @('dry_paved','hard_smooth') } {
      if($isSlick -or $isDrag){return $g*1.02}
      elseif($isMT -or $isCrawler -or $isTruckOffroad){return $g*0.96}
      elseif($isPaddle){return $g*0.90}
      elseif($isTruckHighway){return $g*1.02}
    }
  }
  return $g
}

# Light + medium duty family (utility spectrum + standalone light/medium)
$tires = @(
  @{ class='medium'; name='highway_utility_utility';      tread=0.50; gm=0.90; drain=0.85; wet=1.062; dry=1.00 },
  @{ class='medium'; name='allterrain_utility_utility';   tread=0.70; gm=0.84; drain=0.90; wet=1.12;  dry=1.00 },
  @{ class='medium'; name='mudterrain_utility_utility';   tread=0.85; gm=0.80; drain=0.95; wet=1.12;  dry=0.94 },
  @{ class='medium'; name='logger_utility_utility';       tread=0.95; gm=0.76; drain=0.95; wet=1.12;  dry=0.94 },
  @{ class='light';  name='light_truck_std';             tread=0.55; gm=0.90; drain=0.80; wet=1.05;  dry=1.00 },
  @{ class='light';  name='light_truck_hd';              tread=0.70; gm=0.88; drain=0.80; wet=1.05;  dry=1.00 },
  @{ class='medium'; name='heavy_duty';                   tread=0.60; gm=0.90; drain=0.75; wet=1.038; dry=1.00 }
)

$surfaces = @('dry_paved','hard_smooth','wet_paved','gravel','gravel_wet','dirt','mud','sand','snow','ice','rock','generic')
$mu = @{
  dry_paved=1.00; hard_smooth=0.85; wet_paved=0.70; gravel=0.75; gravel_wet=0.55
  dirt=0.70; mud=0.50; sand=0.55; snow=0.35; ice=0.18; rock=0.90; generic=0.80
}

function EffGrip($tire, [string]$surface) {
  $g = (Baseline $tire.name) * [double]$tire.gm
  $sc = SurfaceScale $surface ([double]$tire.tread) ([double]$tire.drain)
  $g = $g * [double]$sc[0]
  $g = ProfileBias $g $surface $tire.name
  if ($surface -eq 'wet_paved' -or $surface -eq 'gravel_wet') {
    $g = $g * [double]$tire.wet
    if ($surface -eq 'wet_paved') {
      $drySc = SurfaceScale 'dry_paved' ([double]$tire.tread) ([double]$tire.drain)
      $wetSc = SurfaceScale 'wet_paved' ([double]$tire.tread) ([double]$tire.drain)
      $dryBias = 1.0
      $pn = $tire.name.ToLowerInvariant()
      if ($pn.Contains('mudterrain') -or $pn.Contains('crawler') -or $pn.Contains('offroad') -or $pn.Contains('logger')) { $dryBias = 0.96 }
      elseif ($pn.Contains('highway') -or $pn.Contains('trailer')) { $dryBias = 1.02 }
      $ratioCap = ([double]$drySc[0] * [double]$tire.dry * $dryBias) / [math]::Max(0.001, [double]$wetSc[0] * [double]$tire.wet) * 0.98
      if ($ratioCap -lt 1.0) { $g = $g * $ratioCap }
    }
  } elseif ($surface -eq 'dry_paved' -or $surface -eq 'hard_smooth') {
    $g = $g * [double]$tire.dry
  }
  $beam = Clamp ([double]$mu[$surface]) 0.18 1.20
  return [math]::Round([math]::Min($g, [double]$sc[1] / $beam), 3)
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('LIGHT + MEDIUM DUTY TRUCK TIRES x ALL SURFACES')
[void]$sb.AppendLine('Warm 100% condition; baseline x gm x surfaceScale x profileBias x wet/dryScale x cap')
[void]$sb.AppendLine('')

$hdr = 'profile'.PadRight(34)
foreach ($s in $surfaces) { $hdr += ('{0,10}' -f $s) }
[void]$sb.AppendLine($hdr)

$rows = @{}
foreach ($tire in $tires) {
  $line = ('[{0}] {1}' -f $tire.class, $tire.name).PadRight(34)
  $row = @{}
  foreach ($s in $surfaces) {
    $v = EffGrip $tire $s
    $row[$s] = $v
    $line += ('{0,10:n3}' -f $v)
  }
  $rows[$tire.name] = $row
  [void]$sb.AppendLine($line)
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== LOGIC CHECKS ===')
$fail = 0; $pass = 0
function Expect([bool]$ok, [string]$msg) {
  if ($ok) { $script:pass++; [void]$sb.AppendLine("PASS  $msg") }
  else { $script:fail++; [void]$sb.AppendLine("FAIL  $msg") }
}

# Pavement: highway utility should beat logger/MT
Expect ($rows['highway_utility_utility']['dry_paved'] -gt $rows['logger_utility_utility']['dry_paved']) 'highway_utility > logger on dry_paved'
Expect ($rows['highway_utility_utility']['dry_paved'] -gt $rows['mudterrain_utility_utility']['dry_paved']) 'highway_utility > MT on dry_paved'
Expect ($rows['light_truck_std']['dry_paved'] -ge $rows['light_truck_hd']['dry_paved'] - 0.02) 'light_truck_std ~>= light_truck_hd on dry_paved'

# Loose: MT/logger/AT beat highway
foreach ($s in @('mud','dirt','gravel','sand')) {
  Expect ($rows['mudterrain_utility_utility'][$s] -gt $rows['highway_utility_utility'][$s]) "MT > highway on $s"
  Expect ($rows['logger_utility_utility'][$s] -gt $rows['highway_utility_utility'][$s]) "logger > highway on $s"
  Expect ($rows['allterrain_utility_utility'][$s] -gt $rows['highway_utility_utility'][$s]) "AT > highway on $s"
}

# MT best-ish on mud among utility spectrum
Expect ($rows['mudterrain_utility_utility']['mud'] -ge $rows['allterrain_utility_utility']['mud']) 'MT >= AT on mud'
Expect ($rows['logger_utility_utility']['mud'] -ge $rows['highway_utility_utility']['mud']) 'logger >= highway on mud'

# Light HD should beat light std on loose (mild bias + tread)
Expect ($rows['light_truck_hd']['dirt'] -gt $rows['light_truck_std']['dirt']) 'light_truck_hd > light_truck_std on dirt'
Expect ($rows['light_truck_hd']['mud'] -gt $rows['light_truck_std']['mud']) 'light_truck_hd > light_truck_std on mud'

# heavy_duty between highway and AT on dirt
$hd = $rows['heavy_duty']['dirt']
Expect (($hd -ge $rows['highway_utility_utility']['dirt']) -and ($hd -le $rows['allterrain_utility_utility']['dirt'] + 0.05)) `
  "heavy_duty dirt between highway and AT ($hd)"

# Wet paved: all retain usable grip; ice lowest
foreach ($t in $tires) {
  $n = $t.name
  Expect ($rows[$n]['ice'] -lt $rows[$n]['dirt']) "$n ice < dirt"
  Expect ($rows[$n]['ice'] -lt $rows[$n]['dry_paved']) "$n ice < dry_paved"
  Expect ($rows[$n]['wet_paved'] -lt $rows[$n]['dry_paved']) "$n wet_paved < dry_paved"
  Expect ($rows[$n]['wet_paved'] -gt 0.40) "$n wet_paved usable (>0.40)"
}

# Rock: logger/AT should beat highway
Expect ($rows['logger_utility_utility']['rock'] -gt $rows['highway_utility_utility']['rock']) 'logger > highway on rock'
Expect ($rows['allterrain_utility_utility']['rock'] -gt $rows['highway_utility_utility']['rock']) 'AT > highway on rock'

[void]$sb.AppendLine('')
[void]$sb.AppendLine("RESULT: $pass passed, $fail failed")

# Ranking helpers
[void]$sb.AppendLine('')
[void]$sb.AppendLine('=== BEST PER SURFACE ===')
foreach ($s in $surfaces) {
  $best = $null; $bestV = -1
  foreach ($tire in $tires) {
    $v = $rows[$tire.name][$s]
    if ($v -gt $bestV) { $bestV = $v; $best = $tire.name }
  }
  [void]$sb.AppendLine(('{0,-12} {1} ({2:n3})' -f $s, $best, $bestV))
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
if ($fail -gt 0) { Write-Output "FAIL count=$fail"; exit 1 }
Write-Output "OK pass=$pass"
