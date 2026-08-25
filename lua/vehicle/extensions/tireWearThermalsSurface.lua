-- lua/vehicle/extensions/tireWearThermalsSurface.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- Ground-model classify + surface grip bias (cold path; not on 100 Hz thermal step).
local M = {}

local min, max = math.min, math.max
local function lerp(a, b, t) return a + (b - a) * t end

M.classifySurfaceGrip = function(gmName)
    gmName = string.lower(gmName or "")

    -- Base-game keys / aliases first (art/groundmodels.json)
    if gmName == "frictionless" or gmName == "ice" then
        return "ice"
    end
    -- SLIPPERY is wet-asphalt class in BeamNG (collisiontype ASPHALT_WET), NOT ice
    if gmName == "slippery" or gmName == "asphalt_wet" or string.find(gmName, "asphalt_wet") then
        return "wet_paved"
    end
    if gmName == "snow" then
        return "snow"
    end
    if gmName == "mud" then
        return "mud"
    end
    if gmName == "gravel_wet" or string.find(gmName, "gravel_wet") or string.find(gmName, "gravel_riverbed") then
        return "gravel_wet"
    end
    if string.find(gmName, "gravel") or gmName == "dirt_loose" then
        return "gravel"
    end
    -- Dirt before sand so aliases like dirt_sandy stay dirt (not sand)
    if string.find(gmName, "grass") or string.find(gmName, "forest")
        or string.find(gmName, "leaves") or string.find(gmName, "branches")
        or string.find(gmName, "foliage") or string.find(gmName, "dirt") then
        return "dirt"
    end
    if gmName == "sand" or string.find(gmName, "beachsand") or string.find(gmName, "sandtrap")
        or (string.find(gmName, "sand") and not string.find(gmName, "dirt")) then
        return "sand"
    end
    if string.find(gmName, "rock") or string.find(gmName, "cobble") or string.find(gmName, "cliff")
        or string.find(gmName, "stone") then
        return "rock"
    end
    if string.find(gmName, "wet") or string.find(gmName, "puddle") then
        return "wet_paved"
    end
    if string.find(gmName, "asphalt") or string.find(gmName, "road") or string.find(gmName, "concrete")
        or string.find(gmName, "rumble") or string.find(gmName, "kickplate")
        or string.find(gmName, "spike") or string.find(gmName, "grid") then
        return "dry_paved"
    end
    -- Smooth hard props (bridges, ramps, barriers)
    if string.find(gmName, "metal") or string.find(gmName, "wood") or string.find(gmName, "plastic") then
        return "hard_smooth"
    end
    -- Non-drive / special
    if string.find(gmName, "void") or string.find(gmName, "soft_collision") or string.find(gmName, "shock_absorber") then
        return "generic"
    end
    return "generic"
end

M.getSurfaceSanityScale = function(surfaceType, treadCoef, drainage)
    treadCoef = max(0, min(1, treadCoef or 0.5))
    drainage = max(0, min(1, drainage or 0.5))

    if surfaceType == "dry_paved" then
        -- Low tread favors asphalt slightly; hard cap keeps high-G from tripping chassis
        -- Cap 1.15 ≈ peak logged ~1.34 @ Belasco gmμ~0.86 (was 1.49 @ cap 1.28)
        return lerp(1.04, 0.90, treadCoef), 1.15
    elseif surfaceType == "hard_smooth" then
        -- Kerbs/metal: keep below asphalt so curb strikes scrub instead of trip
        return lerp(0.96, 0.90, treadCoef), 1.10
    elseif surfaceType == "wet_paved" then
        -- Drainage/tread help in the wet, but never beat the same tire's dry-paved scale
        -- (MT/logger with wetGripScale were exceeding dry asphalt — illogical).
        local wet = lerp(0.82, 0.98, drainage) * lerp(0.94, 1.02, treadCoef)
        local dry = lerp(1.06, 0.90, treadCoef)
        return min(wet, dry * 0.92), 1.15
    elseif surfaceType == "gravel" then
        return lerp(0.55, 1.05, treadCoef), 1.00
    elseif surfaceType == "gravel_wet" then
        return lerp(0.48, 0.95, treadCoef), 0.88
    elseif surfaceType == "dirt" then
        return lerp(0.62, 1.02, treadCoef), 0.95
    elseif surfaceType == "mud" then
        return lerp(0.34, 1.08, treadCoef), 0.85
    elseif surfaceType == "sand" then
        return lerp(0.42, 1.04, treadCoef), 0.90
    elseif surfaceType == "snow" then
        return lerp(0.36, 1.00, treadCoef), 0.60
    elseif surfaceType == "ice" then
        -- Winter tread helps a little; slicks are awful
        return lerp(0.42, 0.78, treadCoef), 0.30
    elseif surfaceType == "rock" then
        return lerp(0.88, 1.05, treadCoef), 1.40
    end
    return 1.0, 1.30
end

-- Shared surface flags for wear/heat/grip (keeps CalcTyreWear and CalculateTyreGrip aligned)
-- Fills `out` in place — no allocation when caller reuses a table.
M.fillSurfaceFlags = function(out, surfaceType, gmName)
    out = out or {}
    out.ice = surfaceType == "ice"
    out.snow = surfaceType == "snow"
    out.mud = surfaceType == "mud"
    out.sand = surfaceType == "sand"
    out.gravel = surfaceType == "gravel" or surfaceType == "gravel_wet"
    out.dirtGrass = surfaceType == "dirt"
    out.wet = surfaceType == "wet_paved" or surfaceType == "gravel_wet"
    out.dryPaved = surfaceType == "dry_paved" or surfaceType == "hard_smooth"
    out.loose = surfaceType == "dirt" or surfaceType == "mud" or surfaceType == "gravel"
        or surfaceType == "gravel_wet" or surfaceType == "sand" or surfaceType == "snow"
    out.gmName = gmName or ""
    out.surfaceType = surfaceType
    return out
end

-- Cache classifySurfaceGrip + rain morph until contact material or rain state changes
M.resolveWheelSurface = function(w, groundModel, isRaining)
    local matId = w.contactMatId
    if matId == nil then matId = -2 end
    local raining = not not isRaining
    if w.surfCacheMatId == matId and w.surfCacheRaining == raining and w.surfaceType and w.surfaceFlags then
        return w.surfaceType, w.surfaceFlags
    end

    local gmName = (groundModel and groundModel.nameLower) or ""
    local surfaceType = M.classifySurfaceGrip(gmName)
    if raining then
        if surfaceType == "dry_paved" or surfaceType == "hard_smooth" or surfaceType == "rock" then
            surfaceType = "wet_paved"
        elseif surfaceType == "dirt" then
            surfaceType = "mud"
        elseif surfaceType == "gravel" then
            surfaceType = "gravel_wet"
        end
    end

    if not w.surfaceFlags then w.surfaceFlags = {} end
    M.fillSurfaceFlags(w.surfaceFlags, surfaceType, gmName)
    w.surfaceType = surfaceType
    w.surfCacheMatId = matId
    w.surfCacheRaining = raining
    return surfaceType, w.surfaceFlags
end

-- Profile × surface grip bias (compound character on top of treadCoef sanity scale)
-- profile1/profile2 should already be lowercased (tyreData.profile1Lower / profile2Lower).
M.applyProfileSurfaceBias = function(tyreGrip, surfaceType, profile1, profile2)
    local p1 = profile1 or ""
    local p2 = profile2 or ""
    local function has(tag)
        return string.find(p1, tag, 1, true) or string.find(p2, tag, 1, true)
    end

    local isPaddle = has("paddle")
    local isWinter = has("winter")
    local isRally = has("rally")
    local isCrawler = has("crawler")
    local isMudTerrain = has("mudterrain") or has("mud_terrain")
    local isAllTerrain = has("allterrain") or has("all_terrain")
    local isSlick = has("slick")
    local isRain = (p1 == "rain" or p2 == "rain")
    local isDrift = has("drift")
    local isDrag = has("drag")
    -- Truck / commercial family (spectrum names: highway_*_truck, heavy_offroad_truck, logger_utility, etc.)
    local isTruckOffroad = has("offroad") or has("logger")
    local isTruckDrive = has("traction") and has("drive")
    local isTruckHighway = has("highway") or has("trailer") or (has("steer") and has("truck"))
    local isLightTruckHd = has("light_truck_hd") or has("heavy_duty")
    local isLightTruck = has("light_truck") and not isLightTruckHd
    -- Street continuum (standard / sport / vintage): asphalt preference + loose penalty.
    -- Restores asphalt>loose gap after global gm bump; excludes rally/AT/MT/race/truck specialists.
    -- Asphalt *1.02 only on standard/vintage (sport already has dryGripScale 1.02).
    local isSportPlus = has("sport_plus")
    local isSport = has("sport") and not isSportPlus
    local isStreetLoose = (has("standard") or isSport or has("vintage"))
        and not isRally and not isAllTerrain and not isMudTerrain and not isCrawler
        and not isSlick and not isDrag and not isPaddle
        and not isTruckOffroad and not isTruckDrive and not isTruckHighway
        and not isLightTruck and not isLightTruckHd
    local isStreetAsphalt = (has("standard") or has("vintage"))
        and not isRally and not isAllTerrain and not isMudTerrain and not isCrawler
        and not isSlick and not isDrag and not isPaddle
        and not isTruckOffroad and not isTruckDrive and not isTruckHighway
        and not isLightTruck and not isLightTruckHd

    if surfaceType == "sand" then
        if isPaddle then tyreGrip = tyreGrip * 1.35
        elseif isMudTerrain then tyreGrip = tyreGrip * 1.10
        elseif isAllTerrain or isCrawler then tyreGrip = tyreGrip * 1.06
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.08
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.04
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.90
        elseif isStreetLoose then tyreGrip = tyreGrip * 0.90
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.88
        end
    elseif surfaceType == "mud" then
        if isPaddle then tyreGrip = tyreGrip * 1.25
        elseif isMudTerrain or isCrawler then tyreGrip = tyreGrip * 1.14
        elseif isRally or isAllTerrain then tyreGrip = tyreGrip * 1.08
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.12
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.06
        elseif isLightTruckHd or isLightTruck then tyreGrip = tyreGrip * 1.04
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.88
        elseif isStreetLoose then tyreGrip = tyreGrip * 0.86
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.82
        end
    elseif surfaceType == "rock" then
        if isCrawler then tyreGrip = tyreGrip * 1.18
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.14
        elseif isAllTerrain or isTruckDrive then tyreGrip = tyreGrip * 1.06
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.96
        elseif isPaddle then tyreGrip = tyreGrip * 0.80
        elseif isSlick then tyreGrip = tyreGrip * 0.94
        end
    elseif surfaceType == "gravel" or surfaceType == "dirt" then
        -- Rally: raised loose baseline (was 1.12) — asphalt path unchanged
        if isRally then tyreGrip = tyreGrip * 1.20
        elseif isAllTerrain then tyreGrip = tyreGrip * 1.10
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.10
        elseif isMudTerrain then tyreGrip = tyreGrip * 1.06
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.05
        elseif isLightTruckHd or isLightTruck then tyreGrip = tyreGrip * 1.04
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.94
        elseif isStreetLoose then tyreGrip = tyreGrip * 0.90
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.90
        elseif isDrift then tyreGrip = tyreGrip * 0.95
        end
    elseif surfaceType == "gravel_wet" then
        if isRally then tyreGrip = tyreGrip * 1.14
        elseif isAllTerrain then tyreGrip = tyreGrip * 1.08
        elseif isMudTerrain or isCrawler or isTruckOffroad then tyreGrip = tyreGrip * 1.10
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.04
        elseif isRain then tyreGrip = tyreGrip * 1.06
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.90
        elseif isStreetLoose then tyreGrip = tyreGrip * 0.88
        elseif isSlick then tyreGrip = tyreGrip * 0.85
        end
    elseif surfaceType == "snow" or surfaceType == "ice" then
        if isWinter then tyreGrip = tyreGrip * 1.22
        elseif isRain then tyreGrip = tyreGrip * 1.08
        elseif isAllTerrain or isTruckOffroad then tyreGrip = tyreGrip * 1.05
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.03
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.92
        elseif isStreetLoose then tyreGrip = tyreGrip * 0.92
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.82
        end
    elseif surfaceType == "wet_paved" then
        if isRain then tyreGrip = tyreGrip * 1.06 -- stacks mildly with wetGripScale
        elseif isWinter then tyreGrip = tyreGrip * 1.04
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.92 -- extra caution; wetGripScale already harsh
        end
    elseif surfaceType == "dry_paved" or surfaceType == "hard_smooth" then
        -- Slicks already get dryGripScale + surfaceCap; avoid stacking another asphalt bonus
        if isSlick or isDrag then tyreGrip = tyreGrip * 1.0
        elseif isMudTerrain or isCrawler or isTruckOffroad then tyreGrip = tyreGrip * 0.96
        elseif isPaddle then tyreGrip = tyreGrip * 0.90
        elseif isStreetAsphalt then tyreGrip = tyreGrip * 1.02
        elseif isTruckHighway then tyreGrip = tyreGrip * 1.02
        end
    end
    return tyreGrip
end

return M
