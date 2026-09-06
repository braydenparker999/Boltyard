# Bolt Yard — Crawlworks 2.0: Expeditions

An offline Android crawling and exploration game built with Godot 4.4.1 and a native C++ vehicle solver. Explore two 640 × 640 m regions: **Silverpine Range**, a Rocky Mountain inspired pine-and-granite landscape, and **Karelian Taiga**, a Russian forest of birch, spruce, exposed bedrock and lakes. Both are fictional landscapes, with connected trails shaped into their terrain.

Choose a region in **Trails**, select a vehicle, press **Fit a crawling setup**, then **Explore**. Equipment and Setup have their own garage tabs. Each region remembers its discoveries and recovery point; saved vehicle builds remain available across regions.

## Camera and driving

| Control | Action |
|---|---|
| One finger on scenery, **Orbit** | Orbit sideways and tilt vertically |
| One finger on scenery, **Pan** | Move the camera framing sideways and vertically |
| Two-finger pinch / spread | Zoom only |
| **Follow** | Resume the driving view behind the rig |
| **Center** | Recenter the camera |
| Arrow pedals / **R** / **Brake** | Steer, drive, reverse and brake |
| **Rig** | Open drivetrain, throttle and suspension telemetry |

A pedal can remain held while another finger moves the camera. Adding or removing a camera finger rebases the gesture. Menus own their touches; rotation, pause and app backgrounding release stale controls. Garage and driving camera settings save separately. Terrain, granite and tree trunks block obstructed views.

## What changed

- **Natural exploration:** mountain contour trails, granite shelves, forest tracks, rock crossings and lakes. More than 2,400 collidable trees populate Silverpine and more than 3,000 populate Karelia. Shared native terrain triangles and convex rock hulls supply both visible surfaces and physics contact.
- **Terrain and forests:** original granite, litter, birch foliage and neutral daylight sky textures; moss and soil blending; layered conifer/birch crowns, understory and spatial vegetation batches. Performance remains the default quality setting.
- **Working suspension:** each solid axle now has a physical carrier with pitch inertia, two lower and two triangulated upper links, and coilovers acting at their actual mounting points. Axle housings, upper/lower rods, coilover eyes and driveshafts follow the solved geometry. Drivetrain and brake torque react against the axle carriers.
- **Tires and objects:** pressure-dependent tire compression, contact load and friction-limited drive/braking remain active. Rubber compresses at support while metal rims stay circular. Loose stones, logs and crates have gravity, orientation, friction and vehicle contact on the selected map's actual ground.
- **Mobile UI:** two region cards, separate garage tabs, compact round pedals and speedometer, an optional rig drawer, a contour/trail atlas, and independent region progress in portrait and landscape.

The engine remains Godot: the visible gaps were primarily landscape, material and suspension implementation. These are physically grounded game models, not a reproduction of BeamNG's vehicle system or measured real-truck calibration. Tires use compliant contacts and derived rubber guides, not a volumetric carcass. Water has a solid low-grip bed; there is no buoyancy, deformable mud or vehicle self-collision. Actual Samsung A15 frame rate, temperature and touch feel still require a phone test.

## Install and build

Package: `games.boltyard.prototype`. Version **2.0.0 / code 7**. The signing identity is unchanged; install over the previous app to retain saves. No Play Store account, runtime network access or storage permission is required.

The [Android workflow](https://github.com/braydenparker999/Boltyard/actions/workflows/android.yml) produces `bolt-yard-2.0.0-expeditions.apk`, verifies its signature and package, and records rendered gameplay, phone layouts and numerical traces. Final build evidence is recorded in [VALIDATION.md](VALIDATION.md).

Run `bash tools/ci_build.sh` on Ubuntu with JDK17 and an Android SDK. Dependencies are pinned to Godot4.4.1, godot-cpp revision `e4b7c25e721ce3435a029087e3917a30aa73f06b`, SCons4.8.1 and Android NDK23.2.8568313. Native tests exercise mass, contacts, grip, link geometry, torque reaction, route driving and movable objects. Engine tests cover mesh bindings, save migration, UI layouts, raw input ownership and camera lifecycle. Rendered reviews use the actual Compatibility shaders; desktop captures do not measure Android performance.

Key source: `native/soft_rig.hpp`, `native/dynamic_objects.hpp`, `native/expedition_terrain.hpp`, `native/expedition_rocks.hpp`, `native/binding.cpp`, `scripts/expedition_world.gd`, `scripts/offroad_truck.gd`, `shaders/vehicle_skin.gdshaderinc`, `scripts/offroad_main.gd`, `scripts/exploration_map.gd` and `scripts/two_finger_camera.gd`. The camera helper retains its historical filename but now implements one-finger movement and pinch-only zoom.

Legacy Juniper/Copperline fixtures and the original construction scene remain available for regression testing. The application opens `offroad_main.tscn`. [SIMULATION.md](SIMULATION.md) documents the mechanical model and its limits.
