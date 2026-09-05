# Bolt Yard — Soft-body Offroad 0.2

An original offline Android offroading prototype. A native C++ node-and-beam solver simulates a deformable pickup chassis, cab and four tire carcasses. Godot 4.4.1 renders the body directly from the simulated nodes. This is a small experimental vehicle simulation, not BeamNG physics fidelity or a finished commercial game.

## What you can drive and tune

- One pickup with 100 mass nodes and 392 constraints, permanent structural yielding and breakable chassis/cab beams.
- Four deformable tires with individual ground contacts, suspension springs, dampers, steering, drive torque and brakes.
- A test course with bumps, ruts, ledges and uneven terrain. Leaving its visible boundary returns and repairs the truck at the start.
- Ten physical tuning controls: tire radius, relative tire pressure, ride height, spring rate, damping, engine torque, mass, track width, wheelbase and body stiffness.
- Trail, Crawler and Desert setups, six paints, low range and differential coupling. Garage changes rebuild the truck; drivetrain toggles work while driving.
- Live body deformation, strain-colored node/beam view, an impulse impact test and repair/recovery.
- Landscape touch controls, keyboard controls, pause and a locally saved tuning setup.

The pressure control changes carcass stiffness and a bounded grip multiplier; it is not calibrated in bar. Differential locking is a simplified finite coupling between wheel angular velocities. Suspension uses prismatic guides, not complete control-arm geometry. There is no vehicle self-collision, deformable soil, fluid mud, calibrated rubber model, drivetrain damage, detachable panels, multiplayer or part-swap catalog. See [SIMULATION.md](SIMULATION.md) for the implemented mathematics and limitations.

The earlier construction sandbox remains in `main.tscn`; the app now opens `offroad_main.tscn`. Its original blueprint save is separate from the new tuning save.

## Install

Open this repository's [Actions](https://github.com/braydenparker999/Boltyard/actions), choose a successful **Build Android APK** run and download **bolt-yard-android**. Extract `bolt-yard-0.2.0-softbody.apk` and open it on an ARM64 Android phone. Allow installation from your file/download app if Android asks. The APK uses package `games.boltyard.prototype`, version code 2, and the same development signing key as 0.1 so it can update that prototype.

The key included in this repository is for development builds only. No Play Store account or runtime network connection is required. Build and real-device verification status is recorded in [VALIDATION.md](VALIDATION.md).

## Controls

Tap **DRIVE** to leave the garage. Hold **GO** together with **LEFT** or **RIGHT**; use **REV** and **BRAKE** as needed. **REPAIR** resets the simulation at the start. The garage has **X-RAY** and **IMPACT TEST** controls.

Keyboard: WASD or arrows drive and steer, Space brakes, R repairs, Tab switches garage/drive. Garage tuning saves locally. Test installation, simultaneous touches, background/resume and sustained frame rate on the actual target phone before judging the mobile experience.

## Build and test

GitHub Actions installs Godot 4.4.1, its Android template, JDK 17, Android SDK 34 and NDK 23.2.8568313. It pins godot-cpp to commit `e4b7c25e721ce3435a029087e3917a30aa73f06b`, builds Linux and ARM64 GDExtensions with SCons 4.8.1, runs native and engine tests, renders screenshots, exports the APK and verifies its signature and native library contents.

For a complete Ubuntu build with JDK 17 and an Android SDK configured:

```bash
bash tools/ci_build.sh
```

For the standalone physics tests (no Godot dependency):

```bash
mkdir -p build
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_soft_rig.cpp -o build/test-soft-rig
build/test-soft-rig
```

Build the native libraries with `bash tools/build_native.sh` before importing in Godot. The checked-in extension maps Linux x86_64 and Android ARM64 debug builds; other hosts and release exports need corresponding builds and mappings. Use matching Godot 4.4.1 export templates and **Export With Debug**. Do not open the new scene without its native library.

Engine integration tests:

```bash
godot --headless --path . --editor --import
godot --headless --path . --script tests/run.gd
godot --headless --path . --script tests/offroad.gd
```

Run tests against disposable user data: integration tests may write setup/blueprint saves. Screenshots use Mesa software rendering and are not phone performance measurements.

## Source map

| File | Purpose |
| --- | --- |
| `native/soft_rig.hpp` | Standalone physical model and XPBD solver |
| `native/binding.cpp` | Godot interface, fixed cadence, diagnostics |
| `native/test_soft_rig.cpp` | Physics behavior and stability tests |
| `scripts/offroad_truck.gd` | Body and tire mesh deformation |
| `scripts/offroad_world.gd` | Matching sampled terrain and course visuals |
| `scripts/offroad_main.gd` | Tuning, persistence, controls and camera |
| `tests/offroad.gd` | Native extension and scene integration checks |
| `tools/ci_build.sh` | Native build, engine tests, rendering and APK verification |
