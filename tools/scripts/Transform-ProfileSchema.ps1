#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$path = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Tire-Wear-and-Thermals-ReSpin-dev\lua\vehicle\extensions\auto\tireWearThermals.lua'
$src = [IO.File]::ReadAllText($path)

$bak = "$path.bak-schema"
if (-not [IO.File]::Exists($bak)) {
    [IO.File]::Copy($path, $bak, $false)
    Write-Host "Backup: $bak"
}

function Get-Num([hashtable]$m, [string]$key, [double]$default) {
    if ($m.ContainsKey($key)) { return [double]$m[$key] }
    return $default
}

function Transform-ModsMap([hashtable]$m) {
    $cond = Get-Num $m 'skinCoreConductance' 0.068
    $treadI = Get-Num $m 'treadInertia' 0.46
    $carcI  = Get-Num $m 'carcassInertia' 0.75

    $optTemp = Get-Num $m 'optimalTemp' 65
    $adhesion = Get-Num $m 'adhesion' 0.45
    $wear = Get-Num $m 'wearRate' 0.0005
    $drainage = Get-Num $m 'waterDrainage' 0.8
    $gripMult = Get-Num $m 'gripMultiplier' 1.0
    $slipHeat = Get-Num $m 'slipHeatRate' 8.0
    $optP = Get-Num $m 'optimalPressure' 32
    $brakeGain = Get-Num $m 'brakeGainRate' 0.9

    $isSlickish = ($optTemp -ge 75) -or ($gripMult -ge 1.0 -and $adhesion -ge 0.6)
    $isWinter = $optTemp -le 42
    $isOffroad = ($drainage -ge 0.9) -and ($optTemp -le 56)
    $isDrag = ($optP -le 18) -and ($slipHeat -ge 15)
    $isDrift = ($wear -ge 0.0019) -and ($gripMult -le 0.85) -and ($slipHeat -ge 11)
    $isRain = ($drainage -ge 0.9) -and ($optTemp -le 60) -and ($brakeGain -ge 1.3)

    $plateau = if ($m.ContainsKey('tempPlateau')) { [double]$m['tempPlateau'] } elseif ($isSlickish) { 12.5 } elseif ($isOffroad) { 18.0 } else { 15.0 }
    $coldW = if ($m.ContainsKey('coldWidth')) { [double]$m['coldWidth'] } elseif ($isWinter) { 30.0 } elseif ($isSlickish) { 55.0 } else { 45.0 }
    $hotW = if ($m.ContainsKey('hotWidth')) { [double]$m['hotWidth'] } elseif ($isSlickish) { 65.0 } elseif ($isOffroad) { 50.0 } else { 55.0 }
    $floor = if ($m.ContainsKey('gripFloor')) { [double]$m['gripFloor'] } elseif ($isSlickish) { 0.25 } elseif ($isWinter) { 0.15 } else { 0.18 }

    $coldWear = if ($m.ContainsKey('coldWearMult')) { [double]$m['coldWearMult'] } else { [math]::Round(1.5 + $adhesion * 0.6, 3) }
    $hotWear = if ($m.ContainsKey('hotWearMult')) { [double]$m['hotWearMult'] } else { [math]::Round(2.8 + [math]::Max(0, ($optTemp - 55) / 40.0) * 1.4 + $wear * 400.0, 3) }
    $grain = if ($m.ContainsKey('grainTempRatio')) { [double]$m['grainTempRatio'] } elseif ($isSlickish) { 0.78 } else { 0.75 }
    $blister = if ($m.ContainsKey('blisterTempRatio')) { [double]$m['blisterTempRatio'] } elseif ($isSlickish) { 1.35 } elseif ($optTemp -ge 70) { 1.40 } else { 1.45 }

    $longG = if ($m.ContainsKey('longGripMult')) { [double]$m['longGripMult'] } else { 1.0 }
    $latG  = if ($m.ContainsKey('latGripMult')) { [double]$m['latGripMult'] } else { 1.0 }

    $wet = if ($m.ContainsKey('wetGripScale')) { [double]$m['wetGripScale'] } else {
        if ($drainage -ge 0.9) { 1.12 } elseif ($drainage -le 0.2) { 0.72 } else { [math]::Round(0.85 + $drainage * 0.25, 3) }
    }
    $dry = if ($m.ContainsKey('dryGripScale')) { [double]$m['dryGripScale'] } else {
        if ($drainage -le 0.15) { 1.08 } elseif (($drainage -ge 0.95) -and ($optTemp -le 60)) { 0.94 } else { 1.0 }
    }
    $trackC = if ($m.ContainsKey('trackConductivityMult')) { [double]$m['trackConductivityMult'] } else {
        if ($isSlickish) { 1.15 } elseif ($isOffroad) { 0.75 } else { 1.0 }
    }

    if ($isDrag) {
        $longG = 1.12; $latG = 0.92
        $plateau = 10; $coldW = 45; $hotW = 55; $floor = 0.20
        $blister = 1.30; $hotWear = 4.2
    }
    if ($isDrift) {
        $longG = 0.95; $latG = 0.88
        $hotWear = 4.5; $blister = 1.50
    }
    if ($isRain) {
        $wet = 1.22; $dry = 0.92
        $latG = 1.05; $longG = 1.02
    }
    if ($isWinter) {
        $wet = 1.10; $dry = 0.90
        $plateau = 15; $coldW = 30; $hotW = 40; $floor = 0.15
    }

    $out = [ordered]@{}
    $copyKeys = @(
        'adhesion','airConductionRate','airCoolingRate','brakeGainRate','casingCompliance',
        'coreCoolRate','coreVelCoolRate','gripMultiplier','loadSensitivity',
        'optimalPressure','optimalTemp','pressureSensitivity','rollingRes',
        'staticCoolingRate','slipHeatRate','workHeatRate','wearRate','thermalReactionRate',
        'waterDrainage','camberSensitivity','bottomOutSensitivity','scrubSensitivity'
    )
    foreach ($k in $copyKeys) {
        if ($m.ContainsKey($k)) { $out[$k] = [double]$m[$k] }
    }

    $out['skinCoreConductance'] = [math]::Round($cond, 5)
    $out['longGripMult'] = $longG
    $out['latGripMult'] = $latG
    $out['treadInertia'] = $treadI
    $out['carcassInertia'] = $carcI
    $out['tempPlateau'] = $plateau
    $out['coldWidth'] = $coldW
    $out['hotWidth'] = $hotW
    $out['gripFloor'] = $floor
    $out['coldWearMult'] = $coldWear
    $out['hotWearMult'] = $hotWear
    $out['grainTempRatio'] = $grain
    $out['blisterTempRatio'] = $blister
    $out['wetGripScale'] = $wet
    $out['dryGripScale'] = $dry
    $out['trackConductivityMult'] = $trackC

    # Stable key order for readability / diffs
    $order = @(
        'adhesion','airConductionRate','airCoolingRate','brakeGainRate',
        'casingCompliance','coreCoolRate','coreVelCoolRate','skinCoreConductance',
        'gripMultiplier','longGripMult','latGripMult','loadSensitivity',
        'optimalPressure','optimalTemp','pressureSensitivity','rollingRes',
        'staticCoolingRate','slipHeatRate','workHeatRate','wearRate',
        'treadInertia','carcassInertia','thermalReactionRate',
        'tempPlateau','coldWidth','hotWidth','gripFloor',
        'coldWearMult','hotWearMult','grainTempRatio','blisterTempRatio',
        'waterDrainage','wetGripScale','dryGripScale','trackConductivityMult',
        'camberSensitivity','bottomOutSensitivity','scrubSensitivity'
    )
    $ordered = [ordered]@{}
    foreach ($k in $order) {
        if ($out.Contains($k)) { $ordered[$k] = $out[$k] }
    }
    return $ordered
}

function Format-Num([double]$d) {
    $s = ('{0:0.######}' -f $d)
    if ([string]::IsNullOrEmpty($s)) { return '0' }
    return $s
}

function Format-Mods([System.Collections.Specialized.OrderedDictionary]$out, [string]$indent) {
    $keys = @($out.Keys)
    $lines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $keys.Count; $i += 4) {
        $chunk = New-Object System.Collections.Generic.List[string]
        for ($j = $i; $j -lt [math]::Min($i + 4, $keys.Count); $j++) {
            $k = $keys[$j]
            $chunk.Add("$k = $(Format-Num ([double]$out[$k]))") | Out-Null
        }
        $line = $indent + ($chunk -join ', ')
        if (($i + 4) -lt $keys.Count) { $line += ',' }
        $lines.Add($line) | Out-Null
    }
    return ($lines -join "`n")
}

function Parse-ModsBody([string]$body) {
    $map = @{}
    foreach ($match in [regex]::Matches($body, '(\w+)\s*=\s*([-+0-9.eE]+)')) {
        $map[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    return $map
}

# Transform every mods={...} block (incl. mid-line spectrum) and standalone profile = {...} with wearRate
$rx = [regex]'(?ms)((?:^[ \t]*\w+[ \t]*=[ \t]*\{)|(?:mods[ \t]*=[ \t]*\{))(.*?)(^[ \t]*\})'
$sb = New-Object System.Text.StringBuilder
$last = 0
$count = 0

foreach ($match in $rx.Matches($src)) {
    [void]$sb.Append($src.Substring($last, $match.Index - $last))
    $prefix = $match.Groups[1].Value
    $body = $match.Groups[2].Value
    $suffix = $match.Groups[3].Value

    if ($prefix -match 'DEFAULT_MODS' -or $body -notmatch 'wearRate\s*=') {
        [void]$sb.Append($match.Value)
    } else {
        $map = Parse-ModsBody $body
        if ($map.Count -lt 8) {
            [void]$sb.Append($match.Value)
        } else {
            $out = Transform-ModsMap $map
            $indent = if ($prefix -match 'mods') { '        ' } else { '        ' }
            $formatted = Format-Mods $out $indent
            [void]$sb.Append($prefix)
            [void]$sb.Append("`n")
            [void]$sb.Append($formatted)
            [void]$sb.Append("`n")
            [void]$sb.Append($suffix)
            $count++
        }
    }
    $last = $match.Index + $match.Length
}
[void]$sb.Append($src.Substring($last))
$newSrc = $sb.ToString()

$defaultNew = @'
local DEFAULT_MODS = {
    adhesion = 0.45, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.9,
    casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
    gripMultiplier = 1.00, longGripMult = 1.0, latGripMult = 1.0, loadSensitivity = 0.04,
    optimalPressure = 32, optimalTemp = 65, pressureSensitivity = 0.5, rollingRes = 0.8,
    staticCoolingRate = 0.08, slipHeatRate = 8.925, workHeatRate = 5.1, wearRate = 0.0005,
    treadInertia = 0.46, carcassInertia = 0.75, thermalReactionRate = 1.35,
    tempPlateau = 15, coldWidth = 45, hotWidth = 55, gripFloor = 0.18,
    coldWearMult = 1.8, hotWearMult = 3.5, grainTempRatio = 0.75, blisterTempRatio = 1.45,
    waterDrainage = 0.8, wetGripScale = 1.0, dryGripScale = 1.0, trackConductivityMult = 1.0,
    camberSensitivity = 1.0, bottomOutSensitivity = 1.0, scrubSensitivity = 1.0
}
'@

$newSrc = [regex]::Replace($newSrc, '(?s)local DEFAULT_MODS = \{.*?\r?\n\}', $defaultNew.TrimEnd(), 1)

if ($newSrc -notmatch 'CORE_REACTION_RATE') {
    $newSrc = $newSrc.Replace(
        'local THERMAL_BOUNDARY_LAYER = 0.002',
        "local THERMAL_BOUNDARY_LAYER = 0.002`r`nlocal CORE_REACTION_RATE = 0.08 -- Global carcass integration rate (was a dead per-profile knob)"
    )
}

[IO.File]::WriteAllText($path, $newSrc)
Write-Host "Transformed $count profile tables."
Write-Host ("skinCoreConductance={0}" -f ([regex]::Matches($newSrc, 'skinCoreConductance')).Count)
Write-Host ("treadInertia={0}" -f ([regex]::Matches($newSrc, 'treadInertia')).Count)
Write-Host ("carcassInertia={0}" -f ([regex]::Matches($newSrc, 'carcassInertia')).Count)
Write-Host ("tempPlateau={0}" -f ([regex]::Matches($newSrc, 'tempPlateau')).Count)
