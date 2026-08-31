# V2 node-wear spike (private tester / engineering)

Clean-room layer. BeamNG APIs only. No ports from third-party node-wear mods.

## Flags

| Flag | File | Default | Role |
| --- | --- | --- | --- |
| `ENABLE_SCALAR_TREAD_WEAR` | `tireWearThermalsWear.lua` | **true** (soft ×0.15 center + **mild rate curve**) | Everyday tread/zone %; HUD `min(scalar, node)` |
| `ENABLE_SCALAR_RATE_CURVE` | same | **true** | Scale from `scalarTreadCondition` life: 0.12→0.15→0.22 |

| `ENABLE_NODE_WEAR_SPIKE` | `tireWearThermalsNodeWear.lua` | **true** | Contact-node friction/mass wear |
| `ENABLE_RING_WEAR` | same | **true** | Phase 2 sector spread on tread ring |
| `ENABLE_HUD_BRIDGE_A3` | same | **true** | Classic + Crew condition + O\|M\|I from node peak/ring |
| `ENABLE_LOCK_ENERGY_COLE` | same | **true** (**LOCKED**) | Lock wear rate+cid from probe slipF (gates stay ω/slipE) |
| `ENABLE_CAMBER_ENERGY_COLE` | same | **true** (**CLOSED / rates LOCKED**) | Camber scallop slip term from probe slipF (geometry unchanged) |
| `CAMBER_COL_SLICK_SCALE_MIN/MAX` | same | **0.05 / 0.14** (**LOCKED** Soft life A3b) | Slick/circuit `col×` lerps by `camberFrac`; Sport = 1.0 |
| `CAMBER_COL_TRACKDAY_SCALE_MIN/MAX` | same | **0.26 / 0.40** (**LOCKED**) | Track Day profile only; street arm 1.0° held |
| `CAMBER_COL_SPORTPLUS_SCALE_MIN/MAX` | same | **0.30 / 0.45** (**LOCKED**) | Sport Plus profile only; est. from TD, Belasco 22 km confirm |
| `CAMBER_COL_SPORT_SCALE_MIN/MAX` | same | **0.40 / 0.58** (**LOCKED**) | Plain Sport only (not Plus); Belasco 22 km confirm |
| `CAMBER_COL_STANDARD_SCALE_MIN/MAX` | same | **0.52 / 0.68** (**LOCKED**) | Standard profile; est. from 22 km ×1.0 Cond ~85–88% |
| `CAMBER_COL_VINTAGE_SCALE_MIN/MAX` | same | **0.58 / 0.74** (**LOCKED**) | Vintage profile/spectrum; est. one step street-ward of Standard |
| `CAMBER_COL_TRUCK_SCALE_MIN/MAX` | same | **0.62 / 0.78** (**LOCKED**) | Commercial / *truck* / light_truck; est. mild |
| `CAMBER_DEG_ARM_SLICK` | same | **2.0°** (**LOCKED** with Soft life) | Slick/circuit arm floor; Sport/street/Track Day/Plus stay **1.0°** |


| `ENABLE_NODE_COLLISION_PROBE` | `tireWearThermalsNodeProbe.lua` | **true** | Read-only Pitwall colE / slipF (+ feeds gated swap) |
| `ENABLE_BRAKE_LOCK_FADE` | `auto/tireWearThermals.lua` | **false** | Lock stays native |
| `ENABLE_SCALAR_GRIP_FADE` | `auto/tireWearThermals.lua` | **true** (A2 mild) | Stint-life `wearPenalty` from `scalarTreadCondition` only while spike on |

Grain / blister remain thermal-side for now.

## Friction policy (A)

- Thermal core: `setFrictionThermalSensitivity` (compound × temp × …).
- Node spike: `obj:setNodeFrictionSlidingCoefs` + mild `obj:setNodeMass` on
  tread-ring nodes (contact + neighbors). Never writes wheel-level friction API.

## Energy (spike) — cole path **LOCKED**

**Gates** stay on wheel ω / `slipE` / camber (when to wear). **Rate + ring cid**
prefer probe `slipF` / `peakCid` while the arm is open and the probe is loud;
**quiet probe → slipE fallback** is intentional (ABS / no hits) so wear does not
stall. See gated lock / camber sections below.

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

**Verified cars:** Bolide (Phase 1–2 lock/peak/n; **camber accum 2026-08-25** + **low-toe
confirm 2026-08-26** — loud ~60% vs cleaner ~9% park-after; rates LOCKED); **Nightsnake**
(ring wear + wear map CW unify; **cole 5-row matrix 2026-08-25** — park/lock/hold/cruise/reset
pass; front lock Cond drop ~14–16% vs Bolide teens — note only); **Scintilla GT3** (park +
hard-brake soak, wear map CW, 2026-08-23; Soft camber stress 2026-08-26; **Soft life A3b
LOCKED 2026-08-26** — Belasco 22 km fronts Cond ~93–95% / ~5.5–7% drop; **Med/Hard 22 km
2026-08-27** — Med fronts ~5.5–6%, Hard fronts ~4.9–5.9% (94.1/95.1); Soft≈Med≈Hard on
node Cond under shared slick curve — ladder CLOSED).

Note: GT3 **ABS** can prevent a true lock gate (`ω` low + slip). For ring-wear A/B on ABS
cars, disable ABS or force a lock; hard braking alone may only heat brakes without
raising **n**/peak. Pitwall capture shows **`ABS?/no-lock`** when slipE is high but
ω ≥ 14; **`cole→slipE`** when the lock arm used quiet-probe fallback.

### Scintilla GT3 edge cases (dev notes)

| Case | Expect | Do **not** |
| --- | --- | --- |
| Hard brake with ABS on | Gate often stays `idle`; tip `ABS?/no-lock`; brakes heat; peak/n may stay low | Treat as lock-wear failure; do not retune `LOCK_COL_*` |
| True lock A/B | Disable ABS or force lock until gate `lock` + `L:cole` (or `cole→slipE`) | Use Soft/Med Cond% alone to retune soft scalar |
| Soft life (Soft slick Belasco 22 km) | A3b curve **0.05→0.14** + arm **2.0°**: fronts ~**5.5–7%** Cond drop (**LOCKED**) | Retune Sport `CAMBER_COL_BASE` or Soft C4 heat for Soft life |
| Medium 22 km (same curve) | Fronts ~**5.5–6%** Cond, **node-led**; Soft≈Med on Cond (scalar still Med-healthier sc) | Expect Soft≫Med Cond from camber alone — curve is slick-wide |
| Hard 22 km (same curve) | Fronts ~**4.9–5.9%** Cond (94.1/95.1); Soft≈Med≈Hard on node Cond — **ladder CLOSED** | Retune A3b from Hard (scalar separates compounds; node Cond won’t) |
| Track Day 22 km (pre-mute ×2) | Fronts Cond ~**71–75%**, peak ~**25–29%**, **node 93–99%**; sc100 | Leave Track Day on full street col×1.0 |
| Track Day camber **LOCKED** | col× **0.26→0.40**: fronts Cond ~**92%** / peak ~**8%** (22 km A/B) | Soft life / Sport (non-Plus) |
| Sport Plus camber **LOCKED** | col× **0.30→0.45**: fronts Cond ~**90%** / peak ~**6–11%** (22 km confirm) | Soft life / Sport / Track Day |
| Sport camber **LOCKED** | col× **0.40→0.58**: fronts Cond ~**93–94%** / peak ~**3–7%** (22 km confirm; cooler than opt) | Soft life / Plus / Track Day |
| Standard 22 km (×1.0) | Fronts Cond ~**85–88%**, peak ~**12–15%**, cold vs opt 60 | Leave standard on full street ×1.0 |
| Standard camber **LOCKED** | col× **0.52→0.68** est. from ×1.0 run (target Cond ~90–93%) | Soft life / Sport ladder |
| Vintage camber **LOCKED** | col× **0.58→0.74** est. mild (street-ward of Standard) | Soft life / Standard |
| Truck/commercial camber **LOCKED** | col× **0.62→0.78** est. mild | Soft life / Standard |


| Drift smoke / high-camber fronts (pre-proto) | Sport-on-drift: rears Hot ~130°C peak **~3%**; fronts Cold ±5° camber peak **14–23%** | Treat as intentional — lock gate misses spinning slip; street camber farms undriven |
| Drift prototype (1)+(2) | **drift compound OR plain Sport:** gate `drift` + undriven camber mute; rate **0.017** provisional. Feel revisit **only** if tester feedback lands — **non-blocking** for release. | Soft life / Plus; lock rates |
| Soft camber soft confirm (stress arc) | ~3.2 km loaded; Soft louder than Sport — expected | Retune from Soft stress vs Sport low-toe alone |
| Soft/Med ~22 km Cond drop | Often **node-led** (nd &lt; sc) after spike work — Pitwall **sc\|nd** | Blame `SCALAR_TREAD_WEAR_SCALE` 0.15 (Sport street lock is separate) |
| Hard-brake soak | Rim/carcass soak from native brakes; separate from node lock flats | Confuse soak heat with node peak |
| Wear map CW | All four rings advance same CW when rolling (`wheelDir` flip) | Expect mirrored L/R rings |

Park + hard-brake soak + wear-map CW already verified on GT3 (2026-08-23). Full cole
5-row on GT3 is optional — ABS makes row 2 noisy; prefer Bolide/Nightsnake for rate locks.

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
- **Tread % / Cond after lock** — With **A3 HUD bridge** on, Pitwall/Classic/Crew
  `condition` = `min(scalarCond, nodeCond)` where `nodeCond = 100×(1−peak)`. Pitwall
  streams **sc** / **nd** so captures show which side won. A2 grip fade uses **sc**
  (`scalarTreadCondition`) only — never HUD Cond / node peak.
- **Peaks unchanged while cruising** — Node spike does not heal; only **vehicle reset** clears peak and restores nodes.

**Dev workflow:**

- **Respawn vehicle** after any Lua/UI sync. Hot reload can leave **peak** on `tyreData` while `nodeState` is empty → **`n0`** until you re-lock or reset. After respawn, re-run the lock test.
- **`nodeWearTouched` is not lerped** — Pitwall snaps **n** immediately (not smoothed like grip).

## Pitwall capture-first (Win+PrintScreen)

Pitwall Heavy defaults to **opaque dark panels** + a yellow **NODE SPIKE capture line**
per corner (`FR · ON idle · Cond86 · c0% · peak14% · n5 · L:cole/C:idle`) so overexposed
world HDR does not wash key numbers. Re-add the app after UI sync.
Hints: **`ABS?/no-lock`** when slipE high but ω ≥ 14 (typical GT3 ABS); **`cole→slipE`**
when lock arm used quiet-probe fallback.

Under **NODE SPIKE**, each corner shows a circular **Wear map**:

- One segment per tread **ray** (`max(outer,inner)` wear %).
- **White tick** = current contact ray.
- After a lock: bright **arc/sector** where ring wear landed; rest stays dark.
- Hidden when peak = 0 and ring empty (fresh reset).

Not a player feature — Pitwall remains excluded from public zip.

## A3 HUD bridge (Classic + Crew) — Friction coherence **A1 LOCKED** + **A2 fade ON**

When `ENABLE_HUD_BRIDGE_A3` and node spike are on:

| HUD field | Source |
| --- | --- |
| Overall `%` (`condition`) | **min**(scalar tread, `100 × (1 − nodeWearPeak)`) |
| Outer / Mid / Inner | **min**(scalar zone, node outer/mid/inner) |

Classic canvas + Crew zone strip both read the same stream fields. Driver UI removed.

**A1 LOCKED:** Node owns contact scallop feel (relative μ/mass). Soft scalar ×0.15 ages
HUD Cond / zones + leak thresholds. Baseline profile grip still treats `condition` /
`zoneCondition` as **100** while spike on (no double tax from HUD hybrid / node peak).

**A2 mild scalar grip fade ON** (`ENABLE_SCALAR_GRIP_FADE`, default **true**):

| | |
| --- | --- |
| Source | `data.scalarTreadCondition` only (never `min(sc,nd)` / node peak) |
| `lifeUsed` | `(100 − sc) × 0.01` |
| Shape | Full grip until `lifeUsed ≥ 0.30` (**sc &lt; 70%**); floor **0.90** at life≈1 |
| Spike off | Legacy `condition`→wearPenalty (0.75 paved / loose curve) |
| A/B | Set flag **false** to restore pre-A2 (no scalar wearPenalty while spike on) |

## Gated lock energy swap (`ENABLE_LOCK_ENERGY_COLE`) — **CLOSED / LOCKED**

**Sign-off (2026-08-25):** Bolide lock/peak tune + Nightsnake 5-row cole matrix
passed. Do **not** remove slipE fallback or retune `LOCK_COL_*` without a new A/B.

**When (unchanged):** lock arm = contact cid + `slipE > 0.18` + `ω < 14`.

**What (when flag on):** if this GFX window has `slipHits > 0` and `slipF ≥ 80 N`:

- Rate from probe **slipF** (`LOCK_COL_RATE=0.016`, `LOCK_SLIP_F_REF=1800 N`)
- Ring center = probe **peakCid** (fallback `lastTreadContactNode`)
- Pitwall capture tag **L:** `cole` (else `slipE` / `idle`)

If probe quiet while lock arm is open (ABS / no hits), **falls back to slipE rate**
so wear does not stall — **intentional**, not a bug.

GFX order: `stepNodeWearSpike` peeks live bucket → then `stepNodeCollisionProbe` clears into HUD hold.

**Smoke (closed):** same 5-row matrix — lock tag **`cole`**, peak teens band, cruise
holds peak, reset clears. Nightsnake fronts a bit hotter than Bolide — note only.

## Gated camber energy (`ENABLE_CAMBER_ENERGY_COLE`) — **CLOSED** (rates **LOCKED**)

**Sign-off (2026-08-25, Bolide):** park → loaded arc (~60 mph) → park-after. Quiet probe →
slipE slipFrac fallback — same policy as lock. **`CAMBER_COL_*` LOCKED** — no retune.

| Pass | Setup | Result |
| --- | --- | --- |
| Loud (toe scrub) | Static ~±3.5–4° camber; front toe extreme (~8–16° under load) | FR gate **`camber`**, **`camF` ~0.7**; peak ~**60%** / n32 — **toe-contaminated** |
| Cleaner (low toe) | Static ~±3.4° front camber; park toe ~**0.65°** (Bolide camber↔toe couple — best effort) | FR gate **`camber`**, **`camF` ~0.51**; Cond mid ~**92%** → park-after Cond ~**91%** / peak ~**9%** held |

**Native toe / stock camber:** mid-run outside often stays under 1° arm → peak stays 0 (expected).
Rears often `idle` when slipE low despite live camber. Under load, park toe ~0.65° can open to
~4° — still far quieter than the loud pass.

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
Capture also shows **`camF0.xx`** (live `camberFrac`) when &gt; 0; Pitwall row **Camber frac** labels soft/sport/aggressive/race bands for readouts.

### Camber ramp retest (protocol — CLOSED 2026-08-25 / low-toe confirm 2026-08-26)

1. Respawn · Pitwall · park → `map128` · `idle/idle` · peak 0  
2. Static ~±3.5–4°; nudge toe back toward stock after camber (Bolide couples them)  
3. Loaded arc 60–90 s → gate **`camber`**, peak crawls slowly; avoid full lock  
4. Straighten → peak held · park/cruise must not climb · Reset → 0  

Soft band (Sport Bolide low-toe): park-after peak ~**single-digit %** after ~1 km arc.
GT3 Soft race-camber ~3 km: FL peak ~**30%** can happen (Soft + more arm time) — still not
toe-nuke; **do not** retune rates from Soft vs Sport compare alone.


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

- Soft scalar tread **LOCKED** mid-life center ×0.15 (Sport Belasco clean 22 km: FR ~0.9%
  in band; 0.45 overshot). **Mild rate curve on** (2026-08-28): early 0.12 → mid 0.15 →
  late 0.22 from dedicated `scalarTreadCondition` (never node-min'd). A3 `min(sc, nd)` held.
  Spot-check Sport ~22 km sc still ~0.7–1.0% band; endurance sc should age faster late.
- **Friction coherence A1 LOCKED** — Cond = display hybrid; node μ owns contact scallop.
- **A2 mild scalar grip fade ON** (2026-08-30) — `ENABLE_SCALAR_GRIP_FADE` default true;
  fade from `scalarTreadCondition` only: start `lifeUsed ≥ 0.30` (**sc &lt; 70%**), floor **0.90**.
  (Nudged from 0.40 / sc&lt;60% — earlier but still mid-life.)
  Confirm: fresh Sport no felt fade; worn scalar mild loss; hard lock on fresh → node peak
  hurts contact, scalar fade ≈ none.
- **Lock cole energy CLOSED / LOCKED** — gates ω/slipE; rate from slipF; quiet → slipE
  fallback intentional.
- **Camber accumulation CLOSED / rates LOCKED** (Bolide low-toe + **GT3 Soft confirm**
  2026-08-26 — Soft louder than Sport; base `CAMBER_COL_*` held).
- **Soft life A3b CLOSED / LOCKED** (GT3 Soft Belasco 22 km 2026-08-26) — slick curve
  **0.05→0.14** by `camberFrac` + arm **2.0°**; fronts Cond ~**93–95%** (~5.5–7% drop).
- **Med/Hard 22 km CLOSED** (2026-08-27) — Soft≈Med≈Hard on node Cond under shared slick
  curve (Hard fronts ~4.9–5.9%); do not retune A3b. Belasco Soft→Med→Hard ladder done.
- Second-car **cole smoke CLOSED** (Nightsnake 5-row). Phase 3 friction exit checks complete.
- **Private tester `0.2.0` (Beta)** — checklist + pack ready; public Repo still paused.
- Lua locals: elevated but under warn (159/156/127); no peel until compile fails.
- GT3: ABS edge notes + Pitwall `ABS?/no-lock` / `cole→slipE` hints.
- **Track Day camber CLOSED / LOCKED** (2026-08-29) — col× **0.26→0.40**; 22 km fronts
  Cond ~92% / peak ~8%. Soft life / Sport unchanged.
- **Sport Plus camber CLOSED / LOCKED** (2026-08-29) — col× **0.30→0.45**; 22 km fronts
  Cond ~90% / peak ~6–11%. Heat lock held (blister 0); FL stint-max Hot flash note only.
- **Sport camber CLOSED / LOCKED** (2026-08-29) — col× **0.40→0.58**; 22 km fronts Cond
  ~93–94% / peak ~3–7% (stint cooler than opt 66 — quieter than Plus Cond drop; OK).
- **Standard camber CLOSED / LOCKED** (2026-08-30) — col× **0.52→0.68** from 22 km ×1.0
  (fronts Cond ~85–88%); target ~90–93%. Spot-check skipped.
- **Vintage camber CLOSED / LOCKED** (2026-08-30) — col× **0.58→0.74** est. mild
  (one step street-ward of Standard).
- **Truck/commercial camber CLOSED / LOCKED** (2026-08-30) — col× **0.62→0.78** est.
  mild (`purpose=commercial` or *truck* / light_truck).
- **Drift arm widened to plain Sport** (2026-08-30) — native drift configs mount Sport;
  same kinematics gates + camber mute. Rate **0.017** provisional (was 0.022; ~16% Cond
  @ 65s burnout). **Parked / non-blocking:** feel revisit only if tester feedback arrives;
  do not hold other work or release on this checkbox.

## Open bands

Do **not** retune Soft life / camber ladder / drift rate / **drag long** / **wet** /
**street heat** from closed protocols. Drag + wet + street heat closed 2026-08-30.

### Drag — **CLOSED / LOCKED** (2026-08-30)

| Step | Action |
| --- | --- |
| 0 | Parked baseline: classify, cold temps, PSI vs hot tgt, Cond/sc/nd, gate idle |
| 1 | Drag config (or drag-purpose tires): **1–2 launches** + short top-end |
| 2 | Capture: classify, temps vs opt, long grip feel, Cond/gate, PSI; note drive soft-cap vs burnout heat |
| Watch | Do not retune Sport camber / A1 / Soft life from drag |

**Status:** native launches **PASS** (~130% dyn). **`longGripMult` 1.18 LOCKED** — ~1400 hp mod launch
held (park after: rear long ~151%, stint max ~101–103°C, Cond 100). Lat/dry untouched. Satisfied.

### Wet — **CLOSED / LOCKED** (2026-08-30)

| Step | Action |
| --- | --- |
| 0 | Parked baseline dry → rain/wet pad: classify, drainage/surface flags, PSI, Cond |
| 1 | One abuse: wet braking / corner load on known rain or wet surface |
| 2 | Capture: grip/drainage feel vs dry, temps, Cond/gate, surface scale sanity |
| Watch | Rain pad already sanity-passed; open = grip/drainage band notes or lock — no Soft life retune |

**Status:** park / accel / brake / cruise on **ASPHALT_WET** **PASS / no nudge** (μ slide 0.70→0.55,
wet grip softer than dry, spin on accel sane, lock fade off, rainState often 0 with surface wet).
No profile retune. Satisfied.

### Street heat — **CLOSED / LOCKED** (2026-08-30)

| Step | Action |
| --- | --- |
| 0 | Parked baseline Standard or Sport: cold temps vs opt, PSI |
| 1 | One abuse: cruise warm-up / mild street heat (not camber 22 km ladder) |
| 2 | Capture: warm-up time to working band, Hot flash?, blister 0, Cond quiet |
| Watch | Camber ladder already LOCKED; this band is cruise heat only |

**Status:** Sport park Cold (~26°C vs opt 66) → **~10 min cruise ~44 mph** → **Normal ~70°C**
(inside ±18 plateau), Cond ~100, blister 0, PSI toward hot tgt. **PASS / no nudge.** Satisfied.

### Light commercial leftovers — **CLOSED** (2026-08-30)

PSI hot-tgt seed already fixed drag-rear false UNDER; camber truck curve LOCKED; user confirmed
feel OK — **no further commercial band work**.

**A2 feel (optional / user-owned):** extended Belasco supersoft to exercise `sc` &lt; 70% fade —
not a release blocker; report only if fade feels wrong.

### Supersoft C5 life — **OPEN** (2026-08-30)

| Step | Action |
| --- | --- |
| 0 | Respawn cold supersoft (softnessCoef 0.875 / Qualify) |
| 1 | Belasco ~**8–12 laps** (~F1 C5 10–15 lap ceiling) |
| 2 | Capture: Cond/`sc\|nd`, blister, dyn grip; note A2 if `sc` &lt; 70% |
| Watch | Soft C4 wear LOCKED; Sport global scalar ×0.15 LOCKED — do not retune from C5 |

**Status:** `mods.scalarTreadWearScale = 1.0` on `supersoft_slick` only (prior 51 km / 12 laps
Cond ~88% at global ×0.15 was immortal). Est. Cond ~15–25% by ~12 laps. **Confirm** then lock/nudge.