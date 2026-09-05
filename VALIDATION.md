# Validation record — Bolt Yard 0.2, 2026-09-05

## Verified build

[Successful Android build](https://github.com/braydenparker999/Boltyard/actions/runs/33984129744)

Code commit: `6be0cf2e07ff237f70440db6994aa245771450cc`

Artifact: `bolt-yard-0.2.0-softbody.apk`, 27,228,129 bytes.

SHA-256: `51b461870effdc474072271eeb95339b6898b70e849daaab65c1a101e9431ad1`

The downloaded APK matched the build checksum. It contains `lib/arm64-v8a/libboltyard.android.arm64.so`, `libc++_shared.so`, and the GDExtension registration. Android's apksigner verified v1, v2 and v3 signatures. It uses package `games.boltyard.prototype`, version 0.2.0 / code 2, the original development key, ARM64, minimum API 21 and target API 34.

## Automated results

**95 checks passed:**

- 47 standalone native physics tests: topology and mass, settling and symmetry, elastic recovery, permanent rest-length changes, beam failure, a real crash impulse, acceleration, reverse, steering, braking, airborne momentum, pressure response, spring loading, damping response, low-range and differential coupling, fixed cadence, terrain traversal and recovery.
- The native suite also covers every individual numeric garage slider endpoint (20 cases), four combined extremes, a full trail traversal and one minute parked. Ordinary scenarios require zero velocity-cap activations, zero nonfinite-state repairs and no discarded simulation time.
- 17 Godot native-extension and offroad scene checks: registration, node/beam data, four-wheel contact telemetry, load support, propulsion, live drivetrain changes, reset, render-cadence partitions, scene startup, garage/drive switching and simultaneous right/throttle input signs.
- 31 retained engine checks for the earlier construction prototype and its saved blueprints, suspension vehicle, driving and UI.

The native suite passed locally with `-Wall -Wextra -Werror -pedantic`. A separate focused AddressSanitizer/UndefinedBehaviorSanitizer run passed deformation, impacts, pressure settings, steering and terrain scenarios; leak detection was unavailable because that runtime restricted process metadata. The GitHub build reran the complete native suite with its checked-in compile flags.

The parked-brake check allows up to 10 cm of compliant settling after stopping, while requiring final speed below 0.01 m/s. Permanent-yield tests require actual physical beam rest-length changes, rather than only a damage counter. These are prototype behavior tolerances, not real-vehicle calibration.

## Rendering and packaging

Godot 4.4.1 imported the final project without script errors. Garage, driving, intact beam structure, impacted beam structure and impacted body surfaces were rendered under Xvfb/Mesa and inspected. No script/runtime errors appeared in the final test/capture logs. The runner emitted a software-driver V-Sync warning.

Visual review corrected the grounded-wheel display (previously contact nodes were labelled as wheels), restored visible slider tracks, and added a readable backdrop to the garage heading. Increased directional-shadow bias reduced self-shadow artifacts; some fine shadow banding remains in the software-rendered terrain and needs comparison on a phone. Mesh deformation and the diagnostic beam view are present in the captured scenes.

Initial build attempts exposed a missing OS class in the reduced native binding profile, missing shared-library filename suffixes, and an incorrect Godot sky enum. Those were fixed before the successful build. The workflow rejects native test failures, GDScript parse errors, failed engine checks, missing native APK contents and failed signature verification.

The build logs and screenshots are available as the `bolt-yard-build-logs` artifact of the linked run. The APK and its checksum are in `bolt-yard-android`.

## Still needs a physical Android phone

No Android emulator or physical Android device was accessed. The following remain unverified on target hardware:

1. Installation, launch and updating the older prototype.
2. Simultaneous touch steering/throttle, comfortable controls and screen cutouts.
3. Handling over the trail with stock and customized setups, impacts and recovery.
4. Tuning persistence after closing, plus background/resume behavior.
5. Sustained frame rate, temperature, battery use and shadows on the phone GPU.

The screenshot runner uses Mesa software rendering. Its FPS is not a phone benchmark; the native `sim_ms` number excludes mesh construction and rendering. Passing the numerical suite does not establish BeamNG fidelity or a calibrated tire/material model. Physical approximations and missing systems are described in [SIMULATION.md](SIMULATION.md).
