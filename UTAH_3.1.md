# Utah 3.1.0 — rock contact performance and original ground materials

Android version 17 / 3.1.0, arm64, same package and signing key as 3.0.1.

Rock queries now cache exact transformed triangle meshes in a 16 MiB / 256-entry LRU. Refit bounds and a verified previous-face hint reduce nearest-face work. Original local-space inside tests remain intact; scratch storage is reused. No collision triangles, tire contact samples, solver iterations, or physics frequency were removed. Vegetation remains visual-only (109,772 solid instances).

Host benchmark of the authored 698-face rock: about 0.925 ms median physics time versus 1.27–1.35 ms before; roughly 30% less total physics time and 43% fewer nearest-face triangle candidates. These are host measurements, not A15 FPS predictions.

Validation: 11,104 real Utah face/edge comparisons against the original query returned zero maximum error; transformed instance tests and six tire scenarios passed. Three full-map driving/recovery checks passed with four grounded wheels at rest. Linux and Android native builds succeeded. Rendered Performance/High and road views passed, and material resources load with 14 embedded layers and 64 road tiles.

Original terrain base color and 14 source material layers restore dirt, sand, gravel, grass, rock, mud, and asphalt. High uses source normals and roughness. Road restoration uses 35 source textures across 3,252 authored decal records, baked into terrain tiles at 0.25 m/pixel without added road geometry. 146 invisible/default records are omitted. Missing source materials leave 33 records unrestored (32 track_rubber, one m_utah_dirt_variation_04). Road splines are approximated and use first-stage albedo; this is not the full source engine's material pipeline. Missing bridges/mines are still missing.

Private art is excluded from Git. Rebuild it using restore_ground.py with the original map archive, restore_roads.py with original and matched asset archives, then build_ground_arrays.gd under an actual OpenGL display (headless rendering cannot save texture-array pixels). Exported arrays embed their pixels and do not depend on the excluded source PNG layers. Keep the vegetation-filtered collision binary when restoring an asset checkpoint.
