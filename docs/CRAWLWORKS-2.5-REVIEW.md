# Crawlworks 2.5 — Bedrock Narrows examination

This build adds a Blender-authored canyon section to Redstone Canyon. Open the garage's **Trails → DRIVE BEDROCK NARROWS** button to start directly at the new section with the selected vehicle.

## What changed

- A 128 × 64 metre connected bedrock floor replaces the coarse ground inside the section. Curved bedding steps, eroded shoulders, shallow fissures, and sand channels provide continuous wheel-placement choices.
- Continuous sculpted cliff volumes, embedded shelves, talus, and a shaped arch replace isolated wall blocks inside this section. Other map regions retain their previous terrain.
- Blender exports the final floor and rock vertices to both rendering and native contact geometry. The floor's rock/sand weights also control grip.
- Concave cliff and arch contact queries use triangle acceleration and robust inside/outside classification. Conservative distance checks avoid expensive queries for distant shapes. Convex rock queries retain their existing path.
- Existing portrait controls, vehicles, and suspension remain available. Recovery and camera clearance account for the arch's actual opening.

## Editable source

- `tools/blender/bedrock_narrows.blend`: editable Blender 4.2 scene.
- `tools/blender/build_canyon.py`: deterministic authoring/export script.
- `tools/blender/canyon_base.txt`: original terrain foundation for boundary blending.
- `assets/canyon/bedrock_floor.glb`: eight floor chunks; import compression is disabled to preserve contact alignment.
- `native/generated/canyon_floor.hpp` and `canyon_rocks.hpp`: matching contact geometry.

Rebuild from the repository root with Blender 4.2:

```sh
blender --background --factory-startup --python-exit-code 1 --python tools/blender/build_canyon.py
```

Regenerate the runtime exports after changing the authoring script. Manual scene edits are not automatically incorporated by that script. The Blender source directory is excluded from Godot import and the Android package.

The section contains 65,536 floor triangles and 17,964 rock triangles, with 92 convex shapes and 17 closed concave meshes. It reuses the project's generated rock albedo and the documented Poly Haven CC0 detail normal.

## Evidence

Runtime source commit: `c4344da61b899bd47cc0f5b1b8f143f7cde8d4c2`.

- Imported-mesh contract: 2,704 vertex/interior samples; maximum native/render height discrepancy 0.00000668 metres. Camera passage through the arch is unobstructed.
- Native geometry checks cover closed mesh edges, convex constraints, and an independent solid-angle reference for concave inside/outside classification.
- Three low-range driving sequences crossed 13–16 metres each, climbed, and stopped with zero safety clamps, rejected states, or damage. These are bounded automated checks, not exhaustive driving coverage.
- [Rendered review](https://github.com/braydenparker999/Boltyard/actions/runs/34062123033) includes entry, shelves, arch, and the live portrait controls.
- [Android build and regression checks](https://github.com/braydenparker999/Boltyard/actions/runs/34062124662).

## Examination on the Samsung A15

Drive slowly across the bedding steps and shelf edges, try a diagonal line, pass under the arch, and recover nearby. Check whether the tire contact feels consistent with the visible rock and whether portrait frame pacing remains acceptable. A new device performance report is needed; desktop CPU timings do not establish Android performance.

This is the first playable Blender canyon section. Its connected terrain is a substantial structural change, but the cliff silhouettes, arch face, material variation, and surrounding legacy scenery still need art refinement to approach the supplied reference images.
