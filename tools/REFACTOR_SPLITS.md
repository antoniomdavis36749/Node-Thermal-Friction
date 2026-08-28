# Tire Wear Thermals — structure splits (engineering reference)

**Reminder:** Follow this process. Do **not** rush hot-path splits. One cold module at a time, verify locals, sync `-dev`, respawn, smoke-test.

**V2 private tester `0.2.0` (Beta):** Public Repo update paused. Scalar flatspot removed.
Friction/node-wear ownership: `tools/V2_FRICTION_CONTRACT.md`.

---

## Why we split

BeamNG vehicle Lua runs under **LuaJIT’s ~200 register slots per function** (compile error at 201).  
`tools/scripts/Count-LuaLocals.py` counts **distinct local names** per scope (warns ≥190). That is a heuristic, not a 1:1 slot count — but scopes marked `* elevated` are the ones to watch.

**`do`/`end` blocks do NOT reset the 200 budget.** Only **new functions** do.

Goal: keep main `auto/tireWearThermals.lua` readable and every hot function safely under the limit, without changing locked calibration (Sport / Sport Plus / Track Day / Soft–Med–Hard) unless explicitly unlocked.

---

## Current module layout

```
lua/vehicle/extensions/
  auto/tireWearThermals.lua          orchestration + grip + ctw thermal + lifecycle
  tireWearThermalsProfiles.lua       profile tables / interpolate inputs
  tireWearThermalsSurface.lua        ground classify, surface bias
  tireWearThermalsAero.lua           native aero sample
  tireWearThermalsTelemetry.lua      CSV export
  tireWearThermalsClassify.lua       profile interpolate, tire part lookup
  tireWearThermalsPhysicsLoop.lua    prepareWheelFrame + runFixedPhysicsSteps (100 Hz)
  tireWearThermalsHud.lua            guiStream init/flush only
  tireWearThermalsDraft.lua          drafting / pack-air compat
  tireWearThermalsTemp.lua           temp nodes, bias weights, effective temp
  tireWearThermalsGround.lua         GetGroundModelData, blendGroundThermal, setGroundModels
  tireWearThermalsPressure.lua       native PSI, leak, hot writeback, TPMS/garage
  tireWearThermalsWear.lua           stint/damage + pressure/leak (wear integrator)
  tireWearThermalsNodeWear.lua       V2 experimental: clean-room contact-node wear spike
  tireWearThermalsWheel.lua          brake duct, JBeam factors, suspension, alignment, initTyreData
  tireWearThermals.lua               11-line shim
```

Main holds: `ctw` scratch table, thermal prepare/step, grip, `updateGFX`, lifecycle, installs.

See also: `tools/V2_FRICTION_CONTRACT.md`, `tools/V2_NODE_WEAR_SPIKE.md`.

---

## Module contracts (short)

Ownership for **Node-Thermal Friction** — keep changes inside the owning module unless a natural shared helper fits.

| Module | Owns | Must not |
| --- | --- | --- |
| `auto/tireWearThermals.lua` | Orchestration, grip, `ctw` thermal prepare/step, lifecycle, install order | Per-node μ/mass; second PSI writer |
| `…Profiles` | Compound tables / interpolate inputs | Runtime wear energy |
| `…Surface` / `…Ground` | Surface classify, ground LUT/blend | Node wear |
| `…Temp` / `…Draft` / `…Aero` | Temp nodes, pack-air, native aero sample | Friction writes |
| `…Classify` / `…Wheel` | Profile pick, JBeam/susp/align/init | Node spike |
| `…Pressure` | Native PSI, leak, hot writeback | Absolute overwrite of wheel μ |
| `…Wear` | Soft scalar tread/zones, grain/blister, stint fade | Node friction/mass |
| `…NodeWear` | Contact-node wear, ring, cole gates, A3 `min(scalar,node)` HUD | `setFrictionThermalSensitivity` |
| `…NodeProbe` (+ State / controller) | Read-only colE/slipF feed + Pitwall probe | Wear rates (except via cole peek) |
| `…PhysicsLoop` | `prepareWheelFrame` / fixed steps | New friction APIs |
| `…Hud` / `…Telemetry` | guiStream / CSV | Physics ownership |
| UI Classic / Crew / Pitwall | Display only | Second physics story |

**Friction policy A:** thermal core = wheel μ baseline; node layer = relative contact μ/mass only.

**Install order (do not reorder casually):**  
Ground → Pressure → Temp → Draft → Classify → Wheel → Wear → **NodeWear → NodeProbe** → PhysicsLoop → Hud → Telemetry.

New features only if they fit an existing row without a second absolute friction writer.

---

## Shared-state ownership

**Rule:** never rebind shared tables after install (`wheelCache = {}`, `brakeDuctSettings = {…}`). Clear **in place** (`for k in pairs(t) do t[k] = nil end`). Vehicle globals (`obj`, `v`, `wheels`) via getters, not frozen install snapshots. Live scalars that mutate (`ENV_TEMP`) via getters (`getEnvTemp`), not frozen numbers.

| Object | Writers | Cleared by | Clear style |
|--------|---------|------------|-------------|
| `wheelCache` | PhysicsLoop (`prepareWheelFrame`) | `F.clearSharedCaches` (onInit/onReset) | in place |
| `tyreGripTable` | PhysicsLoop / grip path | `F.clearSharedCaches` | in place |
| `baseBrakeCoolings` | main thermal duct path | `F.clearSharedCaches` | in place |
| `tyreData` | Wheel (`initTyreData`) | `initTyreData` (in place) | in place |
| `groundCache.lut` | Ground | `F.clearSharedCaches` / `setGroundModels` | in place (never rebind lut after install) |
| `groundCache.models` | Ground / GE mailbox | not wiped on soft reset | keep models |
| `classifyCache` fields | Classify / Wheel | `F.clearSharedCaches` (nil fields) | field reset |
| `brakeDuctSettings` | Wheel / GE mailbox | `F.clearSharedCaches` (reset slots) | in-place slot write |
| `guiStream` / `wheelIndexMap` | Hud | `initGuiStream` (map in place) | in place for map |
| `ctw` | `ctwPrepare*` / `ctwStep*` | overwritten each wheel tick | scratch bus — see contract below |
| `nativeAero` | Aero sample | `resetNativeAero` | field reset |
| `draft.*` | Draft / mailbox | onInit / unload | field reset |

`F.clearSharedCaches()` is the **only** owner of spawn/reset clears for the tables above that modules capture at install.

---

## Split history (safe order taken)

| Phase | Extracted | Main benefit |
|-------|-----------|--------------|
| 1 | Surface, Aero, Telemetry | Ground/aero/CSV off main |
| 2 | Classify, Hud, Draft, Temp | Cold init + HUD + temp helpers |
| 3 | Thermal integrator refactor | `ctwPrepareDriveGates`, `ctwPrepareThermals`, `ctwStepThermalNodes`, thin `ctwIntegrateThermals` |
| 4 | Ground, Pressure, Wear | Ground cache, PSI API, wear split damage vs pressure |
| 5 | Wheel + section headers | JBeam/suspension/alignment/init off main; navigable `====` blocks in main |

Main line count: ~4975 → ~4410 → ~3389 → ~2887 → **~2514**.

---

## Local counts (last verified)

Run after every split:

```powershell
python tools/scripts/Count-LuaLocals.py lua/vehicle/extensions/auto/tireWearThermals.lua
python tools/scripts/Count-LuaLocals.py lua/vehicle/extensions/tireWearThermalsPhysicsLoop.lua
python tools/scripts/Count-LuaLocals.py lua/vehicle/extensions/tireWearThermalsWear.lua
```

| Scope | ~Distinct locals | Notes |
|-------|------------------|-------|
| `ctwStepThermalNodes` | 159 | elevated — ~41 to hard cap; don’t split unless compile fails |
| `ctwPrepareThermals` | 156 | elevated — same |
| chunk (main) | 127 | elevated — hub locals; OK |
| `CalculateTyreGrip` | 108 | **hot path — do not split yet** |
| `ctwIntegrateWearDamage` | 89 | safe (in `tireWearThermalsWear.lua`) |
| `prepareWheelFrame` | 48 | safe (PhysicsLoop) |
| `ctwPrepareDriveGates` | 58 | safe |
| `ctwIntegrateWearPressure` | 36 | safe |
| `runFixedPhysicsSteps` | 19 | safe (PhysicsLoop) |
| `publishHudBridgeA3` | 24 | safe (`tireWearThermalsNodeWear.lua`) |

---

## Install pattern (required)

Each module:

```lua
local M = {}
function M.install(F, deps)
  -- assign F.someFunction = ...
end
return M
```

At end of main (after `local F = {}` and shared tables exist):

1. `require` the module near other requires.
2. Call `Module.install(F, { ...deps })` **before any `M.* = F.*` exports** and before `return M`.
3. **Order matters:** Ground → Pressure → Temp → Draft → Classify → Wheel → Wear → **PhysicsLoop** → Hud → Telemetry.
4. Pass shared state by reference (`groundCache`, `classifyCache`, `ctw`, closures for `vehicleMass` / `wheelCount` / `ENV_TEMP`).
5. Export to game API only where needed: `M.setGroundModels = F.setGroundModels` (after installs).

**Spawn-breaker (fixed 2026-08-19):** installs after `M.setGroundModels = F.setGroundModels` left exports nil and broke vehicle load.

Hud pitfall (fixed once): `wheelIndexMap = {}` must **clear in place** (`for k in pairs`) — don’t rebind the local inside install closure.

Hud pitfall (fixed 2026-08-19): extracted HUD code must not read main-chunk locals as globals (`THERMAL_TOPOLOGY`, `gfxAccumulator`, `drivenWheelCount`, `NATIVE_SLIP_*`, etc.) — pass via `deps`.

PhysicsLoop owns `prepareWheelFrame` / `runFixedPhysicsSteps`; Hud is stream-only (`initGuiStream` / `flushGuiStream`).

**Shared-table / nil pitfall (fixed 2026-08-19 → ice grip):** never rebind shared tables after install (`wheelCache = {}`, `brakeDuctSettings = {…}`). Clear in place. Vehicle globals (`obj`, `v`, `wheels`) must be read via getters (`getObj` / `getV` / `getWheels`), not frozen install snapshots — same pattern in Wheel, Hud, Pressure, Telemetry, PhysicsLoop.

Thermal pitfall (fixed once): `ctwPrepareThermals` must persist `vehicleSpeed`, `fwdSoftDamp`, `awdSoftDamp` to `ctw` before wear/grip read them (garage PSI gating, duty chips).

Wear pitfall: subfunctions need a **compact `ctw` reload** at the top (or direct `ctw.` access). Removing the reload without replacing references breaks runtime.

---

## Required `ctw` keys (Wear contract)

`ctwPrepareThermals` / `ctwStepThermalNodes` must populate these before Wear runs. Missing keys → wrong wear/PSI (often silent). Behind `DEBUG_THERMALS`, main validates once after the first prepare.

### Damage (`ctwIntegrateWearDamage`)

`avgWeightedTemp`, `current_optimal_temp`, `current_working_temp`, `tempDistWeighted`, `isAirborne`, `loadRaw`, `slipEnergy`, `sideSlipEnergy`, `g_mag`, `tyreWidthCoeff`, `propulsionTorque`, `brakeTorque`, `angularVel`, `wearRate`, `coldWearMult`, `hotWearMult`, `bottomOutSens`, `wLeft`, `wCenter`, `wRight`, `casing_compliance`, `contactDepth`, `rawJBeamTread`, `gmName`, `treadCoef`, `grainTempRatio`, `blisterTempRatio`, `tyreWidth`, `isRaining`, `isWetSurface`, `isDryPaved`, `isLooseSurface`, `isMudSurface`, `isSnowSurface`, `isSandSurface`, `isGravelSurface`, `isDirtGrassSurface`, `isIceSurface`, `vehNotParked`, `sf`, `groundModel`, `rollingWearCoef`, `dualContactBlend`, `dualRoughDelta`

### Pressure (`ctwIntegrateWearPressure`)

`avgWeightedTemp`, `current_optimal_temp`, `blisterTempRatio`, `vehicleSpeed`, `currentTempK`, `initialTempK`, `warmAbsolutePressurePSI`, `thermalAbsPSI`, `dynamicPressurePSI`, `avgCarcassTemp`

---

## Safe vs not-safe targets

### OK to extract (cold / init / optional)

- Ground model LUT + blend
- Pressure group helpers
- Wear damage vs wear pressure (natural break ~puncture/leak section)
- Telemetry, HUD, classify, draft, surface, aero, temp helpers
- New functions inside thermal path **only** when local count forces it

### Do NOT split yet (high risk / hot path)

- `CalculateTyreGrip` — runs every grip step; regression-sensitive
- Further split of `ctwStepThermalNodes` / `ctwPrepareThermals` unless compile or 201-slot error
- `updateGFX` orchestration without a full test matrix
- Anything that touches locked tire profiles or thermal topology without explicit unlock

---

## Process checklist (every split)

1. **Pick one cold boundary** — single responsibility, minimal deps.
2. **Extract** to `tireWearThermals*.lua` with `install(F, deps)`.
3. **Wire** require + install; delete duplicate from main.
4. **Run** `Count-LuaLocals.py` on main + new module.
5. **Compile-check** if lupa available; otherwise in-game load.
6. **Sync** to `-dev` unpack:
   `...\mods\unpacked\Tire-Wear-and-Thermals-ReSpin-dev\lua\vehicle\extensions\`
7. **Respawn** vehicle (Lua changes don’t hot-reload reliably).
8. **Smoke:** load car, drive 1 lap, check HUD temps/PSI/wear, no console errors.
9. **No commit** unless Anton asks.

---

## Optional next steps (when continuing)

- Soft-scalar Sport A/B **CLOSED** — mid-life center `SCALAR_TREAD_WEAR_SCALE` **0.15**;
  **mild rate curve on** (0.12→0.15→0.22 by scalar life) — Cond/leak only, A1 held
- Friction coherence **A1 CLOSED / LOCKED** — node owns contact μ; soft scalar =
  Cond/zones display + leak/puncture thresholds only; wearPenalty skipped while spike on
  (`tools/V2_FRICTION_CONTRACT.md`). Cond→grip fade (A2-curve) = **post-production**.
- **Lock cole energy CLOSED / LOCKED** — gates stay ω/slipE; rate from probe slipF;
  quiet-probe slipE fallback intentional (`tools/V2_NODE_WEAR_SPIKE.md`).
- **Camber accumulation CLOSED / rates LOCKED** (Bolide low-toe + GT3 Soft confirm;
  Soft louder than Sport — base rates held)
- **Soft life A3b CLOSED / LOCKED** — slick `col×` **0.05→0.14** + arm **2.0°**;
  GT3 Soft/Med/Hard Belasco 22 km Soft≈Med≈Hard on node Cond — **ladder CLOSED**.
- Second-car **cole smoke CLOSED** (Nightsnake 5-row) — Phase 3 friction exit checks done
- **Private tester pack `0.2.0` (Beta)** — checklist + zip ready; public Repo still paused
- **Drift prototype** — gate `drift` + undriven camber mute; rate **0.022** — revisit with
  tester drift sessions (not locked)
- Grip refactor — **only** with regression scripts + tester sign-off
- Further hot-path splits — **only** if LuaJIT 201-local compile forces it
- **Lua locals audit 2026-08-25** — `ctwStepThermalNodes` 159 / `ctwPrepareThermals` 156 /
  chunk 127 / grip ~108; all under warn (≥190). No further peel this pass.
- Pitwall polish: A1 `sc|nd` stream + ABS?/cole→slipE capture hints (GT3 edge aid)


---

## Related docs

- `RELEASE_CHECKLIST_TESTERS.md` — pre-tester zip smoke
- `tools/V2_FRICTION_CONTRACT.md` — friction policy A + coherence A1
- `tools/V2_NODE_WEAR_SPIKE.md` — node spike + soft scalar flags
- `tools/scripts/Count-LuaLocals.py` — local scope audit
- `tools/scripts/Pack-Release.ps1` — release zip

---

*Last updated: 2026-08-27 (private tester 0.2.0 Beta; Soft/Med/Hard ladder CLOSED).*
