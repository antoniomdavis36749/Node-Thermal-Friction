# Compatibility tires

Optional NTF-selectable tire JBeams and extra Scintilla configs are **not** in this core tree.

Testers who only want thermals / UI should clone this repo and skip the companion. Testers who want vehicle parts should clone **Node-Thermal Friction Tires** (`Node-Thermal-Friction-Tires`) beside it.

BeamNG Repo: https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/

Core thermals/UI (required): https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/

Do **not** copy `vehicles/` into core Node-Thermal Friction. BeamNG treats a zip that contains `vehicles/` as a vehicle mod and hides `ui/` / `lua/` (apps disappear). Unpacked core stays thermals-only so testers are not forced to load extra parts.

Career part shop also only sees `vehicles/` — tire prices and Scintilla config `Value` / `Population` live in the Compat pack, not here.

Inventory, generators, listing copy, and `Pack-Release.ps1` for the companion zip live in the tires repo.

**NTF clone standard:** pressure wheels use **`numRays`: 20** (~40 tread nodes/wheel) for denser node-wear
scallop maps. `Convert-Tires.ps1` forces 20 on new clones.
