-- License-plate logger for cars that do not have an AMD tune controller.
-- AMD cars keep their own amdTuneLog. Leave this plate off those cars.
-- Both controllers call ntfDevLog. A second step in the same sim tick does not
-- advance the kilometre. note() still writes a second set of circle rows.
-- Console tag [ntfPlateLog]. Rows go through ntfDevLog.

local M = {}

local devOk, devLog = pcall(require, "ntfDevLog")
if not devOk then devLog = nil end

M.type = "auxiliary"
M.defaultOrder = 90

local timer = 0
local logInterval = 1.0

local function init(jbeamData)
    logInterval = (jbeamData and jbeamData.logInterval) or 1.0
    timer = 0
    if devLog and devLog.begin then devLog.begin("ntfPlateLog") end
    log("I", "ntfPlateLog", string.format("ACTIVE (interval=%.1fs)", logInterval))
end

local function reset()
    timer = 0
    if devLog and devLog.reset then devLog.reset("ntfPlateLog") end
end

local function updateGFX(dt)
    if devLog and devLog.step then devLog.step(dt) end
    timer = timer + (dt or 0)
    if timer < logInterval then return end
    timer = 0
    if devLog and devLog.note then
        local note = devLog.note("ntfPlateLog")
        if note and note ~= "" then
            log("I", "ntfPlateLog", "NTF" .. note)
        end
    end
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M
