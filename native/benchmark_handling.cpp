// Reproducible native launch, road contact, steering and brake measurements.
// g++ -std=c++17 -O2 native/benchmark_handling.cpp -o /tmp/benchmark_handling
#include "soft_rig.hpp"
#include <chrono>
#include <cmath>
#include <cstdio>
using boltyard::SoftRig;
using boltyard::Vec3;
static void advance(SoftRig &r, float seconds, float throttle = 0, float steering = 0, bool brake = false) {
    for (int i = 0; i < int(std::lround(seconds * 60)); ++i) r.step(1.0f / 60, throttle, steering, brake);
}
int main() {
    for (int terrain = 0; terrain < 3; ++terrain) {
        SoftRig r; r.set_terrain(terrain); advance(r, 4, 0, 0, true);
        Vec3 start = r.center(); double squared_vertical = 0; int samples = 0;
        float minimum_up = 1, max_vertical = 0;
        auto begin = std::chrono::steady_clock::now();
        for (int frame = 0; frame < 600; ++frame) {
            r.step(1.0f / 60, 1, 0, false);
            const float vy = r.velocity().y;
            if (frame > 60) { squared_vertical += vy * vy; ++samples; }
            minimum_up = std::min(minimum_up, r.up().y); max_vertical = std::max(max_vertical, std::abs(vy));
            if (frame == 119 || frame == 299 || frame == 599)
                std::printf("terrain=%d time=%.0fs speed=%.3fm/s (%.2fkm/h) distance=%.2fm lateral=%.3fm damage=%.5f\n",
                    terrain, (frame + 1) / 60.f, r.speed(), r.speed() * 3.6f, (r.center() - start).length(),
                    r.center().x - start.x, r.damage());
        }
        const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - begin).count();
        std::printf("terrain=%d CPU=%.3fms/60Hz-frame vertical_RMS=%.5fm/s vertical_max=%.4fm/s min_up=%.4f\n",
            terrain, milliseconds / 600, std::sqrt(squared_vertical / samples), max_vertical, minimum_up);
    }
    for (float steer : {0.35f, 1.0f}) {
        SoftRig r; advance(r, 3, 0, 0, true); advance(r, 5, 1);
        float minimum_up = 1;
        for (int frame = 0; frame < 360; ++frame) { r.step(1.f / 60, 0.7f, steer, false); minimum_up = std::min(minimum_up, r.up().y); }
        const float initial_speed = r.speed(); const Vec3 start = r.center(); advance(r, 3, 0, 0, true);
        std::printf("steer=%.2f turn_min_up=%.5f brake_from=%.3fm/s brake_distance=%.3fm speed_after_3s=%.5fm/s damage=%.5f\n",
            steer, minimum_up, initial_speed, (r.center() - start).length(), r.speed(), r.damage());
    }
}
