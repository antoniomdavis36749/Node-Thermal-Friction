-- scripts/tireWearThermals/modScript.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- BeamNG 0.39: native interAero coexists with companion draft (vehicle ext gates convection).
-- HUD Apps still use Angular host; vehicle publishes via queueStream (0.39+) or trigger fallback.
log("I", "tireWearThermals", "Executing modScript initialization (0.39-compatible)...")

load("tireWearThermals")
setExtensionUnloadMode("tireWearThermals", "manual")

load("createbrakeductsliders")
setExtensionUnloadMode("createbrakeductsliders", "manual")

-- Dev-only West Coast lap / telemetry harness is NOT loaded in player builds.
-- Keep lua/ge/extensions/tireWestCoastLapTest.lua in the git tree for tools/, but
-- omit it from Pack-Release.ps1 so Repo installs stay clean.
