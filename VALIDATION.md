# Crawlworks 1.0 validation

Release candidate: package `games.boltyard.prototype`, version 1.0.0 / code 6, unchanged development signing identity. Android artifact/signature results will be recorded here after the workflow completes.

Local checks completed during implementation:

- Existing Godot suites:31 construction,18 offroad,53 catalog,36 explorer,257 vehicle geometry and11 crawl integration checks pass.
- Two-finger input:48 geometry and79 actual-scene integration checks pass, including convex camera clearance, both orientations, GUI/pedal ownership, finger lifecycle, follow/reset, pause/rotation and save round-trip.
- Tire visual checks confirm measured loaded deflection, circular rigid rims and outer tread outside the loaded plane; three camera obstruction regressions also pass.
- Eight new native mechanics scenarios cover crossed-axle articulation, exact unsprung wheel mass, pressure/load footprint, independent lockers, physical differential clearance, tiny-throttle creep/braked hold movable tire contact and measured rebound damping.
- Native prop tests cover convex queries, angular response, dropping, stacks/rest/sleep/wake, reset determinism and coupled drive/brake momentum.
- Rendered views check shared collision/visual rock triangles, landscape/portrait controls, contact skin and the loose-object line.

Final native regressions, gameplay rendering and Android export run again on the exact committed release source. Desktop/software rendering does not establish Samsung A15 FPS, thermal behavior or actual touch feel. Real vehicle/tire calibration has not been performed.

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
