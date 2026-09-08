# Crawling and steering review at 3.2.0

Production physics were tested without changes. The new steering sweep launches through the production drivetrain, so wheel rotation matches road speed before turning. Test configuration: 1200 kg, high range, tire grip 1.3, 0.45 m ride height and 0.30 m suspension travel. It is a representative lifted crawler, not the user's captured phone configuration.

## Results

- All 10 `test_crawling.cpp` scenarios passed: elevated rock-only drive/brake, incline hold/restart, 0.30 m ledge, cadence independence, airborne torque, convex geometry, split-grip differential advantage, high-centering, pressure compliance and complete Copperline traversal.
- All 7 `test_linked_suspension.cpp` scenarios passed, including link geometry, static articulation, mass allocation, axle torque reaction and existing exploration-route fixtures. These verify model consistency, not real-vehicle accuracy.
- Twelve steering cases covered 2, 8 and 15 m/s entry speed, 0.25 and 0.65 steering command, and open/locked axles. Test duration after entry was three seconds with 0.2 throttle.
- At 2 and 8 m/s, all cases stayed upright. At 15 m/s (54 km/h), 0.25 input remained stable; 0.65 input rolled over with both open and locked axles. No safety clamps were recorded. Sharp steering at this speed can physically roll a lifted truck: this reproduction alone does not establish an erroneous rollover.
- Locked axles reduced heading change in the low-speed sharp-turn case (38.5 vs 54.8 degrees over three seconds), though speed also differed. This is not a constant-speed turning-radius measurement.

## Source findings

`wheel_axis()` applies the same steering angle to both front wheels. It lacks an inner/outer steering correction. Steering amplitude decreases with speed, but input response uses a first-order 8-per-second filter rather than an explicit steering-rate limit. The lateral tire model has the previously reproduced side-slope creep defect. Combined longitudinal/lateral impulses already have a shared Coulomb cap; a correction must preserve that budget.

## Crawling-first upgrade order

1. Resolve static lateral tire support and smooth transition to sliding, while retaining rolling, tire shear and multiple contact patches. Validate dry slope hold alongside low-friction breakaway and mixed drive/turn force limits.
2. Add inner/outer front-wheel steering geometry and measured steering-rate control. Keep full low-speed steering authority. Treat any high-speed input assistance separately from physical tire forces. Preserve deliberate front/rear locker controls.
3. Improve low-range driveline behavior with engine speed, torque/engine-braking curves and clutch or torque-converter coupling. Aim for controllable centimetre-scale approaches and descents. No automatic unlimited hill glue.
4. Calibrate existing four-link suspension using corner loads, measured travel, spring/damper response and progressive bump stops. Existing checks do not justify throwing out the current articulated suspension.
5. Improve tire-model calibration and diagnostics: lateral as well as longitudinal slip, contact load, shear and suspension limits. Consider greater tire carcass detail only after measuring its benefit and phone cost.

The current native solver is a coarse node-and-constraint vehicle with contact-based tires. More realistic behavior can be implemented within it. Full BeamNG-equivalent vehicle deformation is not established or promised. No new APK or production physics changes were made in this review.

Primary reference checked: NVIDIA PhysX vehicle documentation describes low-speed tire constraints and inner/outer Ackermann steering correction: https://nvidia-omniverse.github.io/PhysX/physx/5.1.0/docs/Vehicles.html
