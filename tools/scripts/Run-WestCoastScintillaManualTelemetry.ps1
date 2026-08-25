#Requires -Version 5.1
<#
.SYNOPSIS
  MANUAL DRIVE + TELEMETRY — West Coast Belasco / Civetta Scintilla GTs (4 laps).

.DESCRIPTION
  Stops any BeamNG process, launches west_coast_usa + scintilla/gts.pc,
  and arms tireWestCoastLapTest in manual mode for a sport_plus tire tune pass:
    - Teleport once to Belasco racetrack spawn
    - AI disabled (no learn / race / damage-reset AI)
    - CSV telemetry -> tools/output/wc-scintilla-lap-telemetry.csv
    - In-memory CSV buffer with rare flush; sample interval 1.0s
    - Header keeps wall..film; UI-stream fields append after film (dutyMods may be quoted)
    - Status phase=manual_telemetry

  Stock Scintilla GTs uses Sport Plus tires:
    tire_F_245_30_20_sport_plus / tire_R_305_30_20_sport_plus
    JBeam treadCoef=0.4 → PROFILE_POINTS continuum between sport_plus (0.30)
    and sport (0.50); descriptor "Sport Plus" (not slick/race).

  ESC: present on stock GTs but NOT required for this tune pass.

  Trigger file: tools/RUN_WC_MANUAL_TEL (body includes profile=scintilla)

  You drive 4 Belasco laps. Script confirms CSV is writing then exits.

  Soft C4 mute-removal (ReSpin Soft Slick): Phase 1 slick scales=1.0; Phase 2 cruise RR/choke=1.0.
  WCU right-turn bias: expect RL hotter than RR in heavy-accel zones — track/load, not Soft C4 bug.
  while leaving the game running.

  Fails if TELEMETRY_CSV_ARMED / CSV never appear within ArmTimeoutSec after
  phase=manual_telemetry (detects optimistic false-positive arm).

.NOTES
  Kingsnake (sport): Run-WestCoastKingsnakeManualTelemetry.ps1
  GT-IV (race/slick proxy): Run-WestCoastManualTelemetry.ps1
#>
$ErrorActionPreference = 'Stop'
$gameExe = 'C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive\Bin64\BeamNG.drive.x64.exe'
$modVs = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Tire-Wear-and-Thermals-ReSpin-dev\tools'
$modOut = Join-Path $modVs 'output'
$status = Join-Path $modOut 'wc-scintilla-lap-status.json'
$result = Join-Path $modOut 'wc-scintilla-lap-result.txt'
$telemetry = Join-Path $modOut 'wc-scintilla-lap-telemetry.csv'
$armMarker = Join-Path $modVs 'TELEMETRY_CSV_ARMED'
$triggerManual = Join-Path $modVs 'RUN_WC_MANUAL_TEL'
$triggerAuto = Join-Path $modVs 'RUN_WC_GT4_TEST'
$ArmTimeoutSec = 45

# Stock config: vehicles/scintilla/gts.pc (default_pc)
# Tires: tire_F_245_30_20_sport_plus / tire_R_305_30_20_sport_plus
$vehicleConfig = 'scintilla/gts.pc'

Write-Host '=== MANUAL DRIVE + TELEMETRY — CIVETTA SCINTILLA GTs / BELASCO (4 LAPS) ==='
Write-Host "VehicleConfig: $vehicleConfig"
Write-Host 'Tire profile expected: PROFILE_POINTS sport_plus continuum (sport_plus part names; treadCoef=0.4)'
Write-Host 'ESC: present on stock GTs but not required for this tune pass'
Write-Host 'Stopping any existing BeamNG processes...'
Get-Process -Name 'BeamNG.drive*','BeamNG.*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Fresh session files only — do not delete telemetry mid-drive after this launch
foreach ($f in @($status, $result, $telemetry, $armMarker, $triggerAuto)) {
  if (Test-Path $f) { Remove-Item $f -Force }
}

$triggerBody = @"
manual
profile=scintilla
vehicle=scintilla/gts
label=Civetta Scintilla GTs
telemetryCsv=wc-scintilla-lap-telemetry.csv
statusJson=wc-scintilla-lap-status.json
resultTxt=wc-scintilla-lap-result.txt
4 laps
sample=1s buffered
esc=optional_not_required
tires=sport_plus
"@
[IO.File]::WriteAllText($triggerManual, $triggerBody)
Write-Host "Trigger written: $triggerManual"
Write-Host "Telemetry CSV: $telemetry"
Write-Host '  sample interval: 1.0s — in-memory buffer, rare disk flush'
Write-Host '  (append-only; car reset keeps prior rows + RESET marker)'
Write-Host "Status JSON:   $status"
Write-Host "Arm marker:    $armMarker (must appear within ${ArmTimeoutSec}s of manual_telemetry)"

$launchArgs = @(
  '-level', 'west_coast_usa',
  '-vehicleConfig', $vehicleConfig
)

Write-Host "Launching: $gameExe"
Write-Host ("Args: " + ($launchArgs -join ' '))
$p = Start-Process -FilePath $gameExe -ArgumentList $launchArgs -PassThru
Write-Host "PID=$($p.Id)"

# BeamNG often spawns children; parent may exit while game continues — track any BeamNG.drive*
$deadline = (Get-Date).AddMinutes(20)
$armed = $false
$csvOk = $false
$armOk = $false
$lastPhase = ''
$manualPhaseSince = $null
$failed = $false
$failReason = ''
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 5
  $alive = @(Get-Process -Name 'BeamNG.drive*' -ErrorAction SilentlyContinue)
  if ($alive.Count -eq 0) {
    Write-Host "BeamNG process gone (launcher exit=$($p.ExitCode))"
    break
  }
  if (Test-Path $status) {
    try {
      $j = Get-Content $status -Raw | ConvertFrom-Json
      $phase = [string]$j.phase
      if ($phase -ne $lastPhase) {
        Write-Host ("[{0}] phase={1} runKind={2} vehicle={3} telArmed={4} aiStarted={5}" -f `
          (Get-Date -Format 'HH:mm:ss'), $phase, $j.runKind, $j.vehicle, $j.telemetryArmed, $j.aiStarted)
        $lastPhase = $phase
        if ($phase -eq 'manual_telemetry' -and -not $manualPhaseSince) {
          $manualPhaseSince = Get-Date
        }
      }
      if ($phase -eq 'failed') {
        $failed = $true
        $failReason = [string]($j.failReason)
        if (-not $failReason -and $j.extra -and $j.extra.note) { $failReason = [string]$j.extra.note }
        Write-Host ("[{0}] GE reported FAILED: {1}" -f (Get-Date -Format 'HH:mm:ss'), $failReason)
        break
      }
      # Require vehicle-confirmed arm (GE no longer sets telArmed optimistically)
      if ($phase -eq 'manual_telemetry' -and $j.telemetryArmed -eq $true -and -not $j.aiStarted) {
        $armed = $true
      }
    } catch {}
  } else {
    Write-Host ("[{0}] waiting for status... (BeamNG procs={1})" -f (Get-Date -Format 'HH:mm:ss'), $alive.Count)
  }
  if (Test-Path $armMarker) {
    $armOk = $true
  }
  if (Test-Path $telemetry) {
    $n = @(Get-Content $telemetry -ErrorAction SilentlyContinue).Count
    # Header is written on arm; data rows arrive after buffer flush (~8s heartbeat / 45s safety)
    if ($n -ge 1) {
      $csvOk = $true
      Write-Host ("[{0}] telemetry file ready: {1} lines" -f (Get-Date -Format 'HH:mm:ss'), $n)
    }
  }
  if ($armed -and ($csvOk -or $armOk)) { break }

  # Fail if manual_telemetry started but ARM marker + CSV never appear
  if ($manualPhaseSince -and -not $armOk -and -not $csvOk) {
    $waited = ((Get-Date) - $manualPhaseSince).TotalSeconds
    if ($waited -ge $ArmTimeoutSec) {
      $failed = $true
      $failReason = "No TELEMETRY_CSV_ARMED or CSV within ${ArmTimeoutSec}s after manual_telemetry (vehicle extension likely failed to load)"
      Write-Host ("[{0}] FAIL: {1}" -f (Get-Date -Format 'HH:mm:ss'), $failReason)
      break
    }
  }
}

Write-Host ''
Write-Host '==== RESULT FILE ===='
if (Test-Path $result) { Get-Content $result } else { Write-Host '(no result file yet)' }
Write-Host ''
Write-Host '==== STATUS ===='
if (Test-Path $status) { Get-Content $status } else { Write-Host '(no status)' }
Write-Host ''
if (Test-Path $armMarker) {
  Write-Host "Arm marker OK: $armMarker"
  Get-Content $armMarker -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
} else {
  Write-Host 'Arm marker MISSING'
}
Write-Host ''
if (Test-Path $telemetry) {
  $lines = @(Get-Content $telemetry).Count
  Write-Host "Telemetry lines: $lines ($telemetry)"
} else {
  Write-Host 'No telemetry CSV yet'
}

Write-Host ''
if ($failed) {
  Write-Host "FAILED: $failReason"
  Write-Host 'Check beamng.log for: Unable to load extension / more than 60 upvalues / extension unavailable'
  Write-Host 'Game left running (no auto-close). Fix extension load, then re-run this script.'
  exit 1
}
if ($armed -and ($csvOk -or $armOk)) {
  Write-Host 'CONFIRMED: AI OFF, phase=manual_telemetry, vehicle arm confirmed, Scintilla CSV/ARM present.'
  Write-Host 'YOU CAN DRIVE NOW — 4 Belasco laps. Reset anytime; CSV keeps prior data.'
  Write-Host 'ESC optional. Soft-sim target: PROFILE_POINTS sport_plus (treadCoef≈0.4 blend).'
  Write-Host 'Note: data rows flush ~every 8s (heartbeat) / 45s safety / disarm — not every sample.'
} elseif ($armed) {
  Write-Host 'WARNING: telArmed=true but no ARM marker/CSV yet — wait a few seconds or check vehicle extension.'
} else {
  Write-Host 'WARNING: manual_telemetry not confirmed yet — check status/result / BeamNG console.'
}
Write-Host 'Game left running (no auto-close).'
