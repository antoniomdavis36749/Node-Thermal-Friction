# Extended-drift test with overheat throttle + carcass sink (mirrors live mod better)
$ErrorActionPreference = 'Stop'
$outPath = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Node-Thermal-Friction-dev\tools\output\drift-extended-test.txt'

function Lerp([double]$a,[double]$b,[double]$t){ return $a + ($b-$a)*$t }
function Clamp([double]$v,[double]$lo,[double]$hi){
  if($v -lt $lo){return $lo}; if($v -gt $hi){return $hi}; return $v
}
function ThermalGrip([double]$temp,$m){
  $soft=0.5; $comp=[double]$m.casing
  $plat=[double]$m.plat*(0.8+0.4*$soft)
  $wC=[double]$m.wc*(0.8+0.4*$soft)*(1.0+($comp-0.5)*0.15)
  $wH=[double]$m.wh*(0.8+0.4*$soft)
  $diff=[math]::Abs($temp-[double]$m.tOpt)
  $excess=[math]::Max(0.0,$diff-$plat)
  if($temp -lt [double]$m.tOpt){$w=$wC;$p=1.35}else{$w=$wH;$p=2.0}
  $decay=[math]::Exp(-[math]::Pow($excess/[math]::Max(1.0,$w),$p))
  $tm=[double]$m.floor+(1.0-[double]$m.floor)*$decay
  $tol=Lerp 1.18 1.08 0.5
  if($tm -lt 1.0){$tm=[math]::Max(0.50,[math]::Pow($tm,1.0/$tol))}
  $adW=Clamp ([double]$m.ad) 0.15 0.75
  $shaped=$tm*(0.62+0.38*$tm)
  return ($tm+($shaped-$tm)*($adW*0.55))
}
function Baseline($c){ return [double]$c[0]+[double]$c[1]+[double]$c[2] }

# Live STANDALONE_MODIFIERS / PROFILE_POINTS (v4) — blisterSlipThresh=0.32
$profiles = @(
  [ordered]@{name='drift';c=@(0.88,0.12,-0.05);gm=0.88;lat=0.92;long=0.95;tOpt=75.0;plat=14.0;wc=65.0;wh=65.0;floor=0.28;ad=0.48;casing=0.4;slipHeat=10.0;workHeat=3.6;wearRate=0.002;hotWear=4.5;blisterRatio=1.80;treadInertia=0.40;carcassInertia=0.648;react=1.3;skinCore=0.094;airCool=0.0225;staticCool=0.08;coreCool=0.0455},
  [ordered]@{name='sport';c=@(1.02,0.16,-0.06);gm=1.00;lat=1.0;long=1.0;tOpt=66.0;plat=16.0;wc=62.0;wh=55.0;floor=0.28;ad=0.42;casing=0.5;slipHeat=8.1;workHeat=4.4;wearRate=0.00045;hotWear=2.98;blisterRatio=1.55;treadInertia=0.483;carcassInertia=0.782;react=1.2;skinCore=0.076;airCool=0.02625;staticCool=0.08;coreCool=0.035},
  [ordered]@{name='standard';c=@(0.92,0.12,-0.04);gm=1.00;lat=1.0;long=1.0;tOpt=60.0;plat=16.0;wc=58.0;wh=55.0;floor=0.26;ad=0.40;casing=0.6;slipHeat=8.4;workHeat=5.1;wearRate=0.0005;hotWear=3.0;blisterRatio=1.55;treadInertia=0.504;carcassInertia=0.816;react=1.25;skinCore=0.068;airCool=0.0275;staticCool=0.08;coreCool=0.0385}
)

$dt=0.01; $env=21.0; $slip=0.55; $gMag=0.75; $airspeed=22.0; $loadRaw=4500.0; $vehMass=1400.0
$tyreW=0.9; $surfMu=1.0; $wt=0.40
$loadKg=$loadRaw/9.81
$loadKg=((400.0+$loadKg)*$loadKg/(100.0+$loadKg)-0.15*$loadKg)
$cps=@(5,15,30,60,90,120,180,300)

function Simulate($m,[double]$dur){
  $skin=Lerp $env ([double]$m.tOpt) 0.50
  $core=$skin
  $cond=100.0; $blister=0.0; $marbles=0.0; $hotStint=0.0
  $samp=@{}; $t=0.0
  $base=Baseline $m.c
  $adj=[double]$m.react/[math]::Max(0.05,[double]$m.treadInertia)
  $coreRate=0.08/[math]::Max(0.05,[double]$m.carcassInertia)
  $blOn=[double]$m.tOpt*[double]$m.blisterRatio
  $scaleW=[double]$m.wearRate*2000.0
  $n=[int]($dur/$dt)
  $dT=0.0
  for($i=0;$i -lt $n;$i++){
    $seh=$slip/(1.0+$slip*0.12)
    $loadCoeff=$wt*$loadKg
    $rel=$gMag*$loadCoeff/1000.0
    $raw=($seh*0.05)*3.0*$wt
    $raw=$raw*([math]::Max($surfMu-0.5,0.1)*2.0)
    $slipTerm=0.0078*($seh*$seh)*$loadCoeff*[double]$m.slipHeat
    $workTerm=0.145*$rel*[double]$m.workHeat/(1.0+($seh*$seh))
    $raw=$raw+(($slipTerm+$workTerm)*$surfMu/$tyreW)
    $tempDist=$skin/[math]::Max(1.0,[double]$m.tOpt)
    $thermFric=1.0
    if($tempDist -gt 1.1){ $thermFric=[math]::Max(0.30,1.0-($tempDist-1.1)*0.6) }
    $gain=($raw)*$thermFric
    $tempDelta=$skin-$env
    $velCool=[math]::Pow($airspeed,0.8)*[double]$m.airCool*0.155
    $conv=$tempDelta*([double]$m.staticCool*0.04+$velCool)
    $toCore=($core-$skin)*[double]$m.skinCore
    $dT=($gain-$conv+$toCore)*$adj/$tyreW
    $skin=$skin+$dt*$dT
    # carcass: receive from skin, cool slowly
    $fromSkin=($skin-$core)*[double]$m.skinCore
    $coreCool=($core-$env)*[double]$m.coreCool*0.15*(1.0+$airspeed*0.01)
    $core=$core+$dt*($fromSkin-$coreCool)*$coreRate*8.0

    $tempWear=1.0
    if($tempDist -gt 1.0){ $tempWear=Lerp 1.0 ([double]$m.hotWear) (Clamp ($tempDist-1.0) 0 1) }
    $sliding=20.0*(($loadRaw/($vehMass*9.81))*$slip*$tempWear/$tyreW)
    $cond=Clamp ($cond-$sliding*[double]$m.wearRate*$dt) 0 100
    # Live blisterSlipThresh=0.32 (was soft-sim 0.15 — too aggressive vs live)
    $blisterSlipThresh=0.32
    if(($skin -gt $blOn) -and ($slip -gt $blisterSlipThresh)){
      $oh=[math]::Min(2.0,($skin-$blOn)/[math]::Max(12.0,[double]$m.tOpt*0.18))
      $sf=[math]::Min(2.2,$slip/$blisterSlipThresh)
      $blister=Clamp ($blister+0.00028*$scaleW*$oh*$sf*$dt) 0 1
    }
    if(($skin -gt [double]$m.tOpt*0.95) -and ($slip -gt 0.20)){
      $marbles=Clamp ($marbles+0.0004*$slip*$scaleW*$dt) 0 1
    }
    if($skin -ge [double]$m.tOpt*0.90){ $hotStint+=$dt }
    $stint=[math]::Min(0.12,$hotStint/10000.0)
    $t+=$dt
    foreach($cp in $cps){
      if((-not $samp.ContainsKey([string]$cp)) -and ($t -ge $cp - 1e-9)){
        $x=$cond*0.01
        $therm=ThermalGrip $skin $m
        $grip=$base*$therm*[double]$m.gm
        $grip=$grip*(Lerp 0.75 1.0 $x)
        $grip=$grip*(1.0-$blister*0.35)*(1.0-$marbles*0.18)*(1.0-$stint)
        $samp[[string]$cp]=[pscustomobject]@{
          t=$cp; skin=[math]::Round($skin,1); core=[math]::Round($core,1)
          cond=[math]::Round($cond,1); blister=[math]::Round($blister*100,1)
          marbles=[math]::Round($marbles*100,1); stint=[math]::Round($stint*100,2)
          therm=[math]::Round($therm,3); grip=[math]::Round($grip,3)
          lat=[math]::Round($grip*[double]$m.lat,3); long=[math]::Round($grip*[double]$m.long,3)
          dTdt=[math]::Round($dT,2)
        }
      }
    }
  }
  return $samp
}

$sb=New-Object System.Text.StringBuilder
[void]$sb.AppendLine('EXTENDED DRIFT COMPOUND TEST (with overheat throttle + carcass sink)')
[void]$sb.AppendLine('Scenario: sustained outside-rear drift slip=0.55 g=0.75 v=22m/s load=4500N 300s')
[void]$sb.AppendLine('Real-world: FD rears ~1 min/run; tread often 93-121C; half tread gone in ~4 short runs')
[void]$sb.AppendLine('')

$results=@{}
foreach($m in $profiles){
  $base=Baseline $m.c
  $peak=$base*[double]$m.gm
  [void]$sb.AppendLine(("=== {0} === peak={1:n3} latPeak={2:n3} wearRate={3} slipHeat={4} blister@{5:n0}C hotWidth={6}" -f $m.name,$peak,($peak*[double]$m.lat),$m.wearRate,$m.slipHeat,([double]$m.tOpt*[double]$m.blisterRatio),$m.wh))
  $samp=Simulate $m 300.0
  $results[$m.name]=$samp
  [void]$sb.AppendLine('  t | skin | core | cond% | blister% | marbles% | therm | grip | lat  | long | dT/dt')
  foreach($cp in $cps){
    $s=$samp[[string]$cp]
    if($null -ne $s){
      [void]$sb.AppendLine(('  {0,3} | {1,5:n1} | {2,5:n1} | {3,5:n1} | {4,7:n1} | {5,7:n1} | {6,5:n3} | {7,4:n3} | {8,4:n3} | {9,4:n3} | {10,5:n2}' -f $s.t,$s.skin,$s.core,$s.cond,$s.blister,$s.marbles,$s.therm,$s.grip,$s.lat,$s.long,$s.dTdt))
    }
  }
  [void]$sb.AppendLine('')
}

$d=$results['drift']; $s=$results['sport']
[void]$sb.AppendLine('DRIFT VS SPORT')
foreach($cp in @(30,60,120,300)){
  $dd=$d[[string]$cp]; $ss=$s[[string]$cp]
  $r=((100.0-[double]$dd.cond)/[math]::Max(0.01,100.0-[double]$ss.cond))
  [void]$sb.AppendLine(('  @{0}s drift: {1}C/{2}% cond lat={3} blister={4}% | sport: {5}C/{6}% lat={7} | wear-loss {8:n1}x' -f $cp,$dd.skin,$dd.cond,$dd.lat,$dd.blister,$ss.skin,$ss.cond,$ss.lat,$r))
}

$d60=$d['60']; $d120=$d['120']
[void]$sb.AppendLine('')
[void]$sb.AppendLine('FINDINGS')
[void]$sb.AppendLine('- Peak lat grip ~0.78 warm is intentional (slide initiation, lat=0.92); sport ~1.10.')
[void]$sb.AppendLine('- Extended drift equilibrium skin should sit near opt/hot window (~90-120C real).')
[void]$sb.AppendLine('- Live blister onset = tOpt*1.80 (~135C) and slip>0.32; old soft-sim used 1.50/0.15.')
[void]$sb.AppendLine('- If sim equilibrium >> blister onset, compound will blister mid-stint and lose grip.')
[void]$sb.AppendLine('- wearRate 0.002 vs sport 0.00045 (~4.4x): designed for FD-like rapid rear consumption.')
[void]$sb.AppendLine('- Recommendations depend on measured equilibrium vs 93-121C and cond% at 60s.')

[System.IO.File]::WriteAllText($outPath,$sb.ToString())
Write-Output "WROTE $outPath"
