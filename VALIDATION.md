# Validation record — Bolt Yard 0.4, 2026-09-05

The handling rebuild passes 78 native checks and two complete exploration-road driving scenarios. Local Godot tests pass 31 retained construction checks, 18 offroad integration checks, 47 catalog checks, 36 exploration/save/orientation checks, and 257 vehicle geometry checks: **467 assertions plus two road scenarios**.

## Handling

Default pickup speed after five seconds increases from 17.39 to 52.89 km/h on flat ground. Ten-second distance increases from 41.50 to 123.48 metres; flat vertical chassis velocity RMS falls from 0.0444 to 0.00018 m/s. The same host benchmark measures native CPU around 0.17–0.31 ms per 60 Hz frame versus 0.607 ms previously. Timing varies with concurrent host work and excludes graphics.

All three vehicles hold a 27% grade within 0.00071 m over ten seconds and restart uphill. A 1.299 km route completes with 28.8 and 45 km/h cruise targets and braking for bends, without damage, rejected states or velocity clamps. Driving cadence matches exactly at 10/15/30/60/120 Hz and with irregular frame intervals. Reverse-at-speed first brakes before reversing.

The local 21-second actual-control movie reaches 38.9 km/h along the trail, has minimum upright-vector y of 0.972, no damage or solver recoveries, and brakes to rest. A final movie with the finished materials is also required by the Android workflow. These are software-rendered host captures, not phone frame-rate results.

## Bodywork and graphics

The 257 geometry checks cover stock and fully fitted pickup, Scout and buggy builds. They inspect deformed vertices under steering, impact, cab dents and far-origin repair, rejecting nonfinite/degenerate triangles, opened shared seams and mesh-reuse failures. The stock models have 10,132 / 10,202 / 8,678 triangles; fully fitted variants have 10,296 / 10,366 / 8,574.

Actual OpenGL views were inspected for all three vehicles from front, side and rear, plus installed accessory combinations. Fixes include continuous shared panel deformation, enclosed wheel wells and interiors, supported buggy braces, attached roof/spare hardware, readable lamps, correct metal wheels and distinct paint/glass/rubber response.

World checks cover source-color conversion, mipmapped materials, ground/physics agreement, rock/shore geometry, detailed foliage, shadows, cached reflections and the new photographic sky, stone and foliage assets. Generated material prompts and provenance are in assets/world. Water remains scenery over a solid low-grip lake bed; it does not simulate buoyancy.

## Android build

The workflow builds and tests the native Linux and Android ARM64 libraries, renders 13 static views plus four driving frames and a controlled 21-second movie, exports the APK, and verifies signatures, package information and checksum. The downloaded artifact identity will be recorded here after that build completes.

## Device scope

The user tested earlier versions on a Samsung A15 and identified slow/glitchy handling and incomplete vehicle geometry in 0.3. No physical Android device or emulator has been accessed for 0.4. Installation/update behavior, actual touch feel, frame rate, temperature, background/resume and sustained battery cost still need validation on that phone. Existing package, signing key, save paths and orientation support are retained.
