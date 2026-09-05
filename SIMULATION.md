# Bolt Yard 0.3 — implemented simulation

The native C++ model in `native/soft_rig.hpp` drives the vehicle through deformable mass nodes, constraints, wheel torque and contact. Godot receives node positions through `native/binding.cpp` and draws the body and tires around them. There is no underlying rigid vehicle body supplying scripted forward acceleration. This is an experimental game model, not a calibrated vehicle or crash-engineering simulation.

## Three structures and physical parts

All vehicles retain **100 finite-mass nodes**: eight frame nodes, eight cab/cage nodes, and four wheels containing one hub plus two ten-node sidewall rings. Their dimensions, structure and mass distribution differ:

| Vehicle type | Beam records | Frame / cab / wheel mass shares* | Structural differences |
|---|---:|---|---|
| Pickup | 392 | 60% / 18% / 22% | Short cab above the standard frame; twelve cab-floor attachments |
| Scout SUV | 400 | 54% / 25% / 21% | Longer, taller cab with eight additional roof-to-frame braces; slightly front-biased frame mass |
| Nomad buggy | 404 | 59% / 15% / 26% | Lower, narrower cage with twelve additional braces; rear-biased frame mass |

*Shares apply before front and roof accessories are added. Each total includes 320 tire links and four suspension descriptors. Suspension descriptors are solved through the axis guides below rather than as ordinary distance beams. Both eight-node structural cells are internally braced complete graphs, not detailed reproductions of real frame tubing or sheet metal.

The catalog composes each build's configuration. `mass` is the **total vehicle mass including accessories**. The core subtracts the front and roof accessory masses before distributing the base mass, then places the specified front mass equally at the four front frame nodes and roof mass at the four upper cab/cage nodes. Accessories therefore change axle loading and centre of mass without double counting weight. Other catalog mass adjustments, including wheels, change the distributed base mass; they are not separate component inertias.

Parts can change physical tire radius, sidewall spacing, carcass stiffness, friction, spring rate, damping, ride height, travel stops and final drive. Tire width is `0.58 × radius × tire_width_scale`. Front and roof parts contribute weight at their attachment nodes; fitting them does **not** add separate collision meshes, mechanical joints or structural beams. Paint and visual details have no mechanical effect.

Positions use metres, mass kilograms, time seconds, torque N m, spring rate N/m and suspension damping N s/m. Tire pressure is a **dimensionless relative stiffness setting**, not bar or a measured gas pressure.

## Integration, suspension and deformation

The solver uses fixed **1/240 s substeps** and **nine constraint iterations**. The Godot binding accumulates time in 1/120 s increments. Each substep applies drive torque and gravity, predicts node positions, solves structural distances and suspension guides, resolves ground and obstacle contact, then reconstructs velocities and applies damping. Structural-beam traversal reverses on alternate iterations.

Distance constraints use XPBD compliance: with length error `C`, compliance `α = 1/stiffness`, node inverse masses `w₁,w₂`, and timestep `h`, the multiplier increment is `Δλ = (-C - αλ/h²) / (w₁ + w₂ + α/h²)`. Corrections are distributed by inverse mass. Multipliers accumulate within a substep and reset between substeps. The formulation follows [XPBD](https://matthias-research.github.io/pages/publications/XPBD.pdf); the finite iteration count is still an approximation.

Each hub has compliant prismatic guides relative to a lower frame corner. Lateral and longitudinal guides locate the wheel; the vertical guide supplies spring force. Configured travel sets extension, while compression is limited to `min(travel × 0.28/0.22, ride_height × 0.72)`. The damper applies opposing vertical impulses to the frame anchor and the complete wheel assembly using an implicit damping update. It does not treat the lightweight hub as the whole unsprung mass.

These guides are not simulated control arms, solid axles, camber curves or anti-roll bars. Both front wheels share a speed-dependent steering angle; Ackermann geometry and wheel detachment are absent. Tire spokes, ring links and cross-width links form deformable carcasses, with pressure-dependent compliance and modest axial damping. There is no enclosed-gas volume law, temperature, puncture or calibrated tire-force curve.

Frame and cab beams can permanently change their physical rest lengths above chosen trial-strain thresholds and break at larger strains. Tire links and suspension guides do not fail. The damage percentage summarizes structural plastic history and breakage; it is not a measured percentage of destroyed material.

The renderer binds each vehicle's skin to its own undeformed `rest_positions`. Body vertices follow frame/cab nodes, and tire surfaces follow the actual ring nodes. Driving does not mutate this bind pose; rebuilding or recovery refreshes it. Render triangles have no independent mass, do not tear when beams break, and are not a collision mesh.

## Torque, gearing and friction

Wheel angular velocity and inertia are estimated from the tire nodes. Drive torque produces tangential node impulses, with a hub correction for net linear impulse and an opposing chassis torque. Ground friction converts tire rotation into propulsion.

Torque is divided among four wheels, multiplied by the low-range ratio of 2.65 or high-range ratio of 1, and by `final_drive`. Final drive also divides the wheel-speed limiter, trading terminal speed for tractive torque. The limiter is artificial; there is no engine RPM curve, clutch or discrete gearbox. Brakes oppose wheel rotation and suppress drive torque. The locker applies a finite torsional coupling toward the average speed of **all four wheels**, not separately modeled front, rear and centre differentials.

Ground contact uses unilateral compliant normal constraints and bounded tangential position corrections. Tire friction starts at 1.20, multiplied by tire compound, a bounded relative-pressure factor and terrain surface. Other nodes start at 0.45. Juniper Valley surface multipliers are 1.0 on roads, 0.84 on grass, 0.94 in the quarry and 0.58 on the shallow lake bed, with interpolation between samples. These are simplified Coulomb-style coefficients, without distinct static/dynamic tire curves, deformable soil or hydrodynamics.

## Juniper Valley terrain and solid props

`native/terrain_v03.hpp` authors a **768 × 768 m** landscape containing a connected trail loop, hills, quarry, lake basin and groves. Heights are cached on a 385 × 385 grid at 2 m spacing. Physics interpolates the two triangles within each cell, matching the nearby rendered terrain; contact normals come from those same triangle slopes. Distant scenery uses an 8 m mesh and is a coarser visual approximation. The spawn clearing is flat. Terrain modes 0 and 1 retain the flat test plane and original demonstration trail.

Trees, boulders and wayfinding posts use fixed, ground-relative **cylinder proxies**. A nearby-object broad phase runs once per substep. Mass nodes collide with cylinder sides and caps; intact structural beams also collide with cylinder sides, distributing contact corrections through interpolated endpoint masses. This additional beam contact prevents narrow posts from passing through the gap between body nodes. It remains a skeleton/cylinder approximation, not full vehicle-versus-scenery mesh collision. Cylinder contacts are discrete, so sufficiently fast motion can tunnel.

Water appearance does not supply buoyancy or drag: tires contact the solid lake bed. The map has no flowing or deforming mud, movable rocks, destructible trees or arbitrary concave collision meshes. The analytical ground continues outside the authored extent with enclosing slopes; the game handles exploration boundaries separately.

## Verification and limits

The standalone native suite passes **73 checks**, retaining all 47 v0.2 cases and adding 26 cases for distinct structures, exact accessory masses and centre-of-mass shifts, tire width and compound, gearing, suspension travel, bind poses, exploration samples, equipped vehicles, narrow-post contact and legal part endpoints. Tests assert actual motion and deformation as well as finite state. Ordinary-operation cases require zero velocity safety clamps and zero nonfinite recovery events. These results establish regression behavior, not real-world calibration or exhaustive coverage of every combined build and collision.

The solver uses single-precision floats. It caps node velocity at 240 m/s, rejects malformed inputs, reports nonfinite recovery and sheds excess elapsed time after stalls. These safeguards are observable in telemetry; invoking them is not evidence that an extreme event was simulated correctly. Position and speed telemetry average the eight frame nodes rather than the whole vehicle's mass-weighted centre. `sim_ms` excludes drawing and most game work.

Only one selected vehicle is active. There is no self-collision, full triangle collision, continuous collision detection, multi-vehicle collision, dynamic soil, calibrated crash material or complete suspension/gearbox mechanism. Severe collapse can stretch or invert the render skin. The user reported smooth operation of v0.2 on a Samsung A15; v0.3's additional scenery and rendering still require testing on that phone. Desktop tests and native timings do not establish Android frame rate, thermal behavior or battery cost.
