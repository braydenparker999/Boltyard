# Traction investigation at 3.2.0

Source examined: adc2c246026085d90178e7886ec5fc34ca9459c0.

## Reproduced defect

A representative 1675 kg crawler on a synthetic dry 20-degree side slope drifts 1.003 m horizontally downhill over five seconds with the brake released. At the end it moves at 0.218 m/s, while reported wheel slip is only 0.002 m/s. Doubling the surface coefficient from 1.1 to 2.2 does not remove the drift (1.034 m). Holding the brake holds the truck stationary at either dry coefficient. A low-grip control (0.12) still slides with brakes applied, as expected when available friction is insufficient.

`native/benchmark_traction.cpp` reproduces the coefficient/brake controls with no imported assets or cached scenery. It uses a one-metre plane in the imported-terrain backend and the existing production tire solver. Settings are representative of the user's earlier heavy crawler, not an exact live phone capture. The retained baseline output's `load` column is vertical wheel load; the checked-in benchmark labels/reports total normal load explicitly to avoid confusing those quantities on an incline.

## Cause and causal check

In `SoftRig::solve_wheel_manifolds`, position-level tangential resistance only runs with the brake applied. With the brake released, `solve_tire_traction` supplies lateral force proportional to lateral velocity through its 0.065-second response parameter. There is no persistent static lateral support at zero sliding speed. A nonzero downhill drift balances gravity even when the Coulomb limit has ample remaining capacity.

A diagnostic-only build changed `fixed_dt/.065f` to `fixed_dt/.01f` in the lateral response. Dry drift fell from 1.003 m to 0.149 m; terminal speed fell from 0.218 to 0.034 m/s. Low-grip sliding remained. This identifies the response law, not a missing texture/material coefficient, as the source of this particular defect. That faster-damping experiment is not a production fix and is not applied to the game.

## Additional findings

- The 3.1.0 diff adds the exact transformed-rock query cache and an include; it does not change tire force equations. Its cache cannot explain this empty-plane reproduction. This does not exclude a separate map-specific contact issue.
- A separate longitudinal incline sweep on the same representative setup climbed a dry 30-degree slope at 0.3 throttle (4.586 m forward in five seconds, finishing near 1.35 m/s). Longitudinal grip is therefore not universally absent.
- Releasing throttle and brakes on that incline allowed about 40 m of rollback in five seconds, finishing near 18.26 m/s while longitudinal slip was only about 0.156 m/s. That is primarily rolling with weak modeled engine braking, not evidence of ice-like friction. Engine braking/coasting behavior merits its own calibration.
- The existing wheel-slip value measures longitudinal rolling mismatch only. It substantially underreports sideways sliding and is forced to zero while braking. It should not be presented as a complete traction indicator.

## Recommended correction

Add bounded lateral static-contact support while preserving free wheel rotation. Static lateral and longitudinal drive/brake forces must share one friction budget; simply adding a second full-strength lateral constraint would over-grip. Retain multiple rock contact patches, tire deformation and existing geometry detail. Validate dry side-slope hold, low-grip breakaway, combined throttle/steering, banked turns and ledge crawling. Then address coasting/engine-braking response separately and expose lateral slip in diagnostics.

No production physics changes or new APK were made during this investigation. Phone observation is still needed to determine how much of the user's total reported slickness these reproduced behaviors explain.
