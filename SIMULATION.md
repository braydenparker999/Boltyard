# 2.2 contact acceleration and damper packaging

Static hull constructors build a balanced AABB tree once. Outside points traverse nearest bounds first and test the original triangles at leaves; interior points retain the original maximum supporting-plane response. Coplanar distance ties keep original triangle order. Queries on unindexed custom hulls fall back to the original scan. Custom-rock replacement rebuilds its index. Geometry must be reindexed after any authoring mutation. This is exact query acceleration, not collision simplification or a persistent infinite contact plane.

Every wheel still discovers its nine samples per source and revalidates all retained patches at each solver iteration. No solver Hz, iteration count, clock-debt policy, support patch count, friction or tire stiffness was reduced. Compile-time host counters count distance calls and actual closest-triangle tests; they are absent from the release hot path.

For solid axles, each shock's rest eye length is measured between affine chassis/carrier mounts. The tower is raised when needed so the configured bump and droop fit a single telescoping damper, eye clearances and piston overlap. Spring rate and separate compression/rebound damping remain applied along this true axis (so wheel rate depends on the motion ratio). A progressive bumper dissipates additional energy during compression near the end of stroke; it does not apply extra rebound damping. Free spring force remains compression-only: at droop, the rendered captive spring keeps its free length rather than stretching in tension. Spring preload remains zero; pressure and spring rates remain uncalibrated game settings.

Visual body length and shaft length depend on the manufactured package, not the current eye separation. The piston overlap, seat separation and coil pitch change with travel; wire diameter stays 16 mm via a separate axial metre offset. Eye/bolt dimensions use metric mount-local coordinates, and link rods retain solved endpoints. Tower support struts connect to real frame points. This pass retains simplified differentials, driveshaft joints and steering knuckles. Suspension/body self-collision is still absent; severe frame damage can cause hardware intersections. It is not a detailed rigid-part or FEM model.

---

# Crawlworks 2.1 model

This section describes the current model and supersedes conflicting historical notes below. Terrain modes 3–5 use articulated axle carriers and the bounded static tire-patch solve; modes 0–2 retain the legacy driving baseline.

Each axle is a finite-stiffness tetrahedral carrier made from its two wheel hubs and two internal mass nodes. Carrier mass is taken from the existing unsprung assembly mass, preserving total mass; signed wheel equipment mass stays with the wheels. Eight frame nodes, eight cab nodes, four hubs and four carrier nodes make 24 physical mass nodes. The shader continues to receive exactly 100 render positions; the 80 rubber guides are derived visual geometry.

Two lower and two triangulated upper links per axle apply position constraints through affine chassis/carrier mounts. This locates the axle laterally without an additional Panhard bar. Coilover spring, independent compression/rebound damping and progressive compression/droop stops act at the moving shock eyes. Upper/lower rods, coilovers, axle orientation and transfer-case-to-pinion driveshafts use those same solved endpoints. Drive/brake impulses apply opposing carrier pitch reaction. This remains a simplified authored linkage model; steering knuckles, joints and a complete driveline are not independent simulated parts.

Modes 4/5 share 640 m square, 2 m grid heightfields with the renderer. Contact heights use the exact triangle split, including nonplanar cells; normals, material weights and wetness come from the same native data. Curved routes blend into broad contour shoulders. Rounded granite hulls have smoother physical crowns and selected clipped fracture faces, placed as local obstacles with traversable approaches. Their render vertices retain the native hull geometry; lighting normals blend across crowns and preserve sharp ledges. Nearby terrain uses the native grid, while distant terrain uses an 8 m display mesh. Forest detail also changes with distance. These display choices leave native collision unchanged. Tree placements are shared with their trunk colliders. The maps are original work informed by reference research; no BeamNG map assets were imported.

Each tire samples across its width and fore/aft tread arc, retaining at most six static terrain/rock patches. Similar planes from the same source are grouped so repeated samples do not multiply stiffness or grip. Distinct faces, including multiple faces of one rock, keep separate normals, support loads and tangent shear. Pressure sets normal stiffness to `300000 × relative_pressure` N/m. Loaded compression determines the circular-section footprint estimate `2 sqrt(2 R d - d²)` and shoulder bulge. Pressure also affects shear compliance; it does not add an arbitrary friction bonus in crawl modes. Compound and the material at each contact, including wetness, set that patch's friction limit.

The rubber guides deform under normal load and longitudinal/lateral force. The renderer receives the six strongest loaded contact planes and local patch bounds, allowing simultaneous support around a corner while keeping the metal rim and bead rigid. This is a compliant contact envelope with derived rubber geometry, not an independently integrated or finite-element tire carcass. Pressure remains a relative setting, not PSI or bar. Movable objects retain one contact per tire/object pair, selected from width samples, with their own material and equal/opposite impulses. They do not use the static multi-patch solve. Water remains a solid low-grip bed, with no buoyancy or deformable mud; vehicle self-collision is not implemented.

The driving camera button explicitly cycles Follow, Trail and Free. Follow and the closer, higher Trail view ignore scenery drags; two fingers change only span-based zoom. Free enables one-finger orbit/tilt or the Pan button, and Center returns to locked Follow. Steering hitboxes are 108 × 108 logical pixels; pedal hitboxes have a further 18-pixel camera exclusion border. Camera ownership stays separate from held pedals and GUI touches. Older saves start locked unless they contain an explicit 2.1 preset. Camera collision includes convex granite, movable props, trunk cylinders and terrain clearance. Atlas, recovery and discovery records remain scoped by region.

`native/test_tire_contacts.cpp` contains six causal scenarios:

- Change pressure and compare loaded depth, footprint and shoulder width while material friction stays fixed.
- Remove one of two opposing rock faces and check that its physical support disappears.
- Change the contacted material and compare acceleration and wheel slip.
- Apply drive and lateral motion and measure bounded tangent rubber shear.
- Climb a single convex ledge while distinct corner normals carry load.
- Compare the contacted material and friction of movable stone and timber.

Other gates cover carrier/wheel mass conservation, four-link length error under gravity and cross-axle loading, opposite rotor/carrier torque without injected horizontal momentum, nearby terrain/mesh equality, convex hull closure, graded route traversal and raw touch ownership. Damping landing tests release the brakes so wheelbase motion along the four-link arc is not confounded by parking-brake friction. Rendered stills inspect camera layouts, terrain at tire scale and contact deformation. These checks establish internal behavior; real-world calibration and Samsung A15 performance, temperature and touch feel remain unmeasured.

---

# Crawlworks 1.0 model

The following additions supersede the 0.5 crawl suspension and axle limitations below. Mode3 (Copperline) uses coupled solid axles; valley modes retain the independent guide baseline.

Each crawl axle enforces fixed hub separation, two longitudinal trailing-link distances and one diagonal Panhard distance. Spring force uses gradients of the actual moving suspension endpoints. Compression/rebound damping and compression/droop stops are independent setup values. Axle shaft and central differential contacts can support the rig and unload its tires. Wheel camber follows the articulated axle; front steer rotates the rolling axes. The renderer uses those exact hub/link endpoints for metal axle/link meshes, and actual wheel phase/axis for rigid rims.

Tire contact stiffness is pressure-dependent. Per-wheel load and deepest supported compression give a circular-section footprint estimate, `2 sqrt(2 R d - d²)`. Each contact retains its own normal and tangent frame; angular wheel drive/brake impulses respect available friction and reaction inertia. Finite implicit contact shear permits controlled very-low-throttle creep. The derived rubber ring guides flatten at support; the rendered tread padding is clipped to the strongest loaded plane with modest sidewall bulge. This is not a volumetric tire carcass or a fitted real-world tire model.

Front and rear locks are separate. Legacy saved combined switches migrate to both axles unless an explicit per-axle choice exists. Signed wheel-set mass changes (beadlock +18kg, alloy -24kg) are already included in total vehicle mass and are allocated to the physical wheel hubs; they are not added twice or smeared over the body.

Nine bounded convex rigid props are integrated in the same 240Hz step. Contact uses solved position/orientation, rotational effective mass, static/dynamic friction and equal/opposite impulses; drive and brake tire reactions use prop contact-point velocity. Static rock, prop/prop and vehicle/prop contacts participate in the solve. Sleeping bodies wake on contact/impulse. Local convex render triangles never change after upload; solved transforms update each frame. Their density and inertia are simplified game values.

The camera uses stable contact IDs and batches raw screen-touch motion per rendered frame. A two-finger centroid drives orbit/tilt or pan; span ratio drives zoom and wrapped angle delta drives twist. GUI-owned touches, third contacts, tiny spans and lifecycle changes cannot inject stale camera deltas. A convex segment test against expanded rock/prop planes shortens obstructed crawl views. Terrain clearance is also applied before and after smoothing.

All new models remain uncalibrated. Contact discretization, rigid props, derived tire geometry and simplified drivetrain/soil behavior limit real-world accuracy. Desktop tests establish internal invariants and gameplay scenarios; they do not establish real tire friction curves, real suspension response, sustained device FPS or thermal performance.

---

# Crawlworks 0.5 additions

The original 0.4 model description below remains the valley baseline. These additions apply in 0.5:

- **Rock traction correction, all modes:** scenery tires no longer apply passive sliding friction while unbraked and then ignore rock support in drive. Every active tire contact contributes its own normal impulse, material coefficient and tangent frame. Torque is distributed by contact capacity; impulses remain bounded separately at each contact. Incompatible normals are never averaged into one artificial support plane. Brakes use positional friction for stable holding.
- **Copperline geometry:** closed convex pieces are defined in `native/crawl_rocks.hpp`. The binding exports the exact triangles. A per-substep nearby-piece query bounds contact cost. Tire tread uses three width samples; radial support decreases toward axle-facing normals, avoiding a full tire-radius sphere on the sidewall. This remains a bounded contact approximation, not an exact swept tire surface or a deformable carcass. Structural nodes and nine bilinearly weighted underside supports contact the same shapes. No independent axle-housing collider exists yet.
- **Copperline drivetrain:** wheel angular acceleration comes from drive torque and tire-contact reaction impulses. Longitudinal slip uses `v + omega * radius` in m/s, avoiding division by speed near rest. The effective mass includes wheel inertia and hub inverse mass. Engine torque reduces and opposes wheel overspeed; releasing the pedal adds engine drag. Low range is 22× before final drive, with forward/reverse governor speeds 2.2/1.5 m/s before final drive. High range is available. This is not a calibrated clutch, RPM curve or transfer-case model; chassis driveline reaction torque and gyroscopic effects remain absent. Locked coupling is per axle, while the control still switches both axles together. Valley wheel spin retains its 0.4 model.
- **Diagnostics and setup:** wheel vertical support load and the rock-supported share are available in newtons, together with wheel angular velocity, slip, suspension travel and native timing. Low-pressure compliance costs loaded clearance; pressure is still relative, never PSI. Front/roof mass placement and spring/damping/height tuning remain active from v0.4.
- **Presentation:** radial guides flatten against actual supporting contact planes, including rocks. They are still derived render guides. Copperline's original geology shader adds strata and quartz seams; shading relief does not change the collision silhouette.

The rock-only baseline fixture stood over 4 m above ground and moved 0.000044 m under throttle in v0.4. The corrected isolated elevated-platform test supports approximately 11.78 kN, drives over 5 m in three seconds and brakes to rest. Dedicated tests cover incline hold/restart, beveled ledge climb, cadence, airborne momentum, convexity, split grip, high-centering, pressure compliance and a full course traversal. The split-grip fixture travels about 0.78 m open versus 3.08 m locked under the same two-second input. Lowering relative pressure from 1.5 to 0.5 loses about 13.5 mm of loaded wheel-center clearance. These are numerical game-model results, not real vehicle calibration.

The first implementation intentionally preserves the Godot/native pipeline: no demonstrated engine blocker prevented this contact milestone. Solid axle/link kinematics, separate front/rear locker controls, wheel-mass allocation improvements and detailed axle clearance remain follow-up work.

---

# Bolt Yard 0.4 — handling model and validation

Version 0.4 replaces the independently simulated tire rings with four continuous round tire contacts. The frame and cab remain deformable XPBD structures: gravity, suspension loads, traction and collisions act on their actual mass nodes, and structural beams still yield and break. This is an approachable off-road game model, not a calibrated vehicle or crash-engineering simulator.

## Physical structure and render bindings

There are **20 dynamic assemblies**: eight frame nodes, eight cab/cage nodes, and four wheel hubs carrying their complete unsprung assembly masses. The existing **100 render positions** and wheel indices `{16,37,58,79}` remain stable. Eighty sidewall samples follow wheel position, steering, spin and contact flattening; they are render proxies, not independently integrated tire masses.

| Vehicle | Physical beam/guide records | Render graph records | Frame / cab / wheel base-mass shares |
|---|---:|---:|---|
| Pickup | 72 | 392 | 60% / 18% / 22% |
| Scout SUV | 80 | 400 | 54% / 25% / 21% |
| Nomad buggy | 84 | 404 | 59% / 15% / 26% |

Each physical total includes four suspension guides. The 320 tire graph links remain available for the structural display but are not solved as independent tire constraints. Telemetry reports `physical_nodes`, `render_nodes` and `physical_beams` separately. Legacy per-sample mass metadata still sums to the configured vehicle mass; the solver lumps all 21 wheel sample shares at the corresponding physical hub.

The SUV has a longer, taller cab with additional roof-to-frame braces and slightly front-biased mass. The buggy has a low cage, additional bracing and rear-biased frame mass. Front and roof accessory masses are subtracted before base-mass distribution and then placed at their actual frame/roof attachment nodes, preserving the selected total mass without double counting.

Tire radius, width, pressure-dependent compliance, compound grip, spring rate, damping, ride height, travel stops, final drive and accessory mass affect the physical model. Tire width supplies three support lines across the tread on uneven ground. Paint has no mechanical effect. Pressure is a dimensionless relative setting, not bar.

## Integration and contact

The core owns a single accumulator, uses fixed **1/240-second substeps** and **nine constraint iterations**, and alternates structural constraint traversal. Godot runs at 60 physics ticks per second with a 16-step catch-up limit. The redundant binding accumulator and its 50 ms frame cutoff were removed. Ordinary 10–120 Hz or irregular frame delivery advances the same amount of simulated time. A single frame above 100 ms is bounded, and discarded time remains observable in `dropped_time`.

Each substep predicts the 20 physical assembly positions under gravity, solves frame/cab distance constraints and suspension guides, resolves ground and scenery contact, reconstructs velocities, applies material/suspension damping, then applies unbraked tire traction and updates wheel render samples. All distances are metres, masses kilograms, torques N m, spring rates N/m and damping coefficients N s/m.

The body uses XPBD compliant distance constraints. Each hub has prismatic lateral/longitudinal location guides, a configurable vertical spring, compression/droop stops and an implicit damper acting on the complete unsprung mass. Frame/cab beams permanently change rest lengths above selected trial-strain thresholds and break at larger strains. The damage percentage summarizes this structural history; it is not a measured fraction of destroyed material.

Tires contact terrain continuously as round supports, removing the changing facets of the old ten-segment dynamic rings. Loaded tire compliance is `300000 × relative_pressure` N/m. Across-width terrain samples let a wider tire bridge a narrow rut. Structural nodes retain small sphere contacts. Braked tires solve tangential position constraints, providing static hill holding as well as speed-dependent stopping. Unbraked tires use longitudinal force and lateral slip relaxation within a shared friction circle.

Body render vertices follow their own vehicle's undeformed binding and current frame/cab positions. Tire render samples follow their physical hubs. Neither body triangles nor sidewall proxies are independent collision meshes; render triangles do not tear when a beam breaks.

## Driving response

Engine force is divided across four wheels with reductions of **5.5 in low range** and **3.8 in high range**, multiplied by final drive and divided by tire radius. Torque is nearly flat at low speed, then falls smoothly toward artificial road-speed limits of 16.5 m/s in low range, 31 m/s in high range and 9 m/s in reverse; final drive divides those limits. These are game tuning values, not a modeled RPM curve or automatic gearbox.

Positive steering turns right. Front steering changes smoothly and reduces at speed. Tire lateral slip has a finite relaxation time, so a steering input redirects the physical chassis through suspension loads. An open axle limits both wheels to the traction supported by its lower-traction contact; locking retains drive at its planted wheel. Wheel-spin states supply rotation and bounded airborne spin, rather than estimating rotation from deforming polygon nodes.

Brakes suppress drive and use the same tire-ground contact forces as ordinary traction. An opposing direction request first brakes forward motion, then engages reverse near walking speed. Airborne throttle can spin wheels but cannot inject horizontal vehicle momentum. There is no scripted position, heading, forward velocity or upright recovery applied during normal driving.

The base tire coefficient is 1.18, multiplied by compound, a bounded relative-pressure factor and the terrain surface multiplier. Body friction is 0.45. These are simplified Coulomb-style forces; there is no calibrated slip-ratio curve, dynamic soil or hydrodynamic tire behavior.

## World geometry

`native/terrain_v03.hpp` retains its filename as the shared terrain API. It supplies the 768 × 768 m landscape and exact 2 m grid triangles used by nearby scenery and tire contacts. The binding's `get_terrain_samples()` exports the height and surface arrays in one call to avoid hundreds of thousands of per-sample startup calls.

Trees, rocks and posts use fixed, ground-relative cylinder proxies. Physical nodes collide with cylinder sides/caps, and intact structural beams also collide with sides so a narrow post cannot pass through gaps between body nodes. The road traversal regression found a hand-placed rock obstructing the route; hand-authored rocks now receive the same road-clearance treatment as generated scenery.

Water is visual above a solid low-grip lake bed. There is no buoyancy, fluid mud, movable scenery or arbitrary concave collision mesh. The flat plane and original short demonstration course remain terrain modes 0 and 1; the exploration map is mode 2.

## Recorded results

Default pickup, flat ground, four seconds of braked settling followed by full throttle. Both versions use C++17 `g++ -O2` on the same desktop container. Native timings exclude rendering and are **not Samsung A15 frame-rate measurements**.

| Measurement | v0.3 | v0.4 |
|---|---:|---:|
| Speed after 2 seconds | 9.88 km/h | 29.87 km/h |
| Speed after 5 seconds | 17.39 km/h | 52.89 km/h |
| Speed after 10 seconds | 19.78 km/h | 57.88 km/h |
| Distance after 10 seconds | 41.50 m | 123.48 m |
| Flat vertical chassis-velocity RMS | 0.0444 m/s | about 0.0002 m/s |
| Native elapsed time per 60 Hz frame, flat | 0.607 ms | 0.17–0.31 ms across repeat runs |

Elapsed timings vary with other work on the shared host; the latest complete benchmark output is retained rather than selecting only the fastest run.

Additional measured behavior:

- Braking from 15.2 m/s stops in approximately 9.7 m, with about 0.001 m/s residual speed after three seconds.
- All three vehicle structures hold a 27% exploration grade with no more than 0.00071 m drift over ten seconds, then climb 19–20 m horizontally in five seconds from rest.
- The 1.30 km exploration route completes at 29 km/h cruise and 45 km/h cruise with braking for bends. Maximum centreline error is below 1.6 m; the vehicle stays upright and undamaged.
- Full-lock steering reversals and alternating slalom remain stable through measured speeds of 26.8 m/s. Airborne travel, landing, reverse engagement and recovery are separately checked.
- Ordinary driving regressions require zero structural damage, velocity safety clamps, nonfinite-state recoveries and discarded frame time.

Reproduce the native checks and benchmark:

```sh
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_soft_rig.cpp -o /tmp/test_soft_rig
/tmp/test_soft_rig
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_road_drive.cpp -o /tmp/test_road_drive
/tmp/test_road_drive
g++ -std=c++17 -O2 native/benchmark_handling.cpp -o /tmp/benchmark_handling
/tmp/benchmark_handling
```

The baseline is preserved in `native/handling_v03_baseline.txt`, and the new benchmark output in `native/handling_v04_results.txt`. The core suite passes **78 checks** and the separate road suite passes **both complete-route cases**. Tests cover meaningful acceleration, braking, direction changes, steering at speed, road traversal, grade holding/restart, jumps, deformation, exact mass distribution, legal equipment ranges and variable frame cadence.

## Limits

This remains one active vehicle, single-precision simulation and discrete scenery collision. There is no self-collision, continuous collision detection, full triangle collision, simulated control-arm geometry, Ackermann steering, detailed drivetrain reaction torque, gyroscopic wheel dynamics, wheel detachment, tire punctures or independently deformable tire carcass. Severe structural collapse can stretch/invert the render skin. Velocity caps and malformed-input recovery are diagnostics, not evidence that an extreme event was simulated correctly.

Position and speed telemetry average the eight frame nodes. Desktop checks establish regression behavior, not real-world calibration or Android performance, thermal behavior and battery cost. Version 0.4 still needs the user's Samsung A15 test for touch feel, visual smoothness and sustained frame rate.
