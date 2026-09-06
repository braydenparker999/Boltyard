## Crawlworks 2.3 Thumbdrive — verified 2026-09-06

Signed Android build [34055272179](https://github.com/braydenparker999/Boltyard/actions/runs/34055272179) passed from source `99579225adb5ba63b6a8dc592da4e0de08edc6bd`, tree `37c97474306181f405384d7cca4a3d66c72b3b39`. Native recovery checks cover preserved damage, upright heading, support, rejected placement and all trail starts. Actual touch dispatch and camera integration passed 213 checks; the full build retained native, vehicle, terrain and rendered checks. Portrait recovery and portrait/landscape driving screenshots were inspected. The first build exposed a legacy camera fixture touching the new thumb strip; its gesture positions were corrected without weakening movement checks.

Downloaded APK `bolt-yard-2.3.0-thumbdrive.apk`: 43,295,510 bytes; SHA-256 `c1d913faef56f52282de434ddeb34f6b716da57c1f2252dc7508cf88f7254fa8`. Package `games.boltyard.prototype`, version 2.3.0, code 10, ARM64. ZIP integrity, workflow checksum, packaged mobile controls and native recovery binding verified. Official apksigner verified v1/v2/v3 signatures with the unchanged certificate SHA-256 `a882ee66b05eff32ad4629269a96d79bfc3514bcbf0e16e99f42f6046836ea73`.

2.3 has not yet been tested on the user's phone. The supplied 2.2 A15 capture is recorded in README as the device baseline. Recovery uses conservative placement bounds and may refuse dense obstacles; safe-spot history lasts for the current drive. Movies are opt-in via `BOLT_RECORD_MOVIE=1`; ordinary builds still render gameplay and UI stills.

# Crawlworks 2.2 Articulation — verified Android update

[Android run 34051952587](https://github.com/braydenparker999/Boltyard/actions/runs/34051952587) passed on 2026-09-06, building release source [`075e5e8e69998ae284c220c65ca26e9a2ecb3177`](https://github.com/braydenparker999/Boltyard/commit/075e5e8e69998ae284c220c65ca26e9a2ecb3177). Its complete Git tree `bdbc77488a87480aca3c00dd65f7f77786b12701` matches the local tested tree. This documentation-only follow-up records the downloaded evidence.

## Installable package

- `bolt-yard-2.2.0-articulation.apk`: 43,283,045 bytes.
- SHA256: `572d867a93788a0ad2f608ba6847e87d8dc3af9e75e7e1de9c3c1db6f264e746`.
- Package `games.boltyard.prototype`, version 2.2.0, code 9, ARM64.
- The official Android apksigner independently verifies v1, v2 and v3 signatures on the downloaded APK. Its certificate SHA256 remains `a882ee66b05eff32ad4629269a96d79bfc3514bcbf0e16e99f42f6046836ea73`.
- ZIP CRC, workflow checksum, binary AndroidManifest package/version, ARM64 solver, C++ runtime and new suspension interface checked independently. Packaged suspension/tire shader matches the reviewed source byte-for-byte.
- Install over the existing app to retain builds and map progress. Package, signing key and save paths are unchanged; actual phone installation remains untested here.

## Performance and physical behavior

[PERFORMANCE.md](PERFORMANCE.md) and its raw CSVs record the same-host baseline/final scenario ladder. Four-wheel median native CPU cost per 30 Hz presentation frame drops from 27.45 to 2.82 ms, with p95 from 32.28 to 4.17 ms. Silverpine rolling median drops from 44.90 to 4.67 ms. These exclude GPU/render cost and do not establish A15 FPS. No solver frequency, iteration count, tire support count, grip or terrain fidelity was reduced.

Native gates pass 78 baseline cases, both retained road drives, ten crawling scenarios, eight Crawlworks scenarios, the movable-object suite, seven linked-suspension/route scenarios, 190,800 expedition checks, six causal tire-contact scenarios, 80,402 exact reference distance comparisons and the added spring-sag/stroke-packaging test. Soft/firm mean sag is 122.50/60.72 mm; the low/high rebound fixture peaks at 1.403/1.066 m/s with the retained settling thresholds. The pressure-width fixture measures paired sidewall separation to remove common shear, retaining its widening threshold and separate shear test.

The release passes 837 retained/new headless engine assertions, including 288 actual camera-input checks, 257 vehicle geometry checks and 40 suspension-pose checks. Rendered gates additionally pass 27 world checks and 2,315 loaded-rubber checks. The retained legacy driving fixtures also pass. Follow/Trail locking, Free gestures, pinch ownership and save restoration are retained.

## Actual rendered review and clip

[Final focused render run 34051843409](https://github.com/braydenparker999/Boltyard/actions/runs/34051843409) passed, followed by complete rendering on the Android release run. Review covers loaded compression, airborne droop, steering and cross-axle suspension, plus portrait/landscape camera and Rig panels. The first still review caught weak visual tower support and a short diagnostics backdrop; the final build adds visible triangulated braces and encloses the complete report panel.

Fixed body/shaft/eye/wire errors in the four-pose fixture remain below 0.000001 m. The fitted fixture buggy uses 11,558 triangles in the existing material surfaces; no separate simulated decorative bodies were added. Lower/upper link eyes follow actual solved endpoints. New springs have eight turns with fixed 16 mm wire and changing pitch. Detailed knuckle/driveshaft simulation and self-collision remain outside this bounded model.

The downloaded gameplay clip is H.264, 960×540, 24.0667 seconds, 722 encoded frames and 12,704,064 bytes. Its fixture records 720 gameplay frames with actual throttle/brake input and camera touches, with two explicitly labelled trail-start scene cuts. Both routes reach three simultaneously rock-supported wheels:

| Map | Displacement | Peak rock-supported wheels | Peak rock support | Final braked speed | Damage |
|---|---:|---:|---:|---:|---:|
| Silverpine | 9.42 m | 3 | 5.48 kN | 0.00797 m/s | 0 |
| Karelia | 9.03 m | 3 | 8.31 kN | 0.00330 m/s | 0 |

Both routes remain upright without safety clamps or rejected states. Frames extracted from the final movie confirm actual rock contact; static rendered poses expose the working mechanisms. This is desktop software-rendered behavior/appearance evidence, not phone FPS. A15 frame pacing, thermals, installation and thumb feel remain pending. The Rig panel's rolling timing window and Copy performance report action support that next device check.

---

# Crawlworks 2.1 Trailcraft — verified Android release

[Android run 34045707356](https://github.com/braydenparker999/Boltyard/actions/runs/34045707356) completed successfully on 2026-09-06 against [`4dccf62e8293d02109a07d11f011ac796282e7c1`](https://github.com/braydenparker999/Boltyard/commit/4dccf62e8293d02109a07d11f011ac796282e7c1). The 29 changed source/document blobs match the reviewed local files. A later documentation-only commit records this evidence.

## Installable artifact

- File: `bolt-yard-2.1.0-trailcraft.apk`, 43,270,598 bytes.
- SHA256: `1b53665a9e923a0f3dfbf833d8ba8949fe41be6d0dc9f59739b4c0f4b2bb8852`.
- Package `games.boltyard.prototype`; version 2.1.0; Android version code 8.
- Downloaded ZIP CRC, workflow checksum, ARM64 solver, C++ runtime and new contact-patch interfaces verified independently. The packaged tire shader matches the reviewed source byte-for-byte.
- Android apksigner verified v1/v2/v3 signatures. Certificate SHA256 remains `a882ee66b05eff32ad4629269a96d79bfc3514bcbf0e16e99f42f6046836ea73`, supporting updates over the preceding app without replacing its saves.

## Controls, terrain and tire contact

The exact release passes 797 headless engine checks, 27 rendered world checks, and the loaded-rubber geometry fixture. Camera integration covers 288 actual-input checks; the gesture helper covers 60. Follow and Trail remain locked after scenery drags and steering misses. Explicit Free permits orbit/tilt/pan. Pinch stays zoom-only, even while its center moves and its fingers rotate. Portrait/landscape panels, larger steering hitboxes, guards, save migration, menu ownership and lifecycle cancellation pass.

Native gates pass 78 baseline cases, 2 retained full-road scenarios, 10 crawling scenarios, 8 Crawlworks scenarios, 7 linkage/route scenarios, 190,800 terrain/hull checks, the movable-object suite and 6 causal tire-contact scenarios. The latter independently change pressure, remove a supporting rock face, change surface friction, apply traction shear, climb one convex ledge with two loaded normals and compare moving wood/stone materials. Tests measure effects on motion and support; they do not establish real-tire calibration.

The same static load produces 15.24 mm compression at relative pressure 0.55 and 5.16 mm at 1.65. In actual driven corner captures, a tire loads two planes simultaneously and both planes reach its rendered skin. Sampled tread has no measured penetration; rigid rim radius error is below 1 micrometre. Rubber beads remain fixed to the rim. Six bounded static patches are retained; moving objects still use one tire contact per object pair. There is no independently integrated tire carcass or FEM.

Ground curvature at the 99th percentile drops 79%/77% from the prior Silverpine/Karelia design while preserving the exact 2 m contact grid. Curved routes total 1747/2048 m, with maximum sampled grades 0.308/0.133. Native and visible rocks share closed convex hull geometry, and rounded lighting preserves selected hard ledges. The forests contain 2554/3028 native/render-matched trunks. Surface weights, wetness and loose-ground cues come from the same native material data as grip.

## Rendered gameplay and limits

The final H.264 preview is 960×540, 24.0667 seconds, 722 encoded frames. Its fixture records 720 gameplay frames with actual throttle, braking and raw camera touches. Both trail drives stay upright, undamaged and free of emergency state repairs:

| Map | Displacement | Peak granite support | Final held speed |
|---|---:|---:|---:|
| Silverpine | 9.36 m | 6.31 kN | 0.00053 m/s |
| Karelia | 9.06 m | 6.95 kN | 0.00237 m/s |

Two explicitly labelled trail starts are scene cuts; suspension and wheel poses are solved during the drives. The visual review covers terrain/contact close-ups, garage/map/rig panels and Follow/Trail/Free in both orientations. Final captures confirm the compact driving header, readable gauge and corrected shadow bias. The shadows-on/off pair uses an identical camera to separate shadow acne from material detail.

A first still-only review reached its 180-second capture limit; shorter redundant settling allowed the same views to finish. The first Android pass caught a retained recording fixture that expected implicit camera unlocking; the fixture now selects Free explicitly, with all movement assertions retained. The final successful run includes those corrections.

All maps and materials remain original or previously documented assets; no BeamNG maps were imported. Desktop software rendering verifies appearance and behavior, not sustained Samsung A15 FPS, thermal performance, installation or thumb feel. This is a bounded, uncalibrated game simulation, not BeamNG parity.

---

# Crawlworks 2.0 — verified Android release

[Android run 34010969782](https://github.com/braydenparker999/Boltyard/actions/runs/34010969782) completed successfully on 2026-09-06. Source: [`fcad915d2ef2484fbbc37ed8203225cf3cb42132`](https://github.com/braydenparker999/Boltyard/commit/fcad915d2ef2484fbbc37ed8203225cf3cb42132). All 46 changed source/asset blobs were matched against the local reviewed files before the build.

## Installable artifact

- File: `bolt-yard-2.0.0-expeditions.apk`, 43,241,926 bytes.
- SHA256: `eab413923d0f5883efd1d7cc72e8e6ef7297b1fc5e480a8e5b265e1d7c347cd8`.
- Package `games.boltyard.prototype`; version 2.0.0; Android version code 7.
- APK ZIP CRC and workflow checksum verified independently after download. ARM64 solver, C++ runtime, new expedition APIs and all four new textures are present. Packaged vehicle shader include matches the reviewed source exactly.
- `apksigner` verified v1/v2/v3 signatures. Certificate SHA256 remains `a882ee66b05eff32ad4629269a96d79bfc3514bcbf0e16e99f42f6046836ea73`, preserving update compatibility with 1.0.

## Validation

The workflow passed 623 engine checks, including 257 vehicle geometry checks, 100 actual-input camera integration checks, 56 gesture checks, 27 new region/UI checks and 18 rendered-world checks. Native results: 78 baseline cases, 10 crawl scenarios, 8 Crawlworks cases, 7 new linkage/route scenarios, 2 retained complete-road cases,59, 273 map structure checks and the movable-object suite.

Both 90-second native expedition drives reached their fourth route point without damage or safety corrections. Maximum sampled road grades, shared triangle contact, closed convex rock hulls, tree clearance, wheel/carrier mass allocation, actual four-link endpoints and opposing carrier/rotor torque were checked. The two maps contain 2,431 and3,039 native/render-matched trees.

Legacy road control review reached 38.9 km/h, remained upright and undamaged, then stopped. The Copperline review climbed to 1.88 m frame height and held; its loose-object line moved a body 2.809 m through actual contact. Their original numerical gates are retained as headless regressions, and all temporary save fixtures are restored.

## Full rendered gameplay

The final clip is 960×540 H.264, 30.0667 seconds/902 encoded frames,11,397, 102bytes. The fixture records 900 measured gameplay frames across Silverpine and Karelia. Both real throttle drives completed without damage or emergency state repair:

| Map | Displacement | Peak granite support | Final held speed |
|---|---:|---:|---:|
| Silverpine |10.42m|4.46kN|0.00047m/s|
| Karelia |11.04m|4.45kN|0.00247m/s|

Actual raw one-finger orbit/tilt and pan passed. Pinch changed camera distance by 3.58 m while preserving orbit, pitch and pan. Final close screenshots expose the linked axles and tire contacts without caption overlap. Eight portrait/landscape garage, map, rig and camera layouts plus six landscape views were inspected. All new Compatibility shaders compiled without errors.

The earlier local software recording reached 448/900 frames before its 360-second watchdog; it was used only for visual QA. The delivered clip comes from the successful complete CI capture. Desktop software rendering verifies appearance and game behavior, not sustained Samsung A15 FPS or thermal performance. Phone installation and touch feel still need the user's device test. The simulation remains a simplified, uncalibrated game model rather than BeamNG parity.

---

# Crawlworks 1.0 validation

[Android run 34008254341](https://github.com/braydenparker999/Boltyard/actions/runs/34008254341) succeeded against source `98b6db7c6eca622971398c74e76d4960b7b1a78a`. The exact source passed 541 Godot engine checks, 78 general native checks, both full-road scenarios, ten crawl scenarios, eight new Crawlworks mechanics scenarios, and the movable-object suite. Rendered gameplay and camera gates passed, followed by signed ARM64 export.

- APK: `bolt-yard-1.0.0-crawlworks.apk`, 36,326,272 bytes.
- SHA-256: `267ed4c0487c5a802e99d56bc978ce29bb42107d7d790e549ee4e912c77d8fcb`.
- Package/version: `games.boltyard.prototype`, 1.0.0 / code 6, ARM64.
- APK signatures: v1, v2 and v3 verified; update certificate SHA-256 remains `a882ee66b05eff32ad4629269a96d79bfc3514bcbf0e16e99f42f6046836ea73`.
- Downloaded ZIP integrity, artifact checksum, native interfaces, exact final ground shader and package metadata independently checked before delivery.
- Final gameplay clip: H.264, 960×540, 30 fps, 27.0667 seconds, 3,867,601 bytes. It shows a controlled climb/hold, real loose-object drive/brake contact and raw two-finger camera motion.

The final recorded climb ends at z=-9.01m, peak frame height 1.90 m, zero damage and final speed 0.000 m/s. A loose object moves 3.134 m under actual vehicle contact; the settled rig has up.y = 1.000 and zero damage. Raw touch input produces -0.720rad orbit, -3.024m camera distance and 0.396 m pan. The movie includes an explicit reset between the crawl and loose-line demonstrations; the contact poses themselves are solved, not manually posed.

Local checks completed during implementation:

- Existing Godot suites:31 construction,18 offroad,53 catalog,36 explorer,257 vehicle geometry and11 crawl integration checks pass.
- Two-finger input:48 geometry and79 actual-scene integration checks pass, including convex camera clearance, both orientations, GUI/pedal ownership, finger lifecycle, follow/reset, pause/rotation and save round-trip.
- Tire visual checks confirm measured loaded deflection, circular rigid rims and outer tread outside the loaded plane; three camera obstruction regressions also pass.
- Eight new native mechanics scenarios cover crossed-axle articulation, exact unsprung wheel mass, pressure/load footprint, independent lockers, physical differential clearance, tiny-throttle creep/braked hold movable tire contact and measured rebound damping.
- Native prop tests cover convex queries, angular response, dropping, stacks/rest/sleep/wake, reset determinism and coupled drive/brake momentum.
- Rendered views check shared collision/visual rock triangles, landscape/portrait controls, contact skin and the loose-object line.

Final native regressions, gameplay rendering and Android export were repeated on the exact committed release source. Desktop/software rendering does not establish Samsung A15 FPS, thermal behavior or actual touch feel. Real vehicle/tire calibration has not been performed.

---

# Crawlworks 0.5 validation

The crawling milestone adds ten native behavioral scenarios and eleven Godot integration checks. The native full-course test traverses to beyond z = -78 m with controlled throttle/steering, brakes to rest, and requires zero safety clamps, rejected states or structural damage above 1%. Its latest measured minimum up.y is 0.910. This is an actual-input numerical traversal, not an on-device play test.

The elevated-platform scenario confirms rock-only support and powered acceleration without hidden terrain support. Other scenarios cover stable incline hold/restart, low-speed beveled ledges, wheel angular momentum in air, consistent frame cadence, convex shared geometry, open/locked split grip, skid high-centering and pressure-dependent clearance.

Integration coverage checks matching native course selection, fitted equipment, retained lighting across course changes, landscape/portrait control bounds, recovery input clearing, tuning at a checkpoint and preservation of valley discoveries. Recovery now retains the current terrain mode; resetting a truck must not silently switch its collision back to the valley.

`tests/crawling_video.gd` records live throttle input onto the training slab, brakes, and checks progress, vehicle height, upright attitude, damage and final speed. `tests/crawl_views.gd` captures landscape, portrait and a tire-contact close-up. Both are part of Android CI, alongside retained valley tests. Per-wheel loads, spin, slip, travel and native timing are saved in `crawling-trace.json`.

The Android workflow succeeded before delivery (record below). Physical A15 installation, sustained frame rate, thermals and touch feel remain untested here. Version/code are 0.5.0/5; package and signing configuration are unchanged.

## Verified Android delivery

[Android run 34006217325](https://github.com/braydenparker999/Boltyard/actions/runs/34006217325) succeeded against source commit `90d2c39120c0c693e1a0296b86cdc6d70da730d2`. It passed 478 assertions, ten crawling scenarios and both retained full-road scenarios. The rendered crawling capture finished at z = -9.01 m, maximum frame height 1.94 m, damage 0.0000 and zero final speed. Portrait, landscape and loaded-contact views were reviewed from the same run.

- APK: `bolt-yard-0.5.0-crawlworks.apk`, 35,961,091 bytes.
- SHA-256: `2c966371190f61ab2cd18faa782a187fa3b3ff28683bc09df9eac5130561ed2b`.
- Package/version: `games.boltyard.prototype`, 0.5.0 / code 5, ARM64.
- Signing certificate SHA-256: `a882ee66b05eff32ad4629269a96d79bfc3514bcbf0e16e99f42f6046836ea73`, matching v0.4.
- Android apksigner verified v1, v2 and v3 signatures. The downloaded ZIP/APK passed integrity and checksum checks; the native solver and new sandstone shader are packaged.

The graphics captures use desktop software rendering. Their displayed FPS values are not measurements of A15 performance. Installation and sustained play still need the user's device test.

---

# Validation record — Bolt Yard 0.4, 2026-09-05

The handling rebuild passes 78 native checks and two complete exploration-road driving scenarios. Local Godot tests pass 31 retained construction checks, 18 offroad integration checks, 47 catalog checks, 36 exploration/save/orientation checks, and 257 vehicle geometry checks: **467 assertions plus two road scenarios**.

## Handling

Default pickup speed after five seconds increases from 17.39 to 52.89 km/h on flat ground. Ten-second distance increases from 41.50 to 123.48 metres; flat vertical chassis velocity RMS falls from 0.0444 to 0.00018 m/s. The same host benchmark measures native CPU around 0.17–0.31 ms per 60 Hz frame versus 0.607 ms previously. Timing varies with concurrent host work and excludes graphics.

All three vehicles hold a 27% grade within 0.00071 m over ten seconds and restart uphill. A 1.299 km route completes with 28.8 and 45 km/h cruise targets and braking for bends, without damage, rejected states or velocity clamps. Driving cadence matches exactly at 10/15/30/60/120 Hz and with irregular frame intervals. Reverse-at-speed first brakes before reversing.

The local 21-second actual-control movie reaches 38.9 km/h along the trail, has minimum upright-vector y of 0.972, no damage or solver recoveries, and brakes to rest. A final movie with the finished materials is also required by the Android workflow. These are software-rendered host captures, not phone frame-rate results.

## Bodywork and graphics

The 257 geometry checks cover stock and fully fitted pickup, Scout and buggy builds. They inspect deformed vertices under steering, impact, cab dents and far-origin repair, rejecting nonfinite/degenerate triangles, opened shared seams and mesh-reuse failures. The stock models have 10,132 / 10,202 / 8,678 triangles; fully fitted variants have 10,296 / 10,366 / 8,574.

Actual OpenGL views were inspected for all three vehicles from front, side and rear, plus installed accessory combinations. Fixes include continuous shared panel deformation, enclosed wheel wells and interiors, supported buggy braces, attached roof/spare hardware, readable lamps, correct metal wheels and distinct paint/glass/rubber response.

World checks cover source-color conversion, mipmapped materials, ground/physics agreement, rock/shore geometry, detailed foliage, shadows, cached reflections and the new photographic sky, stone and foliage assets. Generated material prompts and provenance are in assets/world. Water remains scenery over a solid low-grip lake bed; it does not simulate buoyancy.

## Android build

The workflow builds and tests the native Linux and Android ARM64 libraries, renders 13 static views plus four driving frames and a controlled 21-second movie, exports the APK, and verifies signatures, package information and checksum. The final [Android workflow](https://github.com/braydenparker999/Boltyard/actions/runs/33992149892) passed against source commit `b45819237a2c816715bec2be3a8152de5acb95e6`. All 80 source/asset updates were compared with that exact Git tree before reviewing its artifacts.

- Artifact: `bolt-yard-0.4.0-trailworks.apk`, 35,940,368 bytes.
- SHA-256: `99e5249891e55a5c6c0adeefce7ab9db3850f42ff6c02d0e7695eecd6847b5f3`.
- Signing certificate SHA-256: `a882ee66b05eff32ad4629269a96d79bfc3514bcbf0e16e99f42f6046836ea73`; matches the previous installed-development build certificate.
- Package: `games.boltyard.prototype`, version 0.4.0 / code 4, ARM64.
- Android orientation: `fullUser` (13); no requested permissions.

The downloaded APK passed ZIP integrity, checksum and native-extension/runtime packaging checks. The three new photographic assets and dust shader are included. Android apksigner verified v1, v2 and v3 signatures. The matching package/key and unchanged save paths support updating in place; actual installation on the user's phone remains untested here.

The final workflow passed all 467 assertions and both full-road scenarios. Static captures contain no script/shader errors. Its final driving trace reports peak 38.9 km/h, minimum up.y 0.972, damage 0.0000, zero safety clamps/rejected states and a clean stop. Review footage and 17 screenshots come from the built source; they are not on-device performance captures.

The build artifacts are `bolt-yard-android` (APK/checksum) and `bolt-yard-build-logs` (logs, images, trace and movie). A later documentation-only commit records these results without changing the app.


## Device scope

The user tested earlier versions on a Samsung A15 and identified slow/glitchy handling and incomplete vehicle geometry in 0.3. No physical Android device or emulator has been accessed for 0.4. Installation/update behavior, actual touch feel, frame rate, temperature, background/resume and sustained battery cost still need validation on that phone. Existing package, signing key, save paths and orientation support are retained.
