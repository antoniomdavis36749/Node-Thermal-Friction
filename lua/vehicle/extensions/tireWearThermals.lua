-- Non-auto shim so short-name `extensions.tireWearThermals` resolves.
-- Real implementation: lua/vehicle/extensions/auto/tireWearThermals.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- (auto/ is loaded via loadModulesInDirectory → loadAtRoot(..., ""); short-name
-- lazy-load only searches lua/vehicle/extensions/<name>.lua — not auto/).
local autoPath = 'lua/vehicle/extensions/auto/tireWearThermals'
local existing = package.loaded[autoPath]
if type(existing) == 'table' then
  return existing
end
return require(autoPath)
