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
   `...\mods\unpacked\Node-Thermal-Friction-dev\lua\vehicle\extensions\`
7. **Respawn** vehicle (Lua changes don’t hot-reload reliably).
8. **Smoke:** load car, drive 1 lap, check HUD temps/PSI/wear, no console errors.
9. **No commit** unless Anton asks.

---

## Optional next steps (when continuing)

- Soft-scalar Sport A/B **CLOSED** — mid-life center `SCALAR_TREAD_WEAR_SCALE` **0.15**;
  **mild rate curve on** (0.12→0.15→0.22 by scalar life) — Cond/leak + A2 fade source
- Friction coherence **A1 CLOSED / LOCKED** — node owns contact μ; soft scalar =
  Cond/zones display + leak/puncture thresholds; baseline grip ignores HUD Cond while spike on
  (`tools/V2_FRICTION_CONTRACT.md`)
- **A2 mild scalar grip fade ON** — `ENABLE_SCALAR_GRIP_FADE` default true; `lifeUsed ≥ 0.30`
  (**sc &lt; 70%**) → floor **0.70 LOCKED** from `scalarTreadCondition` only (`tools/V2_NODE_WEAR_SPIKE.md`)
- **Drag CLOSED / LOCKED** — `longGripMult` **1.18** (native PASS + ~1400 hp mod launch;
  rear long ~151%).
- **Wet CLOSED / LOCKED** — ASPHALT_WET park/accel/brake/cruise **PASS / no nudge**.
- **Street heat REOPENED (2026-09-10)** — tester: abuse overshoot too aggressive.
  Cut **`workHeatRate` ~12%** on `PROFILE_POINTS` (cornering/load); **`slipHeatRate` /
  `rollingRes` held** (straight rolling good). Wear locks held. Confirm: cruise settle
  vs prior; loaded corners milder Hot ceiling.
- **Slick heat REOPENED (2026-09-10)** — same dial-back on `SLICK_SPECTRUM_POINTS`
  `workHeatRate` ~12%; slip/rolling held. Soft/Med/Hard wear+scalar locks held.
- **ROUND-2 heat REOPEN (fleet mid-corner)** — spread cut, not a second work-only gut.
  Topology: g→slip **0.15→0.11**, work coef **0.145→0.135**, `patchUtilPeakHi` **1.40→1.28**,
  `patchUtilBlend` **0.20→0.16**, vertical carcass **0.55→0.48**. Profiles (same 2026-09-10
  cohort: Plus / Track Day / Sport + slick C2–C5): **`workHeatRate` −5%** + **`slipHeatRate`
  −5%** each; rolling/wear held. Rally/winter/drift/utility untouched. Soft-sim gate
  `Test-CornerLoadHeat.ps1` PASS (cruise flat; low-camber/high-util −10…−15%). Camber-proxy
  = slip+load (no dCamber/dt heat). GT3 is not the fleet heat reference car.
- **ROUND-3 heat REOPEN (fleet lateral-G)** — additional slip-weighted cut on live Round-2.
  Topology: g→slip **0.11→0.08**, work coef **0.135→0.128**, `patchUtilPeakHi` **1.28→1.20**,
  `patchUtilBlend` **0.16→0.12**, vertical carcass **0.48→0.42**, velCool g-penalty
  `min(0.18,(g-0.20)*0.22)` → `min(0.12,(g-0.20)*0.14)`. Same cohort: **`slipHeatRate` −6%**
  + **`workHeatRate` −3%**; rolling/wear/A2/`nodeWearScale` held. Rally/winter/drift/utility
  untouched. Soft-sim `Test-CornerLoadHeat.ps1` PASS vs R2 (cruise |d|≤2%; low-camber
  −8…−12%; near-max util pass; GT3 INFO). Tester: ETK / low-camber street outside tire;
  GT3 smoke only.
- **Lock cole energy CLOSED / LOCKED** — gates stay ω/slipE; rate from probe slipF;
  quiet-probe slipE fallback intentional (`tools/V2_NODE_WEAR_SPIKE.md`).
- **Camber accumulation CLOSED / rates LOCKED** (Bolide low-toe + GT3 Soft confirm;
  Soft louder than Sport — base rates held)
- **Soft life A3b CLOSED / LOCKED** — slick `col×` **0.08→0.22** + arm **2.0°**
- **A2 EOL fade LOCKED** — floor **0.70** (2026-09-06; med+soft ~68 km A2×0.85 @ sc~35%)
- **Med/Hard 22 km CLOSED** — Soft≈Med≈Hard on node Cond under then-shared slick curve —
  **ladder CLOSED** (do not retune A3b from Hard).
- Second-car **cole smoke CLOSED** (Nightsnake 5-row) — Phase 3 friction exit checks done
- **Private tester pack `0.2.0` (Beta)** — checklist + zip ready; public Repo still paused
- **Track Day camber CLOSED / LOCKED** — col× **0.26→0.40**; 22 km fronts ~92% / peak ~8%
- **Sport Plus camber CLOSED / LOCKED** — col× **0.30→0.45**; 22 km fronts ~90% / peak ~6–11%
- **Sport camber CLOSED / LOCKED** — col× **0.40→0.58**; 22 km fronts ~93–94% / peak ~3–7%
- **Standard camber CLOSED / LOCKED** — col× **0.52→0.68** (est. from 22 km ×1.0 Cond ~85–88%)
- **Vintage camber CLOSED / LOCKED** — col× **0.58→0.74** (est. mild, street-ward of Standard)
- **Truck/commercial camber CLOSED / LOCKED** — col× **0.62→0.78** (est. mild)
- **Commercial PSI hot tgt** — `seedHotTargetPSI` from native cold fill per pressure
  group (spectrum `optimalPressure` = design; drag rear ~82 no longer forced to 110)
- **Commercial leftovers CLOSED** (2026-08-30) — feel OK; no further commercial band work
- **Slick scalar life** — C5 **4.7** / C4 **4.7 LOCKED** (~37 km fronts sc~70% sc-led).
  C3 **9.3** / C2 **6.4** predictive OPEN. Mid anchors follow spectrum lerp.
- **Street scalar life** — performance band **CLOSED / LOCKED**: Plus **0.19** / TD **0.20** /
  Sport **0.15** / Standard **0.45/0.33**. Secondary `sc` clock (TD 108 km sc~99%); feel =
  `nodeWearScale`. Off-band placeholders REVIEW later.
- **Node wear scale** — `nodeWearScale` on **PROFILE_POINTS** performance band only;
  Sport **1.0** / Plus **1.10** / Track Day **1.0** / Standard **0.82/0.75 LOCKED** (band CLOSED).
- **Drift prototype** — gate `drift` on **drift compound OR plain Sport**; undriven camber
  mute; rate **0.017** provisional. **HELD / non-blocking** — feel revisit only if
  tester feedback lands (may not before next drop)
- **A2 feel** — EOL floor **0.70 LOCKED**; Pitwall **sc%/nd%** + **A2×**
- Grip refactor — **only** with regression scripts + tester sign-off
- Further hot-path splits — **only** if LuaJIT 201-local compile forces it
- **Lua locals audit 2026-08-25** — `ctwStepThermalNodes` 159 / `ctwPrepareThermals` 156 /
  chunk 127 / grip ~108; all under warn (≥190). No further peel this pass.
- Pitwall polish: A1 `sc|nd` stream + ABS?/cole→slipE capture hints (GT3 edge aid)


---

## Related docs

- `RELEASE_CHECKLIST_TESTERS.md` — pre-tester zip smoke
- `tools/V2_FRICTION_CONTRACT.md` — friction policy A + coherence A1 + A2 fade
- `tools/V2_NODE_WEAR_SPIKE.md` — node spike + soft scalar flags + open-band protocols
- `tools/scripts/Count-LuaLocals.py` — local scope audit
- `tools/scripts/Pack-Release.ps1` — core release zip (no vehicles/, no Pitwall)
- `tools/scripts/Pack-Compat-Release.ps1` — Compat Tires zip (vehicles/ only)
- `tools/SPECTRA_STATUS.md` — locked vs provisional spectra

---

*Last updated: 2026-09-21 (round-3 fleet lateral-G REOPEN — topology + street/slick slip −6% / work −3%).*
