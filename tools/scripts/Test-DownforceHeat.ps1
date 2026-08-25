<#
.SYNOPSIS
    Soft-sim sweep: downforce heat aggressiveness analysis + A/B aeroHeatScale.
    Validates the aeroHeatScale discount applied in tireWearThermals.lua.

.DESCRIPTION
    Analyses the effective load_kg_thermal multiplier across speed / downforce levels.
    Default runs A (0.55 mute) vs B (1.0 mute-off) for Scintilla GT-like loads.
    Script-side only — does not edit production THERMAL_TOPOLOGY.

.PARAMETER AeroHeatScale
    Optional single-scale run. Omit to run A/B (0.55 vs 1.0).
#>
param(
    [double]$AeroHeatScale = -1
)

$ErrorActionPreference = 'Stop'

# ============================================================
# CONSTANTS (must match live THERMAL_TOPOLOGY)
# ============================================================
$AERO_SPEED_START_MS  = 15.0    # m/s  (~54 km/h)
$AERO_SPEED_FULL_MS   = 52.0    # m/s  (~187 km/h) — live (was 56)
$AERO_MAX_FRAC        = 0.48    # max fraction of load assumed aero at full speed
$SCALE_A              = 0.55    # current mute
$SCALE_B              = 1.0     # mute-off

# load_kg non-linear curve (mirrors Lua)
function Get-LoadKg([double]$loadN) {
    $lkg = $loadN / 9.81
    $lkg = ((400 + $lkg) * $lkg / (100 + $lkg)) - 0.15 * $lkg
    return $lkg
}

function Get-AeroRamp([double]$speedMs) {
    $range = [Math]::Max(1.0, $AERO_SPEED_FULL_MS - $AERO_SPEED_START_MS)
    $ramp  = [Math]::Max(0.0, [Math]::Min(1.0, ($speedMs - $AERO_SPEED_START_MS) / $range))
    return $ramp
}

function Get-ThermalLoadFrac([double]$speedMs, [double]$scale) {
    $ramp    = Get-AeroRamp $speedMs
    $frac    = $ramp * $AERO_MAX_FRAC
    $thermal = 1.0 - $frac * (1.0 - $scale)
    return $thermal
}

function Show-SpeedSweep([double]$scale, [string]$label) {
    Write-Host ""
    Write-Host ("=== AERO HEAT DISCOUNT: speed sweep  [{0}  aeroHeatScale={1}] ===" -f $label, $scale) -ForegroundColor Cyan
    Write-Host ("  {0,-18} {1,-12} {2,-14} {3,-14} {4,-12}" -f "Speed","AeroRamp","AeroFrac","ThermalFrac","Discount%")
    Write-Host ("-" * 72)
    foreach ($kmh in @(0, 50, 80, 100, 130, 160, 200, 250, 300)) {
        $ms      = $kmh / 3.6
        $ramp    = Get-AeroRamp $ms
        $frac    = $ramp * $AERO_MAX_FRAC
        $tFrac   = Get-ThermalLoadFrac $ms $scale
        $disc    = (1 - $tFrac) * 100
        Write-Host ("  {0,-8} km/h ({1:F1} m/s)   ramp={2:F3}  aeroFrac={3:F3}  thermal={4:F3}  -{5:F1}%" -f $kmh, $ms, $ramp, $frac, $tFrac, $disc)
    }
}

function Get-ScintillaCase([double]$scale) {
    # Scintilla GT rear corner @ 200 km/h (high-DF proxy)
    $staticLoad  = 3100.0
    $aeroExtra   = 520.0
    $totalLoad   = $staticLoad + $aeroExtra
    $speedMs     = 200.0 / 3.6
    $load_kg_base = Get-LoadKg $staticLoad
    $load_kg_full = Get-LoadKg $totalLoad
    $thermalFrac  = Get-ThermalLoadFrac $speedMs $scale
    $load_kg_thermal = $load_kg_full * $thermalFrac
    $rawRatio = $load_kg_full / $load_kg_base
    $thermalRatio = $load_kg_thermal / $load_kg_base
    return [pscustomobject]@{
        scale = $scale
        staticN = $staticLoad
        totalN = $totalLoad
        loadKgBase = [math]::Round($load_kg_base, 2)
        loadKgFull = [math]::Round($load_kg_full, 2)
        thermalFrac = [math]::Round($thermalFrac, 4)
        loadKgTh = [math]::Round($load_kg_thermal, 2)
        aeroAddsHeatPct = [math]::Round(($thermalRatio - 1.0) * 100.0, 2)
        rawAeroAddsPct = [math]::Round(($rawRatio - 1.0) * 100.0, 2)
        aeroRamp = [math]::Round((Get-AeroRamp $speedMs), 4)
    }
}

$scales = if ($AeroHeatScale -ge 0) { @($AeroHeatScale) } else { @($SCALE_A, $SCALE_B) }
$labels = @{
    ([string]$SCALE_A) = 'A (mute ON)'
    ([string]$SCALE_B) = 'B (mute OFF)'
}

Write-Host ""
Write-Host "=== Test-DownforceHeat soft-sim (script-side; Lua untouched) ===" -ForegroundColor Cyan
Write-Host ("  knobs: aeroHeatSpeedStart={0}  aeroHeatSpeedFull={1}  aeroHeatMaxFrac={2}" -f `
    $AERO_SPEED_START_MS, $AERO_SPEED_FULL_MS, $AERO_MAX_FRAC)

foreach ($s in $scales) {
    $lab = if ($labels.ContainsKey([string]$s)) { $labels[[string]$s] } else { "scale=$s" }
    Show-SpeedSweep $s $lab
}

# ============================================================
# SOFT-SIM: Scintilla GT A/B at 200 km/h
# ============================================================
Write-Host ""
Write-Host "=== SOFT-SIM: Scintilla GT rear corner @ 200 km/h ===" -ForegroundColor Cyan
$rows = foreach ($s in $scales) { Get-ScintillaCase $s }
$r0 = $rows[0]
Write-Host ("  Static load:           {0,6} N  -> load_kg = {1:F1}" -f $r0.staticN, $r0.loadKgBase)
Write-Host ("  Static+aero load:      {0,6} N  -> load_kg = {1:F1}" -f $r0.totalN,  $r0.loadKgFull)
Write-Host ("  Raw aero heat lift (no mute): +{0:F1}% vs static-only" -f $r0.rawAeroAddsPct)
Write-Host ""
Write-Host ("  {0,-16} {1,8} {2,12} {3,12} {4,14}" -f 'Case','scale','thermFrac','load_kg_th','aeroHeat+%')
Write-Host ("  " + ('-' * 66))
foreach ($r in $rows) {
    $lab = if ($labels.ContainsKey([string]$r.scale)) { $labels[[string]$r.scale] } else { "scale=$($r.scale)" }
    Write-Host ("  {0,-16} {1,8:F2} {2,12:F3} {3,12:F1} {4,13:F1}%" -f `
        $lab, $r.scale, $r.thermalFrac, $r.loadKgTh, $r.aeroAddsHeatPct)
}

if ($rows.Count -ge 2) {
    $a = $rows | Where-Object { [math]::Abs($_.scale - $SCALE_A) -lt 1e-9 } | Select-Object -First 1
    $b = $rows | Where-Object { [math]::Abs($_.scale - $SCALE_B) -lt 1e-9 } | Select-Object -First 1
    if ($a -and $b) {
        $liftTh = (($b.loadKgTh / [math]::Max(0.01, $a.loadKgTh)) - 1.0) * 100.0
        $liftHeat = $b.aeroAddsHeatPct - $a.aeroAddsHeatPct
        Write-Host ""
        Write-Host "=== A(0.55) vs B(1.0) DELTA ===" -ForegroundColor Yellow
        Write-Host ("  load_kg_thermal B/A:     +{0:F1}%  ({1:F1} -> {2:F1})" -f $liftTh, $a.loadKgTh, $b.loadKgTh)
        Write-Host ("  aero heat-lift vs static: A +{0:F1}%  B +{1:F1}%  (B-A = +{2:F1} pp)" -f `
            $a.aeroAddsHeatPct, $b.aeroAddsHeatPct, $liftHeat)
        Write-Host ("  thermalFrac:              A {0:F3}  B {1:F3}  (ramp={2:F3} @200km/h)" -f `
            $a.thermalFrac, $b.thermalFrac, $a.aeroRamp)
        Write-Host '  Caveat: analytical load_kg_thermal only - not full skin/carcass eq soft-sim.'
        Write-Host '          Use Test-StraightLineSpeedSweep -AeroHeatScale for eq temps.'
    }
}

Write-Host ""
Write-Host '=== LIVE TOPOLOGY (reference; not modified) ===' -ForegroundColor Cyan
Write-Host '  aeroHeatScale=0.55  aeroHeatSpeedStart=15  aeroHeatSpeedFull=52  aeroHeatMaxFrac=0.48'
Write-Host '  load_kg_thermal = load_kg * (1 - aeroRamp * maxFrac * (1 - aeroHeatScale))'
Write-Host 'Done.' -ForegroundColor Green
