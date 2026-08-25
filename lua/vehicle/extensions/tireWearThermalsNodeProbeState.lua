-- Shared accumulators for tireWearThermalsNodeProbe controller (read-only energy A/B).
local M = {}

local abs = math.abs

local enabled = true
local treadWheel = {}
local buckets = {}
local holds = {}
local treadMapCount = 0

local function wheelKey(wheelIndex)
    return tonumber(wheelIndex) or wheelIndex
end

local function freshBucket()
    return {
        hits = 0,
        slipHits = 0,
        slipForceMax = 0,
        slipVelMax = 0,
        normalForceMax = 0,
        depthMax = 0,
        energySum = 0,
        peakCid = 0,
        peakEnergy = 0,
    }
end

local function freshHold()
    return {
        hits = 0,
        slipHits = 0,
        slipForceMax = 0,
        slipVelMax = 0,
        normalForceMax = 0,
        depthMax = 0,
        energySum = 0,
        energyMaxWin = 0,
        peakCid = 0,
        peakEnergy = 0,
    }
end

function M.setEnabled(on)
    enabled = not not on
end

function M.isEnabled()
    return enabled
end

function M.treadMapSize()
    return treadMapCount
end

-- Session counters only (keep tread→wheel map across controller reset).
function M.resetSession()
    for k in pairs(buckets) do buckets[k] = nil end
    for k in pairs(holds) do holds[k] = nil end
end

function M.resetAll()
    for k in pairs(treadWheel) do treadWheel[k] = nil end
    for k in pairs(buckets) do buckets[k] = nil end
    for k in pairs(holds) do holds[k] = nil end
    treadMapCount = 0
end

local function addTreadCid(cid, wKey)
    if not cid then return end
    if treadWheel[cid] == nil then
        treadWheel[cid] = wKey
        treadMapCount = treadMapCount + 1
    end
end

function M.rebuildTreadMap(getWheels)
    for k in pairs(treadWheel) do treadWheel[k] = nil end
    treadMapCount = 0
    local wheels = getWheels and getWheels()
    if not wheels then return end

    local function ingestWheel(wIdx, wd)
        if not wd then return end
        local wKey = wheelKey(wIdx)
        local treadNodes = wd.treadNodes
        if not treadNodes then return end
        -- Prefer ipairs (1-based); also walk pairs for sparse / 0-based tables
        local nIpairs = 0
        for _, cid in ipairs(treadNodes) do
            addTreadCid(cid, wKey)
            nIpairs = nIpairs + 1
        end
        if nIpairs == 0 then
            for _, cid in pairs(treadNodes) do
                if type(cid) == "number" then
                    addTreadCid(cid, wKey)
                end
            end
        end
    end

    if wheels.wheelRotators then
        for wIdx, wd in pairs(wheels.wheelRotators) do
            ingestWheel(wIdx, wd)
        end
    end
    -- Some vehicles only fill wheels.wheels; don't double-count same cids
    if treadMapCount == 0 and wheels.wheels then
        for wIdx, wd in pairs(wheels.wheels) do
            ingestWheel(wIdx, wd)
        end
    end
end

-- Rebuild only if empty (init often runs before treadNodes are ready).
function M.ensureTreadMap(getWheels)
    if treadMapCount > 0 then return treadMapCount end
    M.rebuildTreadMap(getWheels)
    return treadMapCount
end

local function bucketFor(wKey)
    local b = buckets[wKey]
    if not b then
        b = freshBucket()
        buckets[wKey] = b
    end
    return b
end

local function holdFor(wKey)
    local h = holds[wKey]
    if not h then
        h = freshHold()
        holds[wKey] = h
    end
    return h
end

local function resolveWheelKey(cid)
    local mapped = treadWheel[cid]
    if mapped ~= nil then return mapped end
    -- Fallback: BeamNG nodes carry wheelID (same path wheels.lua uses)
    local node = v and v.data and v.data.nodes and v.data.nodes[cid]
    if node and node.wheelID ~= nil then
        return wheelKey(node.wheelID)
    end
    return nil
end

function M.recordCollision(cid, p)
    if not enabled or not cid or not p then return end
    local wKey = resolveWheelKey(cid)
    if not wKey then return end

    local mat1 = p.materialID1 or p.materialID or 0
    local mat2 = p.materialID2 or 0
    if mat1 == 4 and mat2 == 4 then return end

    local slipF = p.slipForce or 0
    local slipV = p.slipVel or 0
    local normalF = p.normalForce or 0
    local depth = p.depth or 0
    local energy = slipF * abs(slipV)

    local b = bucketFor(wKey)
    b.hits = b.hits + 1
    if slipF > 0 then
        b.slipHits = b.slipHits + 1
    end
    if slipF > b.slipForceMax then
        b.slipForceMax = slipF
        b.peakCid = cid
    end
    if abs(slipV) > b.slipVelMax then
        b.slipVelMax = abs(slipV)
    end
    if normalF > b.normalForceMax then
        b.normalForceMax = normalF
    end
    if depth > b.depthMax then
        b.depthMax = depth
    end
    b.energySum = b.energySum + energy
    if energy > b.peakEnergy then
        b.peakEnergy = energy
    end
end

local function mergeHold(h, snap)
    h.hits = h.hits + (snap.hits or 0)
    h.slipHits = h.slipHits + (snap.slipHits or 0)
    h.energySum = h.energySum + (snap.energySum or 0)
    if (snap.energySum or 0) > h.energyMaxWin then
        h.energyMaxWin = snap.energySum or 0
    end
    if (snap.slipForceMax or 0) > h.slipForceMax then
        h.slipForceMax = snap.slipForceMax
        if snap.peakCid and snap.peakCid > 0 then
            h.peakCid = snap.peakCid
        end
    end
    if (snap.slipVelMax or 0) > h.slipVelMax then
        h.slipVelMax = snap.slipVelMax
    end
    if (snap.normalForceMax or 0) > h.normalForceMax then
        h.normalForceMax = snap.normalForceMax
    end
    if (snap.depthMax or 0) > h.depthMax then
        h.depthMax = snap.depthMax
    end
    if (snap.peakEnergy or 0) > h.peakEnergy then
        h.peakEnergy = snap.peakEnergy
        if snap.peakCid and snap.peakCid > 0 then
            h.peakCid = snap.peakCid
        end
    end
end

-- Live bucket for gated wear (call before snapshotAndClear in the same GFX tick).
function M.peek(wKey)
    local b = buckets[wKey]
    if not b then
        return freshBucket()
    end
    return {
        hits = b.hits,
        slipHits = b.slipHits,
        slipForceMax = b.slipForceMax,
        slipVelMax = b.slipVelMax,
        normalForceMax = b.normalForceMax,
        depthMax = b.depthMax,
        energySum = b.energySum,
        peakCid = b.peakCid,
        peakEnergy = b.peakEnergy,
    }
end

function M.snapshotAndClear(wKey)
    local b = buckets[wKey]
    local snap
    if not b then
        snap = freshBucket()
    else
        snap = {
            hits = b.hits,
            slipHits = b.slipHits,
            slipForceMax = b.slipForceMax,
            slipVelMax = b.slipVelMax,
            normalForceMax = b.normalForceMax,
            depthMax = b.depthMax,
            energySum = b.energySum,
            peakCid = b.peakCid,
            peakEnergy = b.peakEnergy,
        }
        buckets[wKey] = freshBucket()
    end
    local h = holdFor(wKey)
    if (snap.hits or 0) > 0 or (snap.slipForceMax or 0) > 0 or (snap.energySum or 0) > 0 then
        mergeHold(h, snap)
    end
    return snap, h
end

function M.getHold(wKey)
    return holdFor(wKey)
end

return M
