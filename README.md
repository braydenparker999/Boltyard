# Bolt Yard — Valley Expedition 0.3

An original offline Android offroading prototype with a native C++ deformable vehicle simulation and Godot 4.4.1 graphics. Version 0.3 expands the working soft-body prototype into an exploration game with three vehicles, interchangeable equipment and portrait support.

## Explore and build

- **Juniper Valley:** a 768 × 768 metre landscape with a forest trail, terraced quarry, overlook, lake shore and ridge. Six named destinations appear on the terrain map. Choose a destination, follow its compass bearing and drive into its discovery radius; discoveries persist.
- **Three distinct vehicles:** Bison Pickup, Scout SUV and Nomad Buggy have different body shapes, native structural bracing, dimensions and weight distributions. Each has 100 simulated mass nodes; their structures have 392, 400 and 404 beams respectively.
- **Six equipment slots:** tires, wheels, suspension, final drive, front bumper and roof equipment. Each vehicle has three compatible options per slot. The Nomad has its own nose brace and spare carrier; expedition armor and cargo racks fit the pickup/SUV. Equipment affects tire geometry and grip, suspension, gearing or mass distribution as appropriate.
- **Saved garage:** separate builds and six paint choices for every vehicle, with ten optional fine-tuning controls. Existing 0.2 pickup tuning migrates into the pickup bay; the old save remains intact. Equipping a part clears only the manual overrides affected by that part.
- **Portrait and landscape:** rotate while playing. The garage changes between a sidebar and bottom sheet, and driving controls rearrange for the screen. Input is cleared during rotation, pause and app backgrounding.
- **New vehicle graphics:** persistent GPU-skinned bodywork, tinted glass, metallic clearcoat paint, detailed rims and tires, visible suspension and matching equipment. Bodywork follows the actual simulated particles. Terrain uses near/far meshes, textured ground, instanced vegetation, fog and a sky environment.
- **Three graphics settings:** Performance is the default. Balanced and High increase terrain detail distance and shadow reach, and enable a static reflection capture at base camp. Sky reflections remain available throughout the map. These are environment reflections, not real-time mirror reflections.

Low range, differential coupling, live deformation, X-ray beam diagnostics, impact testing and repair/recovery remain available. The earlier construction sandbox is retained in `main.tscn`; the app opens `offroad_main.tscn`.

The simulation is experimental and is not calibrated to real vehicle or tire data. Obstacles use cylinder contacts, suspension uses simplified guides, and the lake is scenery without buoyancy. There is no vehicle self-collision, deformable soil, functioning winch, fluid mud, detachable panels or multiplayer. See [SIMULATION.md](SIMULATION.md) for the model and its limits.

## Install

Open the [verified 0.3 build](https://github.com/braydenparker999/Boltyard/actions/runs/33987686884) and download **bolt-yard-android**. Future builds are in this repository's [Actions](https://github.com/braydenparker999/Boltyard/actions). Extract `bolt-yard-0.3.0-explorer.apk` and open it on an ARM64 Android phone. Allow installation from your download/file app if Android asks.

The APK uses package `games.boltyard.prototype`, version 0.3.0 / code 3 and the same development signing key as earlier prototypes, so install it over the existing app to retain saves. The included key is only for development builds. The game needs no Play Store account, runtime network access or storage permission.

The user reported that 0.2 ran smoothly and customization worked on a Samsung A15. Version 0.3's sustained frame rate, temperature, touch comfort and graphics still need comparison on that phone. Start with Performance selected. Build verification and downloadable artifact details are recorded in [VALIDATION.md](VALIDATION.md).

## Controls

Choose a vehicle and equipment, then tap **DRIVE**. Hold **GO** together with **LEFT** or **RIGHT**; **REV** reverses and **BRAKE** stops. **Map** selects a destination. **Repair & camp** rebuilds the vehicle at base camp while keeping builds and discoveries. Returning to the garage also resets the vehicle at camp. The garage includes orbit/zoom controls, **X-ray** and **Impact test**.

Keyboard: WASD or arrows drive and steer, Space brakes, R repairs, Tab changes garage/drive and M opens the map. Escape pauses or closes the map. Saves are local to the installed app.

## Build and test

GitHub Actions installs Godot 4.4.1, its Android template, JDK 17, Android SDK 34 and NDK 23.2.8568313. It pins godot-cpp to `e4b7c25e721ce3435a029087e3917a30aa73f06b` and SCons to 4.8.1, builds Linux and ARM64 GDExtensions, runs native and engine tests, renders screenshots, exports the APK and verifies its signature and native library contents.

Complete Ubuntu build with JDK 17 and Android SDK configured:

```bash
bash tools/ci_build.sh
```

Standalone physics tests, without Godot:

```bash
mkdir -p build
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_soft_rig.cpp -o build/test-soft-rig
build/test-soft-rig
```

Build native libraries with `bash tools/build_native.sh` before importing. The checked-in extension maps Linux x86_64 and Android ARM64 debug builds; other hosts and release exports need corresponding builds and mappings. Use Godot 4.4.1 export templates and **Export With Debug**.

```bash
godot --headless --path . --editor --import
godot --headless --path . --script tests/run.gd
godot --headless --path . --script tests/offroad.gd
godot --headless --path . --script tests/catalog.gd
godot --headless --path . --script tests/explorer.gd
```

Run tests and screenshots against disposable user data. The explorer suite backs up/restores its save fixtures, but the retained prototype tests and capture script may write setup/blueprint saves. Mesa software-rendered screenshots are not phone performance measurements.

## Source map

| File | Purpose |
| --- | --- |
| `native/soft_rig.hpp` | Native node/beam model and XPBD solver |
| `native/terrain_v03.hpp` | Shared exploration heightfield, surfaces and obstacles |
| `native/binding.cpp` | Godot interface, fixed cadence and diagnostics |
| `native/test_soft_rig.cpp` | Physics behavior and stability checks |
| `scripts/vehicle_catalog.gd` | Vehicle definitions, compatible equipment and composed tuning |
| `scripts/offroad_truck.gd` | Persistent particle-bound vehicle geometry |
| `shaders/vehicle_skin.gdshaderinc` | GPU binding to chassis, cab, tire and suspension particles |
| `scripts/offroad_world.gd` | Terrain, vegetation, lighting and quality levels |
| `scripts/offroad_main.gd` | Garage, saves, responsive controls and camera |
| `scripts/exploration_map.gd` | Terrain map and selectable destinations |
| `tests/catalog.gd`, `tests/explorer.gd` | Equipment, save migration, discovery and orientation checks |
| `tools/ci_build.sh` | Test gates, screenshot capture, Android export and verification |
