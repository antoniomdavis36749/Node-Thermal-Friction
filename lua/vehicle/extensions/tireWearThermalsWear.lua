-- lua/vehicle/extensions/tireWearThermalsWear.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local min, max, abs, sqrt, pi = math.min, math.max, math.abs, math.sqrt, math.pi

function M.install(F, deps)
    local ctw = deps.ctw
    local topo = deps.topo
    local DEFAULT_MODS = deps.DEFAULT_MODS
    local getEnvTemp = deps.getEnvTemp or function() return deps.ENV_TEMP end
    local WORKING_TEMP = deps.WORKING_TEMP
    local TORQUE_ENERGY_MULTIPLIER = deps.TORQUE_ENERGY_MULTIPLIER
    local lerp = deps.lerp
    local tempDistToWearMult = deps.tempDistToWearMult
    local applyPressureLeakPa = deps.applyPressureLeakPa
    local deflateTireCompat = deps.deflateTireCompat
    local getNativeGroupPressurePSI = deps.getNativeGroupPressurePSI
    local isTirePressureInflateActive = deps.isTirePressureInflateActive
    local applyHotPressureWriteback = deps.applyHotPressureWriteback
    local MISSING = deps.missing
    local getVehicleMass = deps.getVehicleMass
    local getWheelCount = deps.getWheelCount

    -- Reload bridged thermals from ctw (prepare step writes these each wheel tick).
    F.ctwIntegrateWearDamage = function(wheelID, dt, localEnvTemp, wd, w, data, mods)
        local avgWeightedTemp = ctw.avgWeightedTemp or localEnvTemp or getEnvTemp()
        local current_optimal_temp = ctw.current_optimal_temp or WORKING_TEMP
        local current_working_temp = ctw.current_working_temp or WORKING_TEMP
        local tempDistWeighted = ctw.tempDistWeighted or 1
        local isAirborne = ctw.isAirborne
        local loadRaw = ctw.loadRaw or 0
        local slipEnergy = ctw.slipEnergy or 0
        local sideSlipEnergy = ctw.sideSlipEnergy or 0
        local g_mag = ctw.g_mag or 0
        local tyreWidthCoeff = ctw.tyreWidthCoeff or 1
        local propulsionTorque = ctw.propulsionTorque or 0
        local brakeTorque = ctw.brakeTorque or 0
        local angularVel = ctw.angularVel or 0
        local wearRate = ctw.wearRate
        local coldWearMult = ctw.coldWearMult
        local hotWearMult = ctw.hotWearMult
        local bottomOutSens = ctw.bottomOutSens
        local wLeft = ctw.wLeft or (1 / 3)
        local wCenter = ctw.wCenter or (1 / 3)
        local wRight = ctw.wRight or (1 / 3)
        local casing_compliance = ctw.casing_compliance
        local contactDepth = ctw.contactDepth or 0
        local rawJBeamTread = ctw.rawJBeamTread or 0.5
        local gmName = ctw.gmName or ""
        local treadCoef = ctw.treadCoef or 0.5
        local grainTempRatio = ctw.grainTempRatio or 0.75
        local blisterTempRatio = ctw.blisterTempRatio or 1.55
        local tyreWidth = ctw.tyreWidth or 0.2
        local isRaining = ctw.isRaining
        local isWetSurface = ctw.isWetSurface
        local isDryPaved = ctw.isDryPaved
        local isLooseSurface = ctw.isLooseSurface
        local isMudSurface = ctw.isMudSurface
        local isSnowSurface = ctw.isSnowSurface
        local isSandSurface = ctw.isSandSurface
        local isGravelSurface = ctw.isGravelSurface
        local isDirtGrassSurface = ctw.isDirtGrassSurface
        local isIceSurface = ctw.isIceSurface
        local vehNotParked = ctw.vehNotParked or 0
        local sf = ctw.sf or {}
        local groundModel = ctw.groundModel or MISSING
        local vehicleMass = getVehicleMass()
        local wheelCount = getWheelCount()

        -- HEAT CYCLES: compound hardens (more wear, less grip) — not reduced wear
        if not data.cycleHeated and avgWeightedTemp >= current_optimal_temp * 0.85 then
                data.cycleHeated = true
                data.coolTimer = 0
        elseif data.cycleHeated and avgWeightedTemp < (localEnvTemp + 15) then
                data.coolTimer = (data.coolTimer or 0) + dt
                if data.coolTimer > 45 then
                    data.heatCycles = min(10, (data.heatCycles or 0) + 1)
                    data.cycleHeated = false
                    data.coolTimer = 0
                end
        else
                data.coolTimer = 0
        end

        -- Stint fade: time spent near/above optimal window (stintFadeRate scales kinetics)
        local stintFadeRate = mods.stintFadeRate or DEFAULT_MODS.stintFadeRate or 1.0
        if avgWeightedTemp >= current_optimal_temp * 0.90 then
                data.hotStintTime = (data.hotStintTime or 0) + dt * stintFadeRate
        elseif avgWeightedTemp < current_optimal_temp * 0.70 then
                data.hotStintTime = max(0, (data.hotStintTime or 0) - dt * 0.15)
        end
        -- ~0–12% grip loss over a long hot stint (~20 min at peak @ rate 1.0)
        data.stintFade = min(0.12, (data.hotStintTime or 0) / 10000)

        -- Heat-cycle wear gain folded into stintFadeRate (compound stint character)
        local cycleWearMultiplier = 1.0 + (data.heatCycles or 0) * (0.06 * stintFadeRate)
    
        local wear = 0
        local zoneWearDelta = { 0, 0, 0 }
        -- Soft scalar tread (Friction coherence A1): ages HUD Cond/zones via min(scalar, node);
        -- does NOT feed grip wearPenalty while node spike on. Leak/puncture may still use Cond.
        -- Base ×0.15 LOCKED (Sport Belasco clean ~22 km FR ~0.9%). Mild life curve around that
        -- center: slower when fresh, faster late — Cond/leak clocks only (no μ).
        local ENABLE_SCALAR_TREAD_WEAR = true
        local ENABLE_SCALAR_RATE_CURVE = true
        local SCALAR_TREAD_WEAR_SCALE = 0.15 -- mid-life center (LOCKED Sport band reference)
        local SCALAR_SCALE_EARLY = 0.12 -- fresh (lifeUsed→0)
        local SCALAR_SCALE_LATE = 0.22 -- late life ceiling
        local SCALAR_LIFE_EARLY_END = 0.03 -- 3% used → reach center
        local SCALAR_LIFE_LATE_START = 0.12 -- 12% used → start late ramp
        local SCALAR_LIFE_LATE_FULL = 0.30 -- 30% used → full late rate
        if data.scalarTreadCondition == nil then data.scalarTreadCondition = 100 end
        if ENABLE_SCALAR_TREAD_WEAR and not isAirborne then
                local tempWearPenalty = 1.0
                if tempDistWeighted > 1.0 then
                    tempWearPenalty = lerp(1.0, hotWearMult, max(0.0, min(1.0, tempDistWeighted - 1.0)))
                elseif tempDistWeighted < 0.80 then
                    tempWearPenalty = lerp(1.0, coldWearMult, max(0.0, min(1.0, (0.80 - tempDistWeighted) / 0.50)))
                end

                local slidingWear = 20.0 * ((loadRaw or max(100, vehicleMass)) / (max(100, vehicleMass) * 9.81) * (slipEnergy / (1.0 + slipEnergy * (topo.slideWearEnergySat or 0.35))) * tempWearPenalty / tyreWidthCoeff)
                local surfaceWearScale = 1.0
                if isIceSurface then
                    surfaceWearScale = lerp(0.25, 0.10, treadCoef)
                elseif isWetSurface then
                    surfaceWearScale = 0.80
                elseif isLooseSurface then
                    if isMudSurface or isSnowSurface or string.find(gmName, "grass") then
                        surfaceWearScale = lerp(0.35, 0.15, treadCoef)
                    elseif isGravelSurface then
                        surfaceWearScale = lerp(1.15, 0.70, treadCoef)
                    elseif isSandSurface then
                        surfaceWearScale = lerp(1.00, 0.60, treadCoef)
                    else
                        surfaceWearScale = lerp(0.85, 0.50, treadCoef)
                    end
                end
        
                wear = tempDistToWearMult(tempDistWeighted) * (slidingWear + (vehNotParked * abs(propulsionTorque * 0.008 - brakeTorque * 0.025) * 0.3 * TORQUE_ENERGY_MULTIPLIER) * 0.08 + angularVel * 0.0005 * (ctw.rollingWearCoef or 1.0)) * (wearRate * cycleWearMultiplier / max(0.7, min(1.3, tyreWidth / 0.2))) * (1.0 + min(0.75, (w.suspStress or 0) * 0.35 * bottomOutSens)) * surfaceWearScale * dt
                -- Mild scalar-rate curve from dedicated scalar life (never hybrid / node peak).
                local scalarScale = SCALAR_TREAD_WEAR_SCALE
                if ENABLE_SCALAR_RATE_CURVE then
                    local lifeUsed = max(0, min(1, (100 - (data.scalarTreadCondition or 100)) * 0.01))
                    if lifeUsed <= SCALAR_LIFE_EARLY_END then
                        local t = lifeUsed / max(1e-6, SCALAR_LIFE_EARLY_END)
                        scalarScale = SCALAR_SCALE_EARLY + (SCALAR_TREAD_WEAR_SCALE - SCALAR_SCALE_EARLY) * t
                    elseif lifeUsed <= SCALAR_LIFE_LATE_START then
                        scalarScale = SCALAR_TREAD_WEAR_SCALE
                    else
                        local t = (lifeUsed - SCALAR_LIFE_LATE_START)
                            / max(1e-6, SCALAR_LIFE_LATE_FULL - SCALAR_LIFE_LATE_START)
                        scalarScale = SCALAR_TREAD_WEAR_SCALE
                            + (SCALAR_SCALE_LATE - SCALAR_TREAD_WEAR_SCALE) * min(1, t)
                    end
                end
                data.scalarWearScale = scalarScale
                wear = wear * scalarScale

                -- Path A2: secondary contact (kerb+asphalt) mild wear bump when ID2 rougher — spike excluded upstream
                do
                    local dualB = ctw.dualContactBlend or 0
                    if dualB > 1e-4 then
                        local bump = min(topo.dualContactWearBump or 0.18, (ctw.dualRoughDelta or 0) * 0.55)
                        if bump > 1e-4 then
                            wear = wear * (1.0 + dualB * bump)
                        end
                    end
                end

                -- Excess-camber wear: neutral at camberWearMult=1.0 (bit-identical); >1 adds mild shoulder wear
                do
                    local cwm = mods.camberWearMult or DEFAULT_MODS.camberWearMult or 1.0
                    if abs(cwm - 1.0) > 1e-6 then
                        local excessCam = max(0, abs(w.camber or 0) - (2.5 + casing_compliance * 3.5))
                        wear = wear * max(0.85, 1.0 + excessCam * excessCam * 0.012 * (cwm - 1.0))
                    end
                end

                -- Per-zone wear follows load bias weights (outer/middle/inner)
                zoneWearDelta[1] = wear * wLeft * 3
                zoneWearDelta[2] = wear * wCenter * 3
                zoneWearDelta[3] = wear * wRight * 3
        end

        if not data.zoneCondition then data.zoneCondition = { 100, 100, 100 } end
        if ENABLE_SCALAR_TREAD_WEAR then
            for zi = 1, 3 do
                data.zoneCondition[zi] = max(0, min(100, (data.zoneCondition[zi] or 100) - (zoneWearDelta[zi] or 0)))
            end
            data.condition = max(0, min(100, (data.zoneCondition[1] + data.zoneCondition[2] + data.zoneCondition[3]) / 3))
            -- True scalar life (A1 sc): never min'd with node — drives rate curve + Pitwall sc
            data.scalarTreadCondition = max(0, min(100, (data.scalarTreadCondition or 100) - wear))
        else
            -- Thermal-first: hold full tread so grip curves stay temp/PSI/surface-driven
            data.zoneCondition[1], data.zoneCondition[2], data.zoneCondition[3] = 100, 100, 100
            data.condition = 100
            data.scalarTreadCondition = 100
            data.scalarWearScale = SCALAR_TREAD_WEAR_SCALE
        end
        local scaleWearModifier = (mods.wearRate or 0.0005) * 2000

        -- Flatspot removed (V2 experimental): scalar lock→μ tax was low value vs Beam
        -- pressureWheel articulation. Revisit as clean-room node wear later.
        data.flatSpot = 0

        -- DISTINCT surface modes: clog (loose + offroad/rally only) / grain / blister
        -- isDryPaved already from shared flags (includes hard_smooth)

        -- Dirt packing vs self-cleaning — street/sport/slick never accumulate clog
        local clog = data.clog or 0
        local depthPack = min(1.5, max(0, contactDepth or 0) * 3.0)
        local p1Clog = data.profile1Lower or ""
        local p2Clog = data.profile2Lower or ""
        local isRallyClog = string.find(p1Clog, "rally", 1, true) or string.find(p2Clog, "rally", 1, true)
        local isOffroadClog = string.find(p1Clog, "terrain", 1, true) or string.find(p2Clog, "terrain", 1, true)
                or string.find(p1Clog, "offroad", 1, true) or string.find(p2Clog, "offroad", 1, true)
                or string.find(p1Clog, "mud", 1, true) or string.find(p2Clog, "mud", 1, true)
        local clogEligible = isRallyClog or isOffroadClog
        if clogEligible and (sf.mud or sf.dirtGrass or ((sf.sand or sf.gravel) and (isRaining or isWetSurface))) then
                local packRate = (0.35 + slipEnergy * 0.25 + depthPack) * max(0.05, 1.15 - rawJBeamTread) * (isMudSurface and 1.4 or 1.0)
                if isRallyClog then packRate = packRate * 0.55 end
                clog = clog + packRate * dt
        else
                -- Street compounds / dry pave: clear any residual clog quickly
                local cleanBoost = clogEligible and 1.0 or 3.0
                if string.find(gmName, "sand") or string.find(gmName, "gravel") then cleanBoost = cleanBoost * 2.5 end
                if isDryPaved then cleanBoost = cleanBoost * 1.3 end
                if isRallyClog then cleanBoost = cleanBoost * 1.45 end
                local selfClean = (0.015 + (angularVel * angularVel) * 0.000004 + slipEnergy * 0.02) * lerp(0.4, 2.5, rawJBeamTread) * cleanBoost
                clog = clog - selfClean * dt * max(0.35, 1.0 - depthPack * 0.4)
        end
        if not clogEligible then clog = min(clog, 0) end
        data.clog = max(0, min(1.0, clog))

        -- Graining: cold compound + lateral scrub on hard surfaces (not total slip alone).
        -- GRAIN #1: thresh 0.10→0.045 (live Pitwall corner slip); decay 0.012→0.0035;
        -- rolling polish cap 0.008→0.003. Sport/Plus grainTempRatio 0.88 + rate ×2.
        local grain = data.graining or 0
        local grainColdLimit = current_working_temp * grainTempRatio
        local latGrainWork = max(sideSlipEnergy, slipEnergy * 0.55)
        local grainSlipThresh = 0.045
        local coldSeverity = 0
        if avgWeightedTemp < grainColdLimit then
                coldSeverity = min(1.6, (grainColdLimit - avgWeightedTemp) / max(10.0, grainColdLimit * 0.28))
        end
        if coldSeverity > 0 and latGrainWork > grainSlipThresh and not isAirborne and (isDryPaved or isWetSurface) then
                grain = grain + (mods.grainRate or DEFAULT_MODS.grainRate or 0.00042) * scaleWearModifier * coldSeverity * min(2.8, latGrainWork / grainSlipThresh) * (isWetSurface and 0.55 or 1.0) * dt
        else
                local grainDecay = 0
                local warmFloor = current_working_temp * max(0.82, grainTempRatio + 0.06)
                if avgWeightedTemp >= warmFloor and avgWeightedTemp <= (current_working_temp * 1.15) and latGrainWork < (grainSlipThresh * 0.85) then
                    grainDecay = 0.0035 -- polish in window; was 0.012 (erased out-lap grain)
                end
                if not isAirborne and abs(angularVel) > 3.0 and latGrainWork < (grainSlipThresh * 1.8) then
                    grainDecay = grainDecay + min(0.003, 0.00035 * abs(angularVel))
                end
                grain = grain - grainDecay * dt
        end
        data.graining = max(0, min(1.0, grain))

        -- Blistering: overheat + (light slip OR loaded Hot corner). Does not heal.
        -- Pass #7e: half #7d rate for this run. Gate + rumble damp unchanged.
        local blister = data.blistering or 0
        local blisterStart = current_working_temp * blisterTempRatio
        local blisterSlipStart = 0.14
        local slipForBlister = max(slipEnergy, sideSlipEnergy * 0.85)
        local slipAbuse = (slipForBlister > blisterSlipStart) and min(2.0, slipForBlister / blisterSlipStart) or 0
        local workAbuse = 0
        if g_mag > 0.70 then
                workAbuse = min(1.25, (g_mag - 0.70) / 0.40) * 0.85
        end
        local blisterAbuse = max(slipAbuse, workAbuse)
        local rumbleBlisterScale = 1.0
        if string.find(gmName, "rumble") or string.find(gmName, "kickplate") or string.find(gmName, "spike") then
                rumbleBlisterScale = 0.15
        end
        if avgWeightedTemp > blisterStart and blisterAbuse > 0 and not isAirborne then
                local tempExcess = min(2.0, (avgWeightedTemp - blisterStart) / max(5.0, current_working_temp * 0.07))
                blister = blister + (mods.blisterRate or DEFAULT_MODS.blisterRate or 0.00028) * scaleWearModifier
                    * tempExcess * blisterAbuse * rumbleBlisterScale * dt
        end
        data.blistering = min(1.0, blister)

            data.surfaceDamage = max(data.clog or 0, data.graining or 0, data.blistering or 0)
    end

    -- Pressure leak, native PSI sync, hot write-back (separate local budget from damage).
    F.ctwIntegrateWearPressure = function(wheelID, dt, localEnvTemp, wd, w, data, mods)
        local avgWeightedTemp = ctw.avgWeightedTemp or localEnvTemp or getEnvTemp()
        local current_optimal_temp = ctw.current_optimal_temp or WORKING_TEMP
        local blisterTempRatio = ctw.blisterTempRatio or 1.55
        local vehicleSpeed = ctw.vehicleSpeed or 0
        local currentTempK = ctw.currentTempK
        local initialTempK = ctw.initialTempK
        local warmAbsolutePressurePSI = ctw.warmAbsolutePressurePSI
        local thermalAbsPSI = ctw.thermalAbsPSI or warmAbsolutePressurePSI
        local dynamicPressurePSI = ctw.dynamicPressurePSI

        -- Progressive puncture (BeamNG pressure-group leak), not instant deflate.
        -- Heat leak is carcass-gated and recomputed each step (not sticky). A high-speed
        -- yaw/slide used to flash SKIN avgWeightedTemp past 165 and latch leakRatePa forever
        -- → delayed blowout. Tester: spinout heat spike must not latch leak from skin flash.
        -- Spike/puncture: stock wheels.lua owns setGroupPressure while isPunctured.
        -- Slicks: higher heat-leak floor so WC hotlaps don't "slow flat" near the working window;
        -- soft_slick used to inherit the street 165C gate when optTemp < 80.
        local nativeOwnsSpikeLeak = wd.isPunctured and true or false
        local leak = 0
        local carcassLeakTemp = ctw.avgCarcassTemp or avgWeightedTemp
        local isSlickLeak = string.find(data.profile1Lower or "", "slick", 1, true)
                or string.find(data.profile2Lower or "", "slick", 1, true)
        if (data.blistering or 0) > 0.70 and carcassLeakTemp > current_optimal_temp * 1.30 then
                leak = max(leak, lerp(0, 22000, min(1, (data.blistering - 0.70) / 0.30))) -- Pa/s
        end
        local heatLeakStart = isSlickLeak and 195 or (((mods.optimalTemp or 65) >= 80) and 185 or 165)
        if carcassLeakTemp > heatLeakStart then
                leak = max(leak, 8000 + (carcassLeakTemp - (heatLeakStart - 20)) * 200)
        end
        if data.condition < 5 then
                leak = max(leak, 15000)
        end
        data.leakRatePa = leak
        if nativeOwnsSpikeLeak then
                -- Defer pressure writes to native; track UI severity + follow native gauge.
                data.punctureSeverity = min(1.0, (data.punctureSeverity or 0) + dt * 0.02)
                -- Informational rate for HUD / diagnostics (does not drive setGroupPressure).
                data.leakRatePa = max(leak, wd.punctureLeakRate or 20000)
        elseif leak > 0 then
                local newAbs = applyPressureLeakPa(wd, leak, dt)
                if newAbs then
                    data.punctureSeverity = min(1.0, (data.punctureSeverity or 0) + dt * 0.02)
                    -- Finalize with native deflate only at BeamNG min pressure
                    if newAbs <= 105500 then
                        deflateTireCompat(wheelID)
                    end
                elseif (data.blistering or 0) >= 0.95 and avgWeightedTemp > (data.working_temp * max(1.25, blisterTempRatio - 0.05)) then
                    -- Fallback when pressure groups unavailable
                    deflateTireCompat(wheelID)
                end
        end

        data.currentPressurePSI = dynamicPressurePSI
        data.luaPressurePSI = dynamicPressurePSI
        -- Native group gauge (Pa→PSI); optional rate-limited hot write-back for soft-body stiffness
        local nativePSI = getNativeGroupPressurePSI(wd)
        local dPdt = 0
        if nativePSI then
                local prevNative = data.lastNativePSI or nativePSI
                dPdt = abs(nativePSI - prevNative) / max(dt, 1e-3)
                data.lastNativePSI = nativePSI
                data.nativePressurePSI = nativePSI
                -- Prefer live BeamNG pressure-group reading when leaking or native spike-puncture owns writes
                if (data.leakRatePa or 0) > 0 or nativeOwnsSpikeLeak then
                    data.currentPressurePSI = nativePSI
                else
                    -- User/TPMS fill: only treat as a garage setpoint when the CAR is slow.
                    -- Hop/airborne fronts at 170 mph used to look parked (angularVel forced 0)
                    -- and PV/contact spikes tripped dP/dt ≥ 8 PSI/s, so Cold chased native to ~40.
                    local tpmsPsiS = topo.pressureTpmsDeadbandPsiS or 8.0
                    local garageSpeed = topo.pressureColdRefreshMaxSpeed or 4.0
                    local inGarage = vehicleSpeed < garageSpeed
                    if inGarage and (isTirePressureInflateActive() or dPdt >= tpmsPsiS) then
                        data.coldFillAdopt = true
                    end
                    local parkedOk = (topo.pressureColdRefreshParkedOnly == false) or inGarage
                    if parkedOk
                        and inGarage
                        and dPdt < tpmsPsiS
                        and currentTempK and initialTempK
                        and abs(currentTempK - initialTempK) < 8.0 then
                        local coldNow = data.coldPressurePSI or nativePSI
                        -- Follow native down always (deflate). Follow up only after a real user fill.
                        if nativePSI <= (coldNow + 0.25) or data.coldFillAdopt then
                            local coldAlpha = min(1.0, dt / max(0.5, topo.pressureColdRefreshTau or 2.5))
                            data.coldPressurePSI = coldNow * (1.0 - coldAlpha) + nativePSI * coldAlpha
                            if abs((data.coldPressurePSI or nativePSI) - nativePSI) < 0.2 then
                                data.coldFillAdopt = nil
                            end
                        end
                    end
                end

                -- Safe hot PSI write-back: Lua Gay-Lussac absolute → native group (rate-limited).
                -- Skip UP-writes while rubber is still cold (straight-line fronts never leave ~28°C).
                -- Always allow pull-down: hop/PV chatter trips dP/dt ≥ 8 and used to freeze native at 38 PSI.
                local luaGauge = (thermalAbsPSI or warmAbsolutePressurePSI or 0) - 14.696
                local pullingDown = nativePSI and (nativePSI - luaGauge) > 2.0
                local tireHot = currentTempK and initialTempK and (currentTempK - initialTempK) > 15.0
                if (topo.pressureHotWritebackEnable ~= false)
                    and (data.leakRatePa or 0) <= 0
                    and not nativeOwnsSpikeLeak
                    and not (w.isBroken or w.isTireDeflated)
                    and not isTirePressureInflateActive()
                    and (pullingDown or (tireHot and dPdt < (topo.pressureTpmsDeadbandPsiS or 8.0)))
                then
                    local targetAbsPa = (thermalAbsPSI or warmAbsolutePressurePSI) * 6894.757
                    local maxPsiS = topo.pressureHotWritebackMaxPsiS or 0.35
                    if pullingDown then
                        maxPsiS = max(maxPsiS, topo.pressureHotWritebackRecoverPsiS or 2.5)
                    end
                    local newAbs = applyHotPressureWriteback(
                        wd,
                        targetAbsPa,
                        dt,
                        maxPsiS,
                        topo.pressureHotWritebackDeadbandPsi or 0.15
                    )
                    if newAbs then
                        nativePSI = max(0.1, (newAbs - 101325) / 6894.757)
                        data.nativePressurePSI = nativePSI
                        data.lastNativePSI = nativePSI
                    end
                end
        else
                data.nativePressurePSI = dynamicPressurePSI
        end
        data.pressurePsiDelta = (data.luaPressurePSI or dynamicPressurePSI) - (data.nativePressurePSI or dynamicPressurePSI)
        data.currentFlatSpot = 0 -- feature removed; stream stays 0 for schema stability
        data.currentSurfaceDamage = data.surfaceDamage or 0
        data.currentClog = data.clog or 0
        data.currentGraining = data.graining or 0
        data.currentBlistering = data.blistering or 0
    end

    F.ctwIntegrateWear = function(wheelID, dt, localEnvTemp, wd, w, data, mods)
        F.ctwIntegrateWearDamage(wheelID, dt, localEnvTemp, wd, w, data, mods)
        F.ctwIntegrateWearPressure(wheelID, dt, localEnvTemp, wd, w, data, mods)
    end
end

return M

