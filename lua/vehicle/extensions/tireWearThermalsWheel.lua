-- lua/vehicle/extensions/tireWearThermalsWheel.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local min, max, abs, sqrt, pi, deg, asin = math.min, math.max, math.abs, math.sqrt, math.pi, math.deg, math.asin
local atan2 = math.atan2

function M.install(F, deps)
    local getWheels = deps.getWheels or function() return deps.wheels end
    local getV = deps.getV or function() return deps.v end
    local objPcall = deps.objPcall
    local objCall = deps.objCall or function(name, ...)
        local ok, a, b, c, d = objPcall(name, ...)
        if not ok then return end
        return a, b, c, d
    end
    local vec3 = deps.vec3
    local quat = deps.quat
    local vecLen = deps.vecLen
    local lerp = deps.lerp
    local tyreData = deps.tyreData
    local classifyCache = deps.classifyCache
    local brakeDuctSettings = deps.brakeDuctSettings
    local getEnvTemp = deps.getEnvTemp or function() return deps.ENV_TEMP end
    local WORKING_TEMP = deps.WORKING_TEMP
    local DUCT_DEFAULT_PCT = deps.DUCT_DEFAULT_PCT
    local MAX_DUCT_AIR_FACTOR = deps.MAX_DUCT_AIR_FACTOR
    local SLICK_PREHEAT_BLEND = deps.SLICK_PREHEAT_BLEND
    local STREET_PREHEAT_BLEND = deps.STREET_PREHEAT_BLEND
    local SKIN_PREHEAT_FRAC = deps.SKIN_PREHEAT_FRAC
    local setWheelCount = deps.setWheelCount
    local resetStintDistance = deps.resetStintDistance
    local getTirePartName = deps.getTirePartName
    local getInterpolatedProfile = deps.getInterpolatedProfile
    local getNativeGroupPressurePSI = deps.getNativeGroupPressurePSI
    local getTuneColdFillPSI = deps.getTuneColdFillPSI
    local setNativeGroupPressurePSI = deps.setNativeGroupPressurePSI
    local seedHotTargetPSI = deps.seedHotTargetPSI or function(cold, opt)
        return max(1.0, opt or cold or 25.0)
    end
    local remapSlickSoftness = deps.remapSlickSoftness
    local isRemoteMpVehicle = deps.isRemoteMpVehicle

    -- Brake duct (tuning menu / mailbox)
    F.getBrakeDuctPercent = function(isFront)
        local idx = isFront and 1 or 2
        local key = isFront and "$WheelCoolingDuctFront" or "$WheelCoolingDuctRear"
        local v = getV()
        if v and v.data and type(v.data.variables) == "table" then
            local var = v.data.variables[key]
            if type(var) == "table" and var.val ~= nil then
                local n = tonumber(var.val)
                if n then return max(1, min(100, n)) end
            end
        end
        local fromMailbox = brakeDuctSettings[idx]
        if type(fromMailbox) == "number" then
            return max(1, min(100, fromMailbox))
        end
        return DUCT_DEFAULT_PCT
    end

    -- Maps duct % → tire-side factors (Lua only; native brakeTypeSurfaceCoolingCoef restored stock).
    -- Returns: ductAirCoolFactor, ductSoakCondFactor, open01
    --   ductAirCoolFactor  — freestream cooling on skin / carcass / rim (1.0→MAX @ open)
    --   ductSoakCondFactor — brake→rim soak + rim↔carcass conduction (1.15 closed → 0.85 open)
    F.ductPercentToFactors = function(ductPct)
        local open = max(0, min(1, (ductPct - 1) / 99)) -- 1→0, 100→1
        local ductAirCoolFactor = lerp(1.0, MAX_DUCT_AIR_FACTOR, open)
        local ductSoakCondFactor = lerp(1.15, 0.85, open)
        return ductAirCoolFactor, ductSoakCondFactor, open
    end

    -- JBeam construction factors (cached per wheel at init)
    F.getWheelJBeamData = function(wd)
        local v = getV()
        if not wd or not v or not v.data or type(v.data.wheels) ~= "table" then return nil end
        local row = v.data.wheels[wd.cid]
        if type(row) == "table" then return row end
        if wd.wheelID ~= nil then
            row = v.data.wheels[wd.wheelID]
            if type(row) == "table" then return row end
        end
        return nil
    end

    -- One-shot cache of stock BeamNG tyre/brake construction factors
    F.collectBaseWheelFactors = function(wd)
        local jb = F.getWheelJBeamData(wd) or {}
        local frictionCoef = tonumber(wd.frictionCoef) or tonumber(jb.frictionCoef) or 1.0
        local slidingFrictionCoef = tonumber(wd.slidingFrictionCoef) or tonumber(jb.slidingFrictionCoef) or frictionCoef
        local noLoadCoef = tonumber(wd.noLoadCoef) or tonumber(jb.noLoadCoef) or 1.0
        local fullLoadCoef = tonumber(wd.fullLoadCoef) or tonumber(jb.fullLoadCoef) or 1.0
        local loadSensSlope = tonumber(wd.loadSensitivitySlope) or tonumber(jb.loadSensitivitySlope) or 0.00015
        local dragCoef = tonumber(wd.dragCoef) or tonumber(jb.dragCoef) or 5.0
        local tireWidth = tonumber(wd.tireWidth) or tonumber(jb.tireWidth) or tonumber(wd.width) or 0.2
        local radius = tonumber(wd.radius) or tonumber(jb.radius) or 0.3
        local hubRadius = tonumber(wd.hubRadius) or tonumber(jb.hubRadius) or (radius * 0.65)

        -- Mass: prefer explicit tire/hub totals, else node weights × ray count estimate
        local rayCount = tonumber(wd.rayCount) or tonumber(jb.numRays) or 16
        local tireNodeW = tonumber(jb.nodeWeight) or tonumber(wd.nodeWeight)
        local hubNodeW = tonumber(jb.hubNodeWeight) or tonumber(wd.hubNodeWeight)
        local tireMass = tonumber(jb.tireWeight) or tonumber(wd.tireWeight)
        local hubMass = tonumber(jb.hubWeight) or tonumber(wd.hubWeight)
        if not tireMass and tireNodeW then tireMass = tireNodeW * max(8, rayCount) end
        if not hubMass and hubNodeW then hubMass = hubNodeW * max(8, rayCount) end
        tireMass = max(2.0, tireMass or 8.0)
        hubMass = max(2.0, hubMass or 6.0)

        -- Sidewall stiffness proxy → rolling resistance tendency (docs: higher spring → better RR / sharper peak)
        local sideSpring = tonumber(jb.tireSideBeamSpring) or tonumber(jb.hubSideBeamSpring) or tonumber(wd.tireSideBeamSpring) or 0
        local rrFromSidewall = 1.0
        if sideSpring > 0 then
            -- Normalize around a typical street sidewall (~2e5–6e5)
            rrFromSidewall = max(0.75, min(1.35, sideSpring / 400000))
        end

        local brakeMass = tonumber(wd.brakeMass) or tonumber(jb.brakeMass) or 8.0
        local brakeDiameter = tonumber(wd.brakeDiameter) or tonumber(jb.brakeDiameter) or 0.30
        local brakeVenting = tonumber(wd.brakeVentingCoef) or tonumber(jb.brakeVentingCoef) or 1.0
        local brakeCoolingArea = tonumber(wd.brakeCoolingArea)
        if not brakeCoolingArea then
            brakeCoolingArea = pi * brakeDiameter * brakeDiameter / 2 * 0.7
        end

        return {
            frictionCoef = frictionCoef,
            slidingFrictionCoef = slidingFrictionCoef,
            noLoadCoef = noLoadCoef,
            fullLoadCoef = fullLoadCoef,
            loadSensitivitySlope = loadSensSlope,
            dragCoef = dragCoef,
            tireMass = tireMass,
            hubMass = hubMass,
            tireWidth = tireWidth,
            radius = radius,
            hubRadius = hubRadius,
            rrFromSidewall = rrFromSidewall,
            brakeMass = max(1.0, brakeMass),
            brakeDiameter = max(0.15, brakeDiameter),
            brakeVentingCoef = max(0.2, brakeVenting),
            brakeCoolingArea = max(0.02, brakeCoolingArea),
            rotorMaterial = tostring(wd.rotorMaterial or jb.rotorMaterial or "steel"),
        }
    end
    F.getNativeBrakeTemps = function(wd, envTemp)
        envTemp = envTemp or getEnvTemp()
        local surface, core = envTemp, envTemp
        if wd then
            if type(wd.brakeSurfaceTemperature) == "number" then surface = wd.brakeSurfaceTemperature end
            if type(wd.brakeCoreTemperature) == "number" then core = wd.brakeCoreTemperature end
            local name = wd.name
            if electrics and electrics.values and type(electrics.values.wheelThermals) == "table" and name then
                local wt = electrics.values.wheelThermals[name]
                if type(wt) == "table" then
                    if type(wt.brakeSurfaceTemperature) == "number" then surface = wt.brakeSurfaceTemperature end
                    if type(wt.brakeCoreTemperature) == "number" then core = wt.brakeCoreTemperature end
                end
            end
            -- Legacy fallbacks
            if surface == envTemp and type(wd.brakeThermal) == "table" and type(wd.brakeThermal.brakeTemp) == "number" then
                surface = wd.brakeThermal.brakeTemp
                core = surface
            end
        end
        return surface, core
    end
    --[[
      Wheel suspension state in vehicle-local frame (+Z up).
      Compression > 0 when the hub rises into the arch (bump).
      Ride height adapts slowly while settled so spawn pose / settling does not fake bottom-out.
      Damper velocity is d(hubZ)/dt — not hub−COM world velocity (that mixes yaw/pitch/roll).
    ]]
    local susp = {  -- packed: frees 4 main-chunk locals
        velClamp = 10.0,
        softBumpM = 0.022,   -- start of bump stress (m of compression)
        hardBumpM = 0.065,   -- strong bottom-out region
        droopM = 0.035,      -- unloading / droop threshold
        rideAdapt = 0.55,    -- 1/s adaptive ride-height rate when settled
    }

    F.updateWheelSuspension = function(w, data, wd, dt, invQuat, upVector)
        w.suspensionVelocity = 0
        w.suspensionDeflection = 0
        w.suspCompression = 0
        w.suspStress = 0
        w.suspBump = 0
        w.suspDroop = 0

        if not wd or not wd.node1 then return end
        dt = max(1e-4, dt or 0.01)

        local pos1 = objCall("getNodePosition", wd.node1)
        if not pos1 then return end
        local hx, hy, hz = pos1.x, pos1.y, pos1.z
        if wd.node2 then
            local pos2 = objCall("getNodePosition", wd.node2)
            if pos2 then
                hx = (hx + pos2.x) * 0.5
                hy = (hy + pos2.y) * 0.5
                hz = (hz + pos2.z) * 0.5
            end
        end

        local hubLocalZ
        if invQuat and vec3 then
            hubLocalZ = (invQuat * vec3(hx, hy, hz)).z
        elseif upVector then
            -- Fallback: project hub offset onto vehicle up (node pos is vehicle-relative)
            hubLocalZ = hx * upVector.x + hy * upVector.y + hz * upVector.z
        else
            hubLocalZ = hz
        end

        local lastZ = w.suspHubZ
        w.suspHubZ = hubLocalZ

        -- Damper velocity from local hub Z derivative (stable vs body rotation)
        local suspVel = 0
        if lastZ ~= nil then
            suspVel = (hubLocalZ - lastZ) / dt
            if suspVel > susp.velClamp then suspVel = susp.velClamp
            elseif suspVel < -susp.velClamp then suspVel = -susp.velClamp end
        end
        -- Light smoothing
        local prevVel = w.suspensionVelocitySmoothed or suspVel
        suspVel = prevVel + (suspVel - prevVel) * min(1.0, dt * 25.0)
        w.suspensionVelocitySmoothed = suspVel
        w.suspensionVelocity = suspVel

        -- Adaptive ride height: only crawl toward hubZ when nearly settled and loaded
        local loadN = wd.downForce or 0
        local airborne = (not wd.contactMaterialID1 or wd.contactMaterialID1 == -1) or loadN <= 0
        local ride = data.rideHeightZ
        if ride == nil then
            ride = hubLocalZ
            data.rideHeightZ = ride
        elseif not airborne and abs(suspVel) < 0.12 and loadN > 200 then
            ride = ride + (hubLocalZ - ride) * min(1.0, dt * susp.rideAdapt)
            data.rideHeightZ = ride
        end

        -- +compression when hub rises above ride height (into the arch)
        local compression = hubLocalZ - ride
        w.suspCompression = compression
        w.suspensionDeflection = compression -- keep legacy field name (= bump positive)

        local bump = max(0, compression - susp.softBumpM)
        local droop = max(0, -compression - susp.droopM)
        w.suspBump = bump
        w.suspDroop = droop

        -- Stress: geometric bump + damper bump-stop (compression with downward body / upward wheel vel)
        -- suspVel > 0 ⇒ hub rising ⇒ bump stroke
        local bumpVel = max(0, suspVel)
        local hard = max(0, compression - susp.hardBumpM)
        local stress = bump * 12.0 + hard * 35.0 + bumpVel * bumpVel * 0.45
        -- Soft saturate so highway chatter cannot runaway
        stress = stress / (1.0 + stress * 0.35)
        w.suspStress = stress
    end

    -- Resolve native wheel object for setFrictionThermalSensitivity (index vs wheelID/cid).
    F.resolveWheelFrictionTarget = function(wheelIndex, wd)
        local candidates = { wheelIndex }
        if wd then
            if wd.wheelID ~= nil then candidates[#candidates + 1] = wd.wheelID end
            if wd.cid ~= nil then candidates[#candidates + 1] = wd.cid end
        end
        local seen = {}
        for ci = 1, #candidates do
            local idx = candidates[ci]
            if idx ~= nil and not seen[idx] then
                seen[idx] = true
                local wheel = objCall("getWheel", idx)
                if wheel and type(wheel.setFrictionThermalSensitivity) == "function" then
                    return wheel
                end
            end
        end
        if wd and type(wd.setFrictionThermalSensitivity) == "function" then
            return wd
        end
        return nil
    end

    -- Safe 8-arg friction API (BeamNG stage2 signature; ignore legacy 9th arg)
    F.applyWheelFriction = function(wheel, longGrip, latGrip)
        if isRemoteMpVehicle() then return end
        if not wheel or type(wheel.setFrictionThermalSensitivity) ~= "function" then return end
        local mid = (longGrip + latGrip) * 0.5
        -- Disable native thermal curve; grip comes from this mod
        wheel:setFrictionThermalSensitivity(-300, 1e7, 1e-10, 1e-10, 10, longGrip, mid, latGrip)
    end
    F.initTyreData = function()
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators then return end
        for k in pairs(tyreData) do tyreData[k] = nil end
        resetStintDistance() -- new stint / reload gate for Pitwall trip
        classifyCache.rallyDamper = nil -- re-probe on part reload / re-init
    
        -- Dynamically count active wheels to scale load-sensitivity curves for multi-axle trucks/duallys
        local count = 0
        for _ in pairs(wheels.wheelRotators) do
            count = count + 1
        end
        setWheelCount(count > 0 and count or 4)

        for i, wd in pairs(wheels.wheelRotators) do
            local wheelName = wd.name or "unknown"
            local tirePartName = getTirePartName(wheelName)
            local treadCoef, softnessCoef = wd.treadCoef or 0.5, wd.softnessCoef or 0.5
            local radius = wd.radius or 0.3
            local width = wd.tireWidth or wd.tyreWidth or wd.width or 0.2
            local hubRadius = wd.hubRadius or (radius * 0.65)
        
            -- Resolve and permanently cache the static profile configuration to save CPU cycles
            local initialMods = {}
            local p1, p2, factor, mods = getInterpolatedProfile(treadCoef, softnessCoef, tirePartName, initialMods, radius, width, hubRadius)
            local optTemp = mods and mods.optimalTemp or WORKING_TEMP
        
            -- Slicks: mild blanket preheat. Street: partial ambient→opt soak (sun/garage).
            -- Skin starts cooler than carcass so freestream doesn't fight a fully-soaked tread.
            local isRacingTire = string.find(p1 or "", "slick") or string.find(p2 or "", "slick")
            local preheatBlend = isRacingTire and SLICK_PREHEAT_BLEND or STREET_PREHEAT_BLEND
            local envNow = getEnvTemp()
            local carcassStart = lerp(envNow, optTemp, preheatBlend)
            local skinStart = lerp(envNow, optTemp, preheatBlend * SKIN_PREHEAT_FRAC)
            local wheelNameLower = string.lower(tostring(wheelName))
            local isFront = not not string.match(wheelNameLower, "^f")
            local coldPSI = max(1.0, wd.pressure or 25.0)
            -- Prefer live pressure-group fill when available (matches stock TPMS / cold set).
            -- If native is still pumped from a previous hop/write-back loop, restore the
            -- tuning-menu slider so a respawn/reload does not inherit 40 PSI Cold.
            do
                local nativeCold = getNativeGroupPressurePSI(wd)
                if nativeCold then coldPSI = max(1.0, nativeCold) end
                local sliderPSI = getTuneColdFillPSI(isFront)
                if sliderPSI and nativeCold and (nativeCold - sliderPSI) > 2.5 then
                    coldPSI = sliderPSI
                    setNativeGroupPressurePSI(wd, sliderPSI)
                end
            end
            local baseFactors = F.collectBaseWheelFactors(wd)

            tyreData[i] = {
                working_temp = optTemp,
                temp = { skinStart, skinStart, skinStart, carcassStart, carcassStart, carcassStart, carcassStart, carcassStart },
                spawnAge = 0, -- seconds since init; drives SPAWN_CONV_GRACE_S
                condition = 100,
                scalarTreadCondition = 100, -- A1 pure scalar life (rate curve + sc); never node-min'd
                scalarWearScale = 0.15,
                zoneCondition = { 100, 100, 100 }, -- Outer / Middle / Inner wear (per-zone)
                flatSpot = 0,
                nodeWearPeak = 0,
                nodeWearContact = 0,
                nodeContactCid = 0,
                nodeMuScale = 1,
                nodeSlideScale = 1,
                nodeMassScale = 1,
                nodeWearTouched = 0,
                nodeOmega = 0,
                nodeGate = "idle",
                nodeSpikeOn = 1,
                nodeWearRing = {},
                nodeWearRingContact = 0,
                nodeWearRingN = 0,
                nodeWearRingFlip = 0,
                clog = 0, graining = 0, blistering = 0,
                surfaceDamage = 0, -- Max of distinct damage modes (UI aggregate)
                heatCycles = 0, cycleHeated = false, coolTimer = 0,
                hotStintTime = 0, stintFade = 0,
                stintMaxAvgTemp = 0, -- Pitwall: peak EffectiveTyreTemp this stint (resets with initTyreData)
                leakRatePa = 0, punctureSeverity = 0,
                lastGrip = 1, lastLongGrip = 1, lastLatGrip = 1,
                lastLongGripRaw = 1, lastLatGripRaw = 1,
                lockFade = 0,
                coldPressurePSI = coldPSI,
                -- Per pressure-group: hot tgt seeded from native cold (spectrum opt = design).
                targetHotPressurePSI = seedHotTargetPSI(coldPSI, mods and mods.optimalPressure),
                luaPressurePSI = coldPSI,
                nativePressurePSI = coldPSI,
                lastNativePSI = coldPSI,
                contactDepthSmooth = 0,
                patchHeatScaleSmooth = nil,
                rideHeightZ = nil, -- adaptive suspension baseline (set on first settled sample)
                isFront = isFront,
                softnessRemap = remapSlickSoftness(softnessCoef),
                profile1 = p1,
                profile2 = p2,
                -- Cached lowers for CalcTyreWear / grip hot paths (profiles are static after init)
                profile1Lower = string.lower(tostring(p1 or "")),
                profile2Lower = string.lower(tostring(p2 or "")),
                interpFactor = factor,
                interpolatedMods = initialMods,
                baseFactors = baseFactors,
                lastDriveHeatGate = 0,
                lastDutyMods = ""
            }
        end
    end
    F.sampleContactSurfaceNormal = function(wd, pos1, pos2, upVector)
        local mm = rawget(_G, "mapmgr")
        if not mm or type(mm.surfaceNormalBelow) ~= "function" then return nil end
        local vehPos = objCall("getPosition")
        if not vehPos then return nil end

        local sx, sy, sz
        local nodeId = wd and wd.lastTreadContactNode
        if nodeId then
            local np = objCall("getNodePosition", nodeId)
            if np then
                sx, sy, sz = vehPos.x + np.x, vehPos.y + np.y, vehPos.z + np.z
            end
        end
        if sx == nil and pos1 and pos2 then
            -- Spindle midpoint when tread contact node is missing
            sx = vehPos.x + (pos1.x + pos2.x) * 0.5
            sy = vehPos.y + (pos1.y + pos2.y) * 0.5
            sz = vehPos.z + (pos1.z + pos2.z) * 0.5
        end
        if sx == nil then return nil end

        local sample = (vec3 and vec3(sx, sy, sz)) or { x = sx, y = sy, z = sz }
        local ok, normal = pcall(mm.surfaceNormalBelow, sample, 0.1)
        if not ok or not normal then return nil end
        local nx, ny, nz = normal.x, normal.y, normal.z
        if not nx or not ny or not nz then return nil end
        if nx ~= nx or ny ~= ny or nz ~= nz then return nil end
        local nlen = sqrt(nx * nx + ny * ny + nz * nz)
        if nlen < 0.5 then return nil end
        nx, ny, nz = nx / nlen, ny / nlen, nz / nlen
        -- mapmgr returns (0,0,1) when height probes miss; on a steep bank that reintroduces
        -- gravity-frame camber. Prefer vehicle-frame fallback instead.
        if upVector and abs(nz) > 0.998 and (upVector.z or 1) < 0.90 then
            return nil
        end
        return nx, ny, nz
    end

    -- Spindle camber/toe: ROAD-RELATIVE when loaded with a valid contact normal; otherwise
    -- VEHICLE frame via invQuat (same path as updateWheelSuspension).
    -- getNodePosition is an offset from the vehicle origin in world axes; using raw world-Z as
    -- "camber" treats bank angle as camber (NASCAR ovals: ~24–30° → grip collapse on asphalt).
    -- Road-relative (advancedwheeldebug-style surfaceNormalBelow) keeps setup camber on bank and
    -- picks up body-roll vs surface; vehicle-frame fallback covers airborne / missing normals.
    F.calculateWheelAlignment = function(i, wd, invQuat, upVector)
        if not wd or not wd.node1 or not wd.node2 then return 0, 0, 0, 0 end
        local pos1 = objCall("getNodePosition", wd.node1)
        local pos2 = objCall("getNodePosition", wd.node2)
        if not pos1 or not pos2 then return 0, 0, 0, 0 end
    
        local dx, dy, dz = pos1.x - pos2.x, pos1.y - pos2.y, pos1.z - pos2.z
        local dist = sqrt(dx*dx + dy*dy + dz*dz)
        if dist < 1e-5 then return 0, 0, 0, 0 end
    
        -- World-axis spindle (kept for road-normal camber before vehicle-frame transform)
        local wax, way, waz = dx / dist, dy / dist, dz / dist
        local lax, lay, laz = wax, way, waz

        -- Prefer road-relative camber while the tyre is loaded and a surface normal is available
        local camberFromRoad = false
        local camberRad, camberDeg
        local loadRaw = wd.downForce or 0
        local hasContact = wd.contactMaterialID1 ~= nil and wd.contactMaterialID1 ~= -1
        if hasContact and loadRaw > 0 then
            local nx, ny, nz = F.sampleContactSurfaceNormal(wd, pos1, pos2, upVector)
            if nx then
                local upDot = max(-0.999, min(0.999, wax * nx + way * ny + waz * nz))
                camberRad = -asin(upDot)
                camberDeg = deg(camberRad)
                camberFromRoad = true
            end
        end

        -- World-axis spindle → vehicle frame for toe (and camber fallback)
        if invQuat and vec3 then
            local axis = invQuat * vec3(lax, lay, laz)
            lax, lay, laz = axis.x, axis.y, axis.z
            local len = sqrt(lax * lax + lay * lay + laz * laz)
            if len > 1e-5 then
                lax, lay, laz = lax / len, lay / len, laz / len
            end
        elseif upVector then
            -- Camber only: spindle · vehicle-up (toe stays world-approx without a full basis)
            laz = max(-0.999, min(0.999, lax * upVector.x + lay * upVector.y + laz * upVector.z))
        end
    
        if not camberFromRoad then
            -- Camber: angle of spindle vs vehicle horizontal (Z-up in vehicle frame)
            camberRad = -asin(max(-0.999, min(0.999, laz)))
            camberDeg = deg(camberRad)
        end
    
        -- Toe: stay vehicle-frame (road-relative toe is noisy; grip path is camber-led)
        local sideSign = 1
        if invQuat and vec3 then
            local hub = invQuat * vec3(pos1.x, pos1.y, pos1.z)
            sideSign = hub.x > 0 and 1 or -1
        else
            sideSign = pos1.x > 0 and 1 or -1
        end
        local toeRad = atan2(lay * sideSign, abs(lax))
        local toeDeg = deg(toeRad)
    
        return camberDeg, toeDeg, camberRad, toeRad
    end
end

return M

