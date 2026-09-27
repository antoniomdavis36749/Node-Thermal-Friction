-- lua/vehicle/extensions/tireWearThermalsTelemetry.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- Optional CSV telemetry (cold path; buffered I/O, not on thermal integrate step).
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

    -- Quote CSV fields that contain comma/quote/newline (dutyMods lists use commas).
    F.csvEscape = function(value)
        local s = tostring(value or "")
        if s == "" then return "" end
        if string.find(s, '[,"\r\n]', 1) then
            return '"' .. string.gsub(s, '"', '""') .. '"'
        end
        return s
    end

    -- Write header once per path; skip open/read/check on every sample.
    F.ensureTelemetryHeader = function(ioLib, path)
        if telem.headerReady or not ioLib or not path then return end
        local exists = false
        local rf = ioLib.open(path, "r")
        if rf then
            local first = rf:read(1)
            exists = first ~= nil
            rf:close()
        end
        if exists then
            telem.headerReady = true
            return
        end
        local hdr = ioLib.open(path, "w")
        if hdr then
            hdr:write(telem.csvHeader)
            hdr:close()
            telem.headerReady = true
        end
    end

    F.clearTelemetryCsvBuffer = function()
        for i = 1, telem.csvBufCount do
            telem.csvBuffer[i] = nil
        end
        telem.csvBufCount = 0
    end

    -- Batch-append buffered lines in one open/write/close. Safe to call often (no-op if empty).
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

    -- Flush pending samples first so #RESET stays chronologically after them.
    F.appendTelemetryResetMarker = function(ioLib, path, reason)
        ioLib = ioLib or F.getTelemetryIo()
        if not ioLib or not path then return end
        F.flushTelemetryBuffer(ioLib)
        F.ensureTelemetryHeader(ioLib, path)
        local f = ioLib.open(path, "a")
        if f then
            f:write(string.format("#RESET,%.3f,%s\n", os.clock(), tostring(reason or "reset")))
            f:close()
        end
        telem.lastFlushClock = os.clock()
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

    F.writeTelemetryIfEnabled = function(dt)
        -- Optional CSV telemetry (disabled by default). Samples go to an in-memory buffer;
        -- disk I/O only on flush (safety timer / line cap / disable / reset / explicit).
        if not telem.csvEnabled then return end
        telem.timer = telem.timer + dt
        if telem.timer < telem.interval then
            if F.telemetryBufferNeedsFlush() then
                F.flushTelemetryBuffer()
            end
            return
        end
        telem.timer = 0
        if not telem.path then
            telem.path = "tire_thermals_telemetry.csv"
        end
        -- Ensure header once while armed (not every sample).
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
            -- Legacy numeric prefix (unchanged) + escaped UI-stream suffix
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
                .. string.format("%.3f,%.3f,%.3f,%d,%d,%d,%.1f,%.3f,%.2f,%.2f,%.3f,%.2f,%.2f,%d,%.3f,%.4f\n",
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
                    data.lastStickFlexHeat or 0)
        end
        if F.telemetryBufferNeedsFlush() then
            F.flushTelemetryBuffer()
        end
    end
end

return M
