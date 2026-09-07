# V2 friction ownership contract

Internal experimental rule. Clean-room node wear later must obey this.

## Goal

One grip story: thermal-core (heat, PSI, compounds, surfaces) plus
future node wear (local contact damage). Never two absolute friction writers.

## Owners

| Layer | Owns | Must not |
| --- | --- | --- |
| **Thermal core** (current Node-Thermal Friction) | Skin/carcass/rim/air temps, ducts, PSI, compound curves, surface bias, wheel-level baseline μ via `setFrictionThermalSensitivity` | Per-node mass, local flat geometry, a second thermal model |
| **Node wear** (future, clean-room) | Per-tread-node wear energy, relative contact friction/mass, flats / camber scallop feel | Second PSI model, second full thermal sim, absolute overwrite of wheel μ without reading thermal baseline |
| **UI** | Pitwall thermals + (later) wear map | Two competing tire apps as the default story |

## Friction policy (pick before node spike)

**Preferred for V2 merge:** Policy A

- **A — Thermal baseline, node relative:** Thermal core writes wheel long/lat/mid.
  Node wear multiplies **contact-node** friction/mass by wear scales (0–1).
  Nodes never call `setFrictionThermalSensitivity`.
- **B — Nodes own contact:** Thermal core publishes modifiers only (temps → factors).
  Node layer applies absolute contact friction. Thermal must stop writing wheel μ.

Do not run A and B mixed. Do not run Node-Thermal Friction wheel μ + any third-party node-wear mod.

## Clean-room

Node wear is designed from BeamNG docs/APIs and in-house tests only.
No copy or port from other node-based tire mods.

## Current private tester pack (0.2.0 Beta — Phase 0–1 + node spike)


**Friction coherence A1 LOCKED** — Node owns contact scallop feel (relative μ/mass).
HUD Cond = `min(scalar, node)` display hybrid.

**A2 mild scalar grip fade ON** (`ENABLE_SCALAR_GRIP_FADE`, default **true**) —
while spike on, `wearPenalty` fades from **`scalarTreadCondition` only** (life clock;
never HUD `min(sc,nd)` or node peak). Shape: full grip until `lifeUsed ≥ 0.30` (**sc &lt; 70%**), then
soft fade to floor **0.70** at life≈1 (**LOCKED** 2026-09-06; was mild 0.90). Spike off keeps legacy
condition→wearPenalty. A/B: set flag false.

- Scalar **flatspot removed**.
- Soft **scalar tread/zone wear on** (`ENABLE_SCALAR_TREAD_WEAR`, mid-life scale **0.15** +
  mild **rate curve** 0.12→0.15→0.22 from `scalarTreadCondition`) — HUD uses
  `min(scalar, node)`; node spike owns contact μ; A2 adds mild stint-life fade from
  scalar only. Leak / puncture may still use Cond thresholds as today.
- Grain / blister still thermal-side.
- **Brake lock fade disabled** — native lock.
- **Node wear spike on** (`ENABLE_NODE_WEAR_SPIKE`) — Policy A tread-ring
  friction/mass (Phase 2: `wd.treadNodes` sector). See `tools/V2_NODE_WEAR_SPIKE.md`.
- **A3 Classic + Crew HUD bridge** — `condition` / `zoneCondition` mirror node
  peak / O\|M\|I for display; A2 grip fade ignores those fields (scalar life only).
- **`nodeWearScale`** — PROFILE_POINTS performance band **CLOSED / LOCKED**: Plus **1.10** →
  Track Day / Sport **1.0** → Standard **0.82 / 0.75**. Lock/cam/drift × scale. Separate from scalar `sc`.
- Public Repo update deprioritized; private tester **`0.2.0` (Beta)** + `-dev` / small group first.

## Lock policy

- Native pressureWheel + vehicle brakes decide lock / ABS.
- Node-Thermal Friction may only change grip via thermal/wear/surface scales written once per
  wheel through `setFrictionThermalSensitivity`.
- Do not reintroduce pedal / gx / brakeTorque μ collapses for production.
- If no-ABS cars cannot lock vs stock, tune compound / frictionCoef coupling —
  do not turn lock fade back on as the fix.

## Exit check before Phase 3 merge

- [x] One written policy (A or B) chosen — **Policy A** + **Friction coherence A1**
- [x] Spike feel across cars: Bolide (lock/peak tune) + **Nightsnake** cole 5-row matrix
  (park → lock → hold → cruise ~40 → reset); front lock wear a bit hotter than Bolide
  teens band — note only, no rate change. Clean-room / no foreign code.
- [x] Thermal and node layers do not both absolute-write μ (thermal = wheel baseline; node = relative contact)
- [x] Pitwall shows one coherent story (Cond = display hybrid `min(scalar,node)`; grip = thermal + node relative μ + mild A2 scalar-life fade)
