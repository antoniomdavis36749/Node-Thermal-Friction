-- lua/vehicle/extensions/tireWearThermalsPhysicsLoop.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- prepareWheelFrame + runFixedPhysicsSteps (100 Hz). Hud is stream-only.
local M = {}

local min, max, abs, sin, sqrt = math.min, math.max, math.abs, math.sin, math.sqrt
local atan2 = math.atan2

function M.install(F, deps)
    local getWheels = deps.getWheels or function() return deps.wheels end
    local wheelCache = deps.wheelCache
    local tyreData = deps.tyreData
    local tyreGripTable = deps.tyreGripTable
    local topo = deps.topo
    local objCall = deps.objCall
    local SPIKE_STRIP_MATERIAL_ID = deps.SPIKE_STRIP_MATERIAL_ID
    local NATIVE_SLIP_ENERGY_SCALE = deps.NATIVE_SLIP_ENERGY_SCALE
    local NATIVE_SLIP_VEL_SCALE = deps.NATIVE_SLIP_VEL_SCALE
    local FIXED_DT = deps.FIXED_DT
    local GRIP_STEP_INTERVAL = deps.GRIP_STEP_INTERVAL
    local getGfxAccumulator = deps.getGfxAccumulator
    local setGfxAccumulator = deps.setGfxAccumulator
    local getGripStepCounter = deps.getGripStepCounter
    local setGripStepCounter = deps.setGripStepCounter
    local setDrivenWheelCount = deps.setDrivenWheelCount
    local setDriveLayoutMode = deps.setDriveLayoutMode
    local TempCarcassToAvgTemp = deps.TempCarcassToAvgTemp
    local axleLoadSum, axleLoadCount = {}, {}

    -- Axles and front/rear from hub positions along the car's forward axis (not wheel names).
    -- Wheels closer than axleGroupGapM share an axle (duals, steered pairs). Single-axle
    -- vehicles keep the name-based isFront from init.
    local function resolveAxleGeometry(wheels)
        local fwd = objCall("getDirectionVector")
        if not fwd then return end
        local coords = {}
        for i, wd in pairs(wheels.wheelRotators) do
            local data = tyreData[i]
            local p1 = data and wd.node1 and objCall("getNodePosition", wd.node1)
            if p1 then
                local x, y, z = p1.x, p1.y, p1.z
                local p2 = wd.node2 and objCall("getNodePosition", wd.node2)
                if p2 then x, y, z = (x + p2.x) * 0.5, (y + p2.y) * 0.5, (z + p2.z) * 0.5 end
                coords[#coords + 1] = { i = i, c = x * fwd.x + y * fwd.y + z * fwd.z }
            end
        end
        if #coords > 0 then
            table.sort(coords, function(a, b) return a.c > b.c end)
            local gap = topo.axleGroupGapM or 0.35
            local axleId, lastC = 0, nil
            for k = 1, #coords do
                if not lastC or (lastC - coords[k].c) > gap then axleId = axleId + 1 end
                lastC = coords[k].c
                tyreData[coords[k].i].axleId = axleId
            end
            local front, rear = coords[1].c, coords[#coords].c
            if front - rear > 0.5 then
                local mid = (front + rear) * 0.5
                for k = 1, #coords do
                    tyreData[coords[k].i].isFront = coords[k].c > mid
                end
            end
        end
        -- 0 = no hub position: skipped by axle load sums, never re-probed this spawn.
        for i in pairs(wheels.wheelRotators) do
            if tyreData[i] and tyreData[i].axleId == nil then tyreData[i].axleId = 0 end
        end
    end

    F.prepareWheelFrame = function(dt, localizedEnvTemp, invQuat, upVector, airspeed)
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators then return end
        for i in pairs(wheels.wheelRotators) do
            if tyreData[i] and tyreData[i].axleId == nil then
                resolveAxleGeometry(wheels)
                break
            end
        end
        -- P1: count driven wheels + F/R layout for AWD / FWD Soft-like damp
        local nDriven = 0
        local nFrontDriven = 0
        local nRearDriven = 0
        local propThresh = topo.drivePropDrivenThreshNm or 40
        for iCount, wdCount in pairs(wheels.wheelRotators) do
            if abs(wdCount.propulsionTorque or 0) > propThresh then
                nDriven = nDriven + 1
                local isFront = tyreData[iCount] and tyreData[iCount].isFront
                if isFront == nil then
                    isFront = string.match(string.lower(tostring(wdCount.name or "")), "^f") and true or false
                end
                if isFront then
                    nFrontDriven = nFrontDriven + 1
                else
                    nRearDriven = nRearDriven + 1
                end
            end
        end
        local vehSpeed = F.getVehicleAirspeedRef and F.getVehicleAirspeedRef() or 0
        setDrivenWheelCount(nDriven)
        if nFrontDriven > 0 and nRearDriven > 0 then
            setDriveLayoutMode("awd")
        elseif nFrontDriven > 0 then
            setDriveLayoutMode("fwd")
        elseif nRearDriven > 0 then
            setDriveLayoutMode("rwd")
        else
            setDriveLayoutMode("coast")
        end

        for i, wd in pairs(wheels.wheelRotators) do
            if not wheelCache[i] then 
                wheelCache[i] = {
                    initialTempK = localizedEnvTemp + 273.15,
                    radius = wd.radius or 0.3
                } 
            end
            local w = wheelCache[i]
            local data = tyreData[i]
        
            if data then
                F.updateWheelSuspension(w, data, wd, dt, invQuat, upVector)

                local camberDeg, toeDeg, camberRad, toeRad, axX, axY, axZ, outSign = F.calculateWheelAlignment(i, wd, invQuat, upVector)
                if outSign then w.outSign = outSign end
                local outDir = w.outSign or 1
                w.camber = camberDeg
                -- Standard camber on both sides of the car: negative = top leaning in.
                w.camberStd = camberDeg * outDir
                w.toe = toeDeg
                w.camberRad = camberRad
                w.toeRad = toeRad
                w.airspeed = airspeed

                local groundModelName, gm = F.GetGroundModelData(wd.contactMaterialID1)
                w.groundModel = gm

                local loadRaw = wd.downForce or 0
                local airborneState = (not wd.contactMaterialID1 or wd.contactMaterialID1 == -1) or (loadRaw <= 0)
                w.loadRaw, w.isAirborne = loadRaw, airborneState

                -- This tire's own static load: settles while the car is slow, holds while driving.
                -- Until the first slow second it tracks load slowly so rolling spawns still get a value.
                if not airborneState and loadRaw > 50 then
                    local slow = vehSpeed < (topo.staticLoadMaxSpeed or 1.5)
                    local ref = data.staticLoadN
                    if not ref then
                        ref = loadRaw
                    elseif slow or not data.staticLoadSettled then
                        ref = ref + (loadRaw - ref) * min(1.0, dt / (slow and 0.5 or 2.0))
                    end
                    data.staticLoadN = ref
                    if slow then
                        data.staticLoadSlowT = (data.staticLoadSlowT or 0) + dt
                        if data.staticLoadSlowT >= 1.0 then data.staticLoadSettled = true end
                    end
                end

                -- This wheel's slip angle toward its own outer (+) or inner (-) shoulder, from hub velocity.
                local latTarget = 0
                local groundSpeed = vehSpeed
                if axX and not airborneState and wd.node1 and wd.node2 then
                    local v1 = objCall("getNodeVelocityVector", wd.node1)
                    local v2 = objCall("getNodeVelocityVector", wd.node2)
                    if v1 and v2 then
                        local vx, vy, vz = (v1.x + v2.x) * 0.5, (v1.y + v2.y) * 0.5, (v1.z + v2.z) * 0.5
                        local vAxis = (vx * axX + vy * axY + vz * axZ) * outDir
                        local vPlane = sqrt(max(0, vx * vx + vy * vy + vz * vz - vAxis * vAxis))
                        latTarget = max(-1, min(1, atan2(vAxis, max(3.0, vPlane)) / (topo.latSlipAngleRef or 0.10)))
                        groundSpeed = sqrt(vx * vx + vy * vy + vz * vz)
                    end
                end
                w.groundSpeed = groundSpeed
                -- Patch slip speed over ground speed; the 3 m/s floor keeps crawling from reading as a slide.
                w.slipRatio = abs(wd.lastSlip or 0) / max(3.0, groundSpeed)
                local latPrev = w.latSlipDir or 0
                w.latSlipDir = latPrev + (latTarget - latPrev) * min(1.0, dt / max(0.02, topo.latSlipEmaTau or 0.10))

                -- Ring 1 = outer shoulder, ring 3 = inner. Top-in camber loads the inner shoulder;
                -- sliding outward loads the outer one.
                w.combinedBias = (-w.camberStd * 0.12) - (topo.latSlipShoulderBias or 0.28) * w.latSlipDir
                w.contactMatId = wd.contactMaterialID1 or -1
                w.isBroken = wd.isBroken or false
                w.isTireDeflated = wd.isTireDeflated or false
                w.dynamicRadius = wd.dynamicRadius or wd.radius or w.radius
                w.peakForce = wd.peakForce or 0
                w.contactDepth = wd.contactDepth or 0
                w.downForceRaw = wd.downForceRaw or loadRaw

                -- Invalidate surface cache when material changes (resolveWheelSurface also keys on this)
                if w.surfCacheMatId ~= w.contactMatId then
                    w.surfaceType = nil
                end

                -- Immersion check (same path as stock brake underwater cooling)
                w.underWater = false
                if wd.node1 then
                    w.underWater = not not objCall("inWater", wd.node1)
                end

                -- Spike-strip (mat 32): native wheels.lua owns setGroupPressure while isPunctured.
                -- Node-Thermal Friction only mirrors UI/condition — do NOT arm leakRatePa for applyPressureLeakPa.
                w.isPunctured = wd.isPunctured and true or false
                local mat1, mat2 = wd.contactMaterialID1, wd.contactMaterialID2
                if (mat1 == SPIKE_STRIP_MATERIAL_ID or mat2 == SPIKE_STRIP_MATERIAL_ID or w.isPunctured)
                    and not w.isTireDeflated and not w.isBroken then
                    data.punctureSeverity = max(data.punctureSeverity or 0, 0.5)
                end
                -- Path A2: secondary contact GM for heat/wear blend (never spike — leak ownership stays native)
                w.groundModel2 = nil
                w.contactMatId2 = -1
                if mat2 and mat2 ~= -1 and mat2 ~= mat1
                    and mat1 ~= SPIKE_STRIP_MATERIAL_ID and mat2 ~= SPIKE_STRIP_MATERIAL_ID then
                    w.contactMatId2 = mat2
                    local _, gm2 = F.GetGroundModelData(mat2)
                    w.groundModel2 = gm2
                end

                local scrubSens = data.interpolatedMods and data.interpolatedMods.scrubSensitivity or 1.0
                local dynR = w.dynamicRadius or (wd.radius or 0.3)
                local surfaceSpeed = abs(wd.angularVelocity or 0) * dynR
                -- Toe scrub: soft-saturation v/(1+v/Vref) keeps effect proportional at low-mid speed
                -- and gently saturates above Vref rather than hard-capping. At v=Vref scrub is ~50%
                -- of linear extrapolation; real toe scrub saturates around highway speed.
                local toeScrubVref = topo.toeScrubVref or 70.0
                local toeScrubEnergy = (surfaceSpeed / (1.0 + surfaceSpeed / toeScrubVref)) * abs(sin(w.toeRad or 0)) * 0.025 * scrubSens

                -- Prefer BeamNG core slip energy (sounds.lua uses *5e-6); add explicit long/lat slip
                -- Fix A: high-|lastSlip| longComp boost so burnout/lock can smoke; cruise/corner stay flat.
                local gmStatic = gm.staticFrictionCoefficient or 1
                local nativeWork = (wd.slipEnergy or 0) * NATIVE_SLIP_ENERGY_SCALE
                local absLongSlip = abs(wd.lastSlip or 0)
                local longComp = absLongSlip * NATIVE_SLIP_VEL_SCALE * gmStatic
                local topoSlip = topo
                local boostStart = topoSlip.slipVelBoostStart or 8.0
                local boostFull = topoSlip.slipVelBoostFull or 24.0
                local boostMax = topoSlip.slipVelBoostMax or 9.0
                local boostSpan = max(1e-3, boostFull - boostStart)
                local boostRamp = max(0, min(1, (absLongSlip - boostStart) / boostSpan))
                boostRamp = boostRamp * boostRamp * (3.0 - 2.0 * boostRamp) -- smoothstep
                longComp = longComp * (1.0 + boostMax * boostRamp)
                local sideComp = abs(wd.lastSideSlip or 0) * NATIVE_SLIP_VEL_SCALE * gmStatic
                w.longSlipEnergy = longComp
                w.sideSlipEnergy = sideComp
                w.slipEnergy = max(nativeWork, longComp * 0.55 + sideComp * 0.45)
                -- Wear/lock still see toe scrub + soft-ground depth. Chassis g_mag does not scale this.
                -- Sliding heat uses smoothed wd.slipEnergy in the thermal step, not this signal.
                local dynamicSlipEnergy = w.slipEnergy + toeScrubEnergy
                -- Soft ground depth amplifies scrub/work slightly (paddling / ploughing)
                if (wd.contactDepth or 0) > 0.05 then
                    dynamicSlipEnergy = dynamicSlipEnergy * (1.0 + min(0.6, wd.contactDepth))
                end
                w.dynamicSlipEnergy = dynamicSlipEnergy
            end
        end

        -- Mean load of each axle: left/right split without the car's weight, aero or pitch.
        for k in pairs(axleLoadSum) do axleLoadSum[k], axleLoadCount[k] = nil, nil end
        for i in pairs(wheels.wheelRotators) do
            local data, w = tyreData[i], wheelCache[i]
            local id = data and data.axleId
            if w and id and id > 0 then
                axleLoadSum[id] = (axleLoadSum[id] or 0) + (w.loadRaw or 0)
                axleLoadCount[id] = (axleLoadCount[id] or 0) + 1
            end
        end
        for i in pairs(wheels.wheelRotators) do
            local data, w = tyreData[i], wheelCache[i]
            local id = data and data.axleId
            if w then
                local n = id and axleLoadCount[id] or 0
                w.axleLoadMean = (n >= 2) and (axleLoadSum[id] / n) or nil
            end
        end
    end

    F.runFixedPhysicsSteps = function(dt, localizedEnvTemp)
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators then return end
        local gfxAccumulator = getGfxAccumulator() + dt
        if gfxAccumulator > 0.15 then gfxAccumulator = 0.15 end

        while gfxAccumulator >= FIXED_DT do
            gfxAccumulator = gfxAccumulator - FIXED_DT
            local gripStepCounter = getGripStepCounter() + 1
            setGripStepCounter(gripStepCounter)
            local doGripStep = (gripStepCounter % GRIP_STEP_INTERVAL) == 0

            for i, wd in pairs(wheels.wheelRotators) do
                local w = wheelCache[i]
                local data = tyreData[i]
                if w and data then
                    -- Thermals / wear / pressure leak at 100Hz (do not gate on native wheel handle)
                    F.CalcTyreWear(i, FIXED_DT, localizedEnvTemp)

                    local carcassTemp = TempCarcassToAvgTemp(data.temp, w.combinedBias or 0, 1.0, localizedEnvTemp)
                    local isSlickFail = string.find(data.profile1Lower or "", "slick", 1, true)
                        or string.find(data.profile2Lower or "", "slick", 1, true)
                    local optFail = data.interpolatedMods and data.interpolatedMods.optimalTemp
                    local softFailTemp = isSlickFail and 195 or ((optFail and optFail >= 80) and 185 or 165)
                    if carcassTemp > softFailTemp and (data.leakRatePa or 0) < 5000 then
                        data.leakRatePa = max(data.leakRatePa or 0, 6000)
                    end
                    local cond = data.condition or 100
                    if cond < 0.5 and (data.punctureSeverity or 0) > 0.8 then
                        F.deflateTireCompat(i)
                    end

                    local wheel = F.resolveWheelFrictionTarget(i, wd)
                    if doGripStep then
                        local longGrip, latGrip, grip = F.CalculateTyreGrip(i, localizedEnvTemp)
                        if longGrip ~= longGrip or latGrip ~= latGrip or longGrip <= 0.001 or latGrip <= 0.001 then
                            -- Do not write ice μ; keep last good (spawn defaults to 1.0)
                            longGrip = data.lastLongGripRaw or data.lastLongGrip or 1.0
                            latGrip = data.lastLatGripRaw or data.lastLatGrip or 1.0
                            grip = data.lastGrip or 1.0
                        end
                        -- Raw (unfaded) — lock fade applied live below from ω/slip
                        data.lastLongGripRaw, data.lastLatGripRaw = longGrip, latGrip
                        data.lastGrip = grip
                        tyreGripTable[i] = grip
                    end

                    if wheel then
                        if w.isTireDeflated or w.isBroken then
                            F.applyWheelFriction(wheel, 1.0)
                        else
                            -- Raw thermal grip. Brake lock fade stays off; BeamNG owns lock.
                            local longGrip = data.lastLongGripRaw or data.lastLongGrip or 1.0
                            local latGrip = data.lastLatGripRaw or data.lastLatGrip or longGrip
                            local fade = 0
                            longGrip, latGrip, fade = F.applyBrakeLockFade(longGrip, latGrip, wd, w)
                            data.lastLongGrip, data.lastLatGrip = longGrip, latGrip
                            data.lockFade = fade or 0
                            -- BeamNG has one friction multiplier per wheel; long and lat each weight half.
                            F.applyWheelFriction(wheel, (longGrip + latGrip) * 0.5)
                        end
                    end
                end
            end
        end
        setGfxAccumulator(gfxAccumulator)
    end
end

return M
