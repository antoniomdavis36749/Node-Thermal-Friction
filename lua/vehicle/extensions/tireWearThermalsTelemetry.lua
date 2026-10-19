-- Upstream authorship: see CREDITS.md / NOTICE.

local M = {}

local min, max = math.min, math.max

function M.install(F, deps)
    local telem = deps.telem
    local tyreData = deps.tyreData
    local tyreGripTable = deps.tyreGripTable
    local getWheels = deps.getWheels or function() return deps.wheels end
    local wheelCache = deps.wheelCache
    local getNativeAero = deps.getNativeAero
    local getEnvTemp = deps.getEnvTemp
    local getWaterFilmDepth = deps.getWaterFilmDepth
    local getStintKm = deps.getStintKm
    local ensureTempNodes = deps.ensureTempNodes
    local nativeAeroWheelShare = deps.nativeAeroWheelShare

    F.getTelemetryIo = function()
        if io and type(io.open) == "function" then return io end
        return nil
    end

    F.csvEscape = function(value)
        local s = tostring(value or "")
        if s == "" then return "" end
        if string.find(s, '[,"\r\n]', 1) then
            return '"' .. string.gsub(s, '"', '""') .. '"'
        end
        return s
    end

    F.ensureTelemetryHeader = function(ioLib, path)
        if not ioLib or not path then return path end
        if telem.headerReady then return telem.path or path end
        local function readFirst(p)
            local rf = ioLib.open(p, "r")
            if not rf then return nil end
            local line = rf:read("*l")
            rf:close()
            return line
        end
        local function sibling(origin, version)
            local stem = origin
            if string.sub(origin, -4) == ".csv" then
                stem = string.sub(origin, 1, -5)
            end
            return stem .. "-v" .. tostring(version) .. ".csv"
        end
        local origin = path
        local first = readFirst(path)
        local version = 2
        local newestCol = string.match(telem.csvHeader, "([^,\r\n]+)%s*$") or "carName"
        while first and first ~= "" and not string.find(first, newestCol, 1, true) and version <= 12 do
            path = sibling(origin, version)
            telem.path = path
            first = readFirst(path)
            version = version + 1
        end
        if first and first ~= "" then
            telem.headerReady = true
            return path
        end
        local hdr = ioLib.open(path, "w")
        if hdr then
            hdr:write(telem.csvHeader)
            hdr:close()
            telem.headerReady = true
        end
        return path
    end

    F.clearTelemetryCsvBuffer = function()
        for i = 1, telem.csvBufCount do
            telem.csvBuffer[i] = nil
        end
        telem.csvBufCount = 0
    end

    F.flushTelemetryBuffer = function(ioLib)
        ioLib = ioLib or F.getTelemetryIo()
        if not ioLib or not telem.path then
            telem.lastFlushClock = os.clock()
            return
        end
        if telem.csvBufCount <= 0 then
            telem.lastFlushClock = os.clock()
            return
        end
        F.ensureTelemetryHeader(ioLib, telem.path)
        local f = ioLib.open(telem.path, "a")
        if f then
            f:write(table.concat(telem.csvBuffer, "", 1, telem.csvBufCount))
            f:close()
        end
        F.clearTelemetryCsvBuffer()
        telem.lastFlushClock = os.clock()
    end

    F.telemetryBufferNeedsFlush = function()
        if telem.csvBufCount <= 0 then return false end
        if telem.csvBufCount >= telem.flushMaxLines then return true end
        local now = os.clock()
        if telem.lastFlushClock <= 0 then
            telem.lastFlushClock = now
            return false
        end
        return (now - telem.lastFlushClock) >= telem.flushWallSec
    end

    F.writeTelemetryArmMarker = function(path)
        local ioLib = F.getTelemetryIo()
        if not ioLib or not path then return end
        local f = ioLib.open(telem.armMarker, "w")
        if f then
            f:write(tostring(path) .. "\n")
            f:close()
        end
    end

    F.clearTelemetryArmMarker = function()
        if os and os.remove then os.remove(telem.armMarker) end
    end

    F.readCodeStamp = function()
        local ioLib = F.getTelemetryIo()
        local f = ioLib and telem.codeStamp and ioLib.open(telem.codeStamp, "r")
        if not f then return "none" end
        local line = f:read("*l") or ""
        f:close()
        line = string.gsub(line, "[,\r\n]", " ")
        return line ~= "" and line or "none"
    end

    F.newTelemetryRun = function(reason)
        telem.runSeq = (telem.runSeq or 0) + 1
        local clockStamp = nil
        if os and type(os.date) == "function" then
            local ok, s = pcall(os.date, "%Y%m%d-%H%M%S")
            if ok and type(s) == "string" then clockStamp = s end
        end
        local vehId = (F.streamVehicleId and F.streamVehicleId()) or 0
        telem.runId = string.format("%s-%s-%d",
            clockStamp or string.format("c%d", math.floor(os.clock())), tostring(vehId), telem.runSeq)
        telem.runReason = tostring(reason or "arm")
        telem.runHeaderDue = true
        telem.runSig = nil
    end

    F.telemetrySetupSig = function()
        local sig = {}
        for wheelID, data in pairs(tyreData) do
            local mods = type(data) == "table" and data.interpolatedMods
            if mods then
                sig[#sig + 1] = string.format("%s:%s:%s:%.2f", tostring(wheelID),
                    tostring(data.profile1 or ""), tostring(data.profile2 or ""), mods.rollingHystScale or 1)
            end
        end
        table.sort(sig)
        return table.concat(sig, ";")
    end

    F.bufferFlashLine = function(wheelName, peak, overS, holdS)
        telem.csvBufCount = telem.csvBufCount + 1
        telem.csvBuffer[telem.csvBufCount] = string.format(
            "#FLASH,%s,%s,%.1f,%.2f,%.2f,%.3f,%.3f\n",
            F.csvEscape(telem.runId or ""), F.csvEscape(wheelName or ""),
            tonumber(peak) or 0, tonumber(overS) or 0, tonumber(holdS) or 0,
            os.clock() or 0, (getStintKm and getStintKm()) or 0)
        telem.forceFlush = true
    end

    F.bufferRunHeader = function()
        local dateStr = ""
        if os and type(os.date) == "function" then
            local ok, s = pcall(os.date, "%Y-%m-%dT%H:%M:%S")
            if ok and type(s) == "string" then dateStr = s end
        end
        local context = F.telemetryRunContext and F.telemetryRunContext() or ""
        telem.csvBufCount = telem.csvBufCount + 1
        telem.csvBuffer[telem.csvBufCount] = string.format("#RUN,%s,reason=%s,date=%s,wall=%.3f,stamp=%s,%s\n",
            telem.runId or "", telem.runReason or "", dateStr, os.clock(), F.readCodeStamp(), context)
        telem.runHeaderDue = false
    end

    F.appendTelemetryResetMarker = function(ioLib, path, reason)
        ioLib = ioLib or F.getTelemetryIo()
        if not ioLib or not path then return end
        F.flushTelemetryBuffer(ioLib)
        path = F.ensureTelemetryHeader(ioLib, path) or path
        local f = ioLib.open(path, "a")
        if f then
            f:write(string.format("#RESET,%.3f,%s\n", os.clock(), tostring(reason or "reset")))
            f:close()
        end
        telem.lastFlushClock = os.clock()
        F.newTelemetryRun(reason or "reset")
    end

    F.restoreTelemetryAfterReload = function(reason)
        local ioLib = F.getTelemetryIo()
        if not ioLib then return end
        local mf = ioLib.open(telem.armMarker, "r")
        if not mf then return end
        local path = mf:read("*l")
        mf:close()
        if not path or #path < 3 then return end
        telem.path = path
        telem.headerReady = false
        telem.csvEnabled = true
        F.ensureTelemetryHeader(ioLib, path)
        F.appendTelemetryResetMarker(ioLib, path, reason or "vehicle_reload")
    end

    F.trackHotFlashes = function(dt)
        if not dt or dt <= 0 or dt > 0.5 then return end
        if type(tyreData) ~= "table" then return end
        for wheelID, data in pairs(tyreData) do
            if type(data) == "table" then
                local mods = data.interpolatedMods
                local temp = data.temp
                local mid = temp and temp[2]
                local opt = mods and mods.optimalTemp
                local plateau = mods and mods.tempPlateau
                if type(mid) == "number" and type(opt) == "number" and type(plateau) == "number" then
                    local hotEdge = opt + plateau
                    if mid > hotEdge then
                        if not data.hotOpen then
                            data.hotOpen = true
                            data.hotRunS = 0
                            data.hotFlashPeak = mid
                            data.peakHoldS = 0
                        end
                        data.hotRunS = (data.hotRunS or 0) + dt
                        if mid > (data.hotFlashPeak or mid) then
                            data.hotFlashPeak = mid
                            data.peakHoldS = 0
                        end
                        if mid >= (data.hotFlashPeak or mid) - 2.0 then
                            data.peakHoldS = (data.peakHoldS or 0) + dt
                        end
                    elseif data.hotOpen then
                        data.hotOpen = false
                        data.hotFlashS = data.hotRunS or 0
                        data.hotRunS = 0
                        local name = tostring(wheelID)
                        local wheels = getWheels()
                        local wd = wheels and wheels.wheelRotators and wheels.wheelRotators[wheelID]
                        if wd and wd.name then name = wd.name end
                        if telem.csvEnabled and F.bufferFlashLine then
                            F.bufferFlashLine(name, data.hotFlashPeak or mid, data.hotFlashS or 0, data.peakHoldS or 0)
                        end
                        if log then
                            log("I", "ntfHotFlash", string.format(
                                "%s peak=%.1f over=%.1fs hold=%.1fs",
                                name, data.hotFlashPeak or mid, data.hotFlashS or 0, data.peakHoldS or 0))
                        end
                    end
                end
            end
        end
    end

    F.writeTelemetryIfEnabled = function(dt)
        F.trackHotFlashes(dt)

        if not telem.csvEnabled then return end
        telem.timer = telem.timer + dt
        if telem.timer < telem.interval then
            if telem.forceFlush or F.telemetryBufferNeedsFlush() then
                telem.forceFlush = false
                F.flushTelemetryBuffer()
            end
            return
        end
        telem.timer = 0
        if not telem.path then
            telem.path = "tire_thermals_telemetry.csv"
        end

        if not telem.headerReady then
            local ioLib = F.getTelemetryIo()
            if ioLib then
                F.ensureTelemetryHeader(ioLib, telem.path)
            end
        end
        local tNow = (electrics and electrics.values and electrics.values.timer) or 0
        local wall = os.clock()
        local aeroLoadBase = getNativeAero()
        local totalDownforceN = math.floor(aeroLoadBase.liftN)
        local aeroFracPct = math.floor(aeroLoadBase.fracPct * 10) / 10
        local aeroDragN = math.floor(aeroLoadBase.dragN)
        local aeroFrontN = math.floor(aeroLoadBase.frontN)
        local aeroRearN = math.floor(aeroLoadBase.rearN)
        local copPct = math.floor(aeroLoadBase.copPct * 10) / 10
        local waterFilmDepth = getWaterFilmDepth()
        local envTemp = getEnvTemp()
        local stintKm = (getStintKm and getStintKm()) or 0
        local setupSig = F.telemetrySetupSig()
        if not telem.runId or (telem.runSig and setupSig ~= "" and setupSig ~= telem.runSig) then
            F.newTelemetryRun(telem.runId and "setup_change" or "arm")
        end
        if telem.runHeaderDue and setupSig ~= "" then
            F.bufferRunHeader()
            telem.runSig = setupSig
        end
        local ev = electrics and electrics.values or {}
        local throttle = ev.throttle or 0
        local brake = ev.brake or ev.brake_input or 0
        for wheelID, data in pairs(tyreData) do
            data.temp = ensureTempNodes(data.temp, envTemp)
            local grip = data.lastGrip or tyreGripTable[wheelID] or 0
            local longG = data.lastLongGrip or grip
            local latG = data.lastLatGrip or grip
            local mods = data.interpolatedMods
            local profile = (mods and mods.descriptor)
                or (((data.interpFactor or 0) > 0.5) and data.profile2 or data.profile1)
                or ""
            local purpose = (mods and mods.purpose) or "street"
            local classifyReason = (mods and mods.classifyReason) or "street_spectrum"
            local wc = wheelCache[wheelID]
            local rawLoad = (wc and wc.loadRaw) or 0
            local wheels = getWheels()
            local wd = wheels and wheels.wheelRotators and wheels.wheelRotators[wheelID]
            local wdName = (wd and wd.name) or ""
            local propNm = (wd and wd.propulsionTorque) or 0

            local driven = math.abs(propNm) > 40 and 1 or 0
            local aeroLoadN = math.floor(nativeAeroWheelShare(wdName, rawLoad))
            local nativeTreadC, nativeCoreC = -1, -1
            local nativeId = wd and wd.wheelID
            if obj and nativeId ~= nil and type(obj.getWheelAvgTemperature) == "function" then
                local okT, avgK = pcall(obj.getWheelAvgTemperature, obj, nativeId)
                local okC, coreK = pcall(obj.getWheelCoreTemperature, obj, nativeId)
                if okT and type(avgK) == "number" then nativeTreadC = avgK - 273.15 end
                if okC and type(coreK) == "number" then nativeCoreC = coreK - 273.15 end
            end
            telem.csvBufCount = telem.csvBufCount + 1

            telem.csvBuffer[telem.csvBufCount] = string.format(
                "%.3f,%.2f,%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%d,%.2f,%.2f,%.2f,",
                wall, tNow, tostring(wheelID), data.condition or 0,
                data.temp[1] or 0, data.temp[2] or 0, data.temp[3] or 0,
                data.temp[4] or 0, data.temp[5] or 0, data.temp[6] or 0,
                data.temp[7] or 0, data.temp[8] or 0,
                data.currentPressurePSI or 0, grip, longG, latG,
                data.clog or 0, data.graining or 0, data.blistering or 0,
                data.heatCycles or 0, data.stintFade or 0, data.punctureSeverity or 0, waterFilmDepth)
                .. F.csvEscape(profile) .. ","
                .. F.csvEscape(data.profile1 or "") .. ","
                .. F.csvEscape(data.profile2 or "") .. ","
                .. F.csvEscape(purpose) .. ","
                .. F.csvEscape(classifyReason) .. ","
                .. string.format("%.3f,%.3f,%d,%d,%.1f,",
                    data.lastPatchFrac or 0, data.lastPatchHeatScale or 1,
                    aeroLoadN, totalDownforceN, aeroFracPct)
                .. F.csvEscape(data.lastDutyMods or "") .. ","
                .. string.format("%.3f,%.3f,%.3f,%d,%d,%d,%.1f,%.3f,%.2f,%.2f,%.3f,%.2f,%.2f,%d,%.3f,%.4f,%.2f,%.2f,%.1f,%.2f,%.1f,%d,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.1f,%.2f,%.1f,%.1f,%s,%s,%s,%.1f,%.3f,%s,%s,%d,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n",
                    data.lastDriveHeatGate or 0,
                    data.lastStreetSlipHeatScale or 1,
                    data.lastUtilNudge or 1,
                    aeroDragN, aeroFrontN, aeroRearN, copPct,
                    stintKm,
                    data.conditionScalar or data.condition or 0,
                    data.conditionNode or data.condition or 0,
                    (data.nodeWearPeak or 0) * 100,
                    nativeTreadC, nativeCoreC,
                    data.layoutDampOn or 0,
                    data.lastSlipRatio or 0,
                    data.lastStickFlexHeat or 0,
                    data.hotOpen and (data.hotRunS or 0) or 0,
                    data.hotFlashS or 0,
                    data.hotFlashPeak or 0,
                    data.peakHoldS or 0,
                    propNm, driven, F.csvEscape(wdName),
                    data.lastHystHeat or 0, data.lastFlexHeat or 0,
                    data.lastBrakeSoak or 0, data.lastSlipEnergyHeat or 0,
                    data.lastRollingHeat or 0, data.lastDriveHystHeat or 0, data.lastWorkHystHeat or 0,
                    data.lastAirspeed or 0, data.lastRollingScale or 1, data.lastBandHi or 0, data.lastBrakeC or 0,
                    F.csvEscape(telem.carName or ""), F.csvEscape(telem.trackName or ""),
                    F.csvEscape(telem.runId or ""), data.lastBandLo or 0,
                    (longG + latG) * 0.5,
                    F.csvEscape((data.profileBook and data.profileBook.coeffId1) or ""),
                    F.csvEscape((data.profileBook and data.profileBook.coeffId2) or ""),
                    (mods and mods.rollFromAnchor) or 0,
                    F.csvEscape((mods and mods.packId) or ""),
                    data.jouleRolling or 0, data.jouleFlex or 0, data.jouleSoak or 0,
                    data.jouleSlip or 0, data.jouleDrive or 0, data.jouleWork or 0,
                    data.lastCamberDeg or 0, data.lastSideSlipDeg or 0,
                    data.luaPressurePSI or data.currentPressurePSI or 0,
                    data.nativePressurePSI or data.currentPressurePSI or 0,
                    throttle, brake)
            data.jouleRolling, data.jouleFlex, data.jouleSoak = 0, 0, 0
            data.jouleSlip, data.jouleDrive, data.jouleWork = 0, 0, 0
            local midNow = data.temp and data.temp[2] or 0
            if data.logMid and (midNow - data.logMid) > 40 then
                telem.forceFlush = true
            end
            data.logMid = midNow
        end
        if telem.forceFlush or F.telemetryBufferNeedsFlush() then
            telem.forceFlush = false
            F.flushTelemetryBuffer()
        end
    end
end

return M
