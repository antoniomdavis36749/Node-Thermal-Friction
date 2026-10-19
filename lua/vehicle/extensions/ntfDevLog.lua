-- Shared development log for every AMD tune logger.
-- The CSV sets the bound. A driving note can sit beside it. It does not move a number.
-- inBand is 1 when the middle is inside opt ± tempPlateau, the full-grip plateau.
-- liveGap is long minus lat. The written circle is their average.
-- heatSkinFrac, heatHystFrac, heatFlexFrac, heatSoakFrac name which term is heating the tire.
-- hotS is seconds currently above the hot edge. flashS is the last completed spike.
-- peakHoldS is seconds within 2°C of that spike's peak. A few seconds back into the plateau is acceptable.
-- prop is propulsion torque in N·m. drv is 1 when that torque is above 40 N·m. drv 0 is the undriven tire.
-- rollingHeat, driveHystHeat, and workHystHeat are the three parts of hyst. They match logger v5.
-- coeff1/coeff2 are the grip polynomials resolved at spawn. rollFromAnchor is 1 when that scale is on the anchor.
-- packId is the table the tire copied. cir is the friction number written to the wheel.
-- File: mods/unpacked/Node-Thermal-Friction-work/tools/output/dev-circle-heat.csv

local M = {}

local CSV_PATH = "mods/unpacked/Node-Thermal-Friction-work/tools/output/dev-circle-heat.csv"
local activePath = CSV_PATH
local CSV_HEADER = "log,km,kmh,mph,gear,gearIndex,rpm,throttle,brake,steer,gx,gy,boost,rain,wheel,long,lat,cir,longMult,latMult,gripMult,outC,midC,inC,carcC,rimC,airC,optC,tempDist,coldW,hotW,plateau,bandLo,bandHi,inBand,liveGap,profileGap,gripFloor,psi,psiTarget,slip,slipRatio,slipHeatIn,skinC,hyst,flex,brakeSoak,heatSkinFrac,heatHystFrac,heatFlexFrac,heatSoakFrac,driveGate,driveGateCarc,streetSlipScale,slipHeatRate,workHeatRate,patchHeat,loadN,propNm,brakeNm,surface,wet,purpose,classify,profile,hotS,flashS,flashPeak,peakHoldS,rollingHeat,driveHystHeat,workHystHeat,airspeed,rollScale,snapBandHi,brakeC,carName,trackName,runId,coeff1,coeff2,rollFromAnchor,packId\n"

local distanceM = 0
local flushTimer = 0
local lastStepSim = nil
local csvBuf = {}
local csvCount = 0
local headerReady = false
local csvMissNoted = false
local tagName = "dev"

local function quoteCsv(value)
    local s = tostring(value or "")
    if string.find(s, '[,"\r\n]', 1) then
        return '"' .. string.gsub(s, '"', '""') .. '"'
    end
    return s
end

local function num(value, fmt)
    return string.format(fmt, tonumber(value) or 0)
end

local function readFirst(path)
    local rf = io.open(path, "r")
    if not rf then return nil end
    local line = rf:read("*l")
    rf:close()
    return line
end

local function flush(forceHeader)
    if not io or type(io.open) ~= "function" then return end
    if forceHeader or not headerReady then
        local function versioned(n)
            if string.sub(CSV_PATH, -4) == ".csv" then
                return string.sub(CSV_PATH, 1, -5) .. "-v" .. tostring(n) .. ".csv"
            end
            return CSV_PATH .. "-v" .. tostring(n) .. ".csv"
        end
        local path = CSV_PATH
        local first = readFirst(path)
        local version = 5
        local function headerCurrent(line)
            return line and string.find(line, "runId", 1, true) and string.find(line, "packId", 1, true)
        end
        while first and first ~= "" and not headerCurrent(first) and version <= 12 do
            path = versioned(version)
            version = version + 1
            first = readFirst(path)
        end
        activePath = path
        if not first or first == "" then
            local hdr = io.open(path, "w")
            if hdr then
                hdr:write(CSV_HEADER)
                hdr:close()
            end
        end
        headerReady = true
    end
    if csvCount <= 0 then return end
    local f = io.open(activePath, "a")
    if f then
        f:write(table.concat(csvBuf, "", 1, csvCount))
        f:close()
    elseif log and not csvMissNoted then
        csvMissNoted = true
        log("I", "ntfDevLog", "CSV miss " .. activePath)
    end
    for i = 1, csvCount do
        csvBuf[i] = nil
    end
    csvCount = 0
end

local function push(line)
    csvCount = csvCount + 1
    csvBuf[csvCount] = line
end

local function bounds(w)
    local opt = w.opt or 0
    local plateau = w.plateau or 0
    local bandLo = opt - plateau
    local bandHi = opt + plateau
    local mid = w.mid or 0
    local inBand = (mid >= bandLo and mid <= bandHi) and 1 or 0
    local liveGap = (w.long or 0) - (w.lat or 0)
    local profileGap = (w.longMult or 1) - (w.latMult or 1)
    local skin = math.abs(w.skinC or 0)
    local hyst = math.abs(w.hyst or 0)
    local flex = math.abs(w.flex or 0)
    local soak = math.abs(w.brakeSoak or 0)
    local heatSum = skin + hyst + flex + soak
    local skinFrac, hystFrac, flexFrac, soakFrac = 0, 0, 0, 0
    if heatSum > 1e-9 then
        skinFrac = skin / heatSum
        hystFrac = hyst / heatSum
        flexFrac = flex / heatSum
        soakFrac = soak / heatSum
    end
    return bandLo, bandHi, inBand, liveGap, profileGap, skinFrac, hystFrac, flexFrac, soakFrac
end

M.step = function(dt)
    local sim = electrics and electrics.values and electrics.values.timer
    if sim ~= nil and lastStepSim == sim then return end
    lastStepSim = sim
    local speed = electrics and electrics.values and electrics.values.wheelspeed or 0
    if speed == speed and speed > 0 then
        distanceM = distanceM + speed * dt
    end
    flushTimer = flushTimer + (dt or 0)
    if flushTimer >= 2 then
        flushTimer = 0
        flush(false)
    end
end

M.km = function()
    return distanceM / 1000
end

M.begin = function(tag)
    tagName = tag or tagName
    flush(true)
end

M.reset = function(tag)
    tagName = tag or tagName
    distanceM = 0
    flush(false)
end

M.note = function(tag)
    tagName = tag or tagName
    local ev = electrics and electrics.values or {}
    local km = distanceM / 1000
    local kmh = (ev.wheelspeed or 0) * 3.6
    local mph = kmh * 0.621371
    local rpm = ev.rpm or 0
    local throttle = ev.throttle or 0
    local brake = ev.brake or ev.brake_input or 0
    local steer = ev.steering_input or ev.steering or 0
    local gx = sensors and sensors.gx or 0
    local gy = sensors and sensors.gy or 0
    local boost = ev.turboBoost or ev.boost or 0
    local rain = ev.rainState or 0
    local gearLabel = ev.gear
    local gearIndex = ev.gearIndex
    if powertrain and powertrain.getDevice then
        local gearbox = powertrain.getDevice("gearbox")
        if gearbox and gearbox.gearIndex ~= nil then
            gearIndex = gearbox.gearIndex
        end
    end
    if gearLabel == nil then gearLabel = "?" end

    local ntf = extensions and extensions.tireWearThermals
    local snap = (ntf and type(ntf.circleLogSnapshot) == "function") and ntf.circleLogSnapshot() or nil
    local bits = {}
    if type(snap) == "table" then
        for i = 1, #snap do
            local w = snap[i]
            local bandLo, bandHi, inBand, liveGap, profileGap, skinFrac, hystFrac, flexFrac, soakFrac = bounds(w)
            bits[#bits + 1] = string.format(
                "%s in=%d cir=%.3f gap=%+.3f m=%.0f band=%.0f..%.0f skin=%.2f hyst=%.2f soak=%.2f ov=%.1fs flash=%.1fs pk=%.0f hold=%.1fs prop=%.0f drv=%d rh=%.1f dh=%.1f wh=%.1f air=%.0f sc=%.2f brk=%.0f",
                w.name, inBand, w.cir or 0, liveGap, w.mid or 0, bandLo, bandHi, skinFrac, hystFrac, soakFrac,
                w.hotS or 0, w.flashS or 0, w.flashPeak or 0, w.peakHoldS or 0, w.prop or 0, w.driven or 0,
                w.rollingHeat or 0, w.driveHystHeat or 0, w.workHystHeat or 0, w.airspeed or 0, w.rollScale or 1, w.brakeC or 0
            )
            push(table.concat({
                quoteCsv(tagName),
                num(km, "%.3f"), num(kmh, "%.1f"), num(mph, "%.1f"),
                quoteCsv(gearLabel), tostring(gearIndex or 0),
                num(rpm, "%.0f"), num(throttle, "%.2f"), num(brake, "%.2f"), num(steer, "%.2f"),
                num(gx, "%.2f"), num(gy, "%.2f"), num(boost, "%.1f"), num(rain, "%.2f"),
                quoteCsv(w.name),
                num(w.long, "%.3f"), num(w.lat, "%.3f"), num(w.cir, "%.3f"),
                num(w.longMult or 1, "%.3f"), num(w.latMult or 1, "%.3f"), num(w.gripMult or 1, "%.3f"),
                num(w.outC, "%.1f"), num(w.mid, "%.1f"), num(w.inC, "%.1f"),
                num(w.carc, "%.1f"), num(w.rim, "%.1f"), num(w.air, "%.1f"), num(w.opt, "%.1f"),
                num(w.tempDist, "%.3f"), num(w.coldW, "%.1f"), num(w.hotW, "%.1f"), num(w.plateau, "%.1f"),
                num(bandLo, "%.1f"), num(bandHi, "%.1f"), tostring(inBand),
                num(liveGap, "%+.3f"), num(profileGap, "%+.3f"), num(w.gripFloor, "%.3f"),
                num(w.psi, "%.1f"), num(w.psiTarget, "%.1f"),
                num(w.slip, "%.3f"), num(w.slipRatio, "%.3f"), num(w.slipHeatIn, "%.4f"),
                num(w.skinC, "%.4f"), num(w.hyst, "%.4f"), num(w.flex, "%.4f"), num(w.brakeSoak, "%.4f"),
                num(skinFrac, "%.3f"), num(hystFrac, "%.3f"), num(flexFrac, "%.3f"), num(soakFrac, "%.3f"),
                num(w.driveGate, "%.3f"), num(w.driveGateCarc, "%.3f"), num(w.streetSlipScale or 1, "%.3f"),
                num(w.slipHeatRate, "%.3f"), num(w.workHeatRate, "%.3f"), num(w.patchHeat or 1, "%.3f"),
                num(w.load, "%.0f"), num(w.prop, "%.0f"), num(w.brakeNm, "%.0f"),
                quoteCsv(w.surface), tostring(w.wet or 0),
                quoteCsv(w.purpose), quoteCsv(w.classify), quoteCsv(w.profile),
                num(w.hotS, "%.2f"), num(w.flashS, "%.2f"), num(w.flashPeak, "%.1f"), num(w.peakHoldS, "%.2f"),
                num(w.rollingHeat, "%.4f"), num(w.driveHystHeat, "%.4f"), num(w.workHystHeat, "%.4f"),
                num(w.airspeed, "%.1f"), num(w.rollScale, "%.2f"), num(w.bandHi, "%.1f"), num(w.brakeC, "%.1f"),
                quoteCsv(w.carName), quoteCsv(w.trackName), quoteCsv(w.runId),
                quoteCsv(w.coeff1), quoteCsv(w.coeff2), tostring(w.rollFromAnchor or 0), quoteCsv(w.packId),
            }, ",") .. "\n")
        end
    end
    if #bits == 0 then
        return " | ntf=wait"
    end
    local where = ""
    local first = snap[1]
    if type(first) == "table" then
        local car = first.carName or ""
        local track = first.trackName or ""
        if car ~= "" or track ~= "" then
            where = car .. " " .. track .. " | "
        end
    end
    return " | " .. where .. table.concat(bits, " | ")
end

return M
