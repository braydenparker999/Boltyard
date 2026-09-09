# Crawling contact and steering correction

Changed the production native solver to retain lateral tread deflection on persistent terrain/rock patches. Elastic support uses actual hub displacement, implicit velocity response, pressure-dependent stiffness and bounded strain. Sliding releases excess strain; contact loss and braking clear the state. Longitudinal and lateral impulses still share the same per-patch Coulomb cap. Rolling replaces the tread state over a 0.25 m relaxation length. No extra collision queries or solver iterations were added.

Added geometric inner/outer front steering correction using configured wheelbase and track. Central steering angle slew is limited to 1.8/(1+speed/12) radians per second, retaining the existing speed-dependent target and low-speed steering authority.

## Measured results

Synthetic dry 20-degree side slope, representative 1675 kg crawler, brake released for five seconds: horizontal downhill movement decreased from 1.003 m to 0.020 m at surface coefficient 1.1; terminal speed decreased from 0.218 to approximately 0.002 m/s. At coefficient 2.2 movement was 0.051 m. Initial movement includes settling and tread deflection. This is reduced creep, not proof of perfect static equilibrium at every load or angle.

Low coefficient 0.12 still slides strongly with and without braking. New regression tests require dry movement under 8 cm and final speed below 0.015 m/s, preserve low-grip breakaway, and verify both steering directions and rate limits. Included in the native CI test loop.

Existing tests: 10 crawling, 7 linked-suspension and 6 tire-contact scenarios pass. Twelve production-acceleration steering cases were measured: entry speeds 2, 8 and 15 m/s; commands 0.25 and 0.65; open and locked axles. All 2/8 m/s cases and mild 15 m/s cases stay upright. Sharp 15 m/s cases still roll. No safety clamps were recorded in that sweep.

## Limits

This remains a game tire model with selected calibration constants, not measured real-vehicle validation. Dynamic-object contacts retain their existing lateral response; persistent tread support in this change applies to terrain and static rock manifolds. Engine-braking strength and driveline coupling are unchanged. Android runtime/performance has not been measured for this change. These source-level results do not constitute a delivered APK.
