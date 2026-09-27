-- lua/vehicle/extensions/tireWearThermalsHud.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- guiStream init/flush only. Physics loop lives in tireWearThermalsPhysicsLoop.lua.
local M = {}

function M.install(F, deps)
    local guiStream = deps.guiStream
    local wheelIndexMap = deps.wheelIndexMap
    local getWheels = deps.getWheels or function() return deps.wheels end
    local wheelCache = deps.wheelCache
    local tyreData = deps.tyreData
    local tyreGripTable = deps.tyreGripTable
    local nativeAero = deps.nativeAero
    local getEnvTemp = deps.getEnvTemp or function() return deps.ENV_TEMP end
    local WORKING_TEMP = deps.WORKING_TEMP
    local TEMP_NODE_COUNT = deps.TEMP_NODE_COUNT
    local SEND_INTERVAL = deps.SEND_INTERVAL
    local getWaterFilmDepth = deps.getWaterFilmDepth
    local DOESNT_EXIST_DATA = deps.DOESNT_EXIST_DATA
    local stampStreamIdentity = deps.stampStreamIdentity
    local nativeAeroWheelShare = deps.nativeAeroWheelShare
    local classifySurfaceGrip = deps.classifySurfaceGrip
    local ensureTempNodes = deps.ensureTempNodes
    local TempCarcassToAvgTemp = deps.TempCarcassToAvgTemp
    local EffectiveTyreTemp = deps.EffectiveTyreTemp
    local getNativeBrakeTemps = deps.getNativeBrakeTemps
    local getBrakeDuctPercent = deps.getBrakeDuctPercent
    local getFreestreamAirspeed = deps.getFreestreamAirspeed or function() return 0 end
    local getChassisDynamicsSnapshot = deps.getChassisDynamicsSnapshot or function()
        return { gLong = 0, gLat = 0, gMag = 0, yawRateDeg = 0 }
    end

    F.initGuiStream = function()
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators then return end
        local ENV_TEMP = getEnvTemp()
        guiStream.data = {}
        guiStream.envTemp = ENV_TEMP
        guiStream.trackTemp = ENV_TEMP
        guiStream.rainState = 0
        guiStream.waterFilm = 0
        guiStream.totalDownforceN = 0
        guiStream.aeroFracPct = 0
        guiStream.aeroDragN = 0
        guiStream.aeroFrontN = 0
        guiStream.aeroRearN = 0
        guiStream.aeroFrontPct = 0
        guiStream.aeroRearPct = 0
        guiStream.aeroCopPct = 0
        guiStream.aeroNative = 0
        guiStream.streamHz = math.floor(1.0 / SEND_INTERVAL + 0.5)
        guiStream.elevationM = 0
        guiStream.timeOfDay = 0
        guiStream.cloudCover = 0
        guiStream.packWake = 0
        guiStream.packAirDelta = 0
        guiStream.envTempRange = 0
        guiStream.stintKm = 0
        guiStream.verifyNote = ""
        guiStream.odoKm = 0
        guiStream.airspeedMps = 0
        guiStream.airspeedMph = 0
        guiStream.weightFrontPct = 0
        guiStream.weightRearPct = 0
        guiStream.weightLeftPct = 0
        guiStream.weightRightPct = 0
        guiStream.gLong = 0
        guiStream.gLat = 0
        guiStream.gMag = 0
        guiStream.yawRateDeg = 0
        stampStreamIdentity()
        for k in pairs(wheelIndexMap) do wheelIndexMap[k] = nil end
        local idx = 1
        for i, wd in pairs(wheels.wheelRotators) do
            guiStream.data[idx] = {
                name = tostring(wd.name or "unknown"),
                temp = { ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP },
                tempCategory = "Normal",
                working_temp = WORKING_TEMP, condition = 100, conditionScalar = 100, conditionNode = 100, conditionNodeLead = 0,
                zoneCondition = { 100, 100, 100 },
                tyreGrip = 1, longGrip = 1, latGrip = 1, wearPenalty = 1, camber = 0, camberStd = 0, toe = 0, pressure = 25,
                initialPressure = 25, optimalPressure = 25, coldPressure = 25, targetHotPressure = 25,
                luaPressure = 25, nativePressure = 25, pressureDelta = 0,
                pressureRatio = 1, skinCarcassGap = 0, driveHeatGate = 0, driveHeatGateCarcass = 0,
                streetSlipScale = 1, stintMaxAvgTemp = 0, avgTemp = ENV_TEMP,
                airCoolRate = 0, skinVelCoolScale = 1, workHeatG0 = 0.22,
                slipHeatRate = 0, workHeatRate = 0, trackCondMult = 1, staticCoolRate = 0,
                clog = 0, cycles = 0, graining = 0, blistering = 0, flatspot = 0,
                surfaceDamage = 0, stintFade = 0, leak = 0, waterFilm = 0, ductPercent = 1,
                ductAirCoolFactor = 1, ductSoakCondFactor = 1.15, brakeSoakRateCs = 0,
                carcassAvg = ENV_TEMP, rimTemp = ENV_TEMP, airTemp = ENV_TEMP,
                brakeSurface = ENV_TEMP, brakeCore = ENV_TEMP, brakeThermalEfficiency = 1,
                contactDepth = 0, underWater = false,
                -- Surface / contact diagnostics
                surfaceName = "unknown", surfaceType = "generic",
                muStatic = 1, muSlide = 1, rough = 0,
                loadN = 0, loadPct = 0, peakForce = 0, dynamicRadius = 0.3,
                wheelSpeedMps = 0, wheelSpeedMph = 0,
                slipEnergy = 0, longSlip = 0, sideSlip = 0,
                -- Suspension diagnostics
                suspCompressionMm = 0, suspVel = 0, suspStress = 0, suspBumpMm = 0, suspDroopMm = 0,
                airborne = false,
                profile = "standard", profile1 = "", profile2 = "", compoundClass = "standard",
                purpose = "street", classifyReason = "street_spectrum", dutyMods = "",
                nodeSpikeOn = 1, nodeGate = "idle", nodeContactCid = 0,
                nodeWearPeak = 0, nodeWearContact = 0, nodeWearTouched = 0, nodeOmega = 0,
                nodeMuScale = 1, nodeSlideScale = 1, nodeMassScale = 1,
                nodeWearRing = {}, nodeWearRingContact = 0, nodeWearRingN = 0, nodeWearRingFlip = 0,
                nodeLockEnergySrc = "off",
                nodeCamEnergySrc = "off",
                nodeCamFrac = 0,
                nodeCamColScale = 1,
                nodeCamArmDeg = 1,
                nodeColOn = 0, nodeColMapN = 0, nodeColHits = 0, nodeColSlipHits = 0,
                nodeColSlipF = 0, nodeColSlipV = 0, nodeColNormalF = 0, nodeColDepth = 0,
                nodeColEnergy = 0, nodeColPeakEnergy = 0,
                nodeColHoldHits = 0, nodeColHoldSlipHits = 0, nodeColHoldSlipF = 0, nodeColHoldSlipV = 0,
                nodeColHoldEnergy = 0, nodeColHoldWin = 0, nodeColHoldPeakE = 0,
                nodeColPeakCid = 0, nodeColWheelCid = 0, nodeColMatch = 0,
                isBroken = false, isDetached = false
            }
            wheelIndexMap[i] = idx
            idx = idx + 1
        end
    end

    -- Physics tick: no spindle force FX (arcade applyForce path removed)
    F.update = function(_dt)
    end

    F.flushGuiStream = function(localizedEnvTemp)
            local wheels = getWheels()
            if not wheels or not wheels.wheelRotators then return end
            local totalLoad = 0
            local frontLoad, rearLoad, leftLoad, rightLoad = 0, 0, 0, 0
            local airMps = tonumber(getFreestreamAirspeed()) or 0
            if airMps < 0 then airMps = 0 end
            guiStream.airspeedMps = math.floor(airMps * 100) / 100
            guiStream.airspeedMph = math.floor(airMps * 2.23693629 * 10) / 10
            do
                local dyn = getChassisDynamicsSnapshot() or {}
                guiStream.gLong = math.floor(((dyn.gLong or 0) * 100) + 0.5) / 100
                guiStream.gLat = math.floor(((dyn.gLat or 0) * 100) + 0.5) / 100
                guiStream.gMag = math.floor(((dyn.gMag or 0) * 100) + 0.5) / 100
                guiStream.yawRateDeg = math.floor(((dyn.yawRateDeg or 0) * 10) + 0.5) / 10
            end

            for i, wd in pairs(wheels.wheelRotators) do
                local w = wheelCache[i]
                local data = tyreData[i]
                local idx = wheelIndexMap[i]
                if w and data and idx and guiStream.data[idx] then
                    local entry = guiStream.data[idx]
                    local rawLoad = w.loadRaw or wd.downForce or 0
                    entry.aeroLoadN = math.floor(nativeAeroWheelShare(wd.name, rawLoad))
                    local interpolatedMods = data.interpolatedMods
                    local initialPressurePSI = wd.pressure or 25
                    local cond = data.condition or 100
                    local grip = data.lastGrip or tyreGripTable[i] or 1
                    local longGrip = data.lastLongGrip or grip
                    local latGrip = data.lastLatGrip or grip
                    local carcassTemp = TempCarcassToAvgTemp(data.temp, w.combinedBias or 0, 1.0, localizedEnvTemp)

                    entry.isBroken = w.isBroken
                    entry.isDetached = w.isBroken
                    entry.condition = (w.isBroken) and -1 or cond
                    entry.conditionScalar = (w.isBroken) and -1 or (data.conditionScalar or cond)
                    entry.conditionNode = (w.isBroken) and -1 or (data.conditionNode or cond)
                    entry.conditionNodeLead = (w.isBroken) and -1 or (data.conditionNodeLead or 0)
                    if not entry.zoneCondition then entry.zoneCondition = { cond, cond, cond } end
                    local zc = data.zoneCondition or entry.zoneCondition
                    entry.zoneCondition[1], entry.zoneCondition[2], entry.zoneCondition[3] = zc[1] or cond, zc[2] or cond, zc[3] or cond
                    entry.tyreGrip = (w.isBroken) and 0 or grip
                    entry.longGrip = (w.isBroken) and 0 or longGrip
                    entry.latGrip = (w.isBroken) and 0 or latGrip
                    entry.wearPenalty = (w.isBroken) and 0 or (data.lastWearPenalty or 1)
                    entry.lockFade = (w.isBroken) and 0 or (data.lockFade or 0)
                    entry.nodeSpikeOn = (data.nodeSpikeOn and data.nodeSpikeOn ~= 0) and 1 or 0
                    entry.nodeGate = data.nodeGate or "idle"
                    entry.nodeContactCid = data.nodeContactCid or 0
                    entry.nodeWearPeak = (w.isBroken) and 0 or (data.nodeWearPeak or 0)
                    entry.nodeWearContact = (w.isBroken) and 0 or (data.nodeWearContact or 0)
                    entry.nodeMuScale = (w.isBroken) and 1 or (data.nodeMuScale or 1)
                    entry.nodeSlideScale = (w.isBroken) and 1 or (data.nodeSlideScale or 1)
                    entry.nodeMassScale = (w.isBroken) and 1 or (data.nodeMassScale or 1)
                    entry.nodeWearTouched = data.nodeWearTouched or 0
                    entry.nodeOmega = data.nodeOmega or 0
                    entry.nodeLockEnergySrc = data.nodeLockEnergySrc or "idle"
                    entry.nodeCamEnergySrc = data.nodeCamEnergySrc or "idle"
                    entry.nodeCamFrac = math.floor(((data.nodeCamFrac or 0) * 100) + 0.5) / 100
                    entry.nodeCamColScale = math.floor(((data.nodeCamColScale or 1) * 100) + 0.5) / 100
                    entry.nodeCamArmDeg = math.floor(((data.nodeCamArmDeg or 1) * 10) + 0.5) / 10
                    do
                        local srcRing = data.nodeWearRing
                        local dstRing = entry.nodeWearRing
                        if type(dstRing) ~= "table" then
                            dstRing = {}
                            entry.nodeWearRing = dstRing
                        else
                            for k in pairs(dstRing) do dstRing[k] = nil end
                        end
                        if type(srcRing) == "table" then
                            for k, v in pairs(srcRing) do dstRing[k] = v end
                        end
                        entry.nodeWearRingContact = data.nodeWearRingContact or 0
                        entry.nodeWearRingN = data.nodeWearRingN or 0
                        entry.nodeWearRingFlip = data.nodeWearRingFlip or 0
                    end
                    entry.nodeColOn = (data.nodeColOn and data.nodeColOn ~= 0) and 1 or 0
                    entry.nodeColMapN = data.nodeColMapN or 0
                    entry.nodeColHits = data.nodeColHits or 0
                    entry.nodeColSlipHits = data.nodeColSlipHits or 0
                    entry.nodeColSlipF = math.floor((data.nodeColSlipF or 0) * 10) / 10
                    entry.nodeColSlipV = math.floor((data.nodeColSlipV or 0) * 1000) / 1000
                    entry.nodeColNormalF = math.floor(data.nodeColNormalF or 0)
                    entry.nodeColDepth = math.floor((data.nodeColDepth or 0) * 1000) / 1000
                    entry.nodeColEnergy = math.floor((data.nodeColEnergy or 0) * 10) / 10
                    entry.nodeColPeakEnergy = math.floor((data.nodeColPeakEnergy or 0) * 10) / 10
                    entry.nodeColHoldHits = data.nodeColHoldHits or 0
                    entry.nodeColHoldSlipHits = data.nodeColHoldSlipHits or 0
                    entry.nodeColHoldSlipF = math.floor((data.nodeColHoldSlipF or 0) * 10) / 10
                    entry.nodeColHoldSlipV = math.floor((data.nodeColHoldSlipV or 0) * 1000) / 1000
                    entry.nodeColHoldEnergy = math.floor((data.nodeColHoldEnergy or 0) * 10) / 10
                    entry.nodeColHoldWin = math.floor((data.nodeColHoldWin or 0) * 10) / 10
                    entry.nodeColHoldPeakE = math.floor((data.nodeColHoldPeakE or 0) * 10) / 10
                    entry.nodeColPeakCid = data.nodeColPeakCid or 0
                    entry.nodeColWheelCid = data.nodeColWheelCid or 0
                    entry.nodeColMatch = (data.nodeColMatch and data.nodeColMatch ~= 0) and 1 or 0
                    entry.camber = (w.isBroken) and 0 or ((w.camber or 0) * (wd.wheelDir or 1))
                    entry.camberStd = (w.isBroken) and 0 or (math.floor((w.camberStd or w.camber or 0) * 100) / 100)
                    entry.toe = (w.isBroken) and 0 or math.floor((w.toe or 0) * 100) / 100
                    entry.pressure = (w.isBroken or w.isTireDeflated) and 0 or (math.floor((data.currentPressurePSI or initialPressurePSI) * 10) / 10)
                    entry.luaPressure = (w.isBroken or w.isTireDeflated) and 0 or (math.floor((data.luaPressurePSI or data.currentPressurePSI or initialPressurePSI) * 10) / 10)
                    entry.nativePressure = (w.isBroken or w.isTireDeflated) and 0 or (math.floor((data.nativePressurePSI or data.currentPressurePSI or initialPressurePSI) * 10) / 10)
                    entry.pressureDelta = (w.isBroken or w.isTireDeflated) and 0 or (math.floor(((data.pressurePsiDelta or ((data.luaPressurePSI or 0) - (data.nativePressurePSI or 0))) * 10) + 0.5) / 10)
                    entry.initialPressure = data.coldPressurePSI or initialPressurePSI
                    entry.coldPressure = data.coldPressurePSI or initialPressurePSI
                    entry.optimalPressure = interpolatedMods and interpolatedMods.optimalPressure or 25
                    entry.targetHotPressure = data.targetHotPressurePSI or entry.optimalPressure
                    entry.flatspot = (w.isBroken) and 0 or math.floor((data.currentFlatSpot or 0) * 100)
                    entry.profile = (w.isBroken) and "none" or (interpolatedMods and interpolatedMods.descriptor or (((data.interpFactor or 0) > 0.5) and data.profile2 or data.profile1))
                    entry.profile1 = data.profile1 or ""
                    entry.profile2 = data.profile2 or ""
                    entry.compoundClass = interpolatedMods and interpolatedMods.descriptor or entry.profile
                    entry.purpose = (w.isBroken) and "none" or (interpolatedMods and interpolatedMods.purpose or "street")
                    entry.classifyReason = (w.isBroken) and "none" or (interpolatedMods and interpolatedMods.classifyReason or "street_spectrum")
                    entry.dutyMods = (w.isBroken) and "" or (data.lastDutyMods or "")
                    entry.cycles = data.heatCycles or 0
                    entry.stintFade = math.floor((data.stintFade or 0) * 1000) / 10
                    entry.leak = math.floor((data.punctureSeverity or 0) * 100)
                    entry.waterFilm = math.floor(getWaterFilmDepth() * 100)
                    entry.ductPercent = data.ductPercent or getBrakeDuctPercent(data.isFront)
                    entry.ductAirCoolFactor = math.floor((data.ductAirCoolFactor or 1) * 1000) / 1000
                    entry.ductSoakCondFactor = math.floor((data.ductSoakCondFactor or 1.15) * 1000) / 1000
                    entry.brakeSoakRateCs = math.floor((data.brakeSoakRateCs or 0) * 100) / 100
                    entry.driveHeatGate = math.floor((data.lastDriveHeatGate or 0) * 1000) / 1000
                    entry.driveHeatGateCarcass = math.floor((data.lastDriveHeatGateCarcass or 0) * 1000) / 1000
                    entry.streetSlipScale = math.floor((data.lastStreetSlipHeatScale or 1) * 1000) / 1000
                    entry.patchFrac = math.floor((data.lastPatchFrac or 0) * 1000) / 1000
                    entry.patchHeatScale = math.floor((data.lastPatchHeatScale or 1) * 1000) / 1000
                    entry.depthHeatBoost = math.floor((data.lastDepthHeatBoost or 1) * 1000) / 1000
                    entry.hertzArea = math.floor((data.lastHertzArea or 0) * 100000) / 100000
                    entry.deflArea = math.floor((data.lastDeflArea or 0) * 100000) / 100000
                    entry.depthBlend = math.floor((data.lastDepthBlend or 0) * 1000) / 1000
                    entry.utilNudge = math.floor((data.lastUtilNudge or 1) * 1000) / 1000
                    entry.dualContactBlend = math.floor((data.lastDualContactBlend or 0) * 1000) / 1000
                    entry.airCoolRate = math.floor((data.lastAirCoolProfile or 0) * 10000) / 10000
                    entry.skinVelCoolScale = math.floor((data.lastSkinVelCoolScale or 1) * 1000) / 1000
                    entry.workHeatG0 = math.floor((data.lastWorkHeatG0 or 0.22) * 1000) / 1000
                    entry.slipHeatRate = math.floor((data.lastSlipHeatProfile or 0) * 100) / 100
                    entry.workHeatRate = math.floor((data.lastWorkHeatProfile or 0) * 100) / 100
                    entry.trackCondMult = math.floor((data.lastTrackCondMult or 1) * 1000) / 1000
                    entry.staticCoolRate = math.floor((data.lastStaticCoolProfile or 0) * 10000) / 10000

                    entry.clog = (w.isBroken) and 0 or math.floor((data.currentClog or data.clog or 0) * 100)
                    entry.graining = (w.isBroken) and 0 or math.floor((data.currentGraining or data.graining or 0) * 100)
                    entry.blistering = (w.isBroken) and 0 or math.floor((data.currentBlistering or data.blistering or 0) * 100)
                    entry.surfaceDamage = (w.isBroken) and 0 or math.floor((data.currentSurfaceDamage or 0) * 100)

                    local gm = w.groundModel or DOESNT_EXIST_DATA
                    entry.surfaceName = gm.name or "unknown"
                    entry.surfaceType = w.surfaceType or classifySurfaceGrip(gm.nameLower or gm.name or "")
                    entry.muStatic = math.floor((gm.staticFrictionCoefficient or 1) * 1000) / 1000
                    entry.muSlide = math.floor((gm.slidingFrictionCoefficient or entry.muStatic) * 1000) / 1000
                    entry.rough = math.floor((tonumber(gm.rough) or 0) * 1000) / 1000
                    entry.loadN = math.floor(w.loadRaw or wd.downForce or 0)
                    entry.peakForce = math.floor(w.peakForce or 0)
                    entry.dynamicRadius = math.floor(((w.dynamicRadius or wd.radius or 0.3) * 1000) + 0.5) / 1000
                    do
                        local dynR = w.dynamicRadius or wd.radius or 0.3
                        local spd = math.abs(wd.angularVelocity or 0) * dynR
                        entry.wheelSpeedMps = math.floor(spd * 100) / 100
                        entry.wheelSpeedMph = math.floor(spd * 2.23693629 * 10) / 10
                    end
                    entry.loadPct = 0
                    do
                        local loadN = entry.loadN or 0
                        if loadN > 0 then
                            totalLoad = totalLoad + loadN
                            -- Token after last underscore (FL / wheel_FL) so "wheel" does not fake left.
                            local n = string.lower(tostring(wd.name or entry.name or ""))
                            local token = string.match(n, "([^_]+)$") or n
                            local isFront = data.isFront
                            if isFront == nil then isFront = not not string.match(token, "^f") end
                            if isFront then frontLoad = frontLoad + loadN else rearLoad = rearLoad + loadN end
                            if string.find(token, "l", 1, true) then
                                leftLoad = leftLoad + loadN
                            else
                                rightLoad = rightLoad + loadN
                            end
                        end
                    end
                    entry.slipEnergy = math.floor((w.dynamicSlipEnergy or w.slipEnergy or 0) * 1000) / 1000
                    entry.longSlip = math.floor((w.longSlipEnergy or 0) * 1000) / 1000
                    entry.sideSlip = math.floor((w.sideSlipEnergy or 0) * 1000) / 1000
                    entry.airborne = not not w.isAirborne

                    entry.suspCompressionMm = math.floor((w.suspCompression or 0) * 1000)
                    entry.suspVel = math.floor((w.suspensionVelocity or 0) * 1000) / 1000
                    entry.suspStress = math.floor((w.suspStress or 0) * 1000) / 1000
                    entry.suspBumpMm = math.floor((w.suspBump or 0) * 1000)
                    entry.suspDroopMm = math.floor((w.suspDroop or 0) * 1000)

                    if not entry.temp then entry.temp = { 0, 0, 0, 0, 0, 0, 0, 0 } end
                    if data.temp and not w.isBroken then
                        data.temp = ensureTempNodes(data.temp, localizedEnvTemp)
                        for ti = 1, TEMP_NODE_COUNT do
                            entry.temp[ti] = math.floor((data.temp[ti] or localizedEnvTemp) * 10) / 10
                        end
                        entry.carcassAvg = math.floor(carcassTemp * 10) / 10
                        entry.rimTemp = math.floor((data.temp[7] or localizedEnvTemp) * 10) / 10
                        entry.airTemp = math.floor((data.temp[8] or localizedEnvTemp) * 10) / 10
                        local bSurf, bCore = getNativeBrakeTemps(wd, localizedEnvTemp)
                        entry.brakeSurface = math.floor(bSurf * 10) / 10
                        entry.brakeCore = math.floor(bCore * 10) / 10
                        entry.brakeThermalEfficiency = math.floor((data.brakeThermalEfficiency or 1) * 1000) / 1000
                        entry.contactDepth = math.floor((data.contactDepthSmooth or w.contactDepth or 0) * 1000) / 1000
                        entry.underWater = not not w.underWater
                        entry.working_temp = math.floor((data.working_temp or WORKING_TEMP) * 10) / 10
                    else
                        for ti = 1, TEMP_NODE_COUNT do
                            entry.temp[ti] = localizedEnvTemp
                        end
                        entry.carcassAvg, entry.rimTemp, entry.airTemp = localizedEnvTemp, localizedEnvTemp, localizedEnvTemp
                        entry.brakeSurface, entry.brakeCore = localizedEnvTemp, localizedEnvTemp
                        entry.brakeThermalEfficiency = 1
                        entry.brakeSoakRateCs = 0
                        entry.ductAirCoolFactor = 1
                        entry.ductSoakCondFactor = 1.15
                        entry.dutyMods = ""
                        entry.contactDepth, entry.underWater = 0, false
                        entry.patchFrac, entry.patchHeatScale, entry.depthHeatBoost = 0, 1, 1
                        entry.hertzArea, entry.deflArea, entry.depthBlend = 0, 0, 0
                        entry.working_temp = WORKING_TEMP
                    end

                    local hotTgt = math.max(1.0, entry.targetHotPressure or entry.optimalPressure or 25)
                    local avgT = EffectiveTyreTemp(data.temp, w.combinedBias or 0, (entry.pressure or 0) / hotTgt, localizedEnvTemp, interpolatedMods)
                    -- Effective window: same softness/compliance scale as getProfileThermalGrip.
                    -- interpolatedMods is already the blended compound (not a street default).
                    local softness = wd.softnessCoef or 0.5
                    local compliance = (interpolatedMods and interpolatedMods.casingCompliance) or 0.5
                    local opt, plateau, coldW, hotW = F.thermalGripWindow(interpolatedMods, compliance, softness)
                    entry.optimalTemp = math.floor(opt * 10 + 0.5) / 10
                    entry.tempPlateau = math.floor(plateau * 10 + 0.5) / 10
                    entry.coldWidth = math.floor(coldW * 10 + 0.5) / 10
                    entry.hotWidth = math.floor(hotW * 10 + 0.5) / 10
                    entry.gripMultiplier = math.floor(((interpolatedMods and interpolatedMods.gripMultiplier) or 1) * 1000 + 0.5) / 1000
                    local therm = F.getProfileThermalGrip(interpolatedMods, avgT, compliance, softness)
                    entry.thermalGrip = math.floor((therm or 0) * 1000 + 0.5) / 1000
                    if avgT < (entry.optimalTemp - entry.tempPlateau) then
                        entry.tempCategory = "Cold"
                    elseif avgT > (entry.optimalTemp + entry.tempPlateau) then
                        entry.tempCategory = "Hot"
                    else
                        entry.tempCategory = "Normal"
                    end
                    entry.avgTemp = math.floor(avgT * 10) / 10
                    -- Stint peak avg (same EffectiveTyreTemp as live avg); resets on vehicle reload / initTyreData
                    if not w.isBroken and avgT > (data.stintMaxAvgTemp or 0) then
                        data.stintMaxAvgTemp = avgT
                    end
                    entry.stintMaxAvgTemp = math.floor((data.stintMaxAvgTemp or 0) * 10) / 10
                    entry.pressureRatio = math.floor((entry.pressure / hotTgt) * 1000) / 1000
                    local skinAvg = ((entry.temp[1] or 0) + (entry.temp[2] or 0) + (entry.temp[3] or 0)) / 3.0
                    entry.skinCarcassGap = math.floor((skinAvg - (entry.carcassAvg or skinAvg)) * 10) / 10
                end
            end

            -- Native triangle aero (aeroDebug APIs). Heat uses full wd.downForce (scale 1.0).
            guiStream.totalDownforceN = math.floor(nativeAero.liftN)
            guiStream.aeroDragN = math.floor(nativeAero.dragN)
            guiStream.aeroFrontN = math.floor(nativeAero.frontN)
            guiStream.aeroRearN = math.floor(nativeAero.rearN)
            guiStream.aeroFrontPct = math.floor(nativeAero.frontPct * 10) / 10
            guiStream.aeroRearPct = math.floor(nativeAero.rearPct * 10) / 10
            guiStream.aeroCopPct = math.floor(nativeAero.copPct * 10) / 10
            guiStream.aeroFracPct = math.floor(nativeAero.fracPct * 10) / 10
            guiStream.aeroNative = nativeAero.ok and 1 or 0

            if totalLoad > 1 then
                guiStream.weightFrontPct = math.floor((frontLoad / totalLoad) * 1000) / 10
                guiStream.weightRearPct = math.floor((rearLoad / totalLoad) * 1000) / 10
                guiStream.weightLeftPct = math.floor((leftLoad / totalLoad) * 1000) / 10
                guiStream.weightRightPct = math.floor((rightLoad / totalLoad) * 1000) / 10
                for _, entry in ipairs(guiStream.data) do
                    if entry and (entry.loadN or 0) > 0 then
                        entry.loadPct = math.floor(((entry.loadN or 0) / totalLoad) * 1000) / 10
                    else
                        entry.loadPct = 0
                    end
                end
            else
                guiStream.weightFrontPct, guiStream.weightRearPct = 0, 0
                guiStream.weightLeftPct, guiStream.weightRightPct = 0, 0
            end

    end

    -- Player Classic/Crew payload. Pitwall keeps the full guiStream.
    local PLAYER_WHEEL_KEYS = {
        "name", "profile", "tempCategory", "condition", "conditionScalar", "conditionNode",
        "nodeWearPeak", "tyreGrip", "pressure", "targetHotPressure", "optimalPressure",
        "avgTemp", "working_temp", "rimTemp", "stintFade", "graining", "blistering",
        "camber", "initialPressure", "surfaceDamage",
    }
    local playerStream = { data = {}, playerLean = 1 }

    F.syncPlayerHudStream = function()
        playerStream.vehId = guiStream.vehId
        playerStream.resetGen = guiStream.resetGen
        playerStream.mpRemote = guiStream.mpRemote
        playerStream.streamTag = guiStream.streamTag
        local src = guiStream.data or {}
        local dst = playerStream.data
        for i = 1, #src do
            local s = src[i]
            local d = dst[i]
            if not d then
                d = { temp = { 0, 0, 0, 0, 0, 0, 0, 0 }, zoneCondition = { 100, 100, 100 } }
                dst[i] = d
            end
            if s then
                for k = 1, #PLAYER_WHEEL_KEYS do
                    local key = PLAYER_WHEEL_KEYS[k]
                    d[key] = s[key]
                end
                local st, dt = s.temp, d.temp
                if st and dt then
                    for ti = 1, 8 do dt[ti] = st[ti] end
                end
                local sz, dz = s.zoneCondition, d.zoneCondition
                if sz and dz then
                    dz[1], dz[2], dz[3] = sz[1], sz[2], sz[3]
                end
            end
        end
        for i = #src + 1, #dst do dst[i] = nil end
        return playerStream
    end
end

return M
