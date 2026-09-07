#Requires -Version 5.1
<#
  Soft-sim: spike-strip pressure leak ownership (mat 32 / wd.isPunctured).

  Stock wheels.lua (updateWheelsGFX):
    while isPunctured: P = max(105kPa, P - punctureLeakRate * dt); setGroupPressure

  Old NTF bug: also set leakRatePa from punctureLeakRate and called
  applyPressureLeakPa → double setGroupPressure → ~2x stock deflate.

  Fixed NTF: while isPunctured, skip applyPressureLeakPa; UI-only tracking.

  Checks:
    1) Native-only rate matches stock
    2) Old double-owner is ~2x faster
    3) Fixed NTF (defer) matches native-only
    4) Thermal leak still applies when NOT isPunctured
#>
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'spike-strip-leak.txt'

$MinAbsPa = 105000.0
$PunctureLeakRate = 20000.0  # Pa/s (wheels.lua default)
$StartAbsPa = 32.0 * 6894.757 + 101325.0  # ~32 PSI gauge
$Dt = 0.01
$SimSec = 5.0

function Invoke-NativeLeak([double]$absPa, [double]$ratePaS, [double]$dt) {
  return [math]::Max($MinAbsPa, $absPa - $ratePaS * $dt)
}

# Old NTF: both owners write the same rate each frame
function Invoke-DoubleLeak([double]$absPa, [double]$ratePaS, [double]$dt) {
  $p = Invoke-NativeLeak $absPa $ratePaS $dt
  return Invoke-NativeLeak $p $ratePaS $dt
}

# Fixed NTF: while isPunctured, only native writes
function Invoke-FixedSpikeLeak(
  [double]$absPa,
  [double]$nativeRatePaS,
  [double]$ntfLeakPaS,
  [bool]$isPunctured,
  [double]$dt
) {
  $p = Invoke-NativeLeak $absPa $nativeRatePaS $dt
  if (-not $isPunctured -and $ntfLeakPaS -gt 0) {
    $p = Invoke-NativeLeak $p $ntfLeakPaS $dt
  }
  return $p
}

function Get-GaugePsi([double]$absPa) {
  return [math]::Max(0.1, ($absPa - 101325.0) / 6894.757)
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== Spike-Strip Leak Ownership Soft-Sim ===')
[void]$sb.AppendLine(('native punctureLeakRate={0} Pa/s  start={1:N1} PSI  dt={2}s  sim={3}s' -f `
  $PunctureLeakRate, (Get-GaugePsi $StartAbsPa), $Dt, $SimSec))
[void]$sb.AppendLine('OWNER: native wheels.lua owns setGroupPressure while isPunctured')
[void]$sb.AppendLine('')

$steps = [int]($SimSec / $Dt)
$nativeP = $StartAbsPa
$doubleP = $StartAbsPa
$fixedP = $StartAbsPa
$thermalOnlyP = $StartAbsPa
$thermalRate = 8000.0

for ($i = 0; $i -lt $steps; $i++) {
  $nativeP = Invoke-NativeLeak $nativeP $PunctureLeakRate $Dt
  $doubleP = Invoke-DoubleLeak $doubleP $PunctureLeakRate $Dt
  $fixedP = Invoke-FixedSpikeLeak $fixedP $PunctureLeakRate $PunctureLeakRate $true $Dt
  # Thermal NTF leak with no spike puncture — still allowed
  $thermalOnlyP = Invoke-FixedSpikeLeak $thermalOnlyP 0.0 $thermalRate $false $Dt
}

$nativePsi = Get-GaugePsi $nativeP
$doublePsi = Get-GaugePsi $doubleP
$fixedPsi = Get-GaugePsi $fixedP
$thermalPsi = Get-GaugePsi $thermalOnlyP
$startPsi = Get-GaugePsi $StartAbsPa

[void]$sb.AppendLine(('after {0:N1}s:' -f $SimSec))
[void]$sb.AppendLine(('  native-only:     {0:N2} PSI  (d={1:N2})' -f $nativePsi, ($startPsi - $nativePsi)))
[void]$sb.AppendLine(('  old double-leak: {0:N2} PSI  (d={1:N2})' -f $doublePsi, ($startPsi - $doublePsi)))
[void]$sb.AppendLine(('  fixed (defer):   {0:N2} PSI  (d={1:N2})' -f $fixedPsi, ($startPsi - $fixedPsi)))
[void]$sb.AppendLine(('  thermal-only:    {0:N2} PSI  (d={1:N2})  rate={2} Pa/s no isPunctured' -f `
  $thermalPsi, ($startPsi - $thermalPsi), $thermalRate))
[void]$sb.AppendLine('')

$pass = 0
$fail = 0

# 1) Fixed matches native
$deltaFixedVsNative = [math]::Abs($fixedPsi - $nativePsi)
if ($deltaFixedVsNative -lt 0.05) {
  [void]$sb.AppendLine('PASS: fixed defer matches native-only (|dPSI|<0.05)')
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: fixed vs native dPSI={0:N3}' -f $deltaFixedVsNative))
  $fail++
}

# 2) Old double is meaningfully faster (~2x drop)
$nativeDrop = $startPsi - $nativePsi
$doubleDrop = $startPsi - $doublePsi
if ($doubleDrop -gt $nativeDrop * 1.7 -and $doubleDrop -lt $nativeDrop * 2.3) {
  [void]$sb.AppendLine(('PASS: old double-leak ~2x faster (drop {0:N2} vs {1:N2})' -f $doubleDrop, $nativeDrop))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: double-leak ratio unexpected (drop {0:N2} vs {1:N2})' -f $doubleDrop, $nativeDrop))
  $fail++
}

# 3) Thermal-only still leaks when not punctured
$thermalDrop = $startPsi - $thermalPsi
$expectThermal = ($thermalRate * $SimSec) / 6894.757
if ($thermalDrop -gt ($expectThermal * 0.9) -and $thermalDrop -lt ($expectThermal * 1.1 + 0.5)) {
  [void]$sb.AppendLine(('PASS: thermal leak still applies when not isPunctured (drop {0:N2} PSI)' -f $thermalDrop))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: thermal leak drop={0:N2} expected~{1:N2}' -f $thermalDrop, $expectThermal))
  $fail++
}

# 4) Floor clamp
if ($nativeP -ge $MinAbsPa -and $doubleP -ge $MinAbsPa) {
  [void]$sb.AppendLine('PASS: pressure floor >= 105000 Pa absolute')
  $pass++
} else {
  [void]$sb.AppendLine('FAIL: pressure went below native min')
  $fail++
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine(('RESULT: {0} pass / {1} fail' -f $pass, $fail))
if ($fail -eq 0) {
  [void]$sb.AppendLine('VERDICT: PASS - native owns spike leak; Node-Thermal Friction defer matches stock rate')
} else {
  [void]$sb.AppendLine('VERDICT: FAIL')
}

$text = $sb.ToString()
Set-Content -Path $outPath -Value $text -Encoding UTF8
Write-Output $text
Write-Output ("Wrote {0}" -f $outPath)
if ($fail -gt 0) { exit 1 }
