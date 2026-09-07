#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$gameExe = 'C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive\Bin64\BeamNG.drive.x64.exe'
$modVs = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Node-Thermal-Friction-dev\tools'
$modOut = Join-Path $modVs 'output'
$status = Join-Path $modOut 'wc-gt4-lap-status.json'
$result = Join-Path $modOut 'wc-gt4-lap-result.txt'
$telemetry = Join-Path $modOut 'wc-gt4-lap-telemetry.csv'

Write-Host 'Stopping any existing BeamNG processes...'
Get-Process -Name 'BeamNG.drive*','BeamNG.*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Clear prior outputs
foreach ($f in @($status, $result, $telemetry)) {
  if (Test-Path $f) { Remove-Item $f -Force }
}

$args = @(
  '-level', 'west_coast_usa',
  '-vehicleConfig', 'etkc/race_DCT.pc'
)

# One-shot trigger so tireWestCoastLapTest starts after world ready
$trigger = Join-Path $modVs 'RUN_WC_GT4_TEST'
[IO.File]::WriteAllText($trigger, "10 laps aggressive`n")
Write-Host "Trigger written: $trigger"

Write-Host "Launching: $gameExe"
Write-Host ("Args: " + ($args -join ' '))
$p = Start-Process -FilePath $gameExe -ArgumentList $args -PassThru
Write-Host "PID=$($p.Id)"

$deadline = (Get-Date).AddMinutes(75)
$lastPhase = ''
$lastLap = -1
$lastLearn = -1
$learnConfirmed = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 10
  if ($p.HasExited) {
    Write-Host "BeamNG exited code=$($p.ExitCode)"
    break
  }
  if (Test-Path $status) {
    try {
      $j = Get-Content $status -Raw | ConvertFrom-Json
      $phase = [string]$j.phase
      $lap = [int]$j.lap
      $learn = [int]$j.learnLap
      $changed = ($phase -ne $lastPhase) -or ($lap -ne $lastLap) -or ($learn -ne $lastLearn)
      if ($changed) {
        $spd = if ($null -ne $j.currentSpeedMph) { [double]$j.currentSpeedMph } else { 0 }
        $maxL = if ($null -ne $j.learnMaxSpeedMph) { [double]$j.learnMaxSpeedMph } else { 0 }
        Write-Host ("[{0}] phase={1} mode={2} lap={3}/{4} learn={5} nodes={6} armed={7} spd={8:n1}mph learnMax={9:n1}mph viol={10} resets={11} race={12:n0}s elapsed={13:n0}s" -f `
          (Get-Date -Format 'HH:mm:ss'), $phase, $j.mode, $lap, $j.targetLaps, $learn, `
          $j.nodesHit, $j.lapArmed, $spd, $maxL, $j.learnSpeedViolations, $j.resetCount, $j.raceElapsed, $j.elapsed)
        $lastPhase = $phase
        $lastLap = $lap
        $lastLearn = $learn
      }
      # Early confirmation once learn lap completes under speed cap
      if (-not $learnConfirmed -and $learn -ge 1) {
        $learnConfirmed = $true
        Write-Host ''
        Write-Host '==== LEARN PHASE CONFIRMED ===='
        Write-Host ("learnLap={0} maxMph={1:n2} violations={2} speedOk={3}" -f $learn, $j.learnMaxSpeedMph, $j.learnSpeedViolations, $j.learnSpeedOk)
        Write-Host 'Continuing to aggressive 10-lap stint...'
        Write-Host ''
      }
      if ($phase -eq 'complete' -or $phase -eq 'failed') {
        Write-Host "Test finished: $phase"
        break
      }
    } catch {}
  } else {
    Write-Host ("[{0}] waiting for status..." -f (Get-Date -Format 'HH:mm:ss'))
  }
}

Write-Host ''
Write-Host '==== RESULT FILE ===='
if (Test-Path $result) { Get-Content $result } else { Write-Host '(no result file yet)' }
Write-Host ''
Write-Host '==== STATUS ===='
if (Test-Path $status) { Get-Content $status } else { Write-Host '(no status)' }
Write-Host ''
if (Test-Path $telemetry) {
  $lines = (Get-Content $telemetry).Count
  Write-Host "Telemetry lines: $lines ($telemetry)"
} else {
  Write-Host 'No telemetry CSV yet'
}

# Leave the game running so user can inspect; comment next lines to auto-close
# Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
