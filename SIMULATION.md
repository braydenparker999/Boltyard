# Bolt Yard 0.2 — simulation model

This document describes the implemented prototype in `native/soft_rig.hpp`, its Godot binding in `native/binding.cpp`, and the surfaces drawn by `scripts/offroad_truck.gd` and `scripts/offroad_world.gd`. The vehicle's motion comes from a deformable particle network, wheel torque, and ground contact. It does not use Godot's rigid vehicle body underneath the deforming graphics.

The objective is an inspectable starting point for an off-road simulator. This implementation is not a validated vehicle, tire, or crash-engineering model, and it does not establish BeamNG-equivalent fidelity. Measured validation results belong in `VALIDATION.md`.

## Physical topology and units

Positions are metres, time is seconds, mass is kilograms, spring rates are N/m, suspension damping coefficients are N s/m, and torque is N m. Tire pressure and body stiffness are dimensionless tuning multipliers. In particular, a tire-pressure setting of `1.0` is a relative baseline, not one bar or a measured inflation pressure.

The rig contains **100 finite-mass particles and 392 beam records**:

| Assembly | Particles | Beam records | Share of total mass | Mass at the 1,200 kg default |
|---|---:|---:|---:|---:|
| Chassis | 8 | 28 chassis distance constraints | 60% | 720 kg; 90 kg per node |
| Cab | 8 | 28 internal and 12 attachment distance constraints | 18% | 216 kg; 27 kg per node |
| Four tires and hubs | 84 | 320 tire distance constraints | 22% | 264 kg; 66 kg per wheel assembly |
| Suspension | No additional nodes | 4 spring descriptors | Included above | No additional mass |

Each wheel has one hub and two rings of ten tire particles: 21 equally weighted nodes, about 3.143 kg each at the default mass. Hub indices are 16, 37, 58, and 79; the front wheels are the first two. Forward is negative Z and vertical is positive Y at spawn.

The chassis and cab are each fully braced eight-node cells: every pair of vertices is connected. This prevents the shear mechanisms of an unbraced cube, but the cells are coarse structural approximations. Their connectivity and stiffness do not come from a real frame's geometry, steel section sizes, or material tests.

The chassis uses distance-constraint stiffness `2,800,000 × body_stiffness`; the cab uses `950,000 × body_stiffness`, with `1,700,000 × body_stiffness` for its twelve attachments. These values are network parameters, not Young's modulus. Suspension records are visible in diagnostics but are solved by the axis constraints described below, rather than by the distance-constraint loop.

Changing mass distributes it using the fixed percentages above. Changing tire size also changes tire width to `0.58 × radius`. There is no separate physical inventory of engines, accessories, panels, or cargo.

## Integration and constraint solving

The C++ core takes fixed **1/240 s substeps**. The binding accumulates caller time in **1/120 s increments**, each normally producing two core substeps. Godot's configured 60 Hz physics callback therefore normally runs four substeps. Drawing reads the most recent positions separately; the vehicle renderer does not interpolate between physics states.

Each substep performs this sequence:

1. Smooth the requested steering angle and apply wheel, braking, and drivetrain torques.
2. Add gravity, apply the small global velocity factor `1 - 0.010 h`, and predict particle positions using `x_predicted = x_old + h v`.
3. Clear the constraint multipliers and perform **nine sequential solver iterations**. Each iteration solves beam distances, suspension and wheel-plane guides, then terrain contact and friction. Beam traversal reverses on alternate iterations.
4. Update structural yielding and breakage from the largest pre-correction beam error observed during the substep.
5. Reconstruct velocity from corrected positions, remove inward normal contact velocity, and apply structural and suspension damping.

For an unbroken distance constraint, let `w_a = 1/m_a`, `w_b = 1/m_b`, `L` be its current rest length, `n = (x_b - x_a)/|x_b - x_a|`, and compliance `alpha = 1/k`. The implemented XPBD update is:

\[
C=\lVert x_b-x_a\rVert-L,\qquad \tilde\alpha=\alpha/h^2
\]

\[
\Delta\lambda=\frac{-C-\tilde\alpha\lambda}{w_a+w_b+\tilde\alpha},\qquad
\lambda\leftarrow\lambda+\Delta\lambda
\]

\[
x_a\leftarrow x_a-w_a n\Delta\lambda,\qquad
x_b\leftarrow x_b+w_b n\Delta\lambda.
\]

Multipliers persist across iterations within one substep and reset for the next. This compliant position-constraint formulation follows Macklin, Müller, and Chentanez's [XPBD paper](https://matthias-research.github.io/pages/publications/XPBD.pdf). Nine iterations are a bounded approximation; they do not guarantee convergence, exact energy conservation, or independence from every timestep and topology choice.

All core vectors use single-precision floats. The core is independent of Godot; a [GDExtension](https://docs.godotengine.org/en/4.4/tutorials/scripting/gdextension/what_is_gdextension.html) exposes its configuration, particles, beam states, terrain samples, and telemetry to the game.

## Suspension, steering, and tires

Each hub is guided relative to a lower chassis corner using the current chassis right, forward, and up directions. Lateral and longitudinal constraints are stiff, while the vertical constraint has compliance `1/spring_rate` and unloaded offset `-ride_height`. Travel stops allow 0.22 m of extension and compression of `min(0.28 m, 0.72 × ride_height)`, measured relative to that offset.

These are compliant prismatic guides. They approximate wheel-location hardware without simulating control arms, joints, ball bearings, a solid axle, camber curves, caster, or an anti-roll bar. The guides remain active after nearby structural beams break. Wheel detachment and suspension-component failure are not implemented.

The vertical damper uses the average velocity of all 21 wheel nodes. With relative vertical speed `v_rel`, damping coefficient `c`, and combined inverse mass `W` of the chassis anchor and whole wheel assembly, it applies:

\[
\beta=\frac{c h W}{1+c h W},\qquad J=-\frac{v_{rel}\beta}{W}.
\]

The chassis anchor receives the opposite impulse to the wheel assembly; all wheel nodes receive the same resulting velocity increment. This prevents the light hub alone from representing the entire unsprung mass. Structural damping separately removes a fraction of relative axial velocity along intact beams using equal-and-opposite pair impulses: 0.026 for tire links and 0.018 for other structural links per substep. These are numerical/material damping choices, without a fitted hysteresis model.

The front-wheel steering target is `steer × 0.54 / (1 + speed × 0.027)` radians, approached with a first-order response at rate 8/s. Both front wheels share that target; there is no Ackermann geometry. Tire particles are constrained to the two sidewall planes of each wheel's steering axis with finite compliance.

Tire rings include hub spokes, adjacent and next-nearest ring links, cross-width links, and cross-ring diagonals. Relative pressure scales these stiffnesses, using a square-root dependence for the adjacent ring links and a linear dependence for the other links. Lower settings can change carcass deformation under load. There is **no enclosed-gas pressure force, volume constraint, pressure-volume law, temperature, puncture, or calibrated contact-patch model**. The twenty contacting particles per tire are a coarse discretization of a continuous carcass.

## Drive torque and contact

Wheel angular velocity is estimated from the current node velocities and their moment arms around the wheel axis. Rotational inertia is recomputed from the deformed tire nodes. For applied wheel torque `T`, each tire node receives a tangential velocity increment:

\[
\Delta v_i=(a\times r_i)\frac{T}{I}h,\qquad
I=\sum_i m_i\lVert a\times r_i\rVert^2.
\]

The hub receives a correction for the summed linear impulse on an asymmetric carcass. An opposing rotational increment is distributed over the eight chassis nodes about the chassis centre. This provides an approximate axle/engine reaction through the deformable chassis. Tire-ground friction turns wheel motion into vehicle propulsion; the code does not apply a separate forward acceleration to the chassis.

The torque setting is divided equally among four wheels, multiplied by 2.65 in low range or 1.0 in high range. An artificial speed limiter reduces torque according to the fastest wheel; its reference circumferential speeds are 10.5 m/s and 26 m/s. This is a bounded drive model, not an engine RPM/torque curve, gear train, clutch, or transmission simulation.

With the differential toggle unlocked, wheels receive equal drive torque. With it locked, a finite torsional coupling adds `(mean_omega - wheel_omega) × inertia × 13`, capped at 1,500 N m per wheel. The mean is across **all four wheels**, not independently modelled front, rear, and centre differentials. This coupling permits finite slip and is not an exact locking constraint. Braking opposes wheel rotation up to 2,300 N m per wheel and suppresses drive torque. A small angular rolling-loss term is also applied.

Every particle can contact the static analytic heightfield. Body and hub collision radii are 0.075 m; tire collision radii are `0.12 × tire_radius`. Contact uses a local normal sampled by central differences and the approximate signed clearance `(particle_y - terrain_height) × normal_y - particle_radius`. A unilateral compliant constraint prevents tensile contact impulses, with a foundation stiffness of 4,500,000 N/m.

Friction accumulates tangential position corrections within a substep and limits their magnitude to `mu × normal_lambda × inverse_mass`. Tire friction starts at 1.20; other nodes use 0.45. The trail region `-15 < z < -7` multiplies these by 0.72. Tire friction receives an additional bounded relative-pressure multiplier. This is a simplified Coulomb-style positional contact treatment with no separate static/dynamic coefficient, measured slip-ratio curve, relaxation length, or soil shear model. Ground contact is inelastic in its normal velocity response.

## Permanent damage and visible deformation

Chassis and cab beams can yield and break; tire and suspension records do not. For each structural beam, trial strain is its peak absolute length error during the substep divided by `max(0.02 m, original_rest_length)`. Yield thresholds are 0.115 for chassis beams and 0.095 for cab beams.

Above yield, the signed plastic increment is `0.22 × (trial_strain - yield)`, capped to ±0.025 per substep. It changes the same rest length used by subsequent load-bearing solves. Rest lengths remain between 0.45 and 1.65 times their original lengths. Accumulated absolute rest-length change records plastic history. A beam breaks at trial strain above 0.72, or when accumulated plastic strain exceeds 0.50 and trial strain exceeds 1.5 times yield. Broken beams are skipped by distance solving and axial damping.

The damage readout averages `1` for a broken structural beam or `min(1, 4 × accumulated_plastic_strain)` for an intact one. It is a game diagnostic, not a physical percentage of destroyed material. Because damage uses finite-solver trial errors and chosen thresholds, impact severity and damage progression need calibration; they are not experimentally validated material failure laws.

Visible panels use trilinear interpolation of the eight chassis or eight cab nodes, including modest extrapolation for outlines such as bumpers. Tire surfaces connect the actual ring nodes, with outward padding matching their nominal particle contact radius. The body and tire meshes are regenerated from these positions; the damage shape is not a canned animation. Wireframe mode draws beam endpoints and colors strain and breakage.

The rendered body is a skin, however: its triangles do not carry independent mass or collide with terrain. Breaking beams does not tear or detach render triangles. Body panels, treads, and rims are not independent mechanical components. Severe damage can invert or stretch panels, and visible surfaces can intersect terrain between collision particles.

## Terrain extent, safeguards, and measurement

The course uses an analytic heightfield with elevation changes, narrow ruts, a one-sided articulation hump, rock ripples, and a smooth ledge. Rendering samples the same height function, with 0.25 m lateral and 0.3 m longitudinal spacing near the central trail and coarser spacing farther out. The rendered triangles approximate the continuous collision surface, so the two are not identical between samples. Signs and course markers are decorative and have no native contact.

The visible mesh covers `x = -80..80 m` and `z = -115..65 m`; the analytic collision function itself continues beyond that extent. The driving UI repairs and recovers the truck when its reported position exceeds `|x| = 72 m`, `z < -105 m`, or `z > 55 m`. This is an explicit course boundary, not an endless world.

The native core rejects invalid timesteps and nonfinite controls, clamps supported tuning values, limits node speed to 240 m/s, and restores a particle's previous position if its corrected position becomes nonfinite. Localized test impulses are limited to 45,000 N s and explicit diagnostic displacements to 5 m. These protections bound failure cases; their activation is not evidence of correct physics.

`safety_clamps` counts velocity limiting events, and `rejected_states` counts nonfinite position or velocity repairs. They accumulate until reset. Normal verification should inspect these counters alongside the actual motion rather than treating “still finite” as a stability result.

The core accepts at most 0.1 s per call and at most 24 substeps, recording time discarded by that per-call limit. The binding separately accepts at most 0.05 s per caller update before its 120 Hz accumulator. Shedding elapsed time avoids enormous catch-up steps but makes simulation time run slower than wall time after a stall. The core's `time_dropped()` counter alone cannot observe time discarded before reaching it; binding-level dropped time must be accounted for separately when interpreting telemetry.

Reported position and speed are the averages of the eight chassis nodes, not the whole vehicle's mass-weighted centre and velocity. `sim_ms` measures the latest physics call and excludes mesh reconstruction, rendering, and most game work. Desktop timing or passing automated tests cannot establish Android frame rate, thermal behaviour, battery consumption, or touch responsiveness. Those require testing the exported build on the phone.

## Remaining physical limits

The prototype supports one fixed-topology vehicle against one static heightfield. It has no particle self-collision, beam/triangle collision, continuous collision detection, other dynamic vehicles, arbitrary collision meshes, soil deformation, flowing mud, water forces, gas dynamics, or calibrated crash materials. Suspension and drivetrain constraints are approximations, and complete structural collapse can produce invalid-looking skins even when numerical safeguards keep the nodes finite. These are substantive modelling limits of the current code, not features implied by the term “soft body.”
