-- lua/vehicle/extensions/tireWearThermalsClassify.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local min, max, abs, pi, exp = math.min, math.max, math.abs, math.pi, math.exp

function M.install(F, deps)
    local DEFAULT_MODS = deps.DEFAULT_MODS
    local STANDALONE_MODIFIERS = deps.STANDALONE_MODIFIERS
    local PROFILE_POINTS = deps.PROFILE_POINTS
    local SLICK_SPECTRUM_POINTS = deps.SLICK_SPECTRUM_POINTS
    local UTILITY_SPECTRUM_POINTS = deps.UTILITY_SPECTRUM_POINTS
    local COMMERCIAL_SPECTRUM_POINTS = deps.COMMERCIAL_SPECTRUM_POINTS
    local ATV_UTV_SPECTRUM_POINTS = deps.ATV_UTV_SPECTRUM_POINTS
    local VINTAGE_SPECTRUM_POINTS = deps.VINTAGE_SPECTRUM_POINTS
    local cache = deps.cache
    local lerp = deps.lerp

    -- Dynamic Spectrum Interpolator Helper (0-Allocation In-Place Table Updates)
    F.interpolateSpectrum = function(spectrum, searchKey, value, targetTable)
        local p1, p2
        value = tonumber(value) or 0
        if value ~= value then value = 0 end -- Safe NaN check
    
        -- Safety Check bounds immediately before search sequence
        if value < spectrum[1][searchKey] then
            p1 = spectrum[1]
            p2 = spectrum[2] or spectrum[1]
        elseif value > spectrum[#spectrum][searchKey] then
            p1 = spectrum[#spectrum - 1] or spectrum[1]
            p2 = spectrum[#spectrum]
        else
            for i = 1, #spectrum - 1 do
                if value >= spectrum[i][searchKey] and value <= spectrum[i + 1][searchKey] then
                    p1 = spectrum[i]
                    p2 = spectrum[i + 1]
                    break
                end
            end
        end
    
        p1 = p1 or spectrum[1]
        p2 = p2 or spectrum[2] or spectrum[1]
    
        local diff = p2[searchKey] - p1[searchKey]
        local factor = 0
        if diff > 0 then
            -- Safe clamp factors to bounds (prevents extrapolation issues)
            factor = max(0, min(1, (value - p1[searchKey]) / diff))
        end
    
        -- Clear key space in targetTable to perform allocation-free updates
        for k in pairs(targetTable) do
            targetTable[k] = nil
        end
    
        -- Merge and interpolate metrics
        for k, v1 in pairs(p1.mods) do
            local v2 = p2.mods[k]
            targetTable[k] = v2 and lerp(v1, v2, factor) or v1
        end
        -- Keys only on p2: lerp from a numeric default when factor < 1 so Soft-adjacent
        -- does not inherit full supersoft-only knobs (e.g. scalarTreadWearScale 1.0).
        for k, v2 in pairs(p2.mods) do
            if targetTable[k] == nil then
                if type(v2) == "number" then
                    local v1 = DEFAULT_MODS[k]
                    if k == "scalarTreadWearScale" then v1 = 0.15 end
                    if k == "nodeWearScale" then v1 = 1.0 end
                    if type(v1) == "number" then
                        targetTable[k] = lerp(v1, v2, factor)
                    else
                        targetTable[k] = v2
                    end
                else
                    targetTable[k] = v2
                end
            end
        end
    
        return p1.profile, p2.profile, factor
    end

    -- Helper to safely clear and copy table values in-place without allocations
    F.copyMods = function(src, target)
        local t = target or {}
        for k in pairs(t) do t[k] = nil end
        if type(src) ~= "table" then return t end
        for k, v in pairs(src) do t[k] = v end
        return t
    end

    F.getProfilePointMods = function(profileName)
        for i = 1, #PROFILE_POINTS do
            local pt = PROFILE_POINTS[i]
            if pt and pt.profile == profileName then return pt.mods end
        end
        return nil
    end

    -- Fills missing knobs from DEFAULT_MODS (keeps spectrum interpolation stable)
    F.normalizeProfileMods = function(mods)
        if type(mods) ~= "table" then return mods end
        for k, v in pairs(DEFAULT_MODS) do
            if mods[k] == nil then mods[k] = v end
        end
        return mods
    end

    -- Plateau-Gaussian thermal grip from profile knobs (single source of truth with optimalTemp)
    -- Cold side uses a softer exponent so street/sport compounds are not cliffed below ~40C.
    F.getProfileThermalGrip = function(mods, temp, compliance, softness)
        mods = mods or DEFAULT_MODS
        temp = temp or 21
        compliance = compliance or 0.5
        softness = softness or 0.5
        local tOpt = mods.optimalTemp or DEFAULT_MODS.optimalTemp
        local plateau = (mods.tempPlateau or DEFAULT_MODS.tempPlateau) * (0.8 + 0.4 * softness)
        local wCold = (mods.coldWidth or DEFAULT_MODS.coldWidth) * (0.8 + 0.4 * softness) * (1.0 + (compliance - 0.5) * 0.15)
        local wHot = (mods.hotWidth or DEFAULT_MODS.hotWidth) * (0.8 + 0.4 * softness)
        local floor = mods.gripFloor or DEFAULT_MODS.gripFloor
        local diff = abs(temp - tOpt)
        local excess = max(0.0, diff - plateau)
        local width = (temp < tOpt) and wCold or wHot
        -- Cold/hot exponents are profile knobs (defaults = pre-expansion 1.35 / 2.0)
        local power = (temp < tOpt)
            and (mods.coldGripPower or DEFAULT_MODS.coldGripPower or 1.35)
            or (mods.hotGripPower or DEFAULT_MODS.hotGripPower or 2.0)
        local decay = exp(-((excess / max(1.0, width)) ^ power))
        return floor + (1.0 - floor) * decay
    end
    -- Translates the wheel index position (e.g., "FL") to its actual active JBeam part name (Compatible with 0.35+)
    -- Skips trunk/side spare parts — those contain "tire"/"spare" and were stealing classification from road tires.
    F.isSpareOrAccessoryTireName = function(pLower)
        pLower = pLower or ""
        -- plain find: avoid pattern surprises; match common BeamNG spare slot/part names
        if string.find(pLower, "spare", 1, true) then return true end
        if string.find(pLower, "donut", 1, true) then return true end
        if string.find(pLower, "space_saver", 1, true) or string.find(pLower, "spacesaver", 1, true) then return true end
        if string.find(pLower, "temporary", 1, true) then return true end
        return false
    end

    F.getTirePartName = function(wheelName)
        local nameLower = string.lower(tostring(wheelName or ""))
        local isFront = string.match(nameLower, "^f")
        local isRear = string.match(nameLower, "^r")

        local function partNameFromEntry(k, v_part)
            if type(v_part) == "string" and v_part ~= "" then return v_part end
            if type(v_part) == "table" then
                local n = v_part.name or v_part.partName
                if type(n) == "string" and n ~= "" then return n end
            end
            if type(k) == "string" and k ~= "" then return k end
            return tostring(k)
        end

        local function scoreTirePart(partName)
            local pLower = string.lower(partName or "")
            if not string.find(pLower, "tire", 1, true) and not string.find(pLower, "tyre", 1, true) then
                return -1
            end
            if F.isSpareOrAccessoryTireName(pLower) then return -1 end

            local score = 10
            -- Axle-slot naming: tire_F_* = front, tire_R_* = rear (BeamNG common tires)
            local axleFront = string.find(pLower, "tire_f", 1, true) or string.find(pLower, "_f_", 1, true)
                or string.find(pLower, "front", 1, true)
            local axleRear = string.find(pLower, "tire_r", 1, true) or string.find(pLower, "_r_", 1, true)
                or string.find(pLower, "rear", 1, true)

            if isFront then
                if axleFront then score = score + 50
                elseif axleRear then score = score - 20 end
            elseif isRear then
                if axleRear then score = score + 50
                elseif axleFront then score = score - 20 end
            end

            -- Prefer compound tags over generic unnamed tires
            if string.find(pLower, "vintage", 1, true) or string.find(pLower, "bias", 1, true)
                or string.find(pLower, "whitewall", 1, true) or string.find(pLower, "sport", 1, true)
                or string.find(pLower, "standard", 1, true) or string.find(pLower, "slick", 1, true)
                or string.find(pLower, "race", 1, true) or string.find(pLower, "rally", 1, true)
                or string.find(pLower, "asphalt", 1, true) or string.find(pLower, "tarmac", 1, true)
                or string.find(pLower, "winter", 1, true) or string.find(pLower, "offroad", 1, true)
                or string.find(pLower, "drag", 1, true) or string.find(pLower, "drift", 1, true) then
                score = score + 15
            end
            return score
        end

        local activeParts = v and v.data and (v.data.activePartsData or v.data.activeParts)
        local bestName, bestScore = nil, -1
        if type(activeParts) == "table" then
            for k, v_part in pairs(activeParts) do
                local partName = partNameFromEntry(k, v_part)
                local sc = scoreTirePart(partName)
                if sc > bestScore then
                    bestScore = sc
                    bestName = partName
                end
            end
        end
        if bestName then return bestName end
        return wheelName
    end

    -- True when a plain asphalt-rally damper is fitted (coilover/strut with "rally", not track/race).
    -- Weak evidence only for BeamNG asphalt-rally configs that mount generic *_race tires
    -- (Covet/Bolide/BX). Never sufficient alone for low-tread rubber — caller also needs a
    -- race name (not explicit slick) plus this flag. MUST NOT match chassis/subframes:
    -- Vivace Ardente race mounts vivace_suspension_*_rally + vivace_rally_coilover_*_track —
    -- suspension_*_rally previously forced tarmac_rally despite track-spec coilovers.
    -- Also ignore strut_bar / strutbrace (anti-roll braces, not dampers).
    F.vehicleHasPlainRallyDamper = function()
        if cache.rallyDamper ~= nil then return cache.rallyDamper end
        local found = false
        local activeParts = v and v.data and (v.data.activePartsData or v.data.activeParts)
        if type(activeParts) == "table" then
            for k, v_part in pairs(activeParts) do
                -- Prefer fitted part name; skip empty slots (do not fall back to slot key — empty
                -- vivace_rally_* slots would otherwise look like fitted rally hardware).
                local n = ""
                if type(v_part) == "string" then
                    n = v_part
                elseif type(v_part) == "table" then
                    n = tostring(v_part.name or v_part.partName or "")
                end
                n = string.lower(n)
                if n ~= ""
                    and string.find(n, "rally", 1, true)
                    and (string.find(n, "coilover", 1, true) or string.find(n, "strut", 1, true))
                    and not string.find(n, "strut_bar", 1, true)
                    and not string.find(n, "strutbar", 1, true)
                    and not string.find(n, "strutbrace", 1, true)
                    and not string.find(n, "skin", 1, true)
                    and not string.find(n, "paint", 1, true)
                    and not string.find(n, "light", 1, true)
                    and not string.find(n, "cover", 1, true)
                    and not string.find(n, "interior", 1, true)
                    and not string.find(n, "switch", 1, true)
                    and not string.find(n, "track", 1, true)     -- vivace_rally_coilover_*_track
                    and not string.find(n, "circuit", 1, true)
                    and not string.find(n, "gravel", 1, true)
                    and not string.find(n, "_race", 1, true)     -- race-spec dampers
                    and not string.find(n, "race_", 1, true) then
                    found = true
                    break
                end
            end
        end
        cache.rallyDamper = found
        return found
    end

    F.getVehicleType = function()
        if cache.vehicleType then return cache.vehicleType end
        local vehType = "passenger_car"
    
        if v and type(v) == "table" and v.vehicleDirectory then
            local dirLower = string.lower(tostring(v.vehicleDirectory))
            if string.find(dirLower, "aurata") or string.find(dirLower, "utv") or string.find(dirLower, "atv") or string.find(dirLower, "sxs") then
                vehType = "utv"
            elseif string.find(dirLower, "md_series") or string.find(dirLower, "md%-series") or string.find(dirLower, "medium") or string.find(dirLower, "heavy_duty") or string.find(dirLower, "mt_series") or string.find(dirLower, "durham") or string.find(dirLower, "b_series") or string.find(dirLower, "b%-series") then
                vehType = "medium_duty"
            elseif string.find(dirLower, "semi") or string.find(dirLower, "t_series") or string.find(dirLower, "t%-series") or string.find(dirLower, "trailer") then
                vehType = "semi_truck"
            elseif string.find(dirLower, "pickup") or string.find(dirLower, "van") or string.find(dirLower, "roamer") then
                vehType = "light_truck"
            end
            cache.vehicleType = vehType -- Cache successfully resolved vehicle type
        elseif cache.typeRetryCount > 10 then
            cache.vehicleType = "passenger_car" -- Freeze cache to passenger_car after 10 failed frames
        else
            cache.typeRetryCount = cache.typeRetryCount + 1
        end
    
        return cache.vehicleType or vehType
    end

    -- BeamNG race tires often ship softnessCoef=1.0 (and discrete 0.5/0.8/1.0 tiers).
    -- Densified SLICK_SPECTRUM_POINTS live in 0.50–0.875; remap common JBeam values onto that band.
    -- Soft=0 / very low floors to hard (do not treat fantasy 0 as soft). Continuous midpoints
    -- already in 0.50–0.875 (0.575/0.725/0.875/…) keep interpolating unchanged.
    -- Stock 1.0 still maps to C4 (0.80); C5 supersoft is an explicit 0.875 SKU.
    F.remapSlickSoftness = function(softnessCoef)
        local s = tonumber(softnessCoef) or 0.5
        if s ~= s then s = 0.5 end
        if s >= 0.99 then return 0.80 end                 -- 1.0 and above → soft C4 (not C5)
        if abs(s - 0.8) <= 0.012 then return 0.65 end      -- ~0.8 → medium anchor
        if s >= 0.50 and s <= 0.875 then return s end      -- densified continuum incl. supersoft
        if s < 0.50 then return 0.50 end                  -- hard floor (incl. soft=0)
        -- (0.875, 0.99): approach supersoft from soft
        return 0.80 + ((s - 0.875) / 0.115) * 0.075
    end

    -- Named street sport compounds must not fall through the utility radius band (20" passenger
    -- tires like 275/40R20 sit ~0.36–0.37 m and were misrouted to highway_utility_utility).
    local function isNamedStreetSportCompound(nameLower)
        if string.find(nameLower, "sport_plus", 1, true) then return true end
        if string.find(nameLower, "track_day", 1, true) or string.find(nameLower, "sport_tour", 1, true) then return true end
        if string.find(nameLower, "supersport", 1, true) then return false end
        return string.find(nameLower, "sport", 1, true) ~= nil
    end

    -- Hybrid Profile Resolving Engine (With Dynamic Dimensional Scaling & All Continuous Spectrums)
    F.getInterpolatedProfile = function(treadCoef, softnessCoef, tireName, targetTable, radius, width, hubRadius)
        treadCoef, softnessCoef = treadCoef or 0.5, softnessCoef or 0.5
        local nameLower = string.lower(tostring(tireName or ""))
        local mods = targetTable or {}
        local rawProfile1, rawProfile2, interpFactor
    
        local r, w = max(0.1, radius or 0.3), max(0.1, width or 0.2)
        local hr = max(0.05, min(r - 0.01, hubRadius or (r * 0.65)))
        local sidewall = r - hr
    
        local vehType = F.getVehicleType()
        local isHeavyCommercialName = string.find(nameLower, "22.5") or string.find(nameLower, "19.5") or string.find(nameLower, "24.5") or string.find(nameLower, "steer") or string.find(nameLower, "drive") or string.find(nameLower, "semi")
        local isCommercialTire = (vehType == "semi_truck" or vehType == "medium_duty") or (radius and radius >= 0.44 and width and width >= 0.22) or (isHeavyCommercialName and radius and radius >= 0.40)
        local isUtilityTire = not isCommercialTire and not isNamedStreetSportCompound(nameLower)
            and ((vehType == "light_truck")
                -- 20" passenger radius band (~0.36–0.44 m) was too aggressive:
                -- if `tireName` lookup fails, we still don't want Sport/Track Day (tread~0.40)
                -- to get misrouted into highway_utility_utility.
                or ((radius and radius >= 0.36 and radius < 0.44) and (treadCoef and treadCoef <= 0.37)))
        local isUTVTire = not isCommercialTire and not isUtilityTire and (vehType == "utv" or string.find(nameLower, "utv") or string.find(nameLower, "atv") or string.find(nameLower, "aurata") or string.find(nameLower, "sxs"))
        local isVintageTire = not isCommercialTire and not isUtilityTire and not isUTVTire and (string.find(nameLower, "vintage") or string.find(nameLower, "biasply") or string.find(nameLower, "bias_ply") or string.find(nameLower, "whitewall") or string.find(nameLower, "classic_radial"))

        -- Sealed-road rally rubber — safer default: race/slick/low-tread → circuit slick unless strong evidence.
        -- Strong: explicit *_asphalt / *_tarmac tire names, OR BeamNG competition tarmac SKUs that are
        -- still named *_race (UI type "Asphalt Rally", meshes tire_rally_tarmac_*): 180/580, 200/600, 210/600.
        -- Weak: *_race name (not explicit slick) + plain rally coilover/strut only — never damper alone,
        -- never low-tread-only, never suspension_*_rally subframes (Vivace Ardente race keeps those with
        -- track coilovers). Explicit *_slick stays circuit even with plain rally dampers.
        -- Tradeoff: Bolide/Covet/BX asphalt-rally keep working via plain rally dampers; if those
        -- dampers are absent, only the competition SKUs / explicit asphalt names still map correctly.
        local isAsphaltName = string.find(nameLower, "tarmac", 1, true)
            or (string.find(nameLower, "asphalt", 1, true) and not string.find(nameLower, "supersport", 1, true))
        -- Competition-size asphalt-rally race SKUs (not 210_650 race slicks).
        local isAsphaltRallyRaceSku = string.find(nameLower, "race", 1, true)
            and (string.find(nameLower, "180_580", 1, true)
                or string.find(nameLower, "200_600", 1, true)
                or string.find(nameLower, "210_600", 1, true))
        local isGravelRallyName = string.find(nameLower, "rally", 1, true) and not isAsphaltName
        local isSlickName = string.find(nameLower, "slick", 1, true)
        local isRaceName = string.find(nameLower, "race", 1, true)
        -- Bare "race" in the name does NOT force slick when tread is clearly street (≥~0.35).
        -- Stronger evidence still forces: slick token, low tread, or gt3/gt4/formula/retro|modernrace.
        local isRaceLikeName = isSlickName or treadCoef <= 0.12
            or string.find(nameLower, "gt3", 1, true) or string.find(nameLower, "gt4", 1, true)
            or string.find(nameLower, "formula", 1, true)
            or string.find(nameLower, "retrorace", 1, true)
            or string.find(nameLower, "modernrace", 1, true)
            or (isRaceName and treadCoef < 0.35)
        -- Damper is weak evidence: requires race name + not already a clear circuit slick.
        local hasPlainRallyDamper = false
        local isDamperTarmacHint = false
        if not isAsphaltName and not isAsphaltRallyRaceSku then
            hasPlainRallyDamper = F.vehicleHasPlainRallyDamper()
            isDamperTarmacHint = isRaceName and not isSlickName
                and not isGravelRallyName and not string.find(nameLower, "gravel", 1, true)
                and hasPlainRallyDamper
        end
        local isRallyAsphaltMount = isAsphaltName or isAsphaltRallyRaceSku or isDamperTarmacHint
        local tarmacClassifyReason = isAsphaltName and "asphalt_name"
            or (isAsphaltRallyRaceSku and "race_sku")
            or (isDamperTarmacHint and "rally_damper")
            or nil

        -- 1. DETECT DETACHED OR STANDALONE SPECIFIC DESIGNS FIRST
        -- Vintage before spare: spare slots often contain "tire" and used to win incorrectly.
        local purpose, classifyReason = "street", "street_spectrum"
        if string.find(nameLower, "crawler") or string.find(nameLower, "beadlock") then
            rawProfile1, rawProfile2, interpFactor = "crawler", "crawler", 0; F.copyMods(STANDALONE_MODIFIERS.crawler, mods)
            purpose, classifyReason = "utility", "standalone_crawler"
        elseif string.find(nameLower, "paddle") or string.find(nameLower, "sand") then
            rawProfile1, rawProfile2, interpFactor = "paddle", "paddle", 0; F.copyMods(STANDALONE_MODIFIERS.paddle, mods)
            purpose, classifyReason = "utility", "standalone_paddle"
        elseif isRallyAsphaltMount then
            rawProfile1, rawProfile2, interpFactor = "rally", "rally", 0; F.copyMods(STANDALONE_MODIFIERS.rally, mods)
            purpose, classifyReason = "tarmac_rally", tarmacClassifyReason or "rally_damper"
        elseif isGravelRallyName then
            rawProfile1, rawProfile2, interpFactor = "rally", "rally", 0; F.copyMods(STANDALONE_MODIFIERS.rally, mods)
            purpose, classifyReason = "gravel", "gravel_name"
        elseif string.find(nameLower, "winter") or string.find(nameLower, "snow") then
            rawProfile1, rawProfile2, interpFactor = "winter", "winter", 0; F.copyMods(STANDALONE_MODIFIERS.winter, mods)
            purpose, classifyReason = "winter", "standalone_winter"
        elseif string.find(nameLower, "vintage") or string.find(nameLower, "biasply") or string.find(nameLower, "bias_ply") or string.find(nameLower, "whitewall") then
            rawProfile1, rawProfile2, interpFactor = "vintage", "vintage", 0; F.copyMods(STANDALONE_MODIFIERS.vintage, mods)
            purpose, classifyReason = "street", "standalone_vintage"
        elseif string.find(nameLower, "donut") or string.find(nameLower, "spare") then
            rawProfile1, rawProfile2, interpFactor = "donut", "donut", 0; F.copyMods(STANDALONE_MODIFIERS.donut, mods)
            purpose, classifyReason = "utility", "standalone_donut"
        elseif string.find(nameLower, "rain") or string.find(nameLower, "wet") or string.find(nameLower, "inter") then
            rawProfile1, rawProfile2, interpFactor = "rain", "rain", 0; F.copyMods(STANDALONE_MODIFIERS.rain, mods)
            purpose, classifyReason = "wet", "standalone_rain"
        elseif string.find(nameLower, "drag") then
            rawProfile1, rawProfile2, interpFactor = "drag", "drag", 0; F.copyMods(STANDALONE_MODIFIERS.drag, mods)
            purpose, classifyReason = "drag", "standalone_drag"
        elseif string.find(nameLower, "drift") then
            rawProfile1, rawProfile2, interpFactor = "drift", "drift", 0; F.copyMods(STANDALONE_MODIFIERS.drift, mods)
            purpose, classifyReason = "drift", "standalone_drift"
        elseif string.find(nameLower, "track_day", 1, true) or string.find(nameLower, "sport_tour", 1, true) then
            -- sport_tour is the old Track Day name; do not keep a fourth sport profile.
            rawProfile1, rawProfile2, interpFactor = "track_day", "track_day", 0
            F.copyMods(F.getProfilePointMods("track_day"), mods)
            purpose, classifyReason = "street", "track_day_name"
        elseif string.find(nameLower, "sport_plus", 1, true) then
            -- Native Sport Plus JBeam is treadCoef 0.40; name still owns the Scintilla plus lock.
            rawProfile1, rawProfile2, interpFactor = "sport_plus", "sport_plus", 0
            F.copyMods(F.getProfilePointMods("sport_plus"), mods)
            purpose, classifyReason = "street", "sport_plus_name"
        elseif isRaceLikeName and not string.find(nameLower, "gravel", 1, true) then
            -- Remap BeamNG 0.5/0.8/1.0 soft tiers onto densified 0.50/0.65/0.80 spectrum
            -- (explicit 0.875 SKU is C5 supersoft; 1.0 stays C4).
            -- Name wins when JBeam softnessCoef is missing/clamped: NTF *_supersoft_* → C5.
            if string.find(nameLower, "supersoft", 1, true) then
                softnessCoef = 0.875
            end
            local sc = F.remapSlickSoftness(softnessCoef)
            rawProfile1, rawProfile2, interpFactor = F.interpolateSpectrum(SLICK_SPECTRUM_POINTS, "softness", sc, mods)
            purpose, classifyReason = "circuit", "slick_spectrum"
        elseif isNamedStreetSportCompound(nameLower) then
            -- Bare *_sport JBeam (not plus/track_day/tour); tread may differ from 0.50 anchor.
            rawProfile1, rawProfile2, interpFactor = "sport", "sport", 0
            F.copyMods(F.getProfilePointMods("sport"), mods)
            purpose, classifyReason = "street", "sport_name"
        elseif isCommercialTire then
            rawProfile1, rawProfile2, interpFactor = F.interpolateSpectrum(COMMERCIAL_SPECTRUM_POINTS, "tread", max(0.50, min(0.90, treadCoef)), mods)
            purpose, classifyReason = "commercial", "commercial_spectrum"
        elseif isVintageTire then
            rawProfile1, rawProfile2, interpFactor = F.interpolateSpectrum(VINTAGE_SPECTRUM_POINTS, "tread", max(0.50, min(0.65, treadCoef)), mods)
            purpose, classifyReason = "street", "vintage_spectrum"
        elseif isUtilityTire then
            rawProfile1, rawProfile2, interpFactor = F.interpolateSpectrum(UTILITY_SPECTRUM_POINTS, "tread", max(0.50, min(0.95, treadCoef)), mods)
            purpose, classifyReason = "utility", "utility_spectrum"
        elseif isUTVTire then
            rawProfile1, rawProfile2, interpFactor = F.interpolateSpectrum(ATV_UTV_SPECTRUM_POINTS, "tread", max(0.50, min(0.85, treadCoef)), mods)
            purpose, classifyReason = "utility", "utv_spectrum"
        else
            -- Spectrum path updated to re-aligned discrete JBeam increments
            rawProfile1, rawProfile2, interpFactor = F.interpolateSpectrum(PROFILE_POINTS, "tread", max(0.30, min(1, treadCoef)), mods)
            if string.find(nameLower, "gravel", 1, true) and treadCoef > 0.78 then
                purpose, classifyReason = "gravel", "gravel_mt_name"
            else
                purpose, classifyReason = "street", "street_spectrum"
            end
        end

        -- Fill any missing knobs from DEFAULT_MODS before dimensional scaling
        F.normalizeProfileMods(mods)

        -- DYNAMIC DIMENSIONAL SCALING SYSTEM (Intersects all compiled mods via realistic volumetric ratios)
        local REF_RADIUS, REF_WIDTH, REF_SIDEWALL = 0.315, 0.205, 0.112
        local ref_hr = REF_RADIUS - REF_SIDEWALL
        local ref_vol = pi * (REF_RADIUS^2 - ref_hr^2) * REF_WIDTH
    
        local current_vol = pi * (r^2 - hr^2) * w
        local volumeRatio = current_vol / max(1e-5, ref_vol)

        local widthRatio = w / REF_WIDTH
        local sidewallRatio = sidewall / REF_SIDEWALL

        -- Scale physical thermal mass, wear rate, and heat generation on volumetric curves
        local volScale = max(0.4, min(6.0, volumeRatio))
        if mods.treadInertia then mods.treadInertia = mods.treadInertia * volScale end
        if mods.carcassInertia then mods.carcassInertia = mods.carcassInertia * volScale end
        if mods.airThermalInertia then mods.airThermalInertia = mods.airThermalInertia * volScale end
        if mods.wearRate then mods.wearRate = mods.wearRate / max(0.4, min(4.0, volumeRatio)) end
        if mods.slipHeatRate then mods.slipHeatRate = mods.slipHeatRate / max(0.4, min(4.0, volumeRatio)) end
        if mods.workHeatRate then mods.workHeatRate = mods.workHeatRate * max(0.5, min(2.0, sidewallRatio)) end
        if mods.casingCompliance then mods.casingCompliance = mods.casingCompliance * max(0.3, min(1.8, sidewallRatio)) end

        local conductionScale = 1.0 / max(0.5, min(2.0, sidewallRatio))
        if mods.skinCoreConductance then mods.skinCoreConductance = mods.skinCoreConductance * conductionScale end
        if mods.airConductionRate then mods.airConductionRate = mods.airConductionRate * conductionScale end
        if mods.airCoolingRate then mods.airCoolingRate = mods.airCoolingRate * max(0.6, min(1.8, widthRatio)) end
        if mods.staticCoolingRate then mods.staticCoolingRate = mods.staticCoolingRate * max(0.6, min(1.8, widthRatio)) end

        -- Dynamic physical alignment scaling (thin tires are highly sensitive to roll/camber changes)
        if mods.camberSensitivity then mods.camberSensitivity = mods.camberSensitivity * max(0.5, min(2.5, REF_SIDEWALL / max(1e-5, sidewall))) end
        if mods.scrubSensitivity then mods.scrubSensitivity = mods.scrubSensitivity * max(0.6, min(1.8, w / REF_WIDTH)) end

        -- DYNAMIC DESCRIPTOR CLASSIFICATION ENGINE (compound label; purpose owns duty/use)
        -- Rally asphalt mounts share the rally physics pack — compound = "Rally", purpose = tarmac_rally.
        local descriptor = "Standard"
        if string.find(nameLower, "crawler") or string.find(nameLower, "beadlock") then 
            descriptor = "Crawler"
        elseif string.find(nameLower, "paddle") or string.find(nameLower, "sand") then 
            descriptor = "Paddle"
        elseif isRallyAsphaltMount or isGravelRallyName then
            descriptor = "Rally"
        elseif string.find(nameLower, "winter") or string.find(nameLower, "snow") then 
            descriptor = "Winter"
        elseif string.find(nameLower, "vintage") or string.find(nameLower, "biasply") or string.find(nameLower, "bias_ply") or string.find(nameLower, "whitewall") then 
            descriptor = "Vintage"
        elseif string.find(nameLower, "donut") or string.find(nameLower, "spare") then 
            descriptor = "Spare"
        elseif string.find(nameLower, "rain") or string.find(nameLower, "wet") or string.find(nameLower, "inter") then 
            descriptor = "Wet"
        elseif string.find(nameLower, "drag") then 
            descriptor = "Drag"
        elseif string.find(nameLower, "drift") then 
            descriptor = "Drift"
        elseif isRaceLikeName or treadCoef <= 0.15 then
            -- Slick / low-tread / strong race tokens (bare "race" + street tread stays continuum)
            descriptor = "Slick"
        elseif isCommercialTire then
            descriptor = (treadCoef > 0.78) and "Mud-Terrain" or "Standard"
        elseif isVintageTire then
            descriptor = "Vintage"
        elseif isUtilityTire then
            if treadCoef <= 0.58 then
                descriptor = "Standard"
            elseif treadCoef <= 0.78 then
                descriptor = "All-Terrain"
            else
                descriptor = "Mud-Terrain"
            end
        elseif isUTVTire then
            if treadCoef <= 0.58 then
                descriptor = "Standard"
            elseif treadCoef <= 0.78 then
                descriptor = "All-Terrain"
            else
                descriptor = "Mud-Terrain"
            end
        else
            -- Passenger, sport, and sport plus definitions matching official JBeams
            -- Anchors: sport_plus@0.30, track_day@0.40, sport@0.50, standard@0.60/0.70,
            -- allterrain@0.80/0.85, mudterrain@0.90, crawler@1.00
            if treadCoef <= 0.20 then
                descriptor = "Slick"
            elseif treadCoef <= 0.32 then
                descriptor = "Sport Plus"
            elseif treadCoef <= 0.42 then
                descriptor = "Track Day"
            elseif treadCoef <= 0.58 then
                descriptor = "Sport"
            elseif treadCoef <= 0.72 then
                descriptor = "Standard"
            elseif treadCoef <= 0.85 then
                descriptor = "All-Terrain"
            elseif treadCoef <= 0.95 then
                descriptor = "Mud-Terrain"
            else
                descriptor = "Crawler"
            end
        end

        -- Name-owned compounds keep their descriptor/purpose. Do not remap Track Day
        -- (JBeam tread 0.18 sits in the ≤0.20 Slick band) or Sport Plus onto circuit.
        if classifyReason == "sport_plus_name" then descriptor = "Sport Plus" end
        if classifyReason == "track_day_name" then descriptor = "Track Day" end
        if classifyReason == "sport_name" then descriptor = "Sport" end

        -- Unnamed low-tread street-spectrum path still shows Slick but stays circuit purpose
        if descriptor == "Slick" and purpose == "street" then
            purpose, classifyReason = "circuit", "slick_spectrum"
        end

        mods.descriptor = descriptor
        mods.purpose = purpose
        mods.classifyReason = classifyReason
        return rawProfile1, rawProfile2, interpFactor, mods
    end
end

return M

