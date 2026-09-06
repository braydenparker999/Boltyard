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
