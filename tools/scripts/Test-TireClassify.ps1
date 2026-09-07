# Unit check: purpose + compound descriptor + classifyReason routing
# Mirrors getInterpolatedProfile + vehicleHasPlainRallyDamper + remapSlickSoftness in
# lua/vehicle/extensions/auto/tireWearThermals.lua
$ErrorActionPreference = 'Stop'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir 'tire-classify-test.txt'
$sb = New-Object System.Text.StringBuilder
function Out([string]$s) { [void]$sb.AppendLine($s); Write-Host $s }

# Plain rally coilover/strut only - not suspension/spring/shock/damp, not strut_bar,
# not track/race/gravel/lights. Empty strings are ignored (no slot-key fallback).
function Test-HasPlainRallyDamper([string[]]$parts) {
  foreach ($raw in $parts) {
    if ([string]::IsNullOrEmpty($raw)) { continue }
    $n = $raw.ToLowerInvariant()
    if ($n -notlike '*rally*') { continue }
    if ($n -notmatch 'coilover|strut') { continue }
    if ($n -match 'strut_bar|strutbar|strutbrace') { continue }
    if ($n -match 'skin|paint|light|cover|interior|switch|track|circuit|gravel') { continue }
    if ($n -match '_race|race_') { continue }
    return $true
  }
  return $false
}

# Mirrors F.remapSlickSoftness - BeamNG 0.5/0.8/1.0 -> densified 0.50/0.65/0.80; 0.875 is C5
function Get-RemapSlickSoftness([double]$softnessCoef) {
  $s = $softnessCoef
  if ($s -ne $s) { $s = 0.5 }
  if ($s -ge 0.99) { return 0.80 }
  if ([math]::Abs($s - 0.8) -le 0.012) { return 0.65 }
  if ($s -ge 0.50 -and $s -le 0.875) { return $s }
  if ($s -lt 0.50) { return 0.50 }
  return 0.80 + (($s - 0.875) / 0.115) * 0.075
}

function Get-SlickBand([double]$sc) {
  if ($sc -le 0.5375) { return 'hard' }
  if ($sc -le 0.6125) { return 'hard-mid' }
  if ($sc -le 0.6875) { return 'medium' }
  if ($sc -le 0.7625) { return 'medium-soft' }
  if ($sc -le 0.8375) { return 'soft' }
  return 'supersoft'
}

function Test-IsNamedStreetSportCompound([string]$nameLower) {
  if ($nameLower -like '*sport_plus*') { return $true }
  if ($nameLower -like '*track_day*' -or $nameLower -like '*sport_tour*') { return $true }
  if ($nameLower -like '*supersport*') { return $false }
  return $nameLower -like '*sport*'
}

# Returns hashtable: descriptor, purpose, classifyReason
function Get-Classify([string]$tireName, [double]$treadCoef, [string[]]$parts, [double]$radius = 0.0) {
  $nameLower = $tireName.ToLowerInvariant()
  $isAsphaltName = ($nameLower -like '*tarmac*') -or (($nameLower -like '*asphalt*') -and ($nameLower -notlike '*supersport*'))
  $isAsphaltRallyRaceSku = ($nameLower -like '*race*') -and (
    ($nameLower -like '*180_580*') -or ($nameLower -like '*200_600*') -or ($nameLower -like '*210_600*')
  )
  $isGravelRallyName = ($nameLower -like '*rally*') -and -not $isAsphaltName
  $isSlickName = ($nameLower -like '*slick*')
  $isRaceName = ($nameLower -like '*race*')
  # Bare "race" alone does not force slick when tread is clearly street (>=~0.35)
  $isStrongRace = ($nameLower -like '*gt3*') -or ($nameLower -like '*gt4*') `
    -or ($nameLower -like '*formula*') -or ($nameLower -like '*retrorace*') `
    -or ($nameLower -like '*modernrace*')
  $isRaceLikeName = $isSlickName -or ($treadCoef -le 0.12) -or $isStrongRace `
    -or ($isRaceName -and ($treadCoef -lt 0.35))

  $isDamperTarmacHint = $false
  if (-not $isAsphaltName -and -not $isAsphaltRallyRaceSku) {
    $hasDamper = Test-HasPlainRallyDamper $parts
    $isDamperTarmacHint = $isRaceName -and -not $isSlickName -and -not $isGravelRallyName `
      -and ($nameLower -notlike '*gravel*') -and $hasDamper
  }
  $isRallyAsphaltMount = $isAsphaltName -or $isAsphaltRallyRaceSku -or $isDamperTarmacHint
  $tarmacReason = if ($isAsphaltName) { 'asphalt_name' }
    elseif ($isAsphaltRallyRaceSku) { 'race_sku' }
    elseif ($isDamperTarmacHint) { 'rally_damper' }
    else { $null }

  $purpose = 'street'
  $classifyReason = 'street_spectrum'
  $descriptor = 'Standard'

  if ($nameLower -match 'crawler|beadlock') {
    $purpose = 'utility'; $classifyReason = 'standalone_crawler'; $descriptor = 'Crawler'
  } elseif ($nameLower -match 'paddle|sand') {
    $purpose = 'utility'; $classifyReason = 'standalone_paddle'; $descriptor = 'Paddle'
  } elseif ($isRallyAsphaltMount) {
    $purpose = 'tarmac_rally'; $classifyReason = $tarmacReason; $descriptor = 'Rally'
  } elseif ($isGravelRallyName) {
    $purpose = 'gravel'; $classifyReason = 'gravel_name'; $descriptor = 'Rally'
  } elseif ($nameLower -match 'winter|snow') {
    $purpose = 'winter'; $classifyReason = 'standalone_winter'; $descriptor = 'Winter'
  } elseif ($nameLower -match 'drag') {
    $purpose = 'drag'; $classifyReason = 'standalone_drag'; $descriptor = 'Drag'
  } elseif ($nameLower -match 'drift') {
    $purpose = 'drift'; $classifyReason = 'standalone_drift'; $descriptor = 'Drift'
  } elseif ($nameLower -like '*track_day*' -or $nameLower -like '*sport_tour*') {
    $purpose = 'street'; $classifyReason = 'track_day_name'; $descriptor = 'Track Day'
  } elseif ($nameLower -like '*sport_plus*') {
    $purpose = 'street'; $classifyReason = 'sport_plus_name'; $descriptor = 'Sport Plus'
  } elseif ($isRaceLikeName -and ($nameLower -notlike '*gravel*')) {
    $purpose = 'circuit'; $classifyReason = 'slick_spectrum'; $descriptor = 'Slick'
  } elseif (Test-IsNamedStreetSportCompound $nameLower) {
    $purpose = 'street'; $classifyReason = 'sport_name'; $descriptor = 'Sport'
  } elseif ($nameLower -match 'rain|wet|inter') {
    $purpose = 'wet'; $classifyReason = 'standalone_rain'; $descriptor = 'Wet'
  } elseif ($nameLower -match 'vintage|biasply|bias_ply|whitewall') {
    # Standalone vintage before spare/street continuum (mirrors Lua)
    $purpose = 'street'; $classifyReason = 'standalone_vintage'; $descriptor = 'Vintage'
  } elseif ($nameLower -match 'classic_radial') {
    $purpose = 'street'; $classifyReason = 'vintage_spectrum'; $descriptor = 'Vintage'
  } elseif ($treadCoef -le 0.20) {
    $purpose = 'circuit'; $classifyReason = 'slick_spectrum'; $descriptor = 'Slick'
  } elseif ($treadCoef -le 0.32) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Sport Plus'
  } elseif ($treadCoef -le 0.42) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Track Day'
  } elseif ($treadCoef -le 0.58) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Sport'
  } elseif ($treadCoef -le 0.72) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Standard'
  } elseif ($treadCoef -le 0.85) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'All-Terrain'
  } elseif ($treadCoef -le 0.95) {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Mud-Terrain'
  } else {
    $purpose = 'street'; $classifyReason = 'street_spectrum'; $descriptor = 'Crawler'
  }

  # Street-spectrum MT + gravel name -> gravel purpose (mirrors Lua gravel_mt_name)
  if ($classifyReason -eq 'street_spectrum' -and ($nameLower -like '*gravel*') -and ($treadCoef -gt 0.78)) {
    $purpose = 'gravel'; $classifyReason = 'gravel_mt_name'
  }

  # Low-tread street path still shows Slick but purpose remaps to circuit in Lua;
  # already covered by treadCoef <= 0.20 above.

  return @{
    descriptor = $descriptor
    purpose = $purpose
    classifyReason = $classifyReason
  }
}

$cases = @(
  # --- Pure race (must stay circuit / Slick) ---
  @{ name='Covet race'; tire='tire_F_195_50_15_race'; tread=0.0
    parts=@('covet_coilover_F_race','covet_rallylights','tire_F_195_50_15_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Bolide race'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_race_coilover_F','bolide_rallylights','tire_F_265_40_17_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Bolide topspeed (same tires as asphalt, race dampers)'; tire='tire_F_245_45_16_race'; tread=0.0
    parts=@('bolide_coilover_F_race','bolide_coilover_R_race','tire_F_245_45_16_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='ETK GT4 race_DCT'; tire='tire_F_295_30_18_race'; tread=0.0
    parts=@('etkc_strut_F_wide_race','etkc_shock_R_race','etkc_spring_R_race','tire_F_295_30_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Scintilla race'; tire='tire_F_295_35_19_race'; tread=0.0
    parts=@('scintilla_coilover_F_race','tire_F_295_35_19_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  # REAL bug: Ardente race keeps vivace_suspension_*_rally + track coilovers
  @{ name='Vivace Ardente race (suspension_rally + track coilover)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_suspension_F_rally','vivace_suspension_R_rally','vivace_rally_coilover_F_track','vivace_rally_coilover_R_track','vivace_rally_steering','vivace_rally_swaybar_F','tire_F_235_40_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Vivace race_SQ'; tire='tire_F_245_35_19_race'; tread=0.0
    parts=@('vivace_strut_F_wide_race','vivace_shock_R_wide_race','vivace_spring_R_wide_race','tire_F_245_35_19_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + suspension_rally only (no damper)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_suspension_F_rally','vivace_suspension_R_rally')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + spring/shock_rally must not remap'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_spring_F_rally','bolide_shock_R_rally','tire_F_265_40_17_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Low tread alone + suspension_rally stays circuit'; tire='tire_F_225_45_17_sport'; tread=0.05
    parts=@('vivace_suspension_F_rally')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  # Explicit slick name stays circuit even with plain rally damper
  @{ name='Slick name + rally coilover stays circuit'; tire='tire_F_265_40_17_slick'; tread=0.0
    parts=@('bolide_coilover_F_rally','bolide_coilover_R_rally')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }

  # --- Tarmac rally (compound Rally, purpose tarmac_rally) ---
  @{ name='Covet rally_asphalt (race tire + rally coilover)'; tire='tire_F_180_580_15_altb_race'; tread=0.0
    parts=@('covet_coilover_F_rally','covet_rallylights','tire_F_180_580_15_altb_race')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='Covet asphalt SKU alone (no hardware)'; tire='tire_F_180_580_15_altb_race'; tread=0.0
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='Bolide rally_asphalt'; tire='tire_F_245_45_16_race'; tread=0.0
    parts=@('bolide_coilover_F_rally','bolide_coilover_R_rally','bolide_rallylights','tire_F_245_45_16_race')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='rally_damper' }
  @{ name='BX rally_asp'; tire='tire_F_200_600_16_race'; tread=0.0
    parts=@('bx_strut_F_rally','bx_coilover_R_rally','tire_F_200_600_16_race')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='BX asphalt SKU alone'; tire='tire_R_200_600_16_race'; tread=0.0
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  @{ name='210_600 race SKU alone'; tire='tire_F_210_600_16_race'; tread=0.0
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='race_sku' }
  # 210_650 is a real Race slick SKU, not asphalt-rally
  @{ name='210_650 race slick SKU'; tire='tire_F_210_650_19_race'; tread=0.0
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }

  # Explicit asphalt / tarmac tire names -> tarmac_rally (hardware optional)
  @{ name='Scintilla rally (*_asphalt)'; tire='tire_F_245_40_18_asphalt'; tread=0.40
    parts=@('scintilla_coilover_F_rally')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='asphalt_name' }
  @{ name='Vivace Ardente asphalt'; tire='tire_F_235_40_18_asphalt'; tread=0.40
    parts=@('vivace_rally_coilover_F_asphalt','vivace_suspension_F_rally','tire_F_235_40_18_asphalt')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='asphalt_name' }
  @{ name='tarmac name alone'; tire='tire_F_205_55_16_tarmac'; tread=0.35
    parts=@()
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='asphalt_name' }
  @{ name='asphalt coilover + race tire (custom mount)'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_rally_coilover_F_asphalt')
    expectDesc='Rally'; expectPurpose='tarmac_rally'; expectReason='rally_damper' }

  # Gravel rally
  @{ name='Covet rally_gravel'; tire='tire_F_165_70_14_rally'; tread=0.70
    parts=@('covet_coilover_F_rally','tire_F_165_70_14_rally')
    expectDesc='Rally'; expectPurpose='gravel'; expectReason='gravel_name' }
  @{ name='Bolide rally_gravel'; tire='tire_R_245_45_16_rally'; tread=0.70
    parts=@('bolide_coilover_F_rally')
    expectDesc='Rally'; expectPurpose='gravel'; expectReason='gravel_name' }

  # Street spectrum
  @{ name='Street sport'; tire='tire_F_225_45_17_sport'; tread=0.50
    parts=@()
    expectDesc='Sport'; expectPurpose='street'; expectReason='sport_name' }
  @{ name='Street sport tread 0.40 still sport name'; tire='tire_F_235_40_18_sport'; tread=0.40
    parts=@()
    expectDesc='Sport'; expectPurpose='street'; expectReason='sport_name' }
  @{ name='Scintilla sport 275/40R20 not utility radius'; tire='tire_F_275_40_20_sport'; tread=0.40
    parts=@(); radius=0.364
    expectDesc='Sport'; expectPurpose='street'; expectReason='sport_name' }
  @{ name='Scintilla sport 305/35R20 not utility radius'; tire='tire_R_305_35_20_sport'; tread=0.40
    parts=@(); radius=0.361
    expectDesc='Sport'; expectPurpose='street'; expectReason='sport_name' }
  @{ name='Street sport_plus'; tire='tire_F_245_40_18_sport_plus'; tread=0.40
    parts=@()
    expectDesc='Sport Plus'; expectPurpose='street'; expectReason='sport_plus_name' }
  @{ name='Street track_day name'; tire='tire_F_235_40_18_NTF_track_day'; tread=0.40
    parts=@()
    expectDesc='Track Day'; expectPurpose='street'; expectReason='track_day_name' }
  @{ name='Legacy sport_tour name maps to Track Day'; tire='tire_F_235_40_18_sport_tour'; tread=0.40
    parts=@()
    expectDesc='Track Day'; expectPurpose='street'; expectReason='track_day_name' }
  @{ name='Street track_day JBeam tread 0.18'; tire='tire_F_235_40_18_NTF_track_day'; tread=0.18
    parts=@()
    expectDesc='Track Day'; expectPurpose='street'; expectReason='track_day_name' }
  @{ name='Street track_day tread unnamed'; tire='tire_F_235_40_18_standard'; tread=0.40
    parts=@()
    expectDesc='Track Day'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street NTF hard_slick C2'; tire='tire_F_235_40_18_NTF_hard_slick'; tread=0.00
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Street NTF medium_slick C3'; tire='tire_F_235_40_18_NTF_medium_slick'; tread=0.00
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Street standard mid'; tire='tire_F_205_55_16_standard'; tread=0.60
    parts=@()
    expectDesc='Standard'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street standard'; tire='tire_F_205_55_16_standard'; tread=0.65
    parts=@()
    expectDesc='Standard'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='Street AT/MT mid'; tire='tire_F_265_70_16_offroad'; tread=0.85
    parts=@()
    expectDesc='All-Terrain'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='MT gravel name purpose'; tire='tire_F_265_70_16_gravel'; tread=0.90
    parts=@()
    expectDesc='Mud-Terrain'; expectPurpose='gravel'; expectReason='gravel_mt_name' }

  # Vintage / bias-ply / whitewall (street purpose; not sport+ soft-cap debt path)
  @{ name='Vintage standalone name'; tire='tire_F_185_80_15_vintage'; tread=0.55
    parts=@()
    expectDesc='Vintage'; expectPurpose='street'; expectReason='standalone_vintage' }
  @{ name='Bias-ply name'; tire='tire_R_6_50_16_biasply'; tread=0.50
    parts=@()
    expectDesc='Vintage'; expectPurpose='street'; expectReason='standalone_vintage' }
  @{ name='Whitewall name'; tire='tire_F_205_75_14_whitewall'; tread=0.60
    parts=@()
    expectDesc='Vintage'; expectPurpose='street'; expectReason='standalone_vintage' }
  @{ name='Classic radial vintage'; tire='tire_F_195_70_14_classic_radial'; tread=0.65
    parts=@()
    expectDesc='Vintage'; expectPurpose='street'; expectReason='vintage_spectrum' }

  # Negatives: cosmetic / empty slots must not remap race -> tarmac_rally
  @{ name='Race + skin_rally only'; tire='tire_F_265_40_17_race'; tread=0.0
    parts=@('bolide_skin_rally','tire_F_265_40_17_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + skidplate only'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('vivace_skidplate_rally_F','tire_F_235_40_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + empty rallylights slot string'; tire='tire_F_235_40_18_race'; tread=0.0
    parts=@('','vivace_rally_steering','tire_F_235_40_18_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='Race + strut_bar only'; tire='tire_F_195_50_15_race'; tread=0.0
    parts=@('covet_strut_bar_F','tire_F_195_50_15_race')
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }

  # --- Tweak 2: bare "race" + street tread stays continuum; strong tokens / slick / tread0 still slick ---
  @{ name='estr34 race street tread (not slick)'; tire='estr34_tires_18x10_race'; tread=0.5
    parts=@()
    expectDesc='Sport'; expectPurpose='street'; expectReason='street_spectrum' }
  @{ name='race name + tread0 still slick'; tire='estr34_tires_18x10_race'; tread=0.0
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='slick token + street tread still slick'; tire='estr34_tires_18x10_slick'; tread=0.5
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='bastion_gt4 modernrace tread0'; tire='bastion_gt4_modernrace'; tread=0.0
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='modernrace + street tread still slick (strong token)'; tire='bastion_modernrace_tire'; tread=0.5
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='picnic f4 race tread0'; tire='picnic_f4_race'; tread=0.0
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
  @{ name='sunstorm *_race tread0'; tire='sunstorm_tire_race'; tread=0.0
    parts=@()
    expectDesc='Slick'; expectPurpose='circuit'; expectReason='slick_spectrum' }
)

Out '=== Tire purpose / descriptor / classifyReason ==='
Out ('Mirrored from tireWearThermals.lua @ {0:yyyy-MM-dd}' -f (Get-Date))
Out ''

$fail = 0
foreach ($c in $cases) {
  $got = Get-Classify $c.tire ([double]$c.tread) $c.parts
  $ok = ($got.descriptor -eq $c.expectDesc) -and ($got.purpose -eq $c.expectPurpose) -and ($got.classifyReason -eq $c.expectReason)
  if (-not $ok) { $fail++ }
  $mark = if ($ok) { 'PASS' } else { 'FAIL' }
  Out ("{0}: {1}  tire={2} tread={3}" -f $mark, $c.name, $c.tire, $c.tread)
  Out ("       got  desc={0} purpose={1} reason={2}" -f $got.descriptor, $got.purpose, $got.classifyReason)
  Out ("       want desc={0} purpose={1} reason={2}" -f $c.expectDesc, $c.expectPurpose, $c.expectReason)
  if (-not $ok) {
    Out ("       parts: {0}" -f ($c.parts -join ', '))
  }
}

# --- Tweak 1: slick softnessCoef remap soft-sim ---
Out ''
Out '=== Slick softnessCoef remap (BeamNG 0.5/0.8/1.0 -> densified) ==='
$softCases = @(
  @{ name='soft=1.0 -> soft end'; soft=1.0; expectSc=0.80; expectBand='soft'
    beforeNote='clamp 0.80 soft_slick (collapsed with all soft>=0.80)' }
  @{ name='soft=0.8 -> medium'; soft=0.8; expectSc=0.65; expectBand='medium'
    beforeNote='clamp 0.80 soft_slick (wrong - common med tier)' }
  @{ name='soft=0.5 -> hard'; soft=0.5; expectSc=0.50; expectBand='hard'
    beforeNote='clamp 0.50 hard_slick (unchanged)' }
  @{ name='soft=0 -> hard floor'; soft=0.0; expectSc=0.50; expectBand='hard'
    beforeNote='clamp 0.50 hard floor' }
  @{ name='soft=0.575 midpoint preserved'; soft=0.575; expectSc=0.575; expectBand='hard-mid'
    beforeNote='clamp 0.575 densified mid' }
  @{ name='soft=0.725 midpoint preserved'; soft=0.725; expectSc=0.725; expectBand='medium-soft'
    beforeNote='clamp 0.725 densified mid' }
  @{ name='soft=1.2 -> soft end'; soft=1.2; expectSc=0.80; expectBand='soft'
    beforeNote='clamp 0.80 soft_slick' }
  @{ name='soft=0.875 -> supersoft C5'; soft=0.875; expectSc=0.875; expectBand='supersoft'
    beforeNote='explicit C5 SKU (1.0 stays C4)' }
)
$softFail = 0
foreach ($c in $softCases) {
  $legacy = [math]::Max(0.50, [math]::Min(0.80, [double]$c.soft))
  $sc = Get-RemapSlickSoftness ([double]$c.soft)
  $band = Get-SlickBand $sc
  $ok = ([math]::Abs($sc - [double]$c.expectSc) -lt 1e-9) -and ($band -eq $c.expectBand)
  if (-not $ok) { $softFail++ }
  $mark = if ($ok) { 'PASS' } else { 'FAIL' }
  Out ("{0}: {1}" -f $mark, $c.name)
  Out ("       before clamp={0:N3} ({1})" -f $legacy, $c.beforeNote)
  Out ("       after  remap={0:N3} band={1}  want sc={2:N3} band={3}" -f $sc, $band, $c.expectSc, $c.expectBand)
}
$fail += $softFail

Out ''
if ($fail -eq 0) {
  Out ("OVERALL: PASS ({0} classify + {1} soft-remap)" -f $cases.Count, $softCases.Count)
} else {
  Out ("OVERALL: FAIL ($fail failed)")
}

# Light schema check: compound-character knobs present with neutral defaults
$luaPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'lua\vehicle\extensions\auto\tireWearThermals.lua'
if (-not (Test-Path $luaPath)) {
  $luaPath = Join-Path (Split-Path $PSScriptRoot -Parent) '..\lua\vehicle\extensions\auto\tireWearThermals.lua'
}
$luaPath = [IO.Path]::GetFullPath($luaPath)
$charFail = 0
if (Test-Path $luaPath) {
  Out ''
  Out '=== Compound-character knobs (schema) ==='
  $lua = [IO.File]::ReadAllText($luaPath)
  $need = @(
    @{ k='coldGripPower'; v='1.35' },
    @{ k='hotGripPower'; v='2.0' },
    @{ k='grainRate'; v='0.00042' },
    @{ k='blisterRate'; v='0.00028' },
    @{ k='stintFadeRate'; v='1.0' },
    @{ k='camberWearMult'; v='1.0' }
  )
  foreach ($n in $need) {
    $pat = "$($n.k)\s*=\s*$([regex]::Escape($n.v))"
    $ok = $lua -match $pat
    if (-not $ok) { $charFail++ }
    Out ("{0}: DEFAULT {1}={2}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' }), $n.k, $n.v))
  }
  $stampOk = ($lua -match 'CHARACTER_SLICK_SOFT') -and ($lua -match 'stampSpectrumCharacter') -and ($lua -match '49 knobs')
  if (-not $stampOk) { $charFail++ }
  Out ("{0}: CHARACTER packs + 49-knob schema comment" -f ($(if ($stampOk) { 'PASS' } else { 'FAIL' })))
  # Soft-cap magnitudes present (Pass 6 floors toward 1.0); vintage pack distinct
  $softOk = ($lua -match 'driveSlipHeatMin\s*=\s*0\.90') -and ($lua -match 'DRIVE_SOFTCAP_SPORT_PLUS') `
    -and ($lua -match 'DRIVE_SOFTCAP_TRACK_DAY') -and ($lua -match 'DRIVE_SOFTCAP_VINTAGE') `
    -and ($lua -match 'driveSlipHeatMin\s*=\s*0\.95')
  if (-not $softOk) { $charFail++ }
  Out ("{0}: soft-cap packs still present (street 0.90 + track_day + vintage 0.95)" -f ($(if ($softOk) { 'PASS' } else { 'FAIL' })))
  $noMid = ($lua -notmatch 'DRIVE_SOFTCAP_SPORT_MID') -and ($lua -notmatch 'CHARACTER_SPORT_MID')
  if (-not $noMid) { $charFail++ }
  Out ("{0}: sport_mid packs removed" -f ($(if ($noMid) { 'PASS' } else { 'FAIL' })))
  $noTour = $lua -notmatch '\{\s*"sport_tour"'
  if (-not $noTour) { $charFail++ }
  Out ("{0}: sport_tour is not a fourth GRIP/profile tag" -f ($(if ($noTour) { 'PASS' } else { 'FAIL' })))
  $remapOk = ($lua -match 'remapSlickSoftness') -and ($lua -match 'modernrace')
  if (-not $remapOk) { $charFail++ }
  Out ("{0}: remapSlickSoftness + strong race tokens present" -f ($(if ($remapOk) { 'PASS' } else { 'FAIL' })))
} else {
  Out "SKIP character knob schema (lua not found at $luaPath)"
}

[System.IO.File]::WriteAllText($out, $sb.ToString())
Write-Host "Wrote $out"
if (($fail + $charFail) -gt 0) { exit 1 }
