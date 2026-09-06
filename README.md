# Bolt Yard — Crawlworks 1.0

Crawlworks 1.0 is an offline Android offroading game built with Godot 4.4.1 and a native C++ vehicle solver. Copperline adds technical rock crawling and a loose-object line alongside the retained Juniper Valley exploration map. Three vehicles, six equipment slots, saved per-vehicle builds, and portrait/landscape play remain available.

## Start crawling

In the garage choose **COPPERLINE**, **Fit crawl setup to this rig**, then **DRIVE**. Start in LOW, hold GO and use the throttle slider for gentle torque. Front and rear differential locks can be switched independently. Clear each of the five sections to move the recovery point forward. The optional **LOOSE LINE** on the right contains nine physical stones, logs and crates that can slide, roll, stack and be pushed by the truck.

## Two-finger camera

Place two fingers on scenery; menus and pedals retain their own touches.

| Gesture | Result |
|---|---|
| Pinch / spread | Zoom out / in |
| Twist | Orbit around the rig |
| Two-finger drag, **Drag: Orbit** | Orbit sideways and tilt vertically |
| Two-finger drag, **Drag: Pan** | Pan sideways and up/down |
| **Follow** | Resume the driving view behind the rig |
| **Reset view** | Recenter and restore the default camera |

Garage and driving views save separately, including zoom, tilt, pan, follow and drag mode. Camera contacts rebase after finger changes and clear on screen rotation, pause and app backgrounding. The camera checks terrain and crawl rocks to keep the eye outside solids. Follow off holds the selected view angle while continuing to travel with the truck.

## What 1.0 changes

- **Crawl suspension:** front and rear solid axles, two trailing links and a Panhard bar per axle, physical differential/shaft clearance, independent lockers, compression/rebound damping and separate compression/droop travel.
- **Tire behavior:** pressure-dependent load deflection and footprint, finite low-speed slip, friction-limited angular drive/brake reaction, and actual wheel-set mass at unsprung hubs. Tire rubber flattens and bulges at support while metal rims remain rigid and rotate around the actual steered axle.
- **Movable world:** nine native convex rigid bodies with gravity, rotation, friction, rest/sleep/wake and equal/opposite vehicle contact. Their rendered faces and solved shapes are identical. Recovery resets them to the authored line.
- **Rendering:** fractured collision-backed sandstone silhouettes, layered minerals/quartz, gravel/silt lines, desert plants and grounded signs. Visible axle housings, springs, dampers, trailing links and Panhard bars follow the solved endpoints. Performance remains the default graphics setting.
- **Setup and feedback:** fourteen fine-tuning sliders plus independent axle controls; tire normal loads, squash in millimetres and axle articulation in degrees are visible while crawling. Old garage saves migrate without losing equipment or deliberate tuning.

These are physically grounded game models, not measurements calibrated to a real truck. The tire uses compliant contacts and derived visual guides rather than a full rubber finite-element carcass. There is no deformable soil, buoyancy, vehicle self-collision, working winch or detachable bodywork. Juniper Valley retains its proven independent-guide suspension and driving baseline. Sustained Samsung A15 FPS, thermal behavior and actual touch feel need testing on the phone.

## Android build

Package: `games.boltyard.prototype`. Version: **1.0.0 / code 6**. The development signing identity is unchanged; install over the previous app to retain saves. The game needs no Play Store account, runtime network access or storage permission.

The [Android workflow](https://github.com/braydenparker999/Boltyard/actions/workflows/android.yml) produces `bolt-yard-1.0.0-crawlworks.apk`, signature/package checks, gameplay movies, portrait/landscape/contact views and numerical traces. Build and artifact results are recorded in [VALIDATION.md](VALIDATION.md).

## Development

Run `bash tools/ci_build.sh` on Ubuntu with JDK17 and an Android SDK. The workflow pins Godot 4.4.1, godot-cpp revision `e4b7c25e721ce3435a029087e3917a30aa73f06b`, SCons4.8.1 and Android NDK23.2.8568313. It builds Linux and ARM64 GDExtensions, runs native and engine tests, renders real gameplay and exports/verifies the signed APK.

Native tests include the retained vehicle and complete-road regressions, full crawling course, solid axle/load/grip cases, movable-object contact and drive/brake momentum. Engine tests cover construction, driving, catalog/save migration, body and wheel geometry, actual two-touch input routing and camera lifecycle. Rendered reviews exercise the real Compatibility shaders. Desktop/software-rendered results are not phone performance measurements.

Source: `native/soft_rig.hpp` (vehicle), `native/dynamic_objects.hpp` (props), `native/crawl_rocks.hpp` (shared convex environment), `native/binding.cpp` (Godot API), `scripts/offroad_truck.gd` and `shaders/vehicle_skin.gdshaderinc` (vehicle mesh), `scripts/crawl_world.gd` (Copperline), `scripts/crawl_props.gd` (rigid meshes), `scripts/offroad_main.gd` and `scripts/two_finger_camera.gd` (UI/input), `scripts/vehicle_catalog.gd` (equipment/saves).

The earlier construction sandbox remains in `main.tscn`; the app opens `offroad_main.tscn`. More numerical detail and model limits are in [SIMULATION.md](SIMULATION.md).
