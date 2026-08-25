-- Read-only nodeCollision / slipForce probe for Pitwall energy A/B (Policy A — no wear writes).
local M = {}
M.type = "auxiliary"
M.defaultOrder = 910

local State = require("tireWearThermalsNodeProbeState")

local function nodeCollision(p)
    if not p or not p.id1 then return end
    State.recordCollision(p.id1, p)
end

local function init(_jbeamData)
end

local function reset(_jbeamData)
    -- Keep tread→wheel map; only clear energy session (map often built after init).
    State.resetSession()
end

M.init = init
M.reset = reset
M.nodeCollision = nodeCollision

return M
