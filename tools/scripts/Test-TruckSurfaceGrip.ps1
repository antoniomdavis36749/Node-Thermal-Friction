# Post-fix truck x non-asphalt grip matrix (matches live applyProfileSurfaceBias)
$ErrorActionPreference = 'Stop'
$out = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Node-Thermal-Friction-dev\tools\output\truck-surface-grip-test.txt'

function Lerp([double]$a,[double]$b,[double]$t){ return $a+($b-$a)*$t }
function Clamp([double]$v,[double]$lo,[double]$hi){ if($v -lt $lo){return $lo}; if($v -gt $hi){return $hi}; return $v }

$gripCoeffs = @(
  @{tag='mudterrain'; c=@(0.76,0.08,-0.02)},
  @{tag='allterrain'; c=@(0.82,0.10,-0.03)},
  @{tag='crawler'; c=@(0.72,0.06,-0.02)},
  @{tag='utility'; c=@(0.84,0.08,-0.02)},
  @{tag='truck'; c=@(0.86,0.08,-0.02)},
  @{tag='heavy'; c=@(0.84,0.08,-0.02)}
)
function Baseline([string]$profile) {
  $p=$profile.ToLowerInvariant()
  foreach($row in $gripCoeffs){ if($p.Contains($row.tag)){ $c=$row.c; return $c[0]+$c[1]+$c[2] } }
  return 0.90
}
function SurfaceScale([string]$surface,[double]$tread,[double]$drainage){
  switch($surface){
    'gravel'{return ,@( (Lerp 0.55 1.05 $tread),1.00)}
    'gravel_wet'{return ,@( (Lerp 0.48 0.95 $tread),0.88)}
    'dirt'{return ,@( (Lerp 0.62 1.02 $tread),0.95)}
    'mud'{return ,@( (Lerp 0.34 1.08 $tread),0.85)}
    'sand'{return ,@( (Lerp 0.42 1.04 $tread),0.90)}
    'snow'{return ,@( (Lerp 0.36 1.00 $tread),0.60)}
    'ice'{return ,@( (Lerp 0.42 0.78 $tread),0.30)}
    'rock'{return ,@( (Lerp 0.88 1.05 $tread),1.40)}
    'hard_smooth'{return ,@( (Lerp 0.98 0.92 $tread),1.45)}
    default{return ,@(1.0,1.30)}
  }
}
function ProfileBias([double]$g,[string]$surface,[string]$profile){
  $p=$profile.ToLowerInvariant()
  $isPaddle=$p.Contains('paddle'); $isWinter=$p.Contains('winter'); $isRally=$p.Contains('rally')
  $isCrawler=$p.Contains('crawler'); $isMT=$p.Contains('mudterrain'); $isAT=$p.Contains('allterrain')
  $isSlick=$p.Contains('slick'); $isRain=($p -eq 'rain'); $isDrift=$p.Contains('drift'); $isDrag=$p.Contains('drag')
  $isTruckOffroad=$p.Contains('offroad') -or $p.Contains('logger')
  $isTruckDrive=$p.Contains('traction') -and $p.Contains('drive')
  $isTruckHighway=$p.Contains('highway') -or $p.Contains('trailer') -or ($p.Contains('steer') -and $p.Contains('truck'))
  $isLightTruckHd=$p.Contains('light_truck_hd') -or $p.Contains('heavy_duty')
  $isLightTruck=$p.Contains('light_truck') -and -not $isLightTruckHd
  switch($surface){
    'sand'{
      if($isPaddle){return $g*1.35} elseif($isMT){return $g*1.10} elseif($isAT -or $isCrawler){return $g*1.06}
      elseif($isTruckOffroad){return $g*1.08} elseif($isTruckDrive){return $g*1.04}
      elseif($isTruckHighway){return $g*0.90} elseif($isSlick -or $isDrag){return $g*0.88}
    }
    'mud'{
      if($isPaddle){return $g*1.25} elseif($isMT -or $isCrawler){return $g*1.14} elseif($isAT){return $g*1.08}
      elseif($isTruckOffroad){return $g*1.12} elseif($isTruckDrive){return $g*1.06}
      elseif($isLightTruckHd -or $isLightTruck){return $g*1.04} elseif($isTruckHighway){return $g*0.88}
      elseif($isSlick -or $isDrag){return $g*0.82}
    }
    'rock'{
      if($isCrawler){return $g*1.18} elseif($isTruckOffroad){return $g*1.14}
      elseif($isAT -or $isTruckDrive){return $g*1.06} elseif($isTruckHighway){return $g*0.96}
      elseif($isPaddle){return $g*0.80} elseif($isSlick){return $g*0.94}
    }
    {$_ -in @('gravel','dirt')}{
      if($isRally){return $g*1.12} elseif($isAT){return $g*1.10} elseif($isTruckOffroad){return $g*1.10}
      elseif($isMT){return $g*1.06} elseif($isTruckDrive){return $g*1.05}
      elseif($isLightTruckHd -or $isLightTruck){return $g*1.04} elseif($isTruckHighway){return $g*0.94}
      elseif($isSlick -or $isDrag){return $g*0.90} elseif($isDrift){return $g*0.95}
    }
    'gravel_wet'{
      if($isRally -or $isAT){return $g*1.08} elseif($isMT -or $isCrawler -or $isTruckOffroad){return $g*1.10}
      elseif($isTruckDrive){return $g*1.04} elseif($isRain){return $g*1.06}
      elseif($isTruckHighway){return $g*0.90} elseif($isSlick){return $g*0.85}
    }
    {$_ -in @('snow','ice')}{
      if($isWinter){return $g*1.22} elseif($isRain){return $g*1.08}
      elseif($isAT -or $isTruckOffroad){return $g*1.05} elseif($isTruckDrive){return $g*1.03}
      elseif($isTruckHighway){return $g*0.92} elseif($isSlick -or $isDrag){return $g*0.82}
    }
  }
  return $g
}

$tires=@(
  @{name='highway_steer_truck';tread=0.50;gm=0.84;drain=0.85;wet=1.062;dry=1.00},
  @{name='highway_trailer_truck';tread=0.60;gm=0.78;drain=0.85;wet=1.062;dry=1.00},
  @{name='traction_drive_truck';tread=0.70;gm=0.82;drain=0.80;wet=1.05;dry=1.00},
  @{name='heavy_offroad_truck';tread=0.90;gm=0.72;drain=0.95;wet=1.12;dry=0.94},
  @{name='highway_utility_utility';tread=0.50;gm=0.90;drain=0.85;wet=1.062;dry=1.00},
  @{name='allterrain_utility_utility';tread=0.70;gm=0.84;drain=0.90;wet=1.12;dry=1.00},
  @{name='mudterrain_utility_utility';tread=0.85;gm=0.80;drain=0.95;wet=1.12;dry=0.94},
  @{name='logger_utility_utility';tread=0.95;gm=0.76;drain=0.95;wet=1.12;dry=0.94},
  @{name='truck';tread=0.55;gm=0.90;drain=0.85;wet=1.062;dry=1.00},
  @{name='truck_offroad';tread=0.85;gm=0.82;drain=0.95;wet=1.12;dry=0.94},
  @{name='heavy_duty';tread=0.60;gm=0.90;drain=0.75;wet=1.038;dry=1.00},
  @{name='light_truck_std';tread=0.55;gm=0.90;drain=0.80;wet=1.05;dry=1.00},
  @{name='light_truck_hd';tread=0.70;gm=0.88;drain=0.80;wet=1.05;dry=1.00}
)
$surfaces=@('gravel','gravel_wet','dirt','mud','sand','snow','ice','rock','hard_smooth')
$mu=@{gravel=0.75;gravel_wet=0.55;dirt=0.70;mud=0.50;sand=0.55;snow=0.35;ice=0.18;rock=0.90;hard_smooth=0.85}

function EffGrip($tire,[string]$surface){
  $g=(Baseline $tire.name)*[double]$tire.gm
  $sc=SurfaceScale $surface ([double]$tire.tread) ([double]$tire.drain)
  $g=$g*[double]$sc[0]
  $g=ProfileBias $g $surface $tire.name
  if($surface -eq 'gravel_wet'){ $g=$g*[double]$tire.wet }
  elseif($surface -eq 'hard_smooth'){ $g=$g*[double]$tire.dry }
  # rock: no dryGripScale (matches live fix)
  $beam=Clamp ([double]$mu[$surface]) 0.18 1.20
  return [math]::Round([math]::Min($g, [double]$sc[1]/$beam), 3)
}

$sb=New-Object System.Text.StringBuilder
[void]$sb.AppendLine('TRUCK x NON-ASPHALT GRIP (AFTER FIX)')
[void]$sb.AppendLine('')
$hdr='profile'.PadRight(32); foreach($s in $surfaces){$hdr+=('{0,9}' -f $s)}; [void]$sb.AppendLine($hdr)
$rows=@{}
foreach($tire in $tires){
  $line=$tire.name.PadRight(32); $row=@{}
  foreach($s in $surfaces){ $v=EffGrip $tire $s; $row[$s]=$v; $line+=('{0,9:n3}' -f $v) }
  $rows[$tire.name]=$row; [void]$sb.AppendLine($line)
}
[void]$sb.AppendLine('')
$fail=0;$pass=0
function Expect([bool]$ok,[string]$msg){ if($ok){$script:pass++;[void]$sb.AppendLine("PASS  $msg")}else{$script:fail++;[void]$sb.AppendLine("FAIL  $msg")} }

foreach($s in @('mud','dirt','gravel','sand','rock')){
  Expect ($rows['heavy_offroad_truck'][$s] -gt $rows['highway_steer_truck'][$s]) "heavy_offroad > highway_steer on $s"
  Expect ($rows['logger_utility_utility'][$s] -gt $rows['highway_utility_utility'][$s]) "logger > highway_utility on $s"
  Expect ($rows['truck_offroad'][$s] -gt $rows['truck'][$s]) "truck_offroad > truck on $s"
}
Expect ($rows['heavy_offroad_truck']['mud'] / $rows['highway_steer_truck']['mud'] -ge 1.15) 'heavy_offroad mud advantage >=15%'
Expect ($rows['traction_drive_truck']['dirt'] -gt $rows['highway_steer_truck']['dirt']) 'traction_drive > highway on dirt'
Expect ($rows['traction_drive_truck']['dirt'] -le $rows['heavy_offroad_truck']['dirt']*1.08) 'traction_drive not far above heavy_offroad on dirt'
Expect ($rows['highway_steer_truck']['ice'] -lt $rows['highway_steer_truck']['dirt']) 'highway ice < dirt'
Expect ($rows['mudterrain_utility_utility']['mud'] -ge $rows['allterrain_utility_utility']['mud']) 'MT utility >= AT utility on mud'
Expect ($rows['heavy_offroad_truck']['hard_smooth'] -le $rows['highway_steer_truck']['hard_smooth']) 'offroad <= highway on hard_smooth (pavement-like)'

[void]$sb.AppendLine('')
[void]$sb.AppendLine("RESULT: $pass passed, $fail failed")
[System.IO.File]::WriteAllText($out,$sb.ToString())
if($fail -gt 0){ Write-Output "FAIL count=$fail"; exit 1 }
Write-Output "OK pass=$pass"
