# V2 friction ownership contract

Internal experimental rule. Clean-room node wear later must obey this.

## Goal

One grip story: thermal-core (heat, PSI, compounds, surfaces) plus
future node wear (local contact damage). Never two absolute friction writers.

## Owners

| Layer | Owns | Must not |
| --- | --- | --- |
| **Thermal core** (current ReSpin) | Skin/carcass/rim/air temps, ducts, PSI, compound curves, surface bias, wheel-level baseline μ via `setFrictionThermalSensitivity` | Per-node mass, local flat geometry, a second thermal model |
| **Node wear** (future, clean-room) | Per-tread-node wear energy, relative contact friction/mass, flats / camber scallop feel | Second PSI model, second full thermal sim, absolute overwrite of wheel μ without reading thermal baseline |
| **UI** | Pitwall thermals + (later) wear map | Two competing tire apps as the default story |

## Friction policy (pick before node spike)

**Preferred for V2 merge:** Policy A

- **A — Thermal baseline, node relative:** Thermal core writes wheel long/lat/mid.
  Node wear multiplies **contact-node** friction/mass by wear scales (0–1).
  Nodes never call `setFrictionThermalSensitivity`.
- **B — Nodes own contact:** Thermal core publishes modifiers only (temps → factors).
  Node layer applies absolute contact friction. Thermal must stop writing wheel μ.

Do not run A and B mixed. Do not run ReSpin wheel μ + any third-party node-wear mod.

## Clean-room

Node wear is designed from BeamNG docs/APIs and in-house tests only.
No copy or port from other node-based tire mods.

## Current experimental pack (Phase 0–1 + node spike)

- Scalar **flatspot removed**.
- Scalar **tread/zone wear off** (`ENABLE_SCALAR_TREAD_WEAR = false`) — thermal-first.
- Grain / blister still thermal-side.
- **Brake lock fade disabled** — native lock.
- **Node wear spike on** (`ENABLE_NODE_WEAR_SPIKE`) — Policy A tread-ring
  friction/mass (Phase 2: `wd.treadNodes` sector). See `tools/V2_NODE_WEAR_SPIKE.md`.
- **A3 Classic + Crew HUD bridge** — `condition` / `zoneCondition` mirror node
  peak / O\|M\|I for display only; grip wearPenalty ignores them while spike is on.
- Public Repo release deprioritized; `-dev` + private MP / small group first.

## Lock policy

- Native pressureWheel + vehicle brakes decide lock / ABS.
- ReSpin may only change grip via thermal/wear/surface scales written once per
  wheel through `setFrictionThermalSensitivity`.
- Do not reintroduce pedal / gx / brakeTorque μ collapses for production.
- If no-ABS cars cannot lock vs stock, tune compound / frictionCoef coupling —
  do not turn lock fade back on as the fix.

## Exit check before Phase 3 merge

- [ ] One written policy (A or B) chosen
- [ ] Single vehicle spike: contact energy → node wear → feel, no foreign code
- [ ] Thermal and node layers do not both absolute-write μ
- [ ] Pitwall shows one coherent story
