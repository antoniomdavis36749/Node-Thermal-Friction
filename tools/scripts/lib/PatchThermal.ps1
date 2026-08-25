#Requires -Version 5.1
<#
  Canonical contact-patch thermal helper (mirrors live tireWearThermals.lua).
  Dot-source from soft-sims: . (Join-Path $PSScriptRoot 'lib\PatchThermal.ps1')
  No area-shrink on soft sink — conduction uses depth/rough denom separately.
  Path A: util via downForceRaw, dynR clamp, GM soft fields, dual-mat blend.
#>

function Clamp-Patch([double]$v, [double]$lo, [double]$hi) {
  if ($v -lt $lo) { return $lo }
  if ($v -gt $hi) { return $hi }
  return $v
}

# Live THERMAL_TOPOLOGY patch knobs (Phase B/C/D + Path A)
function Get-LivePatchTopo {
  return @{
    patchFracMin = 0.032
    patchFracHeatMin = 0.022
    patchFracMax = 0.22
    patchFracRef = 0.068
    patchHeatEmaTau = 0.10
    patchHertzDeflBlend = 0.35
    patchDeflWidthFrac = 0.55
    contactDepthEmaTau = 0.08
    patchUtilBlend = 0.20
    patchUtilPeakLo = 0.82
    patchUtilPeakHi = 1.40
    patchDynRadiusMinFrac = 0.55
    patchDynRadiusMaxFrac = 1.06
    softSinkHeatCoef = 1.2
    softSinkRoughCoef = 0.35
    softSinkHeatFloor = 0.72
    softSinkDefaultDepthCoef = 2.2
    softSinkStrengthRef = 1.0
    softSinkStrengthCoef = 0.40
    softSinkFluidCoef = 0.0007
    softSinkStribeckRef = 1.0
    softSinkStribeckCoef = 0.035
    gmConductionDefaultDepthCoef = 2.5
    gmConductionStrengthCoef = 0.30
    gmConductionFluidCoef = 0.0005
    dualContactBlend = 0.32
    dualContactWearBump = 0.18
    freeBeltCoolMult = 1.32
    hystSkinShare = 0.18
  }
}

function Get-PatchRadiusM {
  param(
    [double]$StaticRadiusM,
    [double]$DynamicRadiusM = 0.0,
    [hashtable]$Topo = $null
  )
  if ($null -eq $Topo) { $Topo = Get-LivePatchTopo }
  $staticR = [math]::Max(0.05, $StaticRadiusM)
  $dynR = if ($DynamicRadiusM -gt 0.05) { $DynamicRadiusM } else { $staticR }
  $lo = $staticR * [double]$Topo.patchDynRadiusMinFrac
  $hi = $staticR * [double]$Topo.patchDynRadiusMaxFrac
  return (Clamp-Patch $dynR $lo $hi)
}

function Get-SoftGmExtra {
  param(
    [double]$DefaultDepth = 0.0,
    [double]$Strength = 1.0,
    [double]$FluidDensity = 0.0,
    [double]$StribeckVelocity = 1.0,
    [hashtable]$Topo = $null
  )
  if ($null -eq $Topo) { $Topo = Get-LivePatchTopo }
  if ($Strength -le 0) { $Strength = 1.0 }
  $sRef = [math]::Max(0.2, [double]$Topo.softSinkStrengthRef)
  $softExtra = [math]::Max(0.0, $DefaultDepth) * [double]$Topo.softSinkDefaultDepthCoef `
    + [math]::Max(0.0, 1.0 - $Strength / $sRef) * [double]$Topo.softSinkStrengthCoef `
    + [math]::Max(0.0, $FluidDensity) * [double]$Topo.softSinkFluidCoef `
    + [math]::Max(0.0, 1.0 - [math]::Min(1.0, $StribeckVelocity / [math]::Max(0.1, [double]$Topo.softSinkStribeckRef))) `
      * [double]$Topo.softSinkStribeckCoef
  $condExtra = [math]::Max(0.0, $DefaultDepth) * [double]$Topo.gmConductionDefaultDepthCoef `
    + [math]::Max(0.0, 1.0 - $Strength / $sRef) * [double]$Topo.gmConductionStrengthCoef `
    + [math]::Max(0.0, $FluidDensity) * [double]$Topo.gmConductionFluidCoef
  return @{ SoftExtra = $softExtra; CondExtra = $condExtra }
}

<#
.SYNOPSIS
  Hertz F/P + deflection blend → patchFrac / patchHeatScale (live Phase B + Path A).
#>
function Get-PatchThermal {
  param(
    [double]$LoadRawN,
    [double]$DynamicPressurePSI,
    [double]$TyreWidthM,
    [double]$TyreRadiusM,
    [double]$ContactDepthM = 0.0,
    [double]$PeakForceN = 0.0,
    [double]$LoadUtilN = -1.0,
    [double]$StaticRadiusM = -1.0,
    [double]$DynamicRadiusM = -1.0,
    [double]$Rough = 0.0,
    [double]$DefaultDepth = 0.0,
    [double]$Strength = 1.0,
    [double]$FluidDensity = 0.0,
    [double]$StribeckVelocity = 1.0,
    [double]$Rough2 = -1.0,
    [double]$DualBlend = 0.0,
    [hashtable]$Topo = $null,
    [switch]$NoDepthBoost,
    [switch]$NoUtilNudge,
    [switch]$NoSoftSinkDamp
  )
  if ($null -eq $Topo) { $Topo = Get-LivePatchTopo }

  # A4: prefer dynamicRadius with clamp vs static when provided
  $radiusM = $TyreRadiusM
  if ($StaticRadiusM -gt 0.05) {
    $dynIn = if ($DynamicRadiusM -gt 0.05) { $DynamicRadiusM } else { $TyreRadiusM }
    $radiusM = Get-PatchRadiusM -StaticRadiusM $StaticRadiusM -DynamicRadiusM $dynIn -Topo $Topo
  }

  $hertzArea = [math]::Max(0.004, [math]::Min($TyreWidthM * 0.24,
    $LoadRawN / [math]::Max(10000.0, $DynamicPressurePSI * 6894.76)))
  $deflArea = $hertzArea
  if ($ContactDepthM -gt 1e-4 -and $radiusM -gt 0.05 -and $TyreWidthM -gt 0.04) {
    $d = [math]::Min($ContactDepthM, $radiusM * 0.35)
    $chord = 2.0 * [math]::Sqrt([math]::Max(0.0, 2.0 * $radiusM * $d - $d * $d))
    $deflArea = [math]::Max(0.004, [math]::Min($TyreWidthM * 0.28,
      $TyreWidthM * $chord * [double]$Topo.patchDeflWidthFrac))
  }
  $depthBlend = (Clamp-Patch (($ContactDepthM - 0.005) / 0.040) 0 1) * [double]$Topo.patchHertzDeflBlend
  $estArea = $hertzArea * (1.0 - $depthBlend) + $deflArea * $depthBlend

  $patchFracRaw = 0.0
  if ($TyreWidthM -gt 0.04 -and $radiusM -gt 0.05) {
    $patchFracRaw = ($estArea / $TyreWidthM) / [math]::Max(0.4, 2.0 * [math]::PI * $radiusM)
  }
  $patchFrac = Clamp-Patch $patchFracRaw ([double]$Topo.patchFracMin) ([double]$Topo.patchFracMax)
  $patchFracHeat = Clamp-Patch $patchFracRaw `
    ([double]$(if ($Topo.ContainsKey('patchFracHeatMin')) { $Topo.patchFracHeatMin } else { $Topo.patchFracMin })) `
    ([double]$Topo.patchFracMax)

  $depthHeatBoost = 1.0
  if (-not $NoDepthBoost -and $ContactDepthM -gt 0.006) {
    $depthHeatBoost = 1.0 + [math]::Min(0.16, ($ContactDepthM - 0.006) * 2.0)
  }

  # A3: util denom prefers LoadUtilN (downForceRaw)
  $loadUtil = if ($LoadUtilN -gt 0) { $LoadUtilN } else { $LoadRawN }
  $peakWork = 1.0
  if ($PeakForceN -gt 100 -and $loadUtil -gt 100) {
    $peakWork = Clamp-Patch ($PeakForceN / [math]::Max($loadUtil, 1.0)) `
      ([double]$Topo.patchUtilPeakLo) ([double]$Topo.patchUtilPeakHi)
  }
  $utilNudge = 1.0
  if (-not $NoUtilNudge) {
    $utilNudge = 1.0 + (($peakWork - 1.0) * [double]$(if ($Topo.ContainsKey('patchUtilBlend')) { $Topo.patchUtilBlend } else { 0 }))
  }

  $patchHeatScale = Clamp-Patch (
    ($patchFracHeat / [math]::Max(0.05, [double]$Topo.patchFracRef)) * $depthHeatBoost * $utilNudge
  ) 0.40 1.20

  $freeBeltBias = 1.0 + (1.0 - $patchFrac) * ([double]$Topo.freeBeltCoolMult - 1.0)

  # A2 dual rough blend + A1 GM soft extras
  $roughEff = $Rough
  $defDepth = $DefaultDepth
  $strength = $Strength
  $fluid = $FluidDensity
  $stribeck = $StribeckVelocity
  $dualB = 0.0
  if ($DualBlend -gt 0 -and $Rough2 -ge 0) {
    $dualB = $DualBlend
    $b1 = 1.0 - $dualB
    $roughEff = $Rough * $b1 + $Rough2 * $dualB
  }
  $gm = Get-SoftGmExtra -DefaultDepth $defDepth -Strength $strength `
    -FluidDensity $fluid -StribeckVelocity $stribeck -Topo $Topo

  $softSinkDamp = 1.0
  if (-not $NoSoftSinkDamp) {
    $softSinkDamp = 1.0 / (1.0 + [math]::Max(0.0, $ContactDepthM) * [double]$Topo.softSinkHeatCoef +
      $roughEff * [double]$Topo.softSinkRoughCoef + [double]$gm.SoftExtra)
    $softSinkDamp = [math]::Max([double]$Topo.softSinkHeatFloor, $softSinkDamp)
  }

  # Soft-surface conduction denom (live — no area shrink) + A1 GM extras
  $condDenom = 1.0 + [math]::Max(0.0, $ContactDepthM) * 4.0 + $roughEff * 0.5 + [double]$gm.CondExtra

  return [ordered]@{
    HertzArea      = $hertzArea
    DeflArea       = $deflArea
    EstArea        = $estArea
    DepthBlend     = $depthBlend
    PatchFracRaw   = $patchFracRaw
    PatchFrac      = $patchFrac
    PatchFracHeat  = $patchFracHeat
    DepthHeatBoost = $depthHeatBoost
    PatchHeatScale = $patchHeatScale
    FreeBeltBias   = $freeBeltBias
    SoftSinkDamp   = $softSinkDamp
    CondDenom      = $condDenom
    PeakWorkFactor = $peakWork
    UtilNudge      = $utilNudge
    PatchRadiusM   = $radiusM
    SoftGmExtra    = [double]$gm.SoftExtra
    CondGmExtra    = [double]$gm.CondExtra
    DualBlend      = $dualB
    RoughEff       = $roughEff
  }
}
