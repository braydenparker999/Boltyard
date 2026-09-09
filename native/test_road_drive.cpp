// Whole-map driving regression. The controller supplies the same throttle,
// steering and brake inputs as the player; it never moves/rotates the vehicle.
// g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_road_drive.cpp -o /tmp/test_road_drive
#include "soft_rig.hpp"
#include <cstdio>
#include <vector>
using namespace boltyard;

static bool drive_loop(float cruise_speed) {
    SoftRig rig; rig.set_terrain(2);
    const auto &road = exploration_detail::road;
    rig.reset({road.front().x, rig.terrain_height(road.front().x, road.front().z) + 1.5f, road.front().z});
    for (int i = 0; i < 360; ++i) rig.step(1.f / 120, 0, 0, true);
    std::vector<float> lengths(road.size());
    for (std::size_t j = 1; j < road.size(); ++j)
        lengths[j] = lengths[j - 1] + std::hypot(road[j].x - road[j - 1].x, road[j].z - road[j - 1].z);
    float progress = 0, maximum_error = 0, minimum_up = 1, max_speed = 0;
    int frame = 0;
    for (; frame < 200 * 120 && progress < lengths.back() - 2; ++frame) {
        const Vec3 center = rig.center(); float closest = 1e9f, near_progress = progress;
        for (std::size_t j = 1; j < road.size(); ++j) {
            if (lengths[j] < progress - 8 || lengths[j - 1] > progress + 30) continue;
            const float dx = road[j].x - road[j - 1].x, dz = road[j].z - road[j - 1].z;
            const float t = std::clamp<float>(((center.x - road[j - 1].x) * dx + (center.z - road[j - 1].z) * dz) /
                                       (dx * dx + dz * dz), 0.f, 1.f);
            const float distance = std::hypot(center.x - road[j - 1].x - dx * t, center.z - road[j - 1].z - dz * t);
            if (distance < closest) { closest = distance; near_progress = lengths[j - 1] + t * (lengths[j] - lengths[j - 1]); }
        }
        progress = std::max(progress, near_progress);
        const float lookahead = 4 + 0.6f * rig.speed();
        const float target_distance = std::min(lengths.back(), progress + lookahead);
        std::size_t segment = 1;
        while (segment + 1 < road.size() && lengths[segment] < target_distance) ++segment;
        const float t = (target_distance - lengths[segment - 1]) / (lengths[segment] - lengths[segment - 1]);
        const Vec3 desired(road[segment - 1].x + (road[segment].x - road[segment - 1].x) * t - center.x, 0,
                           road[segment - 1].z + (road[segment].z - road[segment - 1].z) * t - center.z);
        const Vec3 forward = rig.forward(), right = forward.cross(rig.up());
        const float heading_error = std::atan2(desired.dot(right), desired.dot(forward));
        const float steering_limit = 0.60f / (1 + std::pow(rig.speed() / 10, 1.5f));
        const float steer = std::atan2(2 * rig.config().wheelbase * std::sin(heading_error), lookahead) / steering_limit;
        float planned_speed = cruise_speed;
        // Brake before tight bends. Constant 45km/h through a hairpin is not a
        // reasonable traversal test; 3.5m/s² is the controller's corner budget.
        for (std::size_t j = 1; j + 1 < road.size(); ++j) {
            const float distance = lengths[j] - progress;
            if (distance < -10 || distance > 70) continue;
            const Vec3 incoming(road[j].x - road[j - 1].x, 0, road[j].z - road[j - 1].z);
            const Vec3 outgoing(road[j + 1].x - road[j].x, 0, road[j + 1].z - road[j].z);
            const float angle = std::acos(std::clamp(incoming.normalized().dot(outgoing.normalized()), -1.f, 1.f));
            const float corner_speed = std::sqrt(3.5f * 8 / std::max(0.05f, 2 * std::sin(angle * 0.5f)));
            planned_speed = std::min(planned_speed,
                std::sqrt(corner_speed * corner_speed + 2 * 3.0f * std::max(0.f, distance - 14)));
        }
        const bool brake = rig.speed() > planned_speed + 0.35f;
        const float throttle = brake ? 0 : std::clamp((planned_speed - rig.speed()) * 0.6f + 0.18f, 0.f, 1.f);
        rig.step(1.f / 120, throttle, std::clamp(steer, -1.f, 1.f), brake);
        maximum_error = std::max<float>(maximum_error, closest); minimum_up = std::min<float>(minimum_up, rig.up().y);
        max_speed = std::max(max_speed, rig.speed());
        if (!rig.center().finite() || closest > 6 || rig.up().y < 0.80f) break;
    }
    const bool passed = progress >= lengths.back() - 2 && maximum_error < 3 && minimum_up > 0.90f &&
        rig.damage() == 0 && rig.broken_count() == 0 && rig.safety_clamp_count() == 0 &&
        rig.rejected_state_count() == 0 && rig.time_dropped() == 0;
    std::printf("%s cruise=%.1fkm/h route=%.1f/%.1fm time=%.1fs road_error=%.3fm min_up=%.4f max_speed=%.2fkm/h damage=%.5f\n",
        passed ? "PASS" : "FAIL", cruise_speed * 3.6f, progress, lengths.back(), frame / 120.f,
        maximum_error, minimum_up, max_speed * 3.6f, rig.damage());
    return passed;
}
int main() {
    const bool trail = drive_loop(8), fast = drive_loop(12.5f);
    return trail && fast ? 0 : 1;
}
