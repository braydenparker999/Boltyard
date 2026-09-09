# 3.0.1 vegetation collision patch and investigation

The A15 user reports good general performance in 3.0, with severe drops when driving onto rocks. All vegetation is now visual-only, including juniper bushes, branches and trees. Rock and structure collision remains intact. The filter removes exactly 13,906 collider records, leaving 109,772; all 124,212 render placements remain unchanged. The native solver is unchanged in this patch, so this is not a claimed fix for the rock-contact slowdown.

Version code 16 / version name 3.0.1. The delivered APK is a signed data patch of the tested 3.0 APK: only AndroidManifest.xml and data/utah/scenery.json and scenery_collision.bin differ (apart from signatures). The embedded project config is still 3.0.0; the Android package reports 3.0.1. The source export preset and project version are updated for a future full rebuild. Signing identity is retained.

`collision_policy.py` applies the same policy to future full imports. `remove_vegetation_collision.py` patches an existing imported dataset, validates its record layout, preserves all templates and retained records, and is idempotent. Apply the saved collision patch over the saved 3.0 imported asset checkpoint before rebuilding.

## CPU investigation

`native/benchmark_utah_contacts.cpp` runs a controlled, renderer-free comparison with the 698-face authored large Utah rock (model 42), flat terrain, 240 Hz physics, nine constraint iterations and 30 Hz measured frames. On this host, terrain median was 0.384 ms versus 1.297 ms on the rock (3.38×); p95 was 0.489 / 1.569 ms. The rock scenario averaged 3.69 loaded wheels and 1,047 mesh distance queries per measured frame, testing 18,025 nearest-face candidates. These counters do not include every inside-test operation. This is an instrumented host workload comparison, not A15 timing or proof of the dominant device bottleneck.

The imported collider path traverses a BVH, transforms candidate triangle vertices into world space, and runs a closed-mesh inside test. Wheel support, body, axle and skid work can repeat these queries. Prior validation covered ordinary terrain driving and query correctness, but did not establish A15 frame budgets while climbing imported rocks.

Recommended next optimization: measure actual rock-contact hotspots, cache nearby transformed collision geometry and reusable contact candidates, and reduce redundant closest-face searches while retaining the current visible meshes and physical shape. Profile camera collision separately as it also uses these queries. Compare one-, two- and four-wheel contacts with the same camera and render scene before claiming an improvement.

## Roads and ground materials

The original Utah Extra archive contains 3,431 DecalRoad records spanning 39 material names (including invisible AI paths), and 87 terrain image files. Existing terrain import bakes fourteen material identities into a palette and uses only rock/dirt detail maps. The saved game does not render the road/decal records. Road surfaces, lane markings, cracks and dirt tracks therefore require restoring their material bindings and placement/rendering path, not merely downloading more textures.

Restore the existing asphalt, dirt, gravel and rock material images first; import visible road/decal ribbons with their node widths, texture lengths, layering and terrain alignment. Exclude invisible AI paths. Reuse saved donor art for absent dependencies, with a reference audit identifying truly missing assets. Source version mismatches and absent bridge geometry remain separate limitations; an exact complete restoration cannot be promised from the archives currently available.
