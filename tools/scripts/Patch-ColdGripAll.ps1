#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\lua\vehicle\extensions\auto\tireWearThermals.lua' | Resolve-Path
$src = [IO.File]::ReadAllText($path)
$bak = "$path.bak-cold-grip-all"
if (-not [IO.File]::Exists($bak)) { [IO.File]::Copy($path, $bak, $false) }

$rules = @{
  'drag'              = @{ adhesion=0.58; coldWidth=62; gripFloor=0.28; gripMultiplier=1.18; tempPlateau=12 }
  'drift'             = @{ adhesion=0.48; coldWidth=65; gripFloor=0.28; gripMultiplier=0.88; tempPlateau=14 }
  'vintage'           = @{ adhesion=0.28; coldWidth=58; gripFloor=0.26; gripMultiplier=0.82; tempPlateau=16 }
  'crawler'           = @{ adhesion=0.28; coldWidth=58; gripFloor=0.26; gripMultiplier=0.78; tempPlateau=18 }
  'paddle'            = @{ adhesion=0.25; coldWidth=58; gripFloor=0.26; gripMultiplier=0.74; tempPlateau=18 }
  'truck'             = @{ adhesion=0.35; coldWidth=58; gripFloor=0.26; gripMultiplier=0.90; tempPlateau=16 }
  'truck_offroad'     = @{ adhesion=0.32; coldWidth=58; gripFloor=0.26; gripMultiplier=0.82; tempPlateau=16 }
  'heavy_duty'        = @{ adhesion=0.38; coldWidth=58; gripFloor=0.26; gripMultiplier=0.90; tempPlateau=16 }
  'light_truck_std'   = @{ adhesion=0.42; coldWidth=58; gripFloor=0.26; gripMultiplier=0.90; tempPlateau=16 }
  'light_truck_hd'    = @{ adhesion=0.40; coldWidth=58; gripFloor=0.26; gripMultiplier=0.88; tempPlateau=16 }
  'winter'            = @{ adhesion=0.40; coldWidth=42; gripFloor=0.28; gripMultiplier=0.86; tempPlateau=16 }
  'donut'             = @{ adhesion=0.30; coldWidth=55; gripFloor=0.22; gripMultiplier=0.68; tempPlateau=14 }
  'rally'             = @{ adhesion=0.45; coldWidth=62; gripFloor=0.28; gripMultiplier=0.96; tempPlateau=16 }
  'rain'              = @{ adhesion=0.50; coldWidth=62; gripFloor=0.28; gripMultiplier=0.90; tempPlateau=15 }
  'standard'          = @{ adhesion=0.40; coldWidth=58; gripFloor=0.26; gripMultiplier=1.00; tempPlateau=16 }
  'allterrain'        = @{ adhesion=0.36; coldWidth=58; gripFloor=0.26; gripMultiplier=0.86; tempPlateau=18 }
  'mudterrain'        = @{ adhesion=0.32; coldWidth=58; gripFloor=0.26; gripMultiplier=0.82; tempPlateau=18 }
  'hard_slick'        = @{ adhesion=0.48; coldWidth=68; gripFloor=0.30; gripMultiplier=1.00; tempPlateau=14 }
  'medium_slick'      = @{ adhesion=0.52; coldWidth=68; gripFloor=0.30; gripMultiplier=1.08; tempPlateau=14 }
  'soft_slick'        = @{ adhesion=0.55; coldWidth=68; gripFloor=0.30; gripMultiplier=1.15; tempPlateau=14 }
  'highway_utility_utility'     = @{ adhesion=0.40; coldWidth=58; gripFloor=0.26; gripMultiplier=0.90; tempPlateau=16 }
  'allterrain_utility_utility'  = @{ adhesion=0.36; coldWidth=58; gripFloor=0.26; gripMultiplier=0.84; tempPlateau=18 }
  'mudterrain_utility_utility'  = @{ adhesion=0.32; coldWidth=58; gripFloor=0.26; gripMultiplier=0.80; tempPlateau=18 }
  'logger_utility_utility'      = @{ adhesion=0.30; coldWidth=58; gripFloor=0.26; gripMultiplier=0.76; tempPlateau=18 }
  'highway_steer_truck'   = @{ adhesion=0.35; coldWidth=58; gripFloor=0.26; gripMultiplier=0.84; tempPlateau=16 }
  'highway_trailer_truck' = @{ adhesion=0.30; coldWidth=58; gripFloor=0.26; gripMultiplier=0.78; tempPlateau=16 }
  'traction_drive_truck'  = @{ adhesion=0.35; coldWidth=58; gripFloor=0.26; gripMultiplier=0.82; tempPlateau=16 }
  'heavy_offroad_truck'   = @{ adhesion=0.30; coldWidth=58; gripFloor=0.26; gripMultiplier=0.72; tempPlateau=18 }
  'hardpack_utv_utv'      = @{ adhesion=0.35; coldWidth=58; gripFloor=0.26; gripMultiplier=0.84; tempPlateau=16 }
  'allterrain_utv_utv'    = @{ adhesion=0.30; coldWidth=58; gripFloor=0.26; gripMultiplier=0.80; tempPlateau=18 }
  'mud_utv_utv'           = @{ adhesion=0.28; coldWidth=58; gripFloor=0.26; gripMultiplier=0.76; tempPlateau=18 }
  'vintage_biasply_vintage' = @{ adhesion=0.28; coldWidth=58; gripFloor=0.26; gripMultiplier=0.80; tempPlateau=16 }
  'classic_radial_vintage'  = @{ adhesion=0.35; coldWidth=58; gripFloor=0.26; gripMultiplier=0.88; tempPlateau=16 }
}

function Set-Key([string]$block, [string]$key, $val) {
  $pat = "(?m)(^|\s)($key)\s*=\s*[-0-9.]+"
  if ($block -match $pat) {
    return [regex]::Replace($block, $pat, { param($m) "$($m.Groups[1].Value)$key = $val" }, 1)
  }
  return $block
}

function Patch-ModsBlock([string]$block, $rule) {
  foreach ($k in @('adhesion','coldWidth','gripFloor','gripMultiplier','tempPlateau')) {
    if ($null -ne $rule[$k]) { $block = Set-Key $block $k $rule[$k] }
  }
  return $block
}

$standalone = @('drag','drift','vintage','crawler','paddle','truck','truck_offroad','heavy_duty','light_truck_std','light_truck_hd','winter','donut','rally','rain')
foreach ($name in $standalone) {
  $rule = $rules[$name]
  $rx = [regex]::new("(?s)(\n\s*$name\s*=\s*\{)(.*?)(\n\s*\},)")
  $m = $rx.Match($src)
  if (-not $m.Success) { Write-Host "MISS standalone $name"; continue }
  $patched = Patch-ModsBlock $m.Groups[2].Value $rule
  $src = $src.Substring(0, $m.Groups[2].Index) + $patched + $src.Substring($m.Groups[2].Index + $m.Groups[2].Length)
  Write-Host "OK standalone $name"
}

foreach ($name in $rules.Keys) {
  if ($name -in $standalone) { continue }
  if ($name -in @('sport','sport_plus')) { continue }
  $rule = $rules[$name]
  $rx = [regex]::new(('(?s)(profile\s*=\s*"{0}"\s*,\s*mods\s*=\s*\{{)(.*?)(\n\s*\}}\s*\}})' -f [regex]::Escape($name)))
  if (-not $rx.IsMatch($src)) { Write-Host "MISS spectrum $name"; continue }
  $src = $rx.Replace($src, {
    param($mm)
    $inner = Patch-ModsBlock $mm.Groups[2].Value $rule
    return $mm.Groups[1].Value + $inner + $mm.Groups[3].Value
  })
  Write-Host "OK spectrum $name"
}

# PROFILE_POINTS crawler uses profile = "crawler"
$rxC = [regex]::new('(?s)(profile\s*=\s*"crawler"\s*,\s*mods\s*=\s*\{)(.*?)(\n\s*\}\s*\})')
if ($rxC.IsMatch($src)) {
  $src = $rxC.Replace($src, {
    param($mm)
    $inner = Patch-ModsBlock $mm.Groups[2].Value $rules['crawler']
    return $mm.Groups[1].Value + $inner + $mm.Groups[3].Value
  })
  Write-Host "OK profile crawler"
}

[IO.File]::WriteAllText($path, $src)
Write-Host "DONE"
