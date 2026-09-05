# Validation record — Bolt Yard 0.3, 2026-09-05

The integrated Android build passes **204 automated checks**. Actual rendered screenshots were inspected in both orientations, with all three vehicles and the exploration map. Artifact identity and packaging verification are recorded below.

## Verified APK

[Successful Android build](https://github.com/braydenparker999/Boltyard/actions/runs/33987686884)

Code commit: `985be43678fe103ca1a13b297efa70ef9d9a68da`

Artifact: `bolt-yard-0.3.0-explorer.apk`, 27,290,312 bytes.

SHA-256: `9648c48a951997a77b879cddaf6bebd9c3eed5fbec6b3fd610b5179590b25f02`

The downloaded APK matched the workflow checksum and passed ZIP integrity checks. Its ARM64 solver, C++ runtime, extension registration and vehicle shader include are present. Test files and the development keystore are excluded from APK assets.

Android apksigner verified v1, v2 and v3 signatures. The signing certificate fingerprint matches the downloaded v0.2 APK, supporting an in-place update. The binary manifest confirms `games.boltyard.prototype`, version 0.3.0 / code 3, orientation `fullUser` (13), and no requested permissions. The package supports minimum API 21 and targets API 34. Both screen orientations are permitted subject to Android's auto-rotation setting.

All 204 checks passed in the final workflow. Final capture logs contain no script, shader or runtime errors, and visual review confirmed the layout corrections, intact vehicles, clearer shadows and revised lake/boulder appearance. Some distant terrain remains coarse and the graphics are procedural and stylized.

The APK/checksum and all validation logs/screenshots are available as `bolt-yard-android` and `bolt-yard-build-logs` in the linked workflow. No further code changes were made after this verified build; the subsequent commit only updates these documents.

## Automated coverage

- 73 native C++ checks: all 47 retained physics cases plus distinct vehicle structures, equipment effects, exact mass accounting, centre-of-mass shifts, native terrain, narrow-post contacts and part endpoints.
- 17 native-extension/offroad scene checks: registration, contact telemetry, load support, propulsion, live drivetrain changes, recovery, fixed cadence and combined control inputs.
- 31 retained engine checks for the earlier construction prototype.
- 47 catalog checks: three vehicle setups, compatible parts, physical composition, invalid values, tuning precedence and JSON round trips.
- 36 explorer checks: migration that preserves the legacy file, separately saved builds, equipment application, destination/discovery rules, map pause, settings persistence, both orientations, input clearing, camp reset, settled sidebar bounds, footer visibility and navigation size.

The native suite also passed locally with strict warnings; headless Godot checks passed locally. A separate renderer sweep instantiated all 54 compatible vehicle/part selections and verified that normal frame updates reuse the existing source mesh. This is one part selection at a time, not an exhaustive test of all combined equipment builds.

## Rendering review

The first capture pass rendered all three vehicles, portrait garage/driving, map, exploration, beam diagnostics and impact views with Godot 4.4.1 under Xvfb/Mesa. The vehicle skin, tires, windows, cage and equipment were visible without shader errors.

Review found oversized containers caused by wrapped text retaining a previous minimum size. Layout now settles over subsequent frames, and the automated suite checks the resulting bounds. The next screenshot pass confirmed the sidebar/footer and portrait navigation fixes, and removed the diagonal shadow striping. Additional fixes closed two hood side gaps, corrected lake/canopy triangle winding, adjusted daylight/shadow bias, applied the saved quality level after lighting creation, and restricted the static camp reflection to scenery. The final scenery pass replaced visibly repetitive water-color waves with gentle reflection-normal ripples, varied the shoreline and rounded boulder geometry.

The capture script renders 13 views, including a static camp reflection enabled with Balanced quality and a separate across-lake camera view to inspect the shoreline. No script, shader or runtime errors were present in successful capture logs. The runner emits a driver V-Sync warning.

The screenshot runner uses software rendering; its displayed FPS is not a Galaxy A15 measurement. Directional shadows and clearcoat/reflections use the GL Compatibility renderer. They are modest mobile-oriented effects, not ray tracing or real-time mirror surfaces.

## Device status

The user reported smooth operation and working customization for v0.2 on a Samsung A15. No physical Android device or Android emulator was accessed for v0.3. Installation/update, actual multitouch comfort, system auto-rotation, background/resume, sustained FPS, temperature and battery use still need a run on that phone.

Start with the default Performance setting. Balanced and High increase scenery/shadow reach and enable a static reflection at camp. Numerical tests establish regression behavior, not real-vehicle calibration or BeamNG-level fidelity. See [SIMULATION.md](SIMULATION.md) for the implemented mechanics and limitations.
