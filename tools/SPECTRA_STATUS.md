# Spectra maturity status (private Beta)

Honest labels for classify / profile bands. Slick and sport aim at realistic
grip windows and temperatures. Wide feeling-era plateaus stay retired.

| Band | Maturity | Notes |
| --- | --- | --- |
| Street Soft → Standard, Sport, Sport Plus, Track Day | **LOCKED** (wear + life). Sport Plus street heat **LOCKED** under 100°C middle peak. Other street heat stays tester-owned | 26.8 km Corse, hottest middle 75.9°C. GT3 heat is not a verdict |
| Slick Hard C2 / Med C3 / Soft C4 / C5 | **LOCKED** (wear + Soft C4 scalar 4.7). Heat: see the next rows | Medium plateau stays 68–100°C. Shoulders now about 0.80 thermal at 52°C and 0.90 at 110°C. |
| Native race tire (stock softness 1.0 → soft slick 66.9–97.1°C) | Heat **LOCKED**: rolling 2.20. Flex scale 0.75 on every tire. Front soak 1.35, brake 1.1, static cooling 0.140, flex gain 0.00125 are coded, not locked | Wear borrows the Soft C4 package. Its own wear factors are open (`ROADMAP.md` W-01) |
| Medium slick heat | **Coded**: 0.65 rolling 3.80 on trial, 0.725 stays 2.5, flex scale 0.75 on every tire, not locked | 3.80 is fit from the measured 2.5 → 4.44 move on three cars. Flex 0.75 puts the Vivace Belasco FL on the 99.5°C edge (`ROADMAP.md` S-03) |
| Hard / supersoft slick heat | **Not baselined** on the current heat code | Predicted cold-edge scales 2.85 / 2.67 hard and 1.70 supersoft. First straight stays at 1.0 (`ROADMAP.md` S-06, S-07) |
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
