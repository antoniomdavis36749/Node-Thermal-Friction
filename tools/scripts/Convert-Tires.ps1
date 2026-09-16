param(
    # Leave empty to automatically convert all matching tires found in common.zip
    [string[]]$Entries = @(), 
    [string]$BeamNGRoot = 'C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive',
    [string]$ModRoot = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Node-Thermal-Friction-dev',
    
    # Toggle to true to filter base files down to race, slick, and sport templates
    [bool]$OnlyHighPerformance = $true
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$zipPath = Join-Path $BeamNGRoot 'content\vehicles\common.zip'

# Strictly the 6 race compounds
$Spectra = @(
    @{ Id = "supersoft_slick"; Name = "SuperSoft Slick (C5)"; Tread = 0.00; Softness = 1.00; BaseValueAdd = 500; Pressure = 25; Friction = 1.38 },
    @{ Id = "soft_slick";      Name = "Soft Slick (C4)";      Tread = 0.00; Softness = 0.80; BaseValueAdd = 450; Pressure = 26; Friction = 1.35 },
    @{ Id = "medium_slick";    Name = "Medium Slick (C3)";    Tread = 0.00; Softness = 0.65; BaseValueAdd = 400; Pressure = 27; Friction = 1.32 },
    @{ Id = "hard_slick";      Name = "Hard Slick (C2)";      Tread = 0.00; Softness = 0.50; BaseValueAdd = 350; Pressure = 28; Friction = 1.28 },
    @{ Id = "superhard_slick"; Name = "SuperHard Slick (C1)"; Tread = 0.00; Softness = 0.35; BaseValueAdd = 300; Pressure = 29; Friction = 1.23 },
    @{ Id = "endurance_slick"; Name = "Endurance Slick";      Tread = 0.00; Softness = 0.35; BaseValueAdd = 320; Pressure = 29; Friction = 1.25 }
)

function Convert-ToSpectrumJBeam {
    param(
        [string]$Text, 
        [hashtable]$Spectrum
    )
    
    $specId = $Spectrum.Id
    $specName = $Spectrum.Name
    $targetTread = $Spectrum.Tread
    $targetSoftness = $Spectrum.Softness
    $targetPressure = $Spectrum.Pressure
    $targetFriction = $Spectrum.Friction
    $baseValueAdd = $Spectrum.BaseValueAdd

    $idSuffix = $specId
    $nameSuffix = $specName
    
    $lines = $Text -split "\r?\n"
    $out = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $l = $line
        
        # 1. Modify Part ID (Replace _sport with _race, then append compound suffix)
        if ($l -match '"(tire_[FR]_[^"]+?)"\s*:\s*\{') {
            $partId = $Matches[1]
            $newPartId = $partId -replace '_sport', '_race'
            $l = $l -replace '"' + [regex]::Escape($partId) + '"\s*:\s*\{', ('"' + $newPartId + '_' + $idSuffix + '": {')
        }
        
        # 2. Modify Display Name (Replace Sport with Race, then insert compound suffix)
        if ($l -match '"name"\s*:\s*"([^"]+?) Tires"') {
            $displayName = $Matches[1]
            $newDisplayName = $displayName -replace 'Sport', 'Race' -replace 'sport', 'race'
            $l = $l -replace '"name"\s*:\s*"[^"]+? Tires"', ('"name":"' + $newDisplayName + ' ' + $nameSuffix + ' Tires"')
        }

        $l = $l -replace '"authors"\s*:\s*"BeamNG"', '"authors":"BeamNG, Node-Thermal Friction"'
        
        if ($l -match '^(\s*"value"\s*:\s*)(\d+)(,?\s*(?://.*)?)$') {
            $l = $Matches[1] + ([int]$Matches[2] + $baseValueAdd) + $Matches[3]
        }
        
        $l = $l -replace '(\["\$tirepressure_[FR]",\s*"range",\s*"psi",\s*"Tires",\s*)(\d+)(,.*\])', ('$1' + $targetPressure + '$3')

        if ($l -match '"treadCoef"\s*:\s*(\d+(?:\.\d+)?)') {
            $formattedTread = "{0:F2}" -f $targetTread
            $l = $l -replace '"treadCoef"\s*:\s*\d+(?:\.\d+)?', ('"treadCoef":' + $formattedTread)
        }
        if ($l -match '"softnessCoef"\s*:\s*(\d+(?:\.\d+)?)') {
            $formattedSoftness = "{0:F2}" -f $targetSoftness
            $l = $l -replace '"softnessCoef"\s*:\s*\d+(?:\.\d+)?', ('"softnessCoef":' + $formattedSoftness)
        }

        if ($l -match '"frictionCoef"\s*:\s*(\d+(?:\.\d+)?)') {
            $formattedFriction = "{0:F2}" -f $targetFriction
            $l = $l -replace '"frictionCoef"\s*:\s*\d+(?:\.\d+)?', ('"frictionCoef":' + $formattedFriction)
        }
        if ($l -match '"slidingFrictionCoef"\s*:\s*(\d+(?:\.\d+)?)') {
            $formattedFriction = "{0:F2}" -f $targetFriction
            $l = $l -replace '"slidingFrictionCoef"\s*:\s*\d+(?:\.\d+)?', ('"slidingFrictionCoef":' + $formattedFriction)
        }

        # NTF clones standardize on 20-ray pressure wheels (finer treadNodes for node wear).
        if ($l -match '"numRays"\s*:\s*\d+') {
            $l = $l -replace '"numRays"\s*:\s*\d+', '"numRays":20'
        }

        $out.Add($l)
    }

    # If source had no numRays, inject after tireWidth in the joined output.
    $joined = [string]::Join("`r`n", $out)
    if ($joined -notmatch '"numRays"') {
        $joined = [regex]::Replace($joined, '(\{"tireWidth"\s*:\s*[0-9.]+\}\s*,)', "`$1`r`n            {`"numRays`":20},")
        return $joined
    }
    return $joined
}

$candidates = @()

if (Test-Path $zipPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $zipEntries = @()
        if ($Entries.Count -gt 0) {
            foreach ($entryName in $Entries) {
                $entry = $zip.GetEntry($entryName)
                if ($entry) { $zipEntries += $entry }
            }
        } else {
            $zipEntries = $zip.Entries | Where-Object { 
                $_.FullName.StartsWith('vehicles/common/tires/', [System.StringComparison]::OrdinalIgnoreCase) -and 
                $_.FullName.EndsWith('.jbeam', [System.StringComparison]::OrdinalIgnoreCase) 
            }
            if ($OnlyHighPerformance) {
                $zipEntries = $zipEntries | Where-Object { $_.Name -match '(race|slick|sport)' }
            }
        }
        
        foreach ($entry in $zipEntries) {
            $reader = [System.IO.StreamReader]::new($entry.Open())
            $text = try { $reader.ReadToEnd() } finally { $reader.Close() }
            
            $candidates += [PSCustomObject]@{
                Source     = 'Zip'
                Name       = $entry.Name
                Identifier = $entry.FullName
                Text       = $text
            }
        }
    } finally {
        $zip.Dispose()
    }
} else {
    Write-Warning "common.zip not located at '$zipPath'. Skipping vanilla tire extraction."
}

$localFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
Write-Output "Scanning directory '$localFolder' for local JBeam files..."
$localFiles = Get-ChildItem -Path $localFolder -Filter "*.jbeam" -Recurse -ErrorAction SilentlyContinue

$excludeIds = $Spectra | ForEach-Object { [regex]::Escape($_.Id) }
$excludePattern = "_(" + ($excludeIds -join "|") + ")\.jbeam$"

foreach ($file in $localFiles) {
    if ($file.Name -match $excludePattern) {
        continue
    }
    
    $text = Get-Content -Raw -Path $file.FullName -Encoding UTF8
    
    if ($OnlyHighPerformance) {
        $hasMatch = ($file.Name -match '(race|slick|sport)') -or ($text -match '"tire_[FR]_[^"]*?(?:race|slick|sport)[^"]*?"\s*:\s*\{')
        if (-not $hasMatch) {
            continue
        }
    }
    
    $candidates += [PSCustomObject]@{
        Source     = 'Local'
        Name       = $file.Name
        Identifier = $file.FullName
        Text       = $text
    }
}

# Group candidates by Size Prefix to check for native race variants
$groupedCandidates = @{}
foreach ($item in $candidates) {
    $baseName = $item.Name -replace '\.jbeam$', ''
    $sizeKey = $baseName -replace '_(sport|race|drag|slick|rally|wet|rain|drift)$', ''
    $sizeKey = $sizeKey.ToLower()

    if (-not $groupedCandidates.ContainsKey($sizeKey)) {
        $groupedCandidates[$sizeKey] = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    $groupedCandidates[$sizeKey].Add($item)
}

# Re-compile candidate list, prioritizing race templates over sport templates
$filteredCandidates = New-Object System.Collections.Generic.List[PSCustomObject]
foreach ($key in $groupedCandidates.Keys) {
    $group = $groupedCandidates[$key]
    
    # Check if a race reference exists in this specific tire size group
    $hasRaceRef = $false
    foreach ($item in $group) {
        if ($item.Name -match '(race|slick)') {
            $hasRaceRef = $true
            break
        }
    }
    
    foreach ($item in $group) {
        if ($hasRaceRef -and ($item.Name -match 'sport')) {
            # Skip the sport version if we already have a race reference file for this size
            continue
        }
        $filteredCandidates.Add($item)
    }
}

Write-Output "Processing $($filteredCandidates.Count) filtered candidate files..."
$processedCount = 0

foreach ($item in $filteredCandidates) {
    $text = $item.Text
    
    if ($text -match '"tire_[FR]_[^"]+?"\s*:\s*\{') {
        
        foreach ($spec in $Spectra) {
            $specId = $spec.Id
            $converted = Convert-ToSpectrumJBeam -Text $text -Spectrum $spec
            
            $relativeOut = ""
            if ($item.Source -eq 'Zip') {
                $relativeOut = $item.Identifier -replace '\.jbeam$', ("_" + $specId + ".jbeam")
            } else {
                if ($item.Identifier -match 'vehicles[\\/].*') {
                    $relativeOut = $Matches[0] -replace '\.jbeam$', ("_" + $specId + ".jbeam")
                } else {
                    $relativeOut = Join-Path "vehicles\common\tires" ($item.Name -replace '\.jbeam$', ("_" + $specId + ".jbeam"))
                }
            }
            # 3. Rename the output files: Swap '_sport' out for '_race' inside file names
            $relativeOut = $relativeOut -replace '_sport', '_race'
            $relativeOut = $relativeOut -replace '/', '\'
            $outPath = Join-Path $ModRoot $relativeOut
            
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outPath) | Out-Null
            [System.IO.File]::WriteAllText($outPath, $converted, $utf8NoBom)
            
            $processedCount++
        }
        Write-Output "Generated target spectra variants for: $($item.Name) [$($item.Source)]"
    }
}

Write-Output "Execution complete. Generated $processedCount vanilla-based spectrum JBeam files in: $ModRoot"