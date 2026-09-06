# Crawlworks 2.4 — Redstone Canyon

## Scope

- Redstone Canyon joins Silverpine and Karelia in the region chooser. Its native 640 m square contains 1,511 m of connected routes, six destinations and 201 rock hulls: camp, low ledges, an offset crack garden, rim route, slickrock rise and an open arch overlook. The broad main trail bypasses the more technical branches.
- Canyon geology uses rounded, fractured convex surfaces, overlapping mineral beds, sparse vegetation and warm photographic rock materials. Collision exports are also the rendered rock meshes. Terrain material weights drive traction and rendering together.
- Silverpine's immediate technical loop has closer-spaced granite outcrops and a small shallow runoff crossing on its actual native bed. The existing mountain loop, lake and lookout remain available.
- The open crawler has a fabricated hood, dark cage, aluminum fender plates, visible seats, harnesses, steering wheel, shifter and rear engine. The pickup has a squarer windshield rake, horizontal grille detail, bed hardware and body trim. New orange and deep-green paints are selectable. Rock tires have broader sidewall lugs within the existing contact envelope.
- Portrait analog controls, differential/range quick bar and nearby recovery continue through the existing controls and suspension systems. Saved vehicle builds and per-map discoveries are retained.

## Release identity

- APK: `bolt-yard-2.4.0-redstone.apk`, 46,560,540 bytes, version 2.4.0 / code 11.
- SHA-256: `fe3c56c4afd58f729a7102ba454d6d32d78c678d0e1c9691a0a8c802034fe408`.
- Source commit: `db1aab58f43662b9498ac20aff21e2a3e8ed02b2`, tree `8946d2aa4fe9049e0ea0cc9b0e7bb4ef21fccb1a`.
- [Successful Android build](https://github.com/braydenparker999/Boltyard/actions/runs/34058129633).
- [Successful render review](https://github.com/braydenparker999/Boltyard/actions/runs/34058126870).
- Verified APK v1/v2/v3 signatures, existing signing certificate, package identity, ARM64 engine, CRCs, exact release shaders and packaged canyon texture/geology.
- Movie: 960×540, 30 fps, 24.07 seconds. This is deterministic capture rate, not measured phone FPS.

## Review evidence

The release process includes native terrain/manifold/traction checks, exact native-to-render mesh checks, vehicle deformation and tire contact checks, camera and portrait UI integration checks, actual Compatibility renderer screenshots, and a 24-second simulated driving clip across canyon and Silverpine.

The screenshots are real engine renders; the clip uses actual throttle, brake and camera inputs. Review starts are declared scene cuts, not continuous traversal of the entire map. These checks establish desktop simulation and rendering behavior. They do not measure Android GPU performance or prove every optional driving line passable.

Reference screenshots guided silhouettes, palette and route character. This is a mobile procedural art interpretation; it does not reproduce the source games' complete asset fidelity. Texture provenance is recorded in `assets/world/CANYON-TEXTURES.md`.

## Phone examination round

1. Open Trails → Redstone Canyon, equip the crawler setup and try Warmup Ledges at partial throttle. Check that tire placement and rock edges agree.
2. Drive the crack garden; compare the technical line with the broad bypass. Try nearby recovery after a deliberate tip and confirm it keeps you in the area.
3. Inspect the orange crawler and deep-green pickup from front, rear and near tire height. Check bodywork, cage joins, tire proportions and exposed suspension.
4. Return to Silverpine and drive the immediate granite loop and shallow crossing. Confirm switching regions preserves each region's discoveries and your build.
5. Export a fresh performance sample on the SM-A156U at the same quality and render scale as the previous report. Compare frame pacing before increasing scenery density further.

Final driving checks: canyon travel 10.08 m, two simultaneous rock-loaded tires, zero damage, stopped speed 0.00057 m/s; Silverpine travel 10.74 m, two rock-loaded tires, zero damage. Vehicle geometry: 257 passing checks. Camera integration: 213 passing checks. Native/render world contract: 39 passing checks. Suspension visuals: 40 passing checks. Tire contact visuals: 2,315 passing checks.

The implementation remains on `crawlworks-2.4-redstone` in draft PR #3 for the examination round. Main remains the preceding release.
