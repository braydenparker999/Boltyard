## Redrock Basin

A third 640 × 640 m region. **Redrock Basin** is high desert: a sandy wash
draining a basin between a flat-topped mesa, a slickrock dome field, a standing
fin field and a set of scoured pothole benches. The per-region route ceiling
rose from four to six to hold it, and route difficulty is now declared data
rather than an index comparison, so the trail atlas draws the technical lines
in their own colour.

Six named routes share it, and every one hands off to another at a junction
they hold in common, so any technical line can be left for an easier one:

| Route | Grade | What it is |
|---|---|---|
| **Basin Wash** | Easy | The sandy loop, run as a figure eight through camp, that every other route leaves from and returns to |
| **Dome Traverse** | Moderate | Rolling bare slickrock over the eastern swell |
| **Mesa Rim Road** | Moderate | The exposed shelf circuit around the top of the mesa |
| **The Fins** | Technical | Corridors between standing sandstone walls |
| **Devils Staircase** | Technical | The stacked ledge climb up the mesa flank, and the only way to the rim road |
| **Pothole Flats** | Technical | Scoured benches, short drops and the water pocket |

The landform is a bedrock platform cut into flat benches, so the ground a tire
reads stays a surface: the metre-scale walls, fins and ledge steps are exact
convex hulls in the rock cache, the same geometry that is drawn. Bedding fades
out as the grade rises, because risers stacked on a cliff face would be steeper
than the cliff. Route elevations were solved against that landform and then
relaxed until every span is climbable, so the trails follow the ground instead
of cutting a bench into it.

Redrock inverts the other two maps' materials. Bare sandstone is the default
ground and the third material channel carries wind-blown sand rather than
forest floor, so **Sand** joins dirt, dry and wet rock, mud and gravel as a
reported contact material. Dry slickrock is the grippiest surface in the game
and dry sand one of the loosest; a gravel bar runs down the wash between them.
Vegetation is pinyon-juniper rather than forest — 342 trees against Silverpine's
2554 — and that budget is spent on 227 rock hulls instead.

In the Linux render review, at the same quality and framing the other two
regions are captured at, Redrock draws 222 calls and about 155,000 triangles
against Silverpine's 185 calls / 446,000 triangles and Karelian Taiga's 247 /
282,000 — the trees it does not have cost more than the rock it does. These are
desktop Compatibility-renderer counts, not an Android measurement; Samsung A15
frame rate and thermals for this region still need a phone test.

Building a region now costs roughly 40% less than it did, for all three: the
surface pass reuses the nearest-route answer the height pass already computed
rather than walking the whole trail network a second time per grid cell.
Silverpine and Karelian Taiga are otherwise unchanged, vertex for vertex.

---

## 2.3 Thumbdrive

Portrait-first analog steering and progressive throttle replace the digital driving pedals. Range, front/rear axle locks and local recovery sit in a permanent thumb-height row. FWD/REV selects direction; changing direction releases a held throttle. Pause offers control size, vertical position and steering sensitivity, saved with the garage.

Recovery offers **Right vehicle nearby** and **Last safe spot**. It searches within 12 metres for gently sloped ground with conservative clearance from rocks, trees and movable objects; if no site fits, the rig stays put. Repositioning retains heading, damage, broken beams, tuning and world objects. Stable trail positions are kept for the current drive; before any are recorded, Last safe spot uses the trail start. Return to garage and garage repairs remain separate.

The A15 2.2 report supplied by the user covered 240 frames / 9.75 seconds at Performance quality, portrait 720×1560, scale .75: 24.6 FPS average, frame p95 48.06 ms and worst 54.19 ms, with no discarded simulation time or safety corrections. This is the device baseline, not a claim about 2.3 speed.

# Crawlworks 2.2: Articulation

This update targets the severe multi-wheel rock-contact stalls reported on the Samsung A15. Exact convex queries now use a triangle bounding-volume tree, preserving the original rounded collision/render hulls, 240 Hz physics, nine iterations, secondary tire support, grip and mass. Host profiling and measurements are in `PERFORMANCE.md`; on-device acceptance remains pending.

Coilovers now have fixed-length bodies, telescoping shafts, spring seats and constant-diameter spring wire. Mount eyes, bolts and link ends follow solved attachment points. Long-travel packages raise their actual shock towers enough to house the stroke, with visible tower supports and dissipative bump stops. Axle tubes extend to their hub housings. There are no new independently simulated decorative bodies.

In **Rig**, frame median/p95/p99, CPU physics/skin cost, rock-supported wheel count and >50 ms frames show a rolling 240-frame window. **Copy performance report** copies device, setup, map, timing samples and contact telemetry for comparison. Frame intervals include presentation waiting; these are not GPU timings. Background pauses restart the window.

Install the signed 2.2.0 update over the previous app to retain builds and map progress. Package and signing identity are unchanged. Performance quality remains the A15 starting point; sustained device frame rate and thermals still need a phone test.

---

# Bolt Yard — Crawlworks 2.1: Trailcraft

An offline Android crawling and exploration game built with Godot 4.4.1 and a native C++ vehicle solver. Explore three 640 × 640 m regions: **Silverpine Range**, a Rocky Mountain inspired pine-and-granite landscape, **Karelian Taiga**, a Russian forest of birch, spruce, exposed bedrock and lakes, and **Redrock Basin**, a high-desert basin of slickrock domes, standing fins and a mesa rim. All three are fictional landscapes, with connected trails shaped into their terrain.

Choose a region in **Trails**, select a vehicle, press **Fit a crawling setup**, then **Explore**. Equipment and Setup have their own garage tabs. Each region remembers its discoveries and recovery point; saved vehicle builds remain available across regions.

## Camera and driving

| Control | Action |
|---|---|
| Camera preset button | Cycle **Follow → Trail → Free → Follow** |
| **Follow** / **Trail** | Locked driving views; Trail gives a closer, higher view of the front tires |
| One finger on scenery in **Free** | Orbit sideways and tilt vertically |
| **Pan** in Free | Switch one-finger dragging to move the framing sideways and vertically |
| Two-finger pinch / spread | Zoom only |
| **Center** in Free | Return to locked Follow; in the garage, recenter its camera |
| Arrow pedals / **R** / **Brake** | Steer, drive, reverse and brake |
| **Rig** | Open drivetrain, throttle and suspension telemetry |

Follow and Trail ignore scenery drags. Choose Free explicitly before orbiting, tilting or panning; pinching never pans, tilts or twists any preset. A pedal can remain held while other fingers use the camera. Steering targets are 108 × 108 logical pixels, with an additional 18-pixel camera exclusion border around pedal hitboxes. Adding or removing a camera finger rebases the gesture. Menus own their touches; rotation, pause and app backgrounding release stale controls. Garage and driving camera settings save separately, and older saves start in locked Follow. Terrain, granite and tree trunks block obstructed views.

## What changed

- **Smoother terrain:** curved trail routes, broad rolling landforms and rounded granite crowns with selected fractured ledges. These shapes change the native contact surface. Nearby terrain uses the native 2 m triangles; distant scenery uses simpler meshes. Rock render vertices match their convex collision hulls, with smooth crown lighting and distinct ledge rims.
- **Material cues:** ground and rock shading use the same surface weights and wetness that determine grip. Fine normal detail fades with distance. Forests retain layered conifer/birch crowns and spatial batches; Performance remains the default quality setting.
- **Loaded tire contacts:** each tire can retain up to six static terrain/rock patches with separate support planes, loads, friction and rubber shear. Pressure changes loaded compression, footprint and sidewall bulge. Rubber can meet multiple rock faces while the rims and beads stay rigid. Movable stones, logs and crates retain their own contacted materials and equal/opposite contact reactions.
- **Deliberate camera controls:** locked Follow and Trail views, explicit Free camera, pinch-only zoom, larger steering targets and camera touch guards. Region progress, the trail atlas, garage tabs and rig telemetry remain available in portrait and landscape.

The four-link axle carriers and coilovers continue to act at their actual mounting points, with drivetrain and brake torque reactions. Tires remain a bounded contact model with derived rubber geometry; there is no finite-element carcass, puncture model or measured real-truck calibration. Movable objects use one tire contact per object rather than the static multi-patch solve. Water has a solid low-grip bed; buoyancy, deformable mud and vehicle self-collision are not implemented. Samsung A15 frame rate, temperature and touch feel still require a phone test.

All three regions are original landscapes, generated at runtime from the anchor tables and noise fields in `native/expedition_terrain.hpp`; the repository contains no heightmap or terrain mesh files at all. [BeamNG's Johnson Valley development notes](https://beamng.com/game/news/blog/beamng-drive-v0-27/) and [Moab's creator notes](https://www.beamng.com/resources/moab-utah.26830/) informed the use of broad eroded forms and deliberately placed trail obstacles, and Redrock Basin takes the same kind of reference from Colorado Plateau canyon country. No BeamNG maps, heightmaps, meshes or textures were imported, and no real place is reproduced.

## Install and build

Package: `games.boltyard.prototype`. Version **2.1.0 / code 8**. The signing identity is unchanged; install over the previous app to retain saves. No Play Store account, runtime network access or storage permission is required.

The [Android workflow](https://github.com/braydenparker999/Boltyard/actions/workflows/android.yml) exports `bolt-yard-2.1.0-trailcraft.apk`, verifies its signature and package, and records rendered gameplay, phone layouts and numerical traces. Build evidence is recorded in [VALIDATION.md](VALIDATION.md). The [render review workflow](https://github.com/braydenparker999/Boltyard/actions/workflows/render-review.yml) captures Linux camera, world and tire stills without building an APK.

Run `bash tools/ci_build.sh` on Ubuntu with JDK 17 and an Android SDK. Dependencies are pinned to Godot 4.4.1, godot-cpp revision `e4b7c25e721ce3435a029087e3917a30aa73f06b`, SCons 4.8.1 and Android NDK 23.2.8568313. Native tests exercise mass, contacts, grip, link geometry, torque reaction, route driving and movable objects, including six causal tire-contact scenarios. Engine tests cover mesh bindings, save migration, UI layouts, raw input ownership and camera lifecycle. Run `bash tools/render_review.sh` on Linux with Xvfb for still review. Rendered reviews use the actual Compatibility shaders; desktop captures do not measure Android performance.

Key source: `native/soft_rig.hpp`, `native/dynamic_objects.hpp`, `native/expedition_terrain.hpp`, `native/expedition_rocks.hpp`, `native/binding.cpp`, `scripts/expedition_world.gd`, `scripts/offroad_truck.gd`, `shaders/vehicle_skin.gdshaderinc`, `scripts/offroad_main.gd`, `scripts/exploration_map.gd` and `scripts/two_finger_camera.gd`. The camera helper retains its historical filename; driving camera movement is gated by the explicit Free preset.

Legacy Juniper/Copperline fixtures and the original construction scene remain available for regression testing. The application opens `offroad_main.tscn`. [SIMULATION.md](SIMULATION.md) documents the mechanical model and its limits.
