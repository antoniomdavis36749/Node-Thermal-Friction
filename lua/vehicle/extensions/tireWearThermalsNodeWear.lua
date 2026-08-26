-- lua/vehicle/extensions/tireWearThermalsNodeWear.lua
-- Credits: ReSpin V2 experimental. Clean-room vs BeamNG APIs only (no third-party node-wear ports).
-- Policy A: thermal core owns wheel setFrictionThermalSensitivity; this layer only scales
-- tread-node friction/mass via obj:setNodeFrictionSlidingCoefs / obj:setNodeMass.
--
-- Phase 2: lock/scrub wear spreads across wd.treadNodes ring (BeamNG pressureWheel API).
-- Lock/camber energy: gated slipForce from nodeCollision probe (ENABLE_*_ENERGY_COLE) or slipEnergy.
-- A3 HUD bridge (Friction coherence A1): condition = min(scalar, node peak);
-- zone O|M|I from outer/inner ring (display only). Soft scalar does not tax grip.
local M = {}

local min, max, abs = math.min, math.max, math.abs

local ENABLE_NODE_WEAR_SPIKE = true
local ENABLE_RING_WEAR = true
local ENABLE_HUD_BRIDGE_A3 = true
-- Gated energy swap: arm gates stay ω/slipE/camber; rate from probe slipF when armed.
local ENABLE_LOCK_ENERGY_COLE = true
local LOCK_COL_RATE = 0.016 -- base /s at slipF≈LOCK_SLIP_F_REF (tuned under slipE 0.024)
local LOCK_SLIP_F_REF = 1800 -- N → slipCap ~1.0
local LOCK_SLIP_F_MIN = 80 -- N; ignore rolling noise inside lock arm
local ENABLE_CAMBER_ENERGY_COLE = true
-- Soft base; continuous ramp from 1° (street gentle → race loud).
-- Soft life A/B (slick/circuit only): A2 arm 2.0° + A3 camF curve (quieter than flat ×0.30).
-- Sport/street keep full base + 1.0° arm (Bolide scallop unchanged).
local CAMBER_COL_BASE = 0.006
-- Soft life A3b LOCKED (GT3 Soft Belasco 22 km): fronts ~5.5–7% Cond drop.
-- Curve quiet at mild race camber; high camF scrub still costs more than lean.
local CAMBER_COL_SLICK_SCALE_MIN = 0.05
local CAMBER_COL_SLICK_SCALE_MAX = 0.14
local CAMBER_DEG_ARM = 1.0 -- Sport/street wear off below this
local CAMBER_DEG_ARM_SLICK = 2.0 -- Soft life A2; race camber still arms when loaded
local CAMBER_DEG_ZERO = 0.85 -- slight head-start so 1.0° is a whisper, not zero
local CAMBER_FRAC_REF = 4.0 -- |camber|−ZERO over this → frac≈1 (~4.85° = full)
local CAMBER_FRAC_CAP = 1.15
local CAMBER_SLIP_F_REF = 180 -- was 500; camber scrub slipF << lock, REF starved cole
local CAMBER_SLIP_F_MIN = 40 -- N
local LOCK_RING_HALF_WIDTH = 2
local LOCK_RING_OFFSET_WEIGHT = { [0] = 1.0, [1] = 0.45, [2] = 0.22 }

local function isSlickOrCircuit(data)
    if not data then return false end
    local p1 = data.profile1Lower or ""
    local p2 = data.profile2Lower or ""
    if string.find(p1, "slick", 1, true) or string.find(p2, "slick", 1, true) then
        return true
    end
    local mods = data.interpolatedMods
    return mods and mods.purpose == "circuit" or false
end

local function camberArmDegForWheel(data)
    return isSlickOrCircuit(data) and CAMBER_DEG_ARM_SLICK or CAMBER_DEG_ARM
end

-- Soft life A3: slick/circuit scale follows camberFrac (not a flat mute).
local function camberColScaleForWheel(data, camberFrac)
    if not isSlickOrCircuit(data) then return 1.0 end
    local t = max(0, min(1, camberFrac or 0))
    return CAMBER_COL_SLICK_SCALE_MIN
        + (CAMBER_COL_SLICK_SCALE_MAX - CAMBER_COL_SLICK_SCALE_MIN) * t
end

-- Continuous: 1.0°≈0.04 · 2°≈0.29 · 3°≈0.54 · ~5°≈1.0 (cap 1.15).
-- armDeg gates off (Sport 1.0° / slick 2.0°); ramp shape unchanged.
local function camberFracFromDeg(camberDegAbs, armDeg)
    local a = abs(camberDegAbs or 0)
    local arm = armDeg or CAMBER_DEG_ARM
    if a < arm then return 0 end
    return min(CAMBER_FRAC_CAP, max(0, (a - CAMBER_DEG_ZERO) / max(0.1, CAMBER_FRAC_REF)))
end

function M.install(F, deps)
    local getWheels = deps.getWheels or function() return deps.wheels end
    local wheelCache = deps.wheelCache
    local tyreData = deps.tyreData
    local isRemoteMpVehicle = deps.isRemoteMpVehicle or function() return false end
    local ProbeState = nil
    local function getProbeState()
        if ProbeState ~= nil then return ProbeState end
        local ok, mod = pcall(require, "tireWearThermalsNodeProbeState")
        ProbeState = (ok and mod) or false
        return ProbeState
    end

    local nodeState = {}

    local function lerp(a, b, t)
        return a + (b - a) * t
    end

    local function frictionScales(wear)
        wear = max(0, min(1, wear or 0))
        return lerp(1.0, 0.52, wear), lerp(1.0, 0.48, wear), lerp(1.0, 0.88, wear)
    end

    local function wheelKey(wheelIndex)
        return tonumber(wheelIndex) or wheelIndex
    end

    local function treadNodeCount(treadNodes)
        if not treadNodes then return 0 end
        local n = #treadNodes
        if n > 0 then return n end
        n = 0
        for _ in pairs(treadNodes) do n = n + 1 end
        return n
    end

    local function findTreadIndex(treadNodes, cid)
        if not treadNodes or not cid then return nil end
        for idx, nid in ipairs(treadNodes) do
            if nid == cid then return idx end
        end
        return nil
    end

    -- JBeam order: per ray, outer tread then inner tread (even idx = outer in pair).
    local function camberNodeWeight(ringIdx, camberDeg, wheelDir)
        local isOuter = (ringIdx % 2 == 1)
        local camSign = (camberDeg or 0) * (wheelDir or 1)
        if camSign > 0.5 then
            return isOuter and 1.0 or 0.32
        elseif camSign < -0.5 then
            return isOuter and 0.32 or 1.0
        end
        return 0.55
    end

    local function ringOffsetWeight(offset)
        offset = abs(offset)
        return LOCK_RING_OFFSET_WEIGHT[offset] or 0
    end

    local function collectRingTargets(wd, contactCid, halfWidth)
        local treadNodes = wd and wd.treadNodes
        local n = treadNodeCount(treadNodes)
        if not ENABLE_RING_WEAR or n < 2 or not contactCid then
            return { { cid = contactCid, weight = 1.0 } }
        end
        local centerIdx = findTreadIndex(treadNodes, contactCid)
        if not centerIdx then
            return { { cid = contactCid, weight = 1.0 } }
        end
        local out = {}
        local seen = {}
        for offset = -halfWidth, halfWidth do
            local w = ringOffsetWeight(offset)
            if w > 0 then
                local idx = ((centerIdx - 1 + offset) % n) + 1
                local cid = treadNodes[idx]
                if cid and not seen[cid] then
                    seen[cid] = true
                    out[#out + 1] = { cid = cid, weight = w, ringIdx = idx }
                end
            end
        end
        return out
    end

    local function softSatRate(rate, wear)
        if wear > 0.35 then
            local headroom = max(0.08, 1.0 - wear)
            return rate * (headroom ^ 1.15)
        end
        return rate
    end

    -- Circumferential map for Pitwall: one sample per ray = max(outer, inner) wear %.
    -- JBeam treadNodes order: outer, inner, … around the tire. Left/right axles wind
    -- opposite ways, so reverse display order when wheelDir < 0 so all Pitwall rings
    -- advance the same direction when rolling forward.
    local function publishRingMap(data, wd, contactCid)
        local treadNodes = wd and wd.treadNodes
        local n = treadNodeCount(treadNodes)
        local ring = data.nodeWearRing
        if type(ring) ~= "table" then
            ring = {}
            data.nodeWearRing = ring
        else
            for k in pairs(ring) do ring[k] = nil end
        end
        data.nodeWearRingContact = 0
        data.nodeWearRingN = 0
        if n < 1 then return end

        local flip = ((wd and wd.wheelDir) or 1) < 0
        local raw = {}
        local rawContact = 0
        local count = 0

        if n >= 2 and (n % 2 == 0) then
            count = n / 2
            for r = 1, count do
                local o = treadNodes[r * 2 - 1]
                local inn = treadNodes[r * 2]
                local wo = (o and nodeState[o] and nodeState[o].wear) or 0
                local wi = (inn and nodeState[inn] and nodeState[inn].wear) or 0
                raw[r] = math.floor(max(wo, wi) * 100 + 0.5)
                if contactCid and (o == contactCid or inn == contactCid) then
                    rawContact = r
                end
            end
        else
            count = n
            for idx, nid in ipairs(treadNodes) do
                local st = nodeState[nid]
                raw[idx] = math.floor(((st and st.wear) or 0) * 100 + 0.5)
                if nid == contactCid then rawContact = idx end
            end
        end

        if flip then
            for r = 1, count do
                ring[r] = raw[count - r + 1] or 0
            end
            if rawContact > 0 then
                data.nodeWearRingContact = count - rawContact + 1
            end
        else
            for r = 1, count do
                ring[r] = raw[r] or 0
            end
            data.nodeWearRingContact = rawContact
        end
        data.nodeWearRingN = count
        data.nodeWearRingFlip = flip and 1 or 0
    end

    -- Friction coherence A1: HUD condition / O|M|I = min(scalar tread, node peak/zones).
    -- Soft scalar is display/stint aging only; grip wearPenalty skipped while spike on
    -- (node μ owns contact feel — no double tax). See tools/V2_FRICTION_CONTRACT.md.
    local function publishHudBridgeA3(data, wd)
        if not ENABLE_HUD_BRIDGE_A3 or not data then return end
        if not data.zoneCondition then data.zoneCondition = { 100, 100, 100 } end
        local scalarCond = data.condition or 100
        local s1 = data.zoneCondition[1] or 100
        local s2 = data.zoneCondition[2] or 100
        local s3 = data.zoneCondition[3] or 100
        local peak = data.nodeWearPeak or 0
        local nodeCond = max(0, min(100, 100 * (1.0 - peak)))

        local treadNodes = wd and wd.treadNodes
        local n = treadNodeCount(treadNodes)
        local oMax, iMax = 0, 0
        if n >= 2 and (n % 2 == 0) then
            for r = 1, n / 2 do
                local o = treadNodes[r * 2 - 1]
                local inn = treadNodes[r * 2]
                local wo = (o and nodeState[o] and nodeState[o].wear) or 0
                local wi = (inn and nodeState[inn] and nodeState[inn].wear) or 0
                if wo > oMax then oMax = wo end
                if wi > iMax then iMax = wi end
            end
        else
            for idx, nid in ipairs(treadNodes or {}) do
                local wear = (nodeState[nid] and nodeState[nid].wear) or 0
                if idx % 2 == 1 then
                    if wear > oMax then oMax = wear end
                else
                    if wear > iMax then iMax = wear end
                end
            end
        end
        -- Prefer peak so middle never reads healthier than overall when only one side wore
        local mMax = (oMax + iMax) * 0.5
        local n1 = max(0, min(100, 100 * (1.0 - oMax)))
        local n2 = max(0, min(100, 100 * (1.0 - mMax)))
        local n3 = max(0, min(100, 100 * (1.0 - iMax)))
        data.zoneCondition[1] = min(s1, n1)
        data.zoneCondition[2] = min(s2, n2)
        data.zoneCondition[3] = min(s3, n3)
        -- Keep pre-min scalar for Pitwall A1 audit (sc vs nd vs Cond).
        data.conditionScalar = scalarCond
        data.conditionNode = nodeCond
        data.condition = min(scalarCond, nodeCond)
    end

    local function clearHudBridgeA3(data)
        if not data then return end
        data.condition = 100
        data.conditionScalar = 100
        data.conditionNode = 100
        if not data.zoneCondition then data.zoneCondition = { 100, 100, 100 } end
        data.zoneCondition[1], data.zoneCondition[2], data.zoneCondition[3] = 100, 100, 100
    end

    local function publishDebug(data, cid, st, gate, wheelIndex, wd)
        local wear = (st and st.wear) or 0
        local fS, sS, mS = frictionScales(wear)
        data.nodeSpikeOn = 1
        data.nodeContactCid = cid or 0
        data.nodeWearContact = wear
        data.nodeMuScale = fS
        data.nodeSlideScale = sS
        data.nodeMassScale = st and st.baseM and mS or 1.0
        data.nodeGate = gate or "idle"
        local wKey = wheelKey(wheelIndex)
        local nTouch = 0
        for _, ns in pairs(nodeState) do
            if wheelKey(ns.wheelIndex) == wKey and (ns.wear or 0) > 0.005 then
                nTouch = nTouch + 1
            end
        end
        if nTouch == 0 and (data.nodeWearPeak or 0) > 0.005 then
            nTouch = 1
        end
        data.nodeWearTouched = nTouch
        publishRingMap(data, wd, cid)
    end

    local function ensureNodeState(cid, wheelIndex)
        local st = nodeState[cid]
        if st then return st end
        local nd = v and v.data and v.data.nodes and v.data.nodes[cid]
        local baseF = 1.0
        local baseS = 1.0
        local baseM = nil
        if nd then
            baseF = tonumber(nd.frictionCoef) or 1.0
            baseS = tonumber(nd.slidingFrictionCoef) or baseF
            baseM = tonumber(nd.nodeWeight) or tonumber(nd.wheelNodeWeight)
        end
        if baseM == nil then
            local ok, m = pcall(function()
                return obj and obj.getNodeMass and obj:getNodeMass(cid)
            end)
            if ok and type(m) == "number" and m > 0 then baseM = m end
        end
        st = {
            baseF = max(0.05, baseF),
            baseS = max(0.05, baseS),
            baseM = (baseM and baseM > 0) and baseM or nil,
            wear = 0,
            dirty = false,
            wheelIndex = wheelKey(wheelIndex),
        }
        nodeState[cid] = st
        return st
    end

    local function applyNode(cid, st)
        if not obj or type(obj.setNodeFrictionSlidingCoefs) ~= "function" then return end
        local fScale = lerp(1.0, 0.52, st.wear)
        local sScale = lerp(1.0, 0.48, st.wear)
        pcall(function()
            obj:setNodeFrictionSlidingCoefs(cid, st.baseF * fScale, st.baseS * sScale)
        end)
        if st.baseM and type(obj.setNodeMass) == "function" then
            local mScale = lerp(1.0, 0.88, st.wear)
            pcall(function()
                obj:setNodeMass(cid, st.baseM * mScale)
            end)
        end
        st.dirty = true
    end

    local function addWear(cid, wheelIndex, rate, dt)
        if not cid or rate <= 0 or not dt or dt <= 0 then return 0 end
        local st = ensureNodeState(cid, wheelIndex)
        local r = softSatRate(rate, st.wear)
        st.wear = min(1.0, st.wear + r * dt)
        applyNode(cid, st)
        return st.wear
    end

    local function wheelPeakFor(wKey)
        local peak = 0
        for _, ns in pairs(nodeState) do
            if wheelKey(ns.wheelIndex) == wKey and (ns.wear or 0) > peak then
                peak = ns.wear
            end
        end
        return peak
    end

    local function restoreNode(cid, st)
        if not st or not obj then return end
        if type(obj.setNodeFrictionSlidingCoefs) == "function" then
            pcall(function()
                obj:setNodeFrictionSlidingCoefs(cid, st.baseF, st.baseS)
            end)
        end
        if st.baseM and type(obj.setNodeMass) == "function" then
            pcall(function()
                obj:setNodeMass(cid, st.baseM)
            end)
        end
    end

    local function publishOff(data, gate)
        if not data then return end
        data.nodeSpikeOn = ENABLE_NODE_WEAR_SPIKE and 1 or 0
        data.nodeGate = gate or "off"
        data.nodeContactCid = 0
        data.nodeWearContact = 0
        data.nodeWearPeak = data.nodeWearPeak or 0
        data.nodeMuScale = 1
        data.nodeSlideScale = 1
        data.nodeMassScale = 1
        data.nodeWearTouched = 0
        data.nodeOmega = 0
        if type(data.nodeWearRing) == "table" then
            for k in pairs(data.nodeWearRing) do data.nodeWearRing[k] = nil end
        else
            data.nodeWearRing = {}
        end
        data.nodeWearRingContact = 0
        data.nodeWearRingN = 0
        data.nodeWearRingFlip = 0
        data.nodeLockEnergySrc = "off"
        data.nodeCamEnergySrc = "off"
        data.nodeCamFrac = 0
        data.nodeCamColScale = 1
        data.nodeCamArmDeg = CAMBER_DEG_ARM
        -- Do not clear A3 here — air/off must keep peak-based Classic % until reset / spike off
    end

    F.resetNodeWearSpike = function()
        for cid, st in pairs(nodeState) do
            restoreNode(cid, st)
        end
        for k in pairs(nodeState) do nodeState[k] = nil end
        for _, data in pairs(tyreData) do
            if data then
                data.nodeWearPeak = 0
                publishOff(data, "idle")
                clearHudBridgeA3(data)
            end
        end
    end

    F.stepNodeWearSpike = function(dt)
        if isRemoteMpVehicle() then return end
        if not dt or dt <= 0 or dt > 0.25 then return end
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators then return end
        if not ENABLE_NODE_WEAR_SPIKE then
            for i, _ in pairs(wheels.wheelRotators) do
                local data = tyreData[i]
                publishOff(data, "off")
                clearHudBridgeA3(data)
            end
            return
        end

        for i, wd in pairs(wheels.wheelRotators) do
            local w = wheelCache[i]
            local data = tyreData[i]
            if w and data and not w.isAirborne and not w.isBroken then
                local cid = wd.lastTreadContactNode
                local slip = w.dynamicSlipEnergy or w.slipEnergy or 0
                local ang = abs(wd.angularVelocity or 0)
                local lockArm = cid and slip > 0.18 and ang < 14.0
                local armDeg = camberArmDegForWheel(data)
                local camAbs = abs(w.camber or 0)
                local camArm = cid and camAbs >= armDeg and (w.loadRaw or 0) > 800 and slip > 0.08
                local gate = "idle"
                if not cid then
                    gate = "no-node"
                elseif lockArm and camArm then
                    gate = "lock+cam"
                elseif lockArm then
                    gate = "lock"
                elseif camArm then
                    gate = "camber"
                end

                if lockArm then
                    local energyCid = cid
                    local rate = 0
                    local src = "slipE"
                    local usedCole = false
                    if ENABLE_LOCK_ENERGY_COLE then
                        local ps = getProbeState()
                        local peek = ps and ps.peek and ps.peek(wheelKey(i)) or nil
                        local slipF = peek and (peek.slipForceMax or 0) or 0
                        local slipHits = peek and (peek.slipHits or 0) or 0
                        local peakCid = peek and (peek.peakCid or 0) or 0
                        if slipF >= LOCK_SLIP_F_MIN and slipHits > 0 then
                            -- Map slipF → same slipCap shape as legacy slipE path
                            local slipCap = min(1.4, slipF / max(1.0, LOCK_SLIP_F_REF))
                            rate = LOCK_COL_RATE * min(1.45, max(0.15, slipCap) / 0.45)
                            if peakCid > 0 then energyCid = peakCid end
                            src = "cole"
                            usedCole = true
                        end
                    end
                    if not usedCole then
                        local slipCap = min(1.4, slip)
                        rate = 0.024 * min(1.45, slipCap / 0.45)
                        src = "slipE"
                    end
                    local loadN = max(200, w.loadRaw or wd.downForce or 2000)
                    rate = rate * min(1.30, loadN / 4000)
                    for _, tgt in ipairs(collectRingTargets(wd, energyCid, LOCK_RING_HALF_WIDTH)) do
                        addWear(tgt.cid, i, rate * tgt.weight, dt)
                    end
                    data.nodeLockEnergySrc = src
                else
                    data.nodeLockEnergySrc = "idle"
                end

                if camArm then
                    local treadNodes = wd.treadNodes
                    local camberFrac = camberFracFromDeg(w.camber, armDeg)
                    local slipFrac = min(1.15, min(1.2, slip) / 0.28)
                    local camSrc = "slipE"
                    if ENABLE_CAMBER_ENERGY_COLE then
                        local ps = getProbeState()
                        local peek = ps and ps.peek and ps.peek(wheelKey(i)) or nil
                        local slipF = peek and (peek.slipForceMax or 0) or 0
                        local slipHits = peek and (peek.slipHits or 0) or 0
                        if slipF >= CAMBER_SLIP_F_MIN and slipHits > 0 then
                            slipFrac = min(1.15, slipF / max(1.0, CAMBER_SLIP_F_REF))
                            camSrc = "cole"
                        end
                    end
                    local slickScale = camberColScaleForWheel(data, camberFrac)
                    local camBase = CAMBER_COL_BASE * slickScale * camberFrac * slipFrac
                    data.nodeCamFrac = camberFrac
                    data.nodeCamColScale = slickScale
                    data.nodeCamArmDeg = armDeg
                    local wheelDir = wd.wheelDir or 1
                    local camberDeg = (w.camber or 0) * wheelDir
                    local nRing = treadNodeCount(treadNodes)
                    if ENABLE_RING_WEAR and nRing > 0 then
                        for ringIdx, nid in ipairs(treadNodes) do
                            local wCam = camberNodeWeight(ringIdx, camberDeg, 1)
                            if wCam > 0.25 then
                                addWear(nid, i, camBase * wCam, dt)
                            end
                        end
                    elseif cid then
                        addWear(cid, i, camBase, dt)
                    end
                    data.nodeCamEnergySrc = camSrc
                else
                    data.nodeCamEnergySrc = "idle"
                    data.nodeCamFrac = 0
                    data.nodeCamColScale = camberColScaleForWheel(data, 0)
                    data.nodeCamArmDeg = armDeg
                end

                data.nodeWearPeak = wheelPeakFor(wheelKey(i))
                local st = cid and nodeState[cid] or nil
                publishDebug(data, cid, st, gate, i, wd)
                publishHudBridgeA3(data, wd)
                data.nodeOmega = ang
            elseif data then
                data.nodeWearPeak = wheelPeakFor(wheelKey(i))
                publishOff(data, (w and w.isAirborne) and "air" or "off")
                if wd then
                    publishHudBridgeA3(data, wd)
                else
                    local peak = data.nodeWearPeak or 0
                    local nodeCond = max(0, min(100, 100 * (1.0 - peak)))
                    local scalarCond = data.condition or 100
                    data.conditionScalar = scalarCond
                    data.conditionNode = nodeCond
                    data.condition = min(scalarCond, nodeCond)
                end
            end
        end
    end

    F.isNodeWearSpikeEnabled = function()
        return ENABLE_NODE_WEAR_SPIKE and true or false
    end

    F.isLockEnergyColeEnabled = function()
        return ENABLE_LOCK_ENERGY_COLE and true or false
    end

    F.isCamberEnergyColeEnabled = function()
        return ENABLE_CAMBER_ENERGY_COLE and true or false
    end
end

return M
