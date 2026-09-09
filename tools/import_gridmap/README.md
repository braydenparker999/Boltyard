# Gridmap Refresh private conversion — Crawlworks 3.2.0

Source: Gridmap Refresh 1.0 by Bifdro, with original BeamNG assets.
https://www.beamng.com/resources/gridmap-refresh.37015/
The retrieved archive was resource version 66937. Keep the original archive and converted art out of this public repository. This is a private evaluation port, not a standalone redistribution of the map.

## Conversion

1. Extract the source ZIP without running its scripts.
2. Run `python3 tools/import_gridmap/prepare.py SOURCE_ROOT CONVERSION_PROJECT`. This reads COLLADA, JSON and forest definitions as data, converts the 1024-square version-9 terrain to a 1025-square one-metre contact grid, and resolves bundled texture pixels. It does not execute TorqueScript or Lua.
3. Import CONVERSION_PROJECT with Godot 4.4.1, then run `convert.gd` from that project with Godot. The script writes visual LOD resources and shared native collider templates.
4. Run `python3 tools/import_gridmap/pack.py CONVERSION_PROJECT`. It transforms original placements from BeamNG Z-up to Godot Y-up. Trees and bushes have no colliders. Oak/aspen models with missing shared textures are omitted.
5. Copy `assets/gridmap` and `data/gridmap` into this project. Import once with Godot, run `configure_imports.py`, and reimport to enable mipmaps and Android VRAM compression.
6. Run `blend_ground.py`; run `build_ground.gd` in this project with an OpenGL display. It creates compressed texture arrays using the bundled albedo, normals and roughness. Reimport the blend image. Texture blending is visual only; native material boundaries and terrain heights remain unchanged.
7. Build both native libraries using the existing SCons configuration and Godot 4.4.1 godot-cpp. Export the Android debug preset with the project's existing signing key.

The private converted-asset checkpoint can be restored directly without repeating conversion. Its binaries and images are intentionally ignored by git.

## Scope and limitations

- Original terrain at one-metre collision spacing; 1,100 visual placements and 860 authored solid colliders. Collision stays independent of rendering LOD.
- Original ramps, tubes, blocks, obstacle courses, oval and available road markings. Ten terrain surface categories have separate grip mappings. These mappings are game coefficients, not validated BeamNG tire equivalence.
- Grass/dirt texture edges are blended; original height/contact triangles are retained. Textures are capped at 1024 pixels for Android. Ground base textures use 256-pixel array layers; original detail maps remain up to 1024 pixels.
- 13 referenced model files (20 placements) are absent from the source download, including a cave mesh and several Utah rock/cliff pieces. 141 additional oak/aspen foliage placements lack actual shared texture pixels and are omitted. Available beech/palm foliage remains, without collision.
- Several dirt/mud decal materials are missing shared definitions or textures. The older bundled mud albedo and normal replace missing newer PBR `.link` files. A `.link` file is a reference, not a texture image.
- Decal roads are draped along subdivided source node segments; BeamNG spline interpolation is approximated. Available water blocks retain placement and color as simple visual surfaces. Water dynamics, BeamNG missions/triggers, traffic and prefab behavior are not ported. The existing game sky/lighting is used.
- No suspension, tire pressure, slip-curve or drivetrain retune. Global slickness remains a separate investigation. This build establishes a repeatable test environment.

## Validation

`native/test_gridmap_import.cpp`: v4 material-tagged collider loading, old Utah v3 compatibility, native map replacement and broad-phase queries.

`tests/gridmap_contract.gd`: all ten grip mappings, rendered/native one-metre triangle agreement, settled drive and recovery, deep-cave recovery threshold, and Utah two-metre -> Gridmap one-metre switching.

`native/test_tire_contacts.cpp`: six existing causal tire-contact scenarios; all pass without changing tire tuning.

`tests/gridmap_review.gd`: OpenGL portrait captures at the main spawn, off-road materials and elevated oval. Desktop software-renderer results are not A15 frame-rate measurements.
