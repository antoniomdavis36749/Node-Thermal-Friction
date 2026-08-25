# V2 node-wear spike (experimental)

Clean-room layer. BeamNG APIs only. No ports from third-party node-wear mods.

## Flags

| Flag | File | Default | Role |
| --- | --- | --- | --- |
| `ENABLE_SCALAR_TREAD_WEAR` | `tireWearThermalsWear.lua` | **false** | Thermal-first: freeze tread% / zones at 100 |
| `ENABLE_NODE_WEAR_SPIKE` | `tireWearThermalsNodeWear.lua` | **true** | Contact-node friction/mass wear |
| `ENABLE_RING_WEAR` | same | **true** | Phase 2 sector spread on tread ring |
| `ENABLE_HUD_BRIDGE_A3` | same | **true** | Classic + Crew condition + O\|M\|I from node peak/ring |
| `ENABLE_LOCK_ENERGY_COLE` | same | **true** | Lock wear rate+cid from probe slipF (gates stay ω/slipE) |
| `ENABLE_CAMBER_ENERGY_COLE` | same | **true** | Camber scallop slip term from probe slipF (geometry unchanged) |
| `ENABLE_NODE_COLLISION_PROBE` | `tireWearThermalsNodeProbe.lua` | **true** | Read-only Pitwall colE / slipF (+ feeds gated swap) |
| `ENABLE_BRAKE_LOCK_FADE` | `auto/tireWearThermals.lua` | **false** | Lock stays native |

Grain / blister remain thermal-side for now.

## Friction policy (A)

- Thermal core: `setFrictionThermalSensitivity` (compound × temp × …).
- Node spike: `obj:setNodeFrictionSlidingCoefs` + mild `obj:setNodeMass` on
  tread-ring nodes (contact + neighbors). Never writes wheel-level friction API.

## Energy (spike)

Uses wheel `slipEnergy` / `dynamicSlipEnergy` while contact node is set and
ω is low (lock/scrub) or camber is high. Good enough to feel a flat after a
hard lock. Finer `nodeCollision` / `p.slipForce` can come later via an optional
vehicle controller — not required for this spike.

## Rates (LOCKED baseline — private spike)

Tuned live vs Bolide lock captures (too fast → 100%; too slow → 1%; landed ~9–14%
after a typical lock). Soft-sat only after **35%** wear.

| Term | Value |
| --- | --- |
| Lock/scrub base | `0.024 * min(1.45, slipCap/0.45)` · `slipCap = min(1.4, slip)` |
| Load scale | `min(1.30, loadN/4000)` |
| Soft-sat | if wear > 0.35: `rate *= headroom^1.15` |
| Camber scallop | `0.006 * camberFrac * slipFrac` · continuous from **1.0°** · `frac=(|c|−0.85)/4` cap 1.15 |

Do not change without a new timed lock A/B. Target feel: visible peak after ~10 s
lock without slamming to 100% in one event.

## Phase 2 — tread ring wear (2026-08-23)

| Flag | Default | Role |
| --- | --- | --- |
| `ENABLE_RING_WEAR` | **true** | Spread lock wear across `wd.treadNodes` ±2 neighbors |

**Lock sector** (center contact node unchanged rate; neighbors share same energy gate):

| Ring offset | Rate weight |
| --- | --- |
| 0 (contact) | 1.00 |
| ±1 | 0.45 |
| ±2 | 0.22 |

**Camber scallop:** when camber gate arms, wear applies across the full `treadNodes`
ring with outer/inner bias (JBeam order: odd index = outer tread node in each ray pair).

**Phase 2 retest** (after respawn):

1. ~10 s lock → **peak** still teens on worst node; **n ≥ 3** on that corner.
2. Cruise → **c** may pulse above 0% more often (wider worn sector); contact tick
   advances **same CW direction** on all four Pitwall rings (`wheelDir < 0` flipped).
3. Reset → all nodes restore; peak and **n** → 0.

**Verified cars:** Bolide (Phase 1–2 lock/peak/n); **Nightsnake** (ring wear + wear map
CW unify); **Scintilla GT3** (park + hard-brake soak, wear map CW, 2026-08-23).

Note: GT3 **ABS** can prevent a true lock gate (`ω` low + slip). For ring-wear A/B on ABS
cars, disable ABS or force a lock; hard braking alone may only heat brakes without
raising **n**/peak.

Rates on the **contact node** are unchanged from Phase 1 — neighbors add sector width only.

## Retest

1. Respawn. Pitwall tread stays ~100%.
2. Hard lock on asphalt → **Node wear peak** builds in the teens % (baseline ~9–14%
   on a typical lock; soft-sat after 35%).
3. Vehicle reset → peak 0%; nodes restore.
4. Lock fade stays 0%; native lock still works.

## Pitwall (dev sanity UI)

**Pitwall Heavy** (`tireWearThermalsHeavy`) is **dev/testers only** — not planned for public release. Use the **NODE SPIKE** block under TEST CHANNELS to verify the spike without guessing from grip alone.

| Field | Rest (parked) | Lock (~10 s) | Parked after lock | Cruise after lock (~40 mph) | After vehicle reset |
| --- | --- | --- | --- | --- | --- |
| Spike / gate | `ON · idle` | `ON · lock` (or `lock+cam`) | `ON · idle` | `ON · idle` | `ON · idle` |
| Contact cid | `0` or valid id | non-zero contact node | valid id (may differ from lock patch) | changes as tire rolls | `0` |
| ω (rad/s) | ~0 | low if locked | ~0 | high (rolling) | ~0 |
| Wear c / peak / n | 0% / 0% / n0 | c ≈ peak, teens % / **n≥3** | 0% / peak% / **n≥3** | **c** may pulse; peak% / **n≥3** | 0% / 0% / n0 |
| μ F/S · mass | ×1.00 / ×1.00 · m1.00 | below 1.0 if worn | ×1.00 on current contact | ×1.00 until worn node hits patch | ×1.00 |
| Lock fade | 0% | 0% | 0% | 0% | 0% |
| Tread % (scalar) | ~100% | ~100% (scalar off) | ~100% | ~100% | ~100% |
| Dynamic grip | baseline | may dip slightly | ~baseline | thermal/load only until flat patch rolls under | baseline |

**Gates:** `idle`, `no-node`, `lock`, `camber`, `lock+cam`, `air`, `off`.

### Minor Pitwall quirks (read before filing bugs)

**Fixed (2026-08-23):**

| Symptom | Cause | Fix |
| --- | --- | --- |
| **`n0` with non-zero peak** | `nodeWearTouched` compared wheel ids as string vs number | Normalize with `tonumber()` in `tireWearThermalsNodeWear.lua` |
| **`Spike OFF` while spike enabled** | Boolean `nodeSpikeOn` did not survive guiStream JSON | Stream as `1`/`0`; Pitwall treats `1` or `true` as **ON** |

Respawn vehicle after syncing `-dev` so Lua + Pitwall UI pick up both fixes.

**Expected at rest / cruise (not bugs):**

- **Contact wear 0% / peak teens%** — After a lock, the tire often rests on a *different* tread node than the worn patch. **Peak** is the session max; **contact (c)** is wear on the node under the car *now*. Same at cruise until the flat rolls into the patch.
- **μ / mass ×1.00 when not on flat** — Scales follow the *current* contact node. Watch **c** jump toward **peak** when the worn sector hits asphalt.
- **`ON · idle` after lock / at cruise** — Gate is `idle` when slip/ω gates are open; spike module is still enabled (`ON`). Only **`OFF · off`** means `ENABLE_NODE_WEAR_SPIKE` is false.
- **Tread % in Classic / Crew after lock** — With **A3 HUD bridge** on, header /
  overall `condition` = `100 × (1 − peak)`; O\|M\|I bars use outer / mid / inner ring wear.
  Pitwall **Tread** line may still show scalar 100% — compare Classic/Crew to **peak**, not Pitwall tread.
- **Peaks unchanged while cruising** — Node spike does not heal; only **vehicle reset** clears peak and restores nodes.

**Dev workflow:**

- **Respawn vehicle** after any Lua/UI sync. Hot reload can leave **peak** on `tyreData` while `nodeState` is empty → **`n0`** until you re-lock or reset. After respawn, re-run the lock test.
- **`nodeWearTouched` is not lerped** — Pitwall snaps **n** immediately (not smoothed like grip).

## Pitwall capture-first (Win+PrintScreen)

Pitwall Heavy defaults to **opaque dark panels** + a yellow **NODE SPIKE capture line**
per corner (`FR · ON idle · c0% · peak12% · n5 · fade0%`) so overexposed world HDR
does not wash key numbers. Re-add the app after UI sync.

Under **NODE SPIKE**, each corner shows a circular **Wear map**:

- One segment per tread **ray** (`max(outer,inner)` wear %).
- **White tick** = current contact ray.
- After a lock: bright **arc/sector** where ring wear landed; rest stays dark.
- Hidden when peak = 0 and ring empty (fresh reset).

Not a player feature — Pitwall remains excluded from public zip.

## A3 HUD bridge (Classic + Crew)

When `ENABLE_HUD_BRIDGE_A3` and node spike are on (scalar tread still off):

| HUD field | Source |
| --- | --- |
| Overall `%` (`condition`) | `100 × (1 − nodeWearPeak)` |
| Outer / Mid / Inner | Max wear on outer nodes / avg(O,I) / max on inner nodes |

Classic canvas + Crew zone strip both read the same stream fields. Driver UI removed.

Grip path treats `condition` / `zoneCondition` as **100** for wearPenalty while spike is on
(node μ already owns contact feel — no double tax).

## Gated lock energy swap (`ENABLE_LOCK_ENERGY_COLE`)

**When (unchanged):** lock arm = contact cid + `slipE > 0.18` + `ω < 14`. 

**What (when flag on):** if this GFX window has `slipHits > 0` and `slipF ≥ 80 N`:

- Rate from probe **slipF** (`LOCK_COL_RATE=0.016`, `LOCK_SLIP_F_REF=1800 N`)
- Ring center = probe **peakCid** (fallback `lastTreadContactNode`)
- Pitwall capture tag **L:** `cole` (else `slipE` / `idle`)

If probe quiet while lock arm is open (ABS / no hits), **falls back to slipE rate** so wear does not stall.

GFX order: `stepNodeWearSpike` peeks live bucket → then `stepNodeCollisionProbe` clears into HUD hold.

**Retest:** same 5-row matrix. Expect lock tag **`cole`**, peak still teens, cruise does not raise peak, reset clears.

## Gated camber energy (`ENABLE_CAMBER_ENERGY_COLE`)

**When:** camber arm = cid + `|camber| ≥ CAMBER_DEG_ARM` (**1.0°**) + load > 800 + `slipE > 0.08`.

**Continuous ramp** (street gentle → race loud; replaces hard 2°/4° gate and discrete bands):

| \|camber\| | `camberFrac` ≈ | Feel |
| --- | --- | --- |
| &lt; 1.0° | 0 | off |
| 1.0° | ~0.04 | whisper street |
| 2.0° | ~0.29 | mild sport |
| 3.0° | ~0.54 | aggressive |
| ~4.85° | 1.0 | race / scrub (cap 1.15) |

`camberFrac = min(1.15, max(0, (|camber| − 0.85) / 4.0))` while armed (`|camber| ≥ 1.0°`)

**What:** camber **geometry** (outer/inner ring weights) unchanged. Rate:

- `camBase = CAMBER_COL_BASE (0.006) * camberFrac * slipFrac`
- Legacy slipFrac: `min(1.15, min(1.2, slipE) / 0.28)`
- Cole slipFrac: `min(1.15, slipF / 180)` when `slipHits > 0` and `slipF ≥ 40 N`
- Else fall back to slipE term

Pitwall capture: `L:…/C:cole` when camber arm uses probe (`C:slipE` fallback, `C:idle` when not armed).

### Camber ramp retest

1. Respawn · Pitwall · park → `map128` · `idle/idle` · peak 0  
2. **Stock Sport** mild corners (~1–2°) → gate may open; peak crawls **slowly**  
3. Harder turn / more camber (~3°+) → faster climb; avoid full lock  
4. Straighten → peak held · Reset → 0  

Cruise/park must not climb peak. Scalar tread still off until node work is done.

## nodeCollision / slipForce probe (Pitwall — read-only + swap feed)

Loads `lua/vehicle/controller/tireWearThermalsNodeProbe.lua` via
`controller.loadControllerExternal` (no JBeam edit). Accumulates per GFX tick on tread nodes only:

| Pitwall field | Meaning |
| --- | --- |
| Hits / slip hits | nodeCollision count / count with slipForce > 0 |
| slipF max / slipV max | Window max on tread ring |
| colE Σ / peak | Σ(slipForce × \|slipVel\|) / per-event peak |
| slipE | Wheel `dynamicSlipEnergy` (current baseline) |
| Peak cid / wheel cid · match | Max-slip node vs `lastTreadContactNode` |

Wear rates unchanged — probe is display-only until A/B says swap energy source.

### Probe retest matrix (same 5 rows as baseline)

Respawn after sync. Pitwall must show **COL ENERGY (probe)** under NODE SPIKE.

| # | Maneuver | Watch |
| --- | --- | --- |
| 1 | Park | hits ~0 · slipF 0 · colE 0 |
| 2 | ~10 s lock | slip hits > 0 · **slipF max high** · colE Σ >> park · peak cid often ≠ wheel cid (match N OK) |
| 3 | Park after lock | colE drops; peak cid may differ from wheel cid |
| 4 | Cruise ~40 | slip hits low/0 · colE quiet · peak wear unchanged |
| 5 | Reset | all col + wear zero |

**mapN:** count of tread cids mapped for probe routing. Was often **0** because init ran
before `treadNodes` existed and controller reset wiped the map. Fix: keep map across
controller reset; `ensureTreadMap` refills on GFX until `mapN > 0`. Expect **mapN ≈
sum of tread nodes** (e.g. ~64–80 on a 4-wheel car with 16–20 rays), not 0.

## Next

- Continuous camber ramp from **1.0°** (`frac=(|c|−0.85)/4`, base 0.006) — retest stock Sport + harder/race camber.
- Soft scalar tread deferred until node work is done.
- Optional: pack / private tester share.
