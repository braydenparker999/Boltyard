# Validation record — 2026-09-05

## Executed in the authoring workspace

- `python3 tools/check_project.py`: passed. Checks the starter's JSON structure and expected parts, the SVG icon, all explicit `res://` file references, ARM64 and landscape configuration, and development signing key presence.
- `bash -n tools/ci_build.sh`: passed shell syntax validation.
- Workflow YAML parsed with PyYAML; expected Android build job and script command were found.
- Development signing key generated successfully with Java keytool.

These checks do **not** compile GDScript or prove that gameplay works.

## Included but not executed

`tests/run.gd` exercises:

- Starter acceptance, known total mass, and serialization round-trip.
- Rejection of fractional coordinates, overlaps, unknown parts, elevated wheels, disconnected solids, missing motors, and duplicate seats.
- Preservation of the active blueprint after a malformed load; successful save / load round-trip.
- Four-wheel ground contact, resting height and orientation, forward acceleration, braking, turning, and reset.
- Main-scene startup, editor fit, placing a part, undo, and switching between preview and simulation.

The workflow also runs the Godot importer and APK signature verification. All of these require an external build run. They have **not** passed yet.

## Remaining acceptance gates

1. Run the workflow and resolve any GDScript import, engine-test, or export errors.
2. Install and launch the resulting ARM64 APK.
3. Verify the rendered UI and simultaneous touch input in landscape.
4. Test ramps, uneven ground, asymmetric ballast, recovery, and background / resume.
5. Verify save persistence on a real device.
6. Measure sustained FPS and temperature before choosing a supported part budget. The 96-part limit is a design guard, not a measured performance guarantee.

Godot and the Android SDK were not installed in the authoring workspace. Dependency download could not proceed due to the workspace's network restriction. No APK was built, no Android device was accessed, and no runtime screenshot was produced.

