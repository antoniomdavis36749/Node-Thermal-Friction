# V2 friction ownership contract

Internal experimental rule. Clean-room node wear later must obey this.

Live procedure and the open A/B: `tools/VERIFICATION.md`. Read it before a drive or a retune.

## Goal

One grip story: thermal-core (heat, PSI, compounds, surfaces) plus
future node wear (local contact damage). Never two absolute friction writers.

## Owners

| Layer | Owns | Must not |
| --- | --- | --- |
| **Thermal core** (current Node-Thermal Friction) | Skin/carcass/rim/air temps, ducts, PSI, compound curves, surface bias, wheel-level baseline μ via `setFrictionThermalSensitivity` | Per-node mass, local flat geometry, a second thermal model |
| **Node wear** (Policy A, live) | Per-tread-node wear energy, relative contact friction/mass, flats / camber scallop feel | Second PSI model, second full thermal sim, absolute overwrite of wheel μ without reading thermal baseline |
| **UI** | Pitwall thermals + (later) wear map | Two competing tire apps as the default story |

## Friction policy (pick before node spike)

**Preferred for V2 merge:** Policy A

- **A — Thermal baseline, node relative:** Thermal core writes one wheel multiplier,
  `(longGrip + latGrip) / 2`, to all three `setFrictionThermalSensitivity` slots. Those
  slots are BeamNG temperature bands, not axes, so there is no per-axis grip.
  Node wear multiplies **contact-node** friction/mass by wear scales (0–1).
  Nodes never call `setFrictionThermalSensitivity`.
- **B — Nodes own contact:** Thermal core publishes modifiers only (temps → factors).
  Node layer applies absolute contact friction. Thermal must stop writing wheel μ.

Do not run A and B mixed. Do not run Node-Thermal Friction wheel μ + any third-party node-wear mod.

## Phase 1 native correctness — LOCKED 2026-09-26

Smoked on Scintilla GT3 and a normal car. Do not reopen without a new Belasco miss.

- Brake heat, wear, and gates read `wd.brakingTorque` (applied), not `wd.brakeTorque` (capacity).
- One wheel friction coefficient, `(longGrip + latGrip) / 2`. BeamNG's three slots are temperature bands.
- `frictionCoef` and JBeam load sensitivity stay with BeamNG. NTF level is `gripLevelScale` **0.80**. Drag `gripMultiplier` **1.32**.
- Shoulder heat follows each wheel's slip angle and standard camber (`camberStd`). Chassis G does not pick a shoulder.
- Street residual-slip soft-cap stays **off** until a dedicated A/B.

## Phase 2 tire-normalized inputs — CODED 2026-09-26, GT3 smoke passed

Scintilla GT3 smoke passed (tip-over, still feels natural). FWD hard exits with damps on: small drive-tire heat bump, like RWD (smoke). Street heat is logged at 26.8 km on the balanced Corse (`tools/output/corse-street-bank-telemetry.csv`): both temperatures plateaued by 10 km, and native temperature stayed a second thermometer. Layout damp stays on after the FWD medium-slick A/B. Stick flex fade is logged: zero above slip ratio 0.30 (`tools/history/LOCKS.md`). Drag `longGripMult` 1.18 held on two Burnside launches. Locked-band outputs are in `tools/golden/locked-bands.txt`. The open card is stripping NodeProbe from the release zip (`tools/VERIFICATION.md`).

Unchanged on an even four-wheel 1500 kg car with 0.33 m wheels; other cars move toward per-tire physics.

- Axles and front/rear come from hub positions along the car (`axleGroupGapM`), not wheel names.
- Each tire keeps its own static load (`data.staticLoadN`), settled below `staticLoadMaxSpeed`.
- Sliding wear load term = `slideWearLoadShare` × load / own static load (was load / vehicle mass).
- Blister cornering work = the wheel's slip angle × its share of the axle load (was chassis G).
- Drive Nm gates × radius × static load / `driveRefWheelNm` (was √mass). `driveLayoutDampEnable`
  A/Bs the FWD/AWD Soft and AWD excess damps.
- Stick flex fades out between native slip ratio `stickFlexSlipRatioFull` and `Zero`.
- Hydroplaning reads hub ground speed; the chassis-G convection bonus is gone.
- Tip-over lateral cut compares the tire with its axle's mean load (`tipOverLoadRef = "axle"`).

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
