# Compatibility tires

Optional NTF-selectable tire JBeams and extra Scintilla configs are **not** in this core tree.

Testers who only want thermals / UI should clone this repo and skip the companion. Testers who want vehicle parts should clone **Node-Thermal Friction Tires** (`Node-Thermal-Friction-Tires`) beside it — or use the live unpack `Node-Thermal-Friction-Tires-dev`.

BeamNG Repo: https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/

Core thermals/UI (required): https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/

Do **not** copy `vehicles/` into core Node-Thermal Friction. BeamNG treats a zip that contains `vehicles/` as a vehicle mod and hides `ui/` / `lua/` (apps disappear). Unpacked core stays thermals-only so testers are not forced to load extra parts.

Career part shop also only sees `vehicles/` — tire prices and Scintilla config `Value` / `Population` live in the Compat pack, not here.

## Pack / inventory

| Doc / tool | Where |
| --- | --- |
| Compat README + inventory | Tires unpack: `README.md`, `INVENTORY.md`, `LISTING.md` |
| Pack Compat zip | `.\tools\scripts\Pack-Compat-Release.ps1` (defaults to live `-dev` unpack) |
| Pack core zip | `.\tools\scripts\Pack-Release.ps1` |

**NTF clone standard:** pressure wheels use **`numRays`: 16**. Do **not** raise globally —
native cars often tolerate 18–24, but modded vehicles break (hub/sidewall). Repro: 20
(2026-09-15), then 24/18 experimental. `Convert-Tires.ps1` forces 16.

**Advertise:** Scintilla GT3 NTF configs are the primary path. ETKC / Pigniteon — smoke before advertise (see `PUBLISH_CHECKLIST.md`).

## Are NTF tires “special”? (tester FAQ)

| Tier | Now? | Meaning |
| --- | :---: | --- |
| **1. Catalog** | Yes | Expand NTF shop coverage toward native sizes; clear Sport / Track Day / Soft–Hard names + configs |
| **2. Classify** | Yes | NTF names / softness route reliably onto locked ladders (stock still works via classify) |
| **3. Physics special** | **Later** | Extra μ / life / heat only on marked NTF parts (e.g. one-off high-climb “special rubber”). Not for current Beta |

**Paste answer:** Core runs on every tire. NTF Compat parts are the calibrated catalog (1) with clean compound routing (2) — not a different physics engine. Unique “special rubber” (3) is tabled for later one-off configs, not the default street/slick pack.
