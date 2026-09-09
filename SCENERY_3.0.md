# Bolt Yard 3.0 — Utah scenery evaluation

3.0 adds matched Utah scenery to the existing full 2.048 km terrain. Android package `games.boltyard.prototype`, version 3.0.0, version code 15; the existing debug signing identity is retained for an in-place update.

- 124,212 original placements: 1,474 matched static placements and 122,738 matched forest placements.
- 121 shared model templates; 123,678 collision instances. Authored collision meshes are used where supplied. Rocks without a dedicated collision part use their highest visible mesh. Foliage without collision parts stays noncolliding.
- Full 1025×1025 terrain collision grid at native 2 m spacing. Existing routes and map extent remain intact.
- Native instance transforms and shared triangle BVHs preserve concavity and nonuniform scales. A 32 m spatial grid limits per-step collision queries. Camera and local recovery use the imported colliders.
- Rendering uses 64 m MultiMesh batches, original near-detail geometry, source LODs or generated distant LODs when none exist, and spatial loading. High retains detail farther away. Ninety referenced textures use Android-compatible GPU compression; supplied images are capped at 2048 pixels.
- Automatic recovery recognizes the Utah map bounds and attempts recovery once until the vehicle returns to a valid position. Manual recovery remains available.

## Validation

Native Linux and ARM64 libraries compiled with Godot 4.4.1 bindings. Four thousand rotated/sheared/nonuniform instance distance queries matched transformed reference geometry; the loaded full-world spatial index passed completeness checks. The existing rock-query suite passed 81,867 reference comparisons, and native recovery regressions passed.

Godot driving checks passed at three Utah locations: four grounded wheels at rest, finite driving state, no rejected states or safety clamps, measurable movement, and local recovery. Terrain mesh/contact agreement and switching Utah → canyon → Utah passed. Boundary checks cover Utah, canyon, legacy terrain, falling, and nonfinite coordinates.

Rendered portrait reviews fully drained the scenery queue. Performance mode drew 962,969 triangles / 362 draw calls at the trailhead and 700,417 / 284 at the ridge. High drew 1,309,307 / 547 at the trailhead. These are desktop software-renderer workload observations, not A15 frame-rate measurements. On-device memory use, sustained frame pacing, input and installation still need testing on the user's A15.

## Remaining source gaps

The donor is The Other Utah 1.0, downloaded from the original BeamNG resource. Filename matches do not establish that geometry is identical to every newer Utah revision. Fifty-one static model references remain unavailable, including several bridges, mine sections and campsite props. There are 981 unmatched forest placements. Do not treat absent bridges as driveable surfaces.

The source map marks all 1,979 TSStatic records `isRenderEnabled: false`. For this scenery reconstruction, matched static geometry is explicitly restored using its original coordinates, rotations and scales. BeamNG `(x,y,z)` maps to Godot `(x,z-100.207001,-y)`; matrices use the corresponding basis conversion.

Imported BeamNG art is excluded from Git and retained in the private evaluation build. The original authors retain ownership; this evaluation does not establish public redistribution rights.

## Rebuilding the import

Use Python with Pillow and NumPy and Godot 4.4.1. The asset-match report and source archives are in the prior private asset checkpoint. Run `tools/import_utah/prepare_scenery.py --original ORIGINAL.zip --donor DryCan.zip --matches asset-match-report.json --output CONVERSION_DIR`. This produces a separate temporary Godot project; import it with `godot --headless --path CONVERSION_DIR --editor --import`.

Copy `check_materials.gd` into that project and run it, redirecting output to `material-check.log`. Run `resolve_materials.py CONVERSION_DIR DryCan.zip` to resolve case aliases and exact source texture names. Reimport, copy `convert_scenery.gd` into the conversion project, and run it. Run `pack_scenery.py CONVERSION_DIR` to write the validated binary templates and placements.

Copy the generated `assets/utah/scenery` and `data/utah/scenery*` into this repository. Import the game, run `tools/import_utah/fix_lod_materials.gd` and `tools/import_utah/texture_budget.gd`, and reimport. The latter removes unreferenced generated textures and enables VRAM compression; use it only on the generated scenery directory. Keep the recovered 2.6 terrain images and `height.bin`, `surface.bin`, and `manifest.json`.

Build `native/SConstruct` for Linux x86_64 and Android arm64 using `BOLT_GODOT_CPP` and NDK r23c. Run `native/test_imported_scenery.cpp` with `data/utah/scenery_collision.bin`, `tests/utah_terrain.gd`, `tests/utah_recovery.gd`, and the rendered review. Export the Android preset and verify its signature, version and embedded native/data hashes before delivery.
