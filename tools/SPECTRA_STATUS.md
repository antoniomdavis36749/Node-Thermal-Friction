# Spectra maturity status (private Beta)

Honest labels for classify / profile bands. **Feel refinement** concentrated on street
performance + race slicks; other bands remain usable fallbacks, not Belasco-locked.

| Band | Maturity | Notes |
| --- | --- | --- |
| Street Soft → Standard, Sport, Sport Plus, Track Day | **LOCKED** (wear + life); heat round-3 **tester-owned** | ETK / low-camber street mid-turns (outside); GT3 smoke only |
| Slick Hard C2 / Med C3 / Soft C4 / C5 | **LOCKED** (wear + Soft C4 scalar 4.7) | Heat round-3 tester-owned; same non-GT3 protocol |
| Wet / winter (street soft-cap ON) | **Provisional** | Wet asphalt grip path locked 2026-08-30; broader A/B open |
| Rally asphalt / gravel | **Provisional** | Lat/long bumps landed; not Belasco-locked life |
| Drift | **Provisional** | Node rate 0.017 — non-blocking |
| Truck / light truck / truck_offroad | **Provisional fallback** | Scalar life placeholder — not performance-band calibrated |
| Utility / highway_utility | **Provisional fallback** | Same |
| Vintage | **Provisional fallback** | Historical rubber flavor; scalar uncalibrated |
| All-terrain / mud / crawler / paddle | **Provisional fallback** | Scalar placeholders on PROFILE_POINTS |
| Commercial | **Closed leftovers** | PSI hot-tgt feel OK 2026-08-30 |

Crew HUD appends `· provisional` on fallback profile names. Do not treat provisional
scalar life as a locked stint clock.
