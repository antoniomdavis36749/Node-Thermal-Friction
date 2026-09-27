# Locks

Dated decisions that stay put. A comment that says LOCKED follows this file. Reopen a row only when the same protocol misses.

Add a row at the top. One claim per row. Do not retune a neighbor because this row felt hot.

| Date | Claim | Evidence | Do not |
| --- | --- | --- | --- |
| 2026-09-26 | Stick flex is 0 once native slip ratio is above 0.30. Full at or below 0.12. Gain 0.22. | Sport drift, 2.1 km. Driven rears: 178 samples above 0.30, `stickFlex` 0 on all of them. `stick-flex-drift-telemetry.csv`. | Retune the window or the gain from a drift's peak temperature. |
| 2026-09-26 | Phase 1 native API. Applied `brakingTorque`. One grip coefficient `(long + lat) / 2`. `gripLevelScale` 0.80. Drag `gripMultiplier` 1.32. Shoulder from slip angle and `camberStd`. | Smoke: Scintilla GT3 and a street car. Commit `7ba52de`. Contract. | Reopen without a new Belasco miss. Do not put long and lat into separate friction slots. |
| 2026-09-06 | A2 scalar grip fade floor 0.70. Fade starts when scalar life is under 70%. | Belasco med+soft ~68 km, fronts scalar ~35%. | Use HUD `min(scalar, node)` as the fade input. |
| 2026-09-06 | Soft C4 scalar life 4.7. C5 scalar 4.7. | Belasco ~37 km, fronts scalar ~69–70%, scalar-led. | Retune Soft life from a Hard or street run. |
| 2026-08-30 | Drag `longGripMult` 1.18. | Native launches PASS. ~1400 hp mod launch held. | Retune Sport camber or Soft life from a drag launch. |
| 2026-08-30 | Wet asphalt grip path. | Park, accel, brake, cruise on ASPHALT_WET. No nudge. | Treat a broader wet surface set as locked. That set is still provisional. |
| 2026-08-30 | Street cruise heat, Sport. | Park ~26°C to ~10 min at ~44 mph, Normal ~70°C, blister 0. | Treat the 2026-09-10 cornering-rate reopen as a repeal of this cruise pass. Wear stays locked. Heat rates were later reopened. See CHANGELOG. |
| 2026-08-30 | Camber scallop rates. Slick 0.08–0.22 arm 2.0°. Track Day 0.26–0.40. Sport Plus 0.30–0.45. Sport 0.40–0.58. Standard 0.52–0.68. Vintage 0.58–0.74. Truck 0.62–0.78. Street arm 1.0°. | Belasco 22 km confirms plus the spike doc. | Retune the ladder from one GT3 smoke. |
| 2026-08-30 | FWD Soft layout damp 0.58 / 0.48. AWD Soft front damp 0.45 / 0.38. | FWD fronts ~106/120°C down to ~97°C. AWD FR ~96, FL ~109 with brake soak ~620°C. | Nudge the scales from the damp-off A/B. That A/B may only keep or retire the switch. |
| 2026-08-30 | Node-wear scales. Plus 1.10, Sport and Track Day 1.0, Standard 0.82 / 0.75. | Belasco 22 km condition bands. | Mix this with the scalar life clock. |
| — | Policy A. Thermal core writes wheel grip. Node wear scales contact nodes only. | Contract. | Run a second absolute friction writer. |

Band labels that are still provisional live in `tools/SPECTRA_STATUS.md`. This file does not promote them.
