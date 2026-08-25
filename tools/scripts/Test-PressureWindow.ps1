#Requires -Version 5.1
<#
  Soft-sim: three-band pressure→grip window (CalcPressureGripScales).
  Locks perfect / normal / outer behavior for street + race compounds vs
  typical BeamNG stock fills (cold + Gay-Lussac warm).

  Live refs: THERMAL_TOPOLOGY pressure* knobs + CalcPressureGripScales
  in lua/vehicle/extensions/auto/tireWearThermals.lua
#>
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'pressure-window.txt'

function Get-PressureScales([double]$currentPsi, [double]$optP, [double]$sensitivity) {
  $pOffset = ($currentPsi / [math]::Max(1.0, $optP)) - 1.0
  $sens = [math]::Max(0.05, $sensitivity)
  $ph = 0.04; $nu = 0.14; $no = 0.32
  $mildMax = 0.028 + 0.022 * $sens
  $ao = [math]::Abs($pOffset)
  if ($ao -le $ph) {
    return @{ Lat = 1.0; Long = 1.0; POffset = $pOffset; Band = 'neutral' }
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

# Gay-Lussac warm pressure (CalcTyreWear)
function Get-DynamicPsi([double]$initialPsi, [double]$airTempC, [double]$initialTempC, [double]$casingCompliance) {
  $initK = $initialTempC + 273.15
  $curK = $airTempC + 273.15
  $abs0 = $initialPsi + 14.696
  $dampen = 1.0 - $casingCompliance
  $warmAbs = $abs0 * (1.0 + ($curK / $initK - 1.0) * $dampen)
  return [math]::Max(0.1, $warmAbs - 14.696)
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== Pressure Window Soft-Sim (three-band grip) ===')
[void]$sb.AppendLine('Bands (ratio = hotPSI / optimalPressure):')
[void]$sb.AppendLine('  neutral: |off| <= 4%  -> scale 1.0 (no perfect bonus)')
[void]$sb.AppendLine('  normal under: -14%..-4%  | normal over: +4%..+32% (asymmetric)')
[void]$sb.AppendLine('  outer: beyond normal -> soft-then-steep (sens-scaled), floors 0.15/0.30/0.35')
[void]$sb.AppendLine('')

$compounds = @(
  @{ Name = 'standard'; OptP = 32.0; Sens = 0.5; Comp = 0.60; AirC = 55.0 },
  @{ Name = 'sport_plus'; OptP = 31.0; Sens = 0.75; Comp = 0.45; AirC = 70.0 },
  @{ Name = 'slick_soft'; OptP = 28.0; Sens = 0.95; Comp = 0.50; AirC = 80.0 }
)

foreach ($c in $compounds) {
  $opt = [double]$c.OptP
  $sens = [double]$c.Sens
  $mildMax = 0.028 + 0.022 * $sens
  [void]$sb.AppendLine(('--- {0} optP={1:N0} sens={2:N2} mildEdge={3:N1}% ---' -f $c.Name, $opt, $sens, ($mildMax * 100.0)))
  [void]$sb.AppendLine(('  band PSI: neutral {0:N1}-{1:N1} | normal {2:N1}-{3:N1}' -f `
    ($opt * 0.96), ($opt * 1.04), ($opt * 0.86), ($opt * 1.32)))

  $coldFills = @(24.0, 28.0, 30.0, 32.0, 34.0, 36.0, 38.0, 42.0, 50.0)
  [void]$sb.AppendLine('  cold -> warm grip:')
  foreach ($cold in $coldFills) {
    $warm = Get-DynamicPsi $cold ([double]$c.AirC) 22.0 ([double]$c.Comp)
    $s = Get-PressureScales $warm $opt $sens
    $line = '    cold={0,5:N1} warm={1,5:N1} off={2,6:N1}% lat={3:N3} long={4:N3} {5}' -f `
      $cold, $warm, ($s.POffset * 100.0), $s.Lat, $s.Long, $s.Band
    [void]$sb.AppendLine($line)
  }

  [void]$sb.AppendLine('  hot-PSI sweep (direct):')
  foreach ($psi in @(($opt * 0.70), ($opt * 0.86), ($opt * 0.96), $opt, ($opt * 1.04), ($opt * 1.16), ($opt * 1.32), ($opt * 1.50), ($opt * 1.80))) {
    $s = Get-PressureScales $psi $opt $sens
    $line = '    psi={0,5:N1} off={1,6:N1}% lat={2:N3} {3}' -f $psi, ($s.POffset * 100.0), $s.Lat, $s.Band
    [void]$sb.AppendLine($line)
  }
  [void]$sb.AppendLine('')
}

# Lock expectations for CI-ish eyeball
$std = Get-PressureScales 32.0 32.0 0.5
$stockWarm = Get-PressureScales (Get-DynamicPsi 35.0 55.0 22.0 0.60) 32.0 0.5
$farOver = Get-PressureScales 60.0 32.0 0.5
$slickExact = Get-PressureScales 28.0 28.0 0.95

[void]$sb.AppendLine('=== LOCK CHECKS ===')
[void]$sb.AppendLine(('neutral_deadband_ok={0} (lat={1:N3} expect 1.000)' -f ($std.Lat -ge 0.999 -and $std.Lat -le 1.001 -and $std.Band -eq 'neutral'), $std.Lat))
[void]$sb.AppendLine(('stock_cold35_mild_ok={0} (band={1} lat={2:N3} expect normal_over & >=0.95)' -f `
  ($stockWarm.Band -eq 'normal_over' -and $stockWarm.Lat -ge 0.95), $stockWarm.Band, $stockWarm.Lat))
[void]$sb.AppendLine(('far_over_punish_ok={0} (lat={1:N3} expect <0.75)' -f ($farOver.Lat -lt 0.75), $farOver.Lat))
[void]$sb.AppendLine(('slick_neutral_ok={0} (lat={1:N3} band={2})' -f ($slickExact.Band -eq 'neutral' -and $slickExact.Lat -ge 0.999), $slickExact.Lat, $slickExact.Band))

$text = $sb.ToString()
Set-Content -Path $outPath -Value $text -Encoding UTF8
Write-Host $text
Write-Host "Wrote $outPath"

# Hard fail if locks break
if (-not ($std.Lat -ge 0.999 -and $std.Lat -le 1.001 -and $std.Band -eq 'neutral')) { throw 'neutral deadband lock failed' }
if (-not ($stockWarm.Band -eq 'normal_over' -and $stockWarm.Lat -ge 0.95)) { throw 'stock mild lock failed' }
if (-not ($farOver.Lat -lt 0.75)) { throw 'far-over punish lock failed' }
if (-not ($slickExact.Band -eq 'neutral' -and $slickExact.Lat -ge 0.999)) { throw 'slick neutral lock failed' }
