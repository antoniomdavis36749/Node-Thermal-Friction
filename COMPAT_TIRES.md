# Compatibility tires

Optional Respin-selectable tire JBeams and extra Scintilla configs are **not** in this core tree.

Testers who only want thermals / UI should clone this repo and skip the companion. Testers who want vehicle parts should clone **ReSpin Tires** (`Tire-Wear-and-Thermals-ReSpin-Tires`) beside it.

BeamNG Repo: https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/

Core thermals/UI (required): https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/

Do **not** copy `vehicles/` into core ReSpin. BeamNG treats a zip that contains `vehicles/` as a vehicle mod and hides `ui/` / `lua/` (apps disappear). Unpacked core stays thermals-only so testers are not forced to load extra parts.

Career part shop also only sees `vehicles/` — tire prices and Scintilla config `Value` / `Population` live in the Compat pack, not here.

Inventory, generators, listing copy, and `Pack-Release.ps1` for the companion zip live in the tires repo.
