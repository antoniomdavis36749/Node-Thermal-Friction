-- Non-auto shim so short-name `extensions.tireWearThermals` resolves.
-- The live auto module is the traffic gate. The tire code is tireWearThermalsImpl.
-- Upstream authorship: see CREDITS.md / NOTICE.
local autoPath = "lua/vehicle/extensions/auto/tireWearThermals"
local existing = package.loaded[autoPath]
if type(existing) == "table" then
    return existing
end
return require(autoPath)
