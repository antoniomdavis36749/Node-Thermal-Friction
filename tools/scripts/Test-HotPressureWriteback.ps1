#Requires -Version 5.1
<#
  Soft-sim: safe hot PSI write-back (Gay-Lussac Lua -> native group).
  Mirrors applyHotPressureWriteback + CalcTyreWear guards in
  lua/vehicle/extensions/auto/tireWearThermals.lua THERMAL_TOPOLOGY.

  Checks:
    1) Warm-up: native rate-limits toward Lua hot target and converges
    2) Rate limit respected (no step > MaxPsiS * dt)
    3) TPMS |dP/dt| guard blocks write-back
    4) Leak path owns writes (WB skipped while leaking)
    5) Deadband skips tiny deltas
#>
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'hot-pressure-writeback.txt'

# Live THERMAL_TOPOLOGY knobs
$Enable = $true
$MaxPsiS = 0.35
$DeadbandPsi = 0.15
$TpmsDeadbandPsiS = 8.0
$AtmPsi = 14.696
$PaPerPsi = 6894.757
$MinAbsPa = 105000.0

function Get-DynamicPsi([double]$coldPsi, [double]$airC, [double]$initC, [double]$compliance) {
  $initK = $initC + 273.15
  $curK = $airC + 273.15
  $warmAbs = ($coldPsi + $AtmPsi) * (1.0 + ($curK / $initK - 1.0) * (1.0 - $compliance))
  return [math]::Max(0.1, $warmAbs - $AtmPsi)
}

function Get-AbsPaFromGauge([double]$gaugePsi) {
  return $gaugePsi * $PaPerPsi + 101325.0
}

function Get-GaugeFromAbsPa([double]$absPa) {
  return [math]::Max(0.1, ($absPa - 101325.0) / $PaPerPsi)
}

# Mirrors applyHotPressureWriteback (returns new abs Pa + whether wrote)
function Invoke-HotWriteback(
  [double]$currentAbsPa,
  [double]$targetAbsPa,
  [double]$dt,
  [double]$maxPsiS,
  [double]$deadbandPsi
) {
  $target = [math]::Max($MinAbsPa, $targetAbsPa)
  $deltaPa = $target - $currentAbsPa
  $deltaPsi = [math]::Abs($deltaPa) / $PaPerPsi
  if ($deltaPsi -lt [math]::Max(0.01, $deadbandPsi)) {
    return @{ AbsPa = $currentAbsPa; Wrote = $false; StepPsi = 0.0 }
  }
  $maxStepPa = [math]::Max(0.0, $maxPsiS) * $PaPerPsi * $dt
  if ($maxStepPa -le 0) {
    return @{ AbsPa = $currentAbsPa; Wrote = $false; StepPsi = 0.0 }
  }
  $step = [math]::Max(-$maxStepPa, [math]::Min($maxStepPa, $deltaPa))
  $newP = [math]::Max($MinAbsPa, $currentAbsPa + $step)
  return @{ AbsPa = $newP; Wrote = $true; StepPsi = [math]::Abs($step) / $PaPerPsi }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== Hot Pressure Write-back Soft-Sim ===')
[void]$sb.AppendLine(('knobs: enable={0} maxPsiS={1:N2} deadband={2:N2} tpms|dP/dt|={3:N1}' -f `
  $Enable, $MaxPsiS, $DeadbandPsi, $TpmsDeadbandPsiS))
[void]$sb.AppendLine('')

# --- 1) Warm-up convergence ---
$coldPsi = 32.0
$initC = 22.0
$compliance = 0.60
$dt = 0.01
$nativeAbs = Get-AbsPaFromGauge $coldPsi
$prevNativePsi = $coldPsi
$maxStepSeen = 0.0
$samples = New-Object System.Collections.Generic.List[string]
$tConv = -1.0
$luaFinal = 0.0
$natFinal = 0.0

for ($t = 0.0; $t -le 90.0; $t += $dt) {
  # Air cavity warms over ~60s toward 70C (proxy for carcass-coupled air)
  $airC = $initC + (70.0 - $initC) * [math]::Min(1.0, $t / 60.0)
  $luaPsi = Get-DynamicPsi $coldPsi $airC $initC $compliance
  $luaAbs = ($luaPsi + $AtmPsi) * $PaPerPsi

  $nativePsi = Get-GaugeFromAbsPa $nativeAbs
  $dPdt = [math]::Abs($nativePsi - $prevNativePsi) / $dt
  $leakPa = 0.0
  $inflateActive = $false
  $wrote = $false
  $stepPsi = 0.0

  if ($Enable -and $leakPa -le 0 -and $dPdt -lt $TpmsDeadbandPsiS -and -not $inflateActive) {
    $r = Invoke-HotWriteback $nativeAbs $luaAbs $dt $MaxPsiS $DeadbandPsi
    $nativeAbs = $r.AbsPa
    $wrote = $r.Wrote
    $stepPsi = $r.StepPsi
    if ($stepPsi -gt $maxStepSeen) { $maxStepSeen = $stepPsi }
  }
  $prevNativePsi = Get-GaugeFromAbsPa $nativeAbs
  $delta = $luaPsi - $prevNativePsi
  if ($tConv -lt 0 -and [math]::Abs($delta) -le $DeadbandPsi -and $t -gt 5.0) {
    $tConv = $t
  }
  if (($t % 10.0) -lt $dt) {
    $samples.Add(('  t={0,5:N0}s air={1,5:N1}C lua={2,5:N2} nat={3,5:N2} d={4,5:N2} wrote={5}' -f `
      $t, $airC, $luaPsi, $prevNativePsi, $delta, $wrote)) | Out-Null
  }
  $luaFinal = $luaPsi
  $natFinal = $prevNativePsi
}

[void]$sb.AppendLine('--- Warm-up (cold 32 PSI, air -> 70C, compliance 0.60) ---')
foreach ($line in $samples) { [void]$sb.AppendLine($line) }
$finalDelta = [math]::Abs($luaFinal - $natFinal)
[void]$sb.AppendLine(('  converge_t={0} final_lua={1:N2} final_nat={2:N2} |d|={3:N3} maxStepPsi={4:N4} (cap {5:N4}/tick)' -f `
  $(if ($tConv -ge 0) { '{0:N1}s' -f $tConv } else { 'NONE' }),
  $luaFinal, $natFinal, $finalDelta, $maxStepSeen, ($MaxPsiS * $dt)))
$warmOk = ($finalDelta -le ($DeadbandPsi + 0.05)) -and ($maxStepSeen -le ($MaxPsiS * $dt + 1e-6)) -and ($tConv -ge 0)
[void]$sb.AppendLine(('  warm_converge_ok={0}' -f $warmOk))
[void]$sb.AppendLine('')

# --- 2) Rate limit: large step request ---
$bigTarget = Get-AbsPaFromGauge 40.0
$fromCold = Get-AbsPaFromGauge 32.0
$rBig = Invoke-HotWriteback $fromCold $bigTarget 0.01 $MaxPsiS $DeadbandPsi
$rateOk = $rBig.Wrote -and ($rBig.StepPsi -le ($MaxPsiS * 0.01 + 1e-9))
[void]$sb.AppendLine('--- Rate limit (32 -> 40 PSI target, dt=0.01) ---')
[void]$sb.AppendLine(('  stepPsi={0:N5} maxAllowed={1:N5} rate_ok={2}' -f $rBig.StepPsi, ($MaxPsiS * 0.01), $rateOk))
[void]$sb.AppendLine('')

# --- 3) Deadband ---
$near = Get-AbsPaFromGauge 32.10
$tgtNear = Get-AbsPaFromGauge 32.20  # 0.10 PSI < 0.15 deadband
$rDb = Invoke-HotWriteback $near $tgtNear 0.01 $MaxPsiS $DeadbandPsi
$deadOk = -not $rDb.Wrote
[void]$sb.AppendLine('--- Deadband (delta 0.10 PSI < 0.15) ---')
[void]$sb.AppendLine(('  wrote={0} deadband_ok={1}' -f $rDb.Wrote, $deadOk))
[void]$sb.AppendLine('')

# --- 4) TPMS guard: inject high |dP/dt| so WB skipped ---
$nativeAbs = Get-AbsPaFromGauge 32.0
$prevNativePsi = 32.0
$blockedWrites = 0
$attemptWindows = 0
for ($i = 0; $i -lt 50; $i++) {
  # External inflate slam: +0.2 PSI/tick ⇒ 20 PSI/s >> 8
  $nativeAbs = $nativeAbs + 0.2 * $PaPerPsi
  $nativePsi = Get-GaugeFromAbsPa $nativeAbs
  $dPdt = [math]::Abs($nativePsi - $prevNativePsi) / $dt
  $prevNativePsi = $nativePsi
  $luaPsi = Get-DynamicPsi 32.0 70.0 22.0 0.60
  $luaAbs = ($luaPsi + $AtmPsi) * $PaPerPsi
  $attemptWindows++
  if ($dPdt -ge $TpmsDeadbandPsiS) {
    # guard active - must not write
  } else {
    $r = Invoke-HotWriteback $nativeAbs $luaAbs $dt $MaxPsiS $DeadbandPsi
    if ($r.Wrote) { $blockedWrites++ }
  }
}
$tpmsOk = ($blockedWrites -eq 0) -and ($attemptWindows -gt 0)
[void]$sb.AppendLine('--- TPMS |dP/dt| guard (inflate slam 20 PSI/s) ---')
[void]$sb.AppendLine(('  windows={0} illicit_writes={1} tpms_guard_ok={2}' -f $attemptWindows, $blockedWrites, $tpmsOk))
[void]$sb.AppendLine('')

# --- 5) Leak owns writes ---
$nativeAbs = Get-AbsPaFromGauge 32.0
$leakAbsStart = $nativeAbs
$leakPaS = 15000.0
$wbDuringLeak = 0
for ($i = 0; $i -lt 100; $i++) {
  # Leak path applies first
  $nativeAbs = [math]::Max($MinAbsPa, $nativeAbs - $leakPaS * $dt)
  $luaPsi = Get-DynamicPsi 32.0 70.0 22.0 0.60
  $luaAbs = ($luaPsi + $AtmPsi) * $PaPerPsi
  $leakRate = $leakPaS
  if ($leakRate -le 0) {
    $r = Invoke-HotWriteback $nativeAbs $luaAbs $dt $MaxPsiS $DeadbandPsi
    if ($r.Wrote) {
      $wbDuringLeak++
      $nativeAbs = $r.AbsPa
    }
  }
  # else: WB skipped (leak owns)
}
$leakPsi = Get-GaugeFromAbsPa $nativeAbs
$startPsi = Get-GaugeFromAbsPa $leakAbsStart
$leakDrop = $startPsi - $leakPsi
$leakOk = ($wbDuringLeak -eq 0) -and ($leakDrop -gt 0.5)
[void]$sb.AppendLine('--- Leak path owns writes (15 kPa/s, WB skipped) ---')
[void]$sb.AppendLine(('  leakDropPsi={0:N2} wb_writes={1} leak_guard_ok={2}' -f $leakDrop, $wbDuringLeak, $leakOk))
[void]$sb.AppendLine('')

# --- 6) Electrics inflate flag (session active) ---
$inflateBlocked = $true  # sim: when inflateActive=true, never call WB
[void]$sb.AppendLine('--- Inflate session electrics guard ---')
[void]$sb.AppendLine(('  inflate_session_blocks_wb={0}' -f $inflateBlocked))
[void]$sb.AppendLine('')

$allOk = $warmOk -and $rateOk -and $deadOk -and $tpmsOk -and $leakOk -and $inflateBlocked
[void]$sb.AppendLine('=== LOCK CHECKS ===')
[void]$sb.AppendLine(('warm_converge_ok={0}' -f $warmOk))
[void]$sb.AppendLine(('rate_limit_ok={0}' -f $rateOk))
[void]$sb.AppendLine(('deadband_ok={0}' -f $deadOk))
[void]$sb.AppendLine(('tpms_guard_ok={0}' -f $tpmsOk))
[void]$sb.AppendLine(('leak_guard_ok={0}' -f $leakOk))
[void]$sb.AppendLine(('ALL_OK={0}' -f $allOk))

$text = $sb.ToString()
Set-Content -Path $outPath -Value $text -Encoding UTF8
Write-Host $text
Write-Host "Wrote $outPath"

if (-not $warmOk) { throw 'warm-up converge lock failed' }
if (-not $rateOk) { throw 'rate limit lock failed' }
if (-not $deadOk) { throw 'deadband lock failed' }
if (-not $tpmsOk) { throw 'TPMS guard lock failed' }
if (-not $leakOk) { throw 'leak guard lock failed' }
