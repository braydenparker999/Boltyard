# Crawlworks 2.2 performance record

Status: host CPU bottleneck reproduced and accelerated; Samsung A15 acceptance pending. No phone FPS or GPU timing is claimed.

## Fixed host comparison

AMD EPYC 9V74 x86_64, Ubuntu GCC 13.3, `-O2`, single-thread native simulation. Baseline is 2.1 source a85f5dd with counting-only instrumentation; final is 2.2. Both use the same benchmark source, tuning, scenario construction, 30 Hz calls, 240 Hz substeps and nine solver iterations. Each fixture warms for 90 frames (3 simulated seconds), then measures 180 frames (6 seconds). Rolling fixtures drive for 140 measured frames and brake for 40; stationary fixtures hold the brakes. These are warmed physics-only wall timings, excluding rendering, initialization and A15 thermals. Final baseline and optimized runs were sequential with no concurrent local builds/tests. Host scheduling still affects tails.

The standalone `-pg` baseline profile attributes 46.77% of sampled self time to rock_distance and 39.23% to closest_triangle: 86% combined. Profiled timings are not used in the table. Every exact distance query previously scanned every hull triangle.

| Scenario | Median ms, 2.1 → 2.2 | p95 ms, 2.1 → 2.2 | p99 ms, 2.1 → 2.2 | Mean rock wheels, 2.2 | Triangles/frame, 2.1 → 2.2 |
|---|---:|---:|---:|---:|---:|
| ground | 0.33 → 0.34 | 0.43 → 0.49 | 0.61 → 0.90 | 0.00 | 0 → 0 |
| one | 7.69 → 0.98 | 10.03 → 1.11 | 11.60 → 1.23 | 1.00 | 337,920 → 21,872 |
| two_same | 16.74 → 1.70 | 18.74 → 2.00 | 21.43 → 2.12 | 2.00 | 721,920 → 41,872 |
| two_separate | 13.35 → 1.56 | 15.76 → 1.70 | 17.64 → 1.91 | 2.00 | 583,680 → 41,280 |
| diagonal | 17.04 → 1.75 | 19.74 → 2.07 | 35.73 → 2.57 | 2.00 | 768,000 → 47,712 |
| four | 27.45 → 2.82 | 32.28 → 4.17 | 52.26 → 6.32 | 4.00 | 1,259,520 → 90,528 |
| ledge_roll | 5.92 → 2.09 | 7.24 → 2.46 | 11.43 → 3.62 | 2.61 | 181,613 → 56,411 |
| silverpine_roll | 44.90 → 4.67 | 56.52 → 5.51 | 67.22 → 6.28 | 1.84 | 1,850,368 → 113,570 |
| karelia_roll | 26.47 → 3.24 | 33.47 → 4.01 | 36.30 → 4.34 | 1.29 | 1,102,399 → 93,430 |

All final measured frames are below 33.3 ms of native CPU time, with zero discarded simulation time and zero chassis damage. This does not imply total phone frame time below 33.3 ms. Four-wheel contact median is reduced by about 90%; closest-triangle work falls about 93%. Ground-only cost stays near 0.34 ms. Final suspension geometry changes some trajectories and settled heights slightly; an earlier acceleration-only comparison retained the baseline fixture outputs, and 80,402 direct reference comparisons have zero measured distance error.

`native/benchmark_contacts.cpp` contains the full fixtures. No-contact, one-wheel, two same-hull, two separate-hull, diagonal and four-wheel fixtures use generated 320-triangle expedition granite on level ground. A separate original low ledge and the Silverpine (11,-50) / Karelia (-89,-119) trail starts cover rolling transitions and braking with full map collision. Means refer to distinct rock-supported wheels, not patch count. Raw [baseline](tests/evidence/2.2-contact-baseline.csv) and [final](tests/evidence/2.2-contact-final.csv) CSVs also record total patches, queries, worst frame and >33.3 ms counts.

## Physical and visual evidence

Native gates retain mass, reaction impulse, pressure, grip, secondary corner support, face-removal, brake hold, cross-axle and route behavior. The spring-rate comparison settles at 122.50 mm mean sag for 20 kN/m and 60.72 mm at 40 kN/m, clear of bump stops. Both damper stroke packages fit their fixed bodies. The retained landing regression verifies independent rebound settling with unchanged causal thresholds.

The tire-width fixture now measures corresponding sidewall separation, cancelling common traction shear. Its previous absolute hub-offset measure conflated lateral squirm with widening. The pressure/width threshold and independent shear regression remain in place.

Headless engine checks include all 257 vehicle geometry assertions, 288 actual camera-input assertions, 40 new suspension checks and 2,315 loaded-rubber checks. The suspension fixture covers loaded, airborne droop, steering and cross-axle states; fixed lengths and eye attachment errors remain below one micrometre. A fitted buggy has 11,558 triangles, sharing the existing material surfaces. Actual shader/render review and signed Android export are recorded in VALIDATION.md after completion.

## Device test and limits

Start with Performance quality and the same map, build, tuning and orientation for comparisons. Drive over a single rock, then hold two and four tires on rock; compare rolling contact with braked hold. In Rig, frame median/p95/p99 and >50 ms counts cover the last 240 presentation frames. CPU physics and skin preparation are separated; frame intervals include presentation waiting. Copy performance report captures those raw samples plus device/setup/map metadata. The report has no remote transmission.

Measure after a cold start and again after at least ten minutes. The initial A15 goal remains p95 ≤33.3 ms / p99 ≤50 ms with no repeated contact-triggered stalls. It is a target, not a demonstrated result. GPU timestamps, hidden-scenery/hidden-tire GPU isolation, actual install/thermal behavior and device frame pacing remain unmeasured. The update preserves package, key and save paths; the delivered APK must still be checked independently before installation.
