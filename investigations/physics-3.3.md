# Crawlworks 3.3.0 — crawling physics implementation

This pass replaces the previous map-dependent drive equations with one SI-unit drivetrain and tire-contact path. It is a bounded mobile simulation, not a measured digital twin of a particular truck.

## Changes

- Engine inertia, idle control, a torque curve, converter slip and multiplication, finite lock-up, engine braking, reverse and a three-speed automatic. First gear is 3.06:1, axle ratio 4.10:1 and low range 2.72:1, multiplied by the existing final-drive setting. Neutral disconnects the engine. The part-time 4WD transfer case couples front/rear carrier speeds; axle lockers independently couple left/right wheels.
- Finite service brakes (2600 Nm per front wheel and 2200 Nm per rear wheel at full input), variable pedal pressure and a 3000 Nm rear parking brake. Brakes share tire friction capacity with cornering. Low-speed brake support is solved within the suspension constraint iterations, still bounded by available torque and normal load. Insufficient brake torque permits rollback.
- Persistent lateral tire shear follows the contacted material/body and surface normal, including moving obstacles. Contact states match one-to-one and reuse buffers. Longitudinal and lateral forces share one Coulomb budget. Tire pressure changes compliance and footprint rather than directly multiplying friction. Severe compression gains progressive rim support. The reference pressure mapping is 20 psi per former tuning unit; it is not a measured pressure-deflection curve.
- Solid axle carriers, four-link suspension and wheel manifolds now work consistently across maps. Their actual attachment geometry still drives the visible suspension parts. Existing Ackermann steering and steering-rate limits are retained.
- Position storage uses double precision to prevent tiny position-projection errors accumulating into airborne lateral momentum. Rendering remains in Godot's native precision.
- Movable-object contact polygons use the actual tilted support planes. The former flattening of support-face depths could inject energy into stacked crates. Normal impulses now also release when a contact unloads.
- The RIG drawer provides Neutral and Parking brake. Touch brake position controls pressure and displays its percentage. Telemetry includes RPM, gearing, lateral slip, friction usage and a bounded 20-minute trace in the copied performance report.

## Cleanup

Removed unreachable wheel-contact branches and the duplicate map-specific tire/drive response. Excluded obsolete prototype scripts/scenes and investigation documents from Android exports. Reused persistent tire-state buffers. Original map meshes, collision surfaces and installed textures remain available. Public-source builds treat private map packages as optional and validate them when present.

## Verification and interpretation

Native gates cover finite stopping distance, light/full brake response, engine versus neutral coasting, weak-brake rollback, braked incline hold, combined friction limits, transfer-case and axle-locker behavior, two steering directions, render-cadence independence, mass allocation, airborne momentum, spring sag, rebound damping, ledge contact, high-centering, loose-body momentum and the complete Copperline course. Exact rock queries are compared with their reference geometry.

Old acceleration assertions that assumed a scripted low-range speed target were replaced with ratio, torque, braking and contact behavior checks. Neutral controls isolate spring settling and passive coast from automatic idle creep. The narrow-post fixture approaches at crawling speed: at full throttle the truck can physically deflect around the pole, so requiring a fixed final position is not a valid collision test.

Desktop timings measure native CPU cost; they are not A15 FPS measurements. Godot integration checks cover garage state, map selection, touch ownership, camera layouts, vehicle geometry and suspension visuals. The final APK must additionally be checked for version, ARM64 native libraries, assets and signature before delivery.

## First phone test

1. Open Gridmap Refresh, use the pickup and select LOW. Begin with both axle lockers on and the existing rock tire package. Tire pressure is now shown in psi; old saved values preserve their equivalent setting.
2. Crawl an incline and a ledge with small throttle. Slide within the brake pedal to compare light braking with a full stop. Try lifting the throttle on a descent, then compare neutral coasting.
3. Try cross-axle obstacles with each locker independently. Observe actual tire load, side slip and suspension travel in RIG.
4. Compare a level surface with several tires on rocks using the same graphics setting. Use RIG → Copy performance report after reproducing any slide, jolt or frame drop.

Converter and tire parameters remain reference estimates. This does not implement full tire finite elements, soil rutting, tire heat/wear, full vehicle self-collision or BeamNG-equivalent crash deformation. A15 frame pacing and subjective tire feel require the user's phone test.

## Local release evidence

All 15 native suites pass, including 70 general vehicle checks and eight drivetrain scenarios. Light/full braking from the same rolling setup stopped in 7.235 m / 2.023 m. The braked incline held for 30 seconds with less than 0.02 m drift; reducing brake pressure to 1% allowed rollback. In-gear/neutral coast speeds after two seconds were approximately 4.05 / 6.67 m/s. The 20-degree dry side-slope control moved 5–8 mm sideways over five seconds with service brakes released, while the slippery control slid freely. These are synthetic fixtures, not measured truck calibration.

The packaged-resource smoke test loads Gridmap, Utah, Redstone Canyon, Rockies and Karelia with the new native API and original installed assets. Android version is 3.3.0 (code 19), package games.boltyard.prototype. The build uses official Godot 4.4.1 and Android NDK 23.2.8568313. Unneeded symbols were stripped from the bundled C++ runtime; its exported dynamic symbols remain.

The public GitHub push was blocked by automatic approval review because publication was not explicitly authorized. The ARM64 build and export were completed locally. No source was pushed by this release step.
