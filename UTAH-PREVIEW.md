# Utah terrain preview — 2.6.0

Select Garage → Trails → Utah Extra, then Drive. This private evaluation build
imports the supplied Utah Extra 6.0 terrain by DrowsySam. It is a ground-only
prototype, not a complete BeamNG map conversion.

- Full 2,048 × 2,048 m horizontal extent, 200.1 m relative relief.
- One 1,025² grid at 2 m spacing supplies both native contacts and near geometry.
- 64 terrain chunks switch between 2, 8 and 16 m vertex spacing. Skirts cover LOD
  cracks; fine geometry is retained only near the truck. Test views use
  123,904–190,208 terrain triangles, before the vehicle.
- Four texture samples per ground pixel, with mipmaps. Fourteen original ground
  identities map to sandstone/soil/vegetation/asphalt colors and tire materials.
- Five source trail locations and sixteen source crawling-route segments appear
  on the fully revealed map. Routes are reference lines; sections that originally
  crossed separate rock or bridge meshes are incomplete.
- Existing vehicle physics, suspension, portrait analog controls and axle toggles
  remain in use. Recovery supports the larger region and starts at Crawl 1.
- Stock Utah cliffs, boulders, bridges, road decals and vegetation are absent.
  Terrain holes and unresolved layer codes use closed dirt ground for this test.
  Vertical source datum is removed. The map edge has no authored boundary yet.

## Rebuild

Run `python tools/import_utah.py /path/to/UtahExtraDS.zip` (NumPy and Pillow), then
build the native extension with the pinned Godot 4.4.1 toolchain and import/export
with Godot 4.4.1. Export includes `data/utah/*.bin` and `data/utah/*.json`.
The source ZIP and converted textures/data are excluded from git; their use in a
public release needs the relevant asset permissions. Existing source inspection
records preserve the unresolved stock mesh references for later conversion.

## Validation

- Native plane sampling, material lookup, finite-value rejection, exact edge
  sampling, empty legacy obstacles and recovery beyond the old map bounds passed.
- Godot integration settled/driven/recovered at three source locations; all four
  wheels grounded at rest, no safety clamps or rejected simulation states.
- Fine mesh triangle centroids match collision heights within 2 mm; switching
  between Canyon and Utah preserved the correct collision mode.
- Compatibility viewport screenshots reviewed. Android ARM64 APK exported and
  verified with the existing package/signing certificate, version code 13.
- Actual phone frame rate and terrain driving feel still need an A15 playtest.
