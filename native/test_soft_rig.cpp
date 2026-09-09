// Standalone numerical/behavior tests. No Godot, display, Android or network needed.
// g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_soft_rig.cpp -o /tmp/test_soft_rig
#include "soft_rig.hpp"

#include <chrono>
#include <functional>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

using boltyard::Beam;
using boltyard::Config;
using boltyard::SoftRig;
using boltyard::Vec3;

namespace {
void require(bool condition, const std::string &message) {
    if (!condition) throw std::runtime_error(message);
}
void simulate(SoftRig &rig, float seconds, float throttle = 0, float steer = 0, bool brake = false) {
    int steps = int(std::lround(seconds * 120));
    for (int i = 0; i < steps; ++i) rig.step(1.0f / 120.0f, throttle, steer, brake);
}
void healthy(const SoftRig &rig) {
    require(rig.safety_clamp_count() == 0, "velocity safety cap activated");
    require(rig.rejected_state_count() == 0, "a nonfinite state was recovered");
    require(rig.time_dropped() == 0, "simulation silently shed ordinary frame time");
    for (const auto &p : rig.particles) {
        require(p.pos.finite() && p.prev.finite() && p.velocity.finite(), "nonfinite particle");
        require(p.inv_mass > 0 && std::isfinite(p.inv_mass), "invalid nodal mass");
        require(p.velocity.length() < 100, "implausible ordinary-operation nodal velocity");
    }
    for (const auto &b : rig.beams) {
        require(b.a >= 0 && b.a < rig.node_count() && b.b >= 0 && b.b < rig.node_count(), "invalid beam index");
        require(std::isfinite(b.rest) && b.rest > 0, "invalid rest length");
    }
}
float structural_error(const SoftRig &rig) {
    float e = 0;
    for (const auto &b : rig.beams) if (b.kind <= boltyard::CAB && !b.broken)
        e += std::abs((rig.particles[b.a].pos - rig.particles[b.b].pos).length() - b.rest);
    return e;
}
float changed_rest_lengths(const SoftRig &rig) {
    float e = 0;
    for (const auto &b : rig.beams) if (b.kind <= boltyard::CAB)
        e += std::abs(b.rest - b.original_rest);
    return e;
}
Vec3 mass_velocity(const SoftRig &rig) {
    Vec3 p; float total_mass = 0;
    for (const auto &n : rig.particles) if(!n.tire) { float m = (n.wheel>=0?SoftRig::nodes_per_wheel:1.f) / n.inv_mass; p += n.velocity * m; total_mass += m; }
    return p / total_mass;
}
float mean_hub_y(const SoftRig &rig) {
    float result = 0;
    for (int hub : rig.wheel_hubs) result += rig.particles[hub].pos.y * 0.25f;
    return result;
}
float total_mass(const SoftRig &rig) {
    float mass = 0;
    for (const auto &p : rig.particles) mass += 1 / p.inv_mass;
    return mass;
}
Vec3 center_of_mass(const SoftRig &rig) {
    Vec3 weighted;
    for (const auto &p : rig.particles) weighted += p.pos / p.inv_mass;
    return weighted / total_mass(rig);
}

} // namespace

int main() {
    const auto started = std::chrono::steady_clock::now();
    int passed = 0, failed = 0;
    auto test = [&](const std::string &name, const std::function<void()> &fn) {
        try { fn(); ++passed; std::cout << "PASS  " << name << '\n'; }
        catch (const std::exception &e) { ++failed; std::cerr << "FAIL  " << name << ": " << e.what() << '\n'; }
    };

    test("shipped settings, physical assemblies and stable render bindings", [] {
        SoftRig rig;
        const Config &c = rig.config();
        require(c.tire_radius == 0.46f && c.engine_torque == 450 && c.mass == 1200 && c.damping == 3000,
                "native defaults diverged from Android garage defaults");
        require(rig.node_count() == 100 && rig.beam_count() == 392, "unexpected renderer topology");
        require(rig.physical_node_count() == 24 && rig.physical_beam_count() == 92,
                "render wheel samples incorrectly counted as dynamic assemblies");
        require(rig.wheel_hubs == std::array<int, 4>{16, 37, 58, 79}, "hub indices changed");
        float mass = 0;
        for (const auto &p : rig.particles) mass += 1 / p.inv_mass;
        require(std::abs(mass - c.mass) < 0.02f, "node masses do not sum to configured vehicle mass");
        require(structural_error(rig) < 1e-5f, "initial frame contains pre-strained beams");
        require(rig.forward().dot({0, 0, -1}) > 0.999f && rig.up().y > 0.999f, "vehicle coordinate convention");
        healthy(rig);
    });

    test("gravity settles onto all four physical tires", [] {
        SoftRig rig; const float initial = rig.center().y;
        simulate(rig, 7, 0, 0, true);
        require(initial - rig.center().y > 0.4f, "vehicle did not fall");
        require(rig.center().y > 0.70f && rig.center().y < 1.0f, "incorrect loaded ride height");
        require(rig.speed() < 0.07f, "stationary suspension did not settle");
        require(rig.contact_count() >= 4, "vehicle has no tire support");
        for (int w = 0; w < 4; ++w) require(rig.wheel_contact_count(w) > 0, "a wheel never reached ground");
        require(rig.up().y > 0.999f && rig.damage() == 0, "normal landing deformed/tipped the vehicle");
        healthy(rig);
    });

    test("undriven flat-ground settling preserves left-right symmetry", [] {
        SoftRig rig; simulate(rig, 9, 0, 0, true);
        std::cout<<"  settle x="<<rig.center().x<<" speed="<<rig.speed()<<"\n";
        require(std::abs(rig.center().x) < 0.01f, "solver developed lateral drift");
        for (int axle = 0; axle < 2; ++axle) {
            auto l = rig.particles[rig.wheel_hubs[2 * axle]].pos;
            auto r = rig.particles[rig.wheel_hubs[2 * axle + 1]].pos;
            require(std::abs(l.y - r.y) < 0.005f && std::abs(l.z - r.z) < 0.008f,
                    "left and right suspension settle asymmetrically");
        }
        healthy(rig);
    });

    test("elastic chassis displacement recovers without permanent damage", [] {
        SoftRig rig; rig.reset({0, 50, 8});
        rig.displace_node(12, {0.06f, 0, 0});
        float before = structural_error(rig);
        require(before > 0.10f, "disturbance did not deform the actual beam network");
        simulate(rig, 0.5f);
        require(structural_error(rig) < before * 0.03f, "elastic deformation did not recover");
        require(changed_rest_lengths(rig) == 0 && rig.damage() == 0, "elastic event permanently yielded beams");
        healthy(rig);
    });

    test("above-yield deformation permanently changes structural rest lengths", [] {
        SoftRig rig; rig.reset({0, 50, 8});
        rig.displace_node(12, {0.50f, 0, 0});
        simulate(rig, 0.5f);
        float permanent = changed_rest_lengths(rig);
        require(permanent > 0.03f && rig.damage() > 0.001f, "large strain did not yield");
        simulate(rig, 0.5f);
        require(changed_rest_lengths(rig) >= permanent * 0.999f, "plastic deformation spontaneously repaired");
        require(rig.broken_count() == 0, "moderate permanent deformation tore the entire cab");
        healthy(rig);
    });

    test("severe beam failure remains bounded without numerical intervention", [] {
        SoftRig rig; rig.reset({0, 8, 8}); rig.displace_node(12, {1.50f, 0, 0});
        simulate(rig, 8);
        require(rig.broken_count() > 0, "severe strain did not break beams");
        require(rig.damage() > 0 && rig.damage() <= 1, "invalid damage metric");
        healthy(rig);
    });

    test("garage crash impulse produces physical permanent damage", [] {
        SoftRig rig; simulate(rig, 5, 0, 0, true);
        rig.apply_impact({16000, 0, 4000}); simulate(rig, 2);
        require(rig.damage() > 0.01f && changed_rest_lengths(rig) > 0.1f, "crash tool is only cosmetic");
        require(rig.center().x > 1, "impact did not transmit real momentum");
        healthy(rig);
    });



    test("brakes reduce speed through contact and hold the stopped vehicle", [] {
        SoftRig rig; simulate(rig, 4, 0, 0, true); simulate(rig, 6, 1);
        float before = rig.speed(); float z = rig.center().z;
        simulate(rig, 2, 0, 0, true);
        require(rig.speed() < before * 0.03f, "wheel braking did not stop chassis");
        require(std::abs(rig.center().z - z) < before * before / (2 * 7.5f) + 0.8f, "braking deceleration below 0.76 g on dry level ground");
        Vec3 stopped = rig.center(); simulate(rig, 3, 0, 0, true);
        // The coarse deformable tire rings settle a few centimeters as the
        // carcass unloads; reject continued rolling, not this elastic relaxation.
        require((rig.center() - stopped).length() < 0.10f && rig.speed() < 0.01f,
                "braked tires continue rolling after suspension/carcase relaxation");
        healthy(rig);
    });

    test("reverse torque moves backward without a scripted velocity", [] {
        SoftRig rig; simulate(rig, 4, 0, 0, true); float start_z = rig.center().z;
        simulate(rig, 4, -0.7f);
        require(rig.center().z > start_z + 5, "reverse torque has incorrect sign");
        require(rig.wheel_angular_velocity(0) > 1, "reverse does not rotate tires backward");
        healthy(rig);
    });





    test("engine torque alone cannot accelerate airborne center of mass", [] {
        SoftRig rig; rig.reset({0, 50, 8}); simulate(rig, 1.5f, 1, 0.3f);
        Vec3 v = mass_velocity(rig);
        require(std::abs(v.x) < 0.015f && std::abs(v.z) < 0.015f,
                "internal motor/constraints injected horizontal center-of-mass momentum");
        require(v.y < -12, "airborne gravity is absent");
        require(rig.contact_count() == 0, "airborne test accidentally used contact");
        healthy(rig);
    });

    test("lower tire pressure increases loaded round-tire compliance", [] {
        SoftRig soft, hard; Config a, b; a.tire_pressure = 0.5f; b.tire_pressure = 2.0f;
        soft.configure(a); hard.configure(b);
        simulate(soft, 7, 0, 0, true); simulate(hard, 7, 0, 0, true);
        require(mean_hub_y(hard) - mean_hub_y(soft) > 0.008f, "pressure slider did not change tire deformation");
        require(soft.damage() == 0 && hard.damage() == 0, "tire pressure incorrectly damaged chassis");
        healthy(soft); healthy(hard);
    });

    test("spring rate controls loaded suspension compression", [] {
        SoftRig soft, firm; Config a, b; a.spring_rate = 15000; b.spring_rate = 65000;
        soft.configure(a); firm.configure(b);
        // Isolate spring sag from brake-induced four-link jacking.
        soft.set_neutral(true); firm.set_neutral(true);
        simulate(soft, 6, 0, 0, false); simulate(firm, 6, 0, 0, false);
        require(soft.suspension_travel(0) > firm.suspension_travel(0) + 0.08f,
                "spring stiffness did not alter physical compression");
        require(firm.center().y - soft.center().y > 0.08f, "spring load response does not move vehicle body");
        healthy(soft); healthy(firm);
    });

    test("physical damper coefficient materially reduces landing oscillation", [] {
        SoftRig soft, firm; Config a, b; a.damping = 1000; b.damping = 7000;
        soft.configure(a); firm.configure(b);
        float low_motion = 0, high_motion = 0;
        for (int i = 0; i < 360; ++i) {
            soft.step(1.0f / 120, 0, 0, true); firm.step(1.0f / 120, 0, 0, true);
            if (i > 60) { low_motion += std::abs(soft.linear_velocity().y); high_motion += std::abs(firm.linear_velocity().y); }
        }
        require(high_motion < low_motion * 0.45f, "damping slider is ineffective or saturated");
        healthy(soft); healthy(firm);
    });





    test("10-120 Hz and irregular frame delivery preserve real-time trajectories", [] {
        SoftRig reference; simulate(reference, 8, 0.65f, 0.20f);
        for (int fps : {10, 15, 30, 60, 120}) {
            SoftRig rig;
            for (int i = 0; i < 8 * fps; ++i) rig.step(1.0f / fps, 0.65f, 0.20f, false);
            for (int i = 0; i < rig.node_count(); ++i)
                require((rig.particles[i].pos - reference.particles[i].pos).length() < 1e-4f,
                        "ordinary low frame cadence changes speed or driving trajectory");
            healthy(rig);
        }
        SoftRig irregular;
        const int ticks[] = {3, 11, 6, 17, 4, 20}; int elapsed = 0, frame = 0;
        while (elapsed < 8 * 240) {
            int count = std::min(ticks[frame++ % 6], 8 * 240 - elapsed);
            irregular.step(count / 240.0f, 0.65f, 0.20f, false); elapsed += count;
        }
        for (int i = 0; i < irregular.node_count(); ++i)
            require((irregular.particles[i].pos - reference.particles[i].pos).length() < 1e-4f,
                    "irregular 12-80 Hz frames introduce slow motion or nondeterminism");
        healthy(irregular); healthy(reference);
    });

    test("terrain sampling provides flat spawn and continuous drivable obstacles", [] {
        SoftRig rig; rig.set_terrain(1);
        require(std::abs(rig.terrain_height(0, 8)) < 1e-6f, "spawn is not flat");
        require(rig.terrain_normal(0, 8).y > 0.999f, "spawn normal tilted");
        float variation = 0;
        for (float z = -50; z < 0; z += 0.25f) for (float x = -3; x <= 3; x += 0.5f) {
            Vec3 n = rig.terrain_normal(x, z);
            require(n.finite() && std::abs(n.length() - 1) < 1e-4f && n.y > 0.55f, "invalid/undrivable heightfield normal");
            variation = std::max(variation, std::abs(rig.terrain_height(x, z)));
        }
        require(variation > 0.8f, "trail has no elevation features");
        rig.configure(Config{});
        require(std::abs(rig.terrain_height(0, -10)) > 0.1f, "configure lost selected terrain");
    });

    test("default truck crosses ruts articulation rocks and ledge without numerical repair", [] {
        SoftRig rig; rig.set_terrain(1); simulate(rig, 4, 0, 0, true);
        float max_articulation = 0;
        for (int i = 0; i < 22 * 120; ++i) {
            rig.step(1.0f / 120, 0.65f, 0, false);
            max_articulation = std::max(max_articulation,
                std::abs(rig.suspension_travel(0) - rig.suspension_travel(1)));
            require(rig.up().y > 0.55f, "default truck rolled instead of completing the ledge jump");
        }
        require(rig.center().z < -100 && rig.up().y > 0.85f, "truck failed to traverse and land upright after trail features");
        require(max_articulation > 0.02f, "terrain did not articulate independent wheels");
        require(rig.damage() == 0, "routine off-road trail caused false structural damage");
        healthy(rig);
    });

    test("one-minute parked stability retains support and stays undamaged", [] {
        SoftRig rig; simulate(rig, 60, 0, 0, true);
        require(rig.speed() < 0.08f && rig.up().y > 0.999f, "long parked simulation drifts/oscillates");
        require(rig.contact_count() >= 4 && rig.damage() == 0, "parked vehicle lost integrity/support");
        healthy(rig);
    });

    const std::array<std::pair<float Config::*, std::pair<float, float>>, 10> ranges{{
        {&Config::tire_radius, {0.32f, 0.65f}}, {&Config::tire_pressure, {0.5f, 2.0f}},
        {&Config::spring_rate, {15000, 65000}}, {&Config::damping, {1000, 7000}},
        {&Config::ride_height, {0.15f, 0.65f}}, {&Config::engine_torque, {150, 900}},
        {&Config::mass, {900, 2000}}, {&Config::track_width, {1.6f, 2.3f}},
        {&Config::wheelbase, {2.3f, 3.3f}}, {&Config::body_stiffness, {0.5f, 2.0f}}
    }};
    for (std::size_t i = 0; i < ranges.size(); ++i) for (int extreme = 0; extreme < 2; ++extreme) {
        test("garage range " + std::to_string(i) + (extreme ? " maximum" : " minimum"), [&, i, extreme] {
            SoftRig rig; Config c;
            auto member = ranges[i].first; float value = extreme ? ranges[i].second.second : ranges[i].second.first;
            c.*member = value; rig.configure(c);
            require(rig.config().*member == value, "advertised slider endpoint was silently clamped");
            simulate(rig, 4, 0, 0, true); simulate(rig, 4, 0.7f, 0.25f); simulate(rig, 2, 0, 0, true);
            require(rig.up().y > 0.75f && rig.damage() == 0, "a single legal garage extreme destabilized ordinary driving");
            healthy(rig);
        });
    }

    for (int mode = 0; mode < 4; ++mode) {
        test("combined garage extreme " + std::to_string(mode), [&, mode] {
            Config c;
            for (std::size_t i = 0; i < ranges.size(); ++i) {
                bool use_high = mode == 1 || (mode == 2 && i % 2 == 0) || (mode == 3 && i % 2 != 0);
                c.*ranges[i].first = use_high ? ranges[i].second.second : ranges[i].second.first;
            }
            SoftRig rig; rig.configure(c);
            simulate(rig, 5, 0, 0, true); simulate(rig, 5, 0.65f, 0.10f); simulate(rig, 2, 0, 0, true);
            require(rig.up().y > 0.6f, "combined allowed setup rolled during gentle flat test");
            require(rig.center().y > 0.2f && rig.center().y < 2.0f, "combined setup lost its chassis support");
            healthy(rig);
        });
    }

    test("repair explicitly rebuilds original undamaged state", [] {
        SoftRig rig; rig.displace_node(12, {1.5f, 0, 0}); simulate(rig, 1);
        require(rig.damage() > 0, "repair precondition missing"); rig.reset();
        require(rig.damage() == 0 && rig.broken_count() == 0 && changed_rest_lengths(rig) == 0,
                "explicit repair retained broken/yielded beams");
        require(structural_error(rig) < 1e-5f, "repair failed to rebuild undeformed geometry");
        healthy(rig);
    });

    test("invalid input and frame stalls are bounded and observable", [] {
        SoftRig rig; Config c;
        c.tire_radius = std::numeric_limits<float>::quiet_NaN(); c.mass = -1;
        rig.configure(c);
        require(std::isfinite(rig.config().tire_radius) && rig.config().mass == 900, "malformed setup not bounded");
        Vec3 before = rig.center(); rig.step(-1, 1, 0, false);
        rig.step(std::numeric_limits<float>::quiet_NaN(), 1, 0, false);
        require((rig.center() - before).length() == 0, "invalid elapsed time changed simulation");
        rig.step(2.0f, 0, 0, true);
        require(rig.time_dropped() > 1.89f, "stall protection failed to report discarded wall-clock time");
        require(rig.rejected_state_count() == 0 && rig.safety_clamp_count() == 0, "ordinary stall caused numerical repair");
        rig.particles[12].velocity = {1000, 0, 0}; rig.step(SoftRig::fixed_dt, 0, 0, false);
        require(rig.safety_clamp_count() > 0, "extreme velocity safeguard is not observable");
    });

    test("three vehicle structures have distinct load-bearing geometry and bracing", [] {
        SoftRig pickup, suv, buggy; Config c;
        c.vehicle_type = 1; suv.configure(c); c.vehicle_type = 2; buggy.configure(c);
        require(pickup.beam_count() == 392 && suv.beam_count() == 400 && buggy.beam_count() == 404,
                "vehicle selection did not change physical structure");
        require(suv.rest_positions[14].z - suv.rest_positions[12].z >
                (pickup.rest_positions[14].z - pickup.rest_positions[12].z) * 1.8f,
                "SUV roof is not physically longer than pickup cab");
        require(buggy.rest_positions[12].y < pickup.rest_positions[12].y - 0.2f,
                "buggy cage does not have its own low geometry");
        require(center_of_mass(suv).y > center_of_mass(pickup).y + 0.07f,
                "SUV upper-body mass did not raise center of mass");
        require(center_of_mass(buggy).z > center_of_mass(pickup).z + 0.06f,
                "rear-engine buggy mass did not shift toward rear axle");
        for (SoftRig *rig : {&pickup, &suv, &buggy}) {
            require(rig->node_count() == 100 && rig->rest_positions.size() == 104,
                    "vehicle shape broke skin binding topology");
            require(std::abs(total_mass(*rig) - 1200) < 0.03f, "vehicle mass was not conserved");
            require(structural_error(*rig) < 1e-5f, "vehicle variant was born prestrained");
            healthy(*rig);
        }
    });

    test("front and roof parts add their exact mass at physical attachments", [] {
        SoftRig base, equipped; Config c;
        c.mass = 1380; c.front_accessory_mass = 80; c.roof_accessory_mass = 100;
        equipped.configure(c);
        require(std::abs(total_mass(equipped) - 1380) < 0.03f, "accessory masses were double counted or omitted");
        for (int i = 0; i < equipped.node_count(); ++i) {
            const float expected = i < 8 && (i % 4) < 2 ? 20.0f : (i >= 12 && i < 16 ? 25.0f : 0);
            require(std::abs(1 / equipped.particles[i].inv_mass - 1 / base.particles[i].inv_mass - expected) < 0.002f,
                    "part weight changed unrelated nodes or missed attachment corners");
        }
        require(center_of_mass(equipped).y > center_of_mass(base).y + 0.055f,
                "roof cargo did not raise center of mass");
        require(center_of_mass(equipped).z < center_of_mass(base).z - 0.065f,
                "front armor did not shift axle loading forward");
        simulate(equipped, 4, 0, 0, true); simulate(equipped, 5, 0.7f, 0.25f);
        require(equipped.damage() == 0 && equipped.up().y > 0.95f, "legal accessory loads destabilized ordinary driving");
        healthy(equipped);
    });

    test("wide tire parts change the actual two-sidewall contact geometry", [] {
        SoftRig narrow, wide; Config c;
        c.tire_width_scale = 0.75f; narrow.configure(c);
        c.tire_width_scale = 1.4f; wide.configure(c);
        const int hub = narrow.wheel_hubs[0];
        const float narrow_width = std::abs(narrow.rest_positions[hub + 1].x - narrow.rest_positions[hub + 11].x);
        const float wide_width = std::abs(wide.rest_positions[hub + 1].x - wide.rest_positions[hub + 11].x);
        require(std::abs(wide_width / narrow_width - 1.4f / 0.75f) < 1e-4f,
                "tire width is only a visual scale");
        require(std::abs(total_mass(narrow) - total_mass(wide)) < 0.03f,
                "tire width silently changed configured total mass");
        simulate(wide, 5, 0, 0, true); simulate(wide, 5, 0.75f, 0.3f);
        require(wide.damage() == 0 && wide.up().y > 0.97f, "wide tire geometry destabilized steering");
        healthy(wide);
    });

    test("tire compound changes measured sliding distance through contact friction", [] {
        SoftRig low_grip, high_grip; Config c;
        c.tire_grip = 0.7f; low_grip.configure(c); c.tire_grip = 1.4f; high_grip.configure(c);
        float distances[2]{}; int index = 0;
        for (SoftRig *rig : {&low_grip, &high_grip}) {
            simulate(*rig, 4, 0, 0, true);
            for (auto &p : rig->particles) p.velocity = {4, 0, 0};
            const Vec3 start = rig->center(); simulate(*rig, 1, 0, 0, true);
            distances[index++] = (rig->center() - start).length(); healthy(*rig);
        }
        require(distances[0] > 0.6f && distances[1] < distances[0] * 0.60f,
                "compound selection did not affect physical traction");
    });



    test("long-travel kit changes physical droop stops", [] {
        float lowest[2]{};
        for (int i = 0; i < 2; ++i) {
            SoftRig rig; Config c;
            c.suspension_travel = i ? 0.4f : 0.12f; c.spring_rate = 15000; c.damping = 1000;
            rig.configure(c); rig.reset({0, 50, 8});
            for (int hub : rig.wheel_hubs) for (int j = 0; j < SoftRig::nodes_per_wheel; ++j)
                rig.particles[hub + j].velocity.y = -8;
            for (int step = 0; step < 120; ++step) {
                rig.step(1.0f / 120, 0, 0, false);
                lowest[i] = std::min(lowest[i], rig.suspension_travel(0));
            }
            healthy(rig);
        }
        require(lowest[0] > -0.18f && lowest[0] < -.08f && lowest[1] < lowest[0] - 0.10f,
                "travel kit did not change suspension droop under load");
    });

    test("rest skin positions persist through driving and rebind on recovery", [] {
        SoftRig rig; const auto original = rig.rest_positions;
        simulate(rig, 4, 0.7f, 0.3f);
        for (std::size_t i = 0; i < original.size(); ++i)
            require((rig.rest_positions[i] - original[i]).length() == 0, "driving mutated skin bind pose");
        rig.reset({20, 7, -35});
        for (std::size_t i = 0; i < original.size(); ++i)
            require((rig.rest_positions[i] - rig.particles[i].pos).length() == 0, "recovery retained obsolete bind origin");
        require((rig.rest_positions[0] - original[0]).length() > 40, "recovery did not rebind skin positions");
    });

    test("exploration map has matched stable normals surfaces and flat spawn", [] {
        SoftRig rig; rig.set_terrain(2);
        require(std::abs(rig.terrain_height(0, 8)) < 1e-6f && rig.terrain_normal(0, 8).y > 0.999f,
                "exploration spawn is not flat");
        float maximum = 0;
        for (int z = -380; z <= 380; z += 20) for (int x = -380; x <= 380; x += 20) {
            const float h = rig.terrain_height(float(x), float(z));
            const Vec3 n = rig.terrain_normal(float(x), float(z));
            const float surface = rig.terrain_surface(float(x), float(z));
            require(std::isfinite(h) && n.finite() && std::abs(n.length() - 1) < 1e-4f && n.y > 0,
                    "exploration heightfield has invalid sample");
            require(surface >= 0.5f && surface <= 1.01f, "terrain surface returned impossible friction multiplier");
            maximum = std::max(maximum, h);
        }
        require(maximum > 60 && boltyard::exploration_obstacles().size() >= 40,
                "exploration world has no meaningful terrain/solid props");
        require(rig.terrain_surface(96, 81) < rig.terrain_surface(0, 8) * 0.7f,
                "lake bed and road have identical traction");
        rig.configure(Config{});
        require(rig.terrain_height(-95, 180) > 30, "garage configure lost exploration terrain mode");
    });

    for (int type = 0; type < 3; ++type) {
        test("vehicle " + std::to_string(type) + " equipped exploration drive remains stable", [type] {
            SoftRig rig; Config c; c.vehicle_type = type;
            c.mass = (type == 0 ? 1200 : (type == 1 ? 1080 : 950)) + 95;
            c.wheelbase = type == 0 ? 2.7f : (type == 1 ? 2.4f : 2.6f);
            c.tire_width_scale = 1.2f; c.tire_grip = 1.2f; c.tire_radius = 0.50f;
            c.front_accessory_mass = 65; c.roof_accessory_mass = 30;
            c.suspension_travel = 0.30f; c.final_drive = 1.25f;
            rig.configure(c); rig.set_terrain(2);
            simulate(rig, 4, 0, 0, true); const Vec3 start = rig.center();
            simulate(rig, 10, 0.75f, 0); simulate(rig, 2, 0, 0, true);
            require(rig.center().z < start.z - 25, "equipped vehicle failed to progress on exploration road");
            require(rig.up().y > 0.97f && rig.damage() == 0, "equipped vehicle destabilized on easy road");
            require(rig.speed() < 0.2f, "equipped vehicle failed to brake");
            healthy(rig);
        });
    }

    test("structural beam contacts stop a narrow post between body nodes", [] {
        SoftRig obstacle, clear;
        obstacle.set_terrain(2); clear.set_terrain(0);
        for (SoftRig *rig : {&obstacle, &clear}) {
            // Wayfinding post at(-7,8), centered between left/right body nodes.
            rig->reset({-7, 1.5f, 14.35f}); simulate(*rig, 4, 0, 0, true); simulate(*rig, 8, .3f); simulate(*rig, 1, 0, 0, true);
            healthy(*rig);
        }
        std::cout<<"  post obstacle z="<<obstacle.center().z<<" speed="<<obstacle.speed()<<" clear z="<<clear.center().z<<" contacts="<<obstacle.contact_count()<<"\n";
        require(obstacle.center().z > 9.3f && obstacle.speed() < 0.1f,
                "narrow solid obstacle passed through frame between mass nodes");
        require(clear.center().z < obstacle.center().z - 12,
                "obstacle response cannot be distinguished from unimpeded driving");
        require(obstacle.contact_count() >= 5, "solid obstacle did not participate in constraints");
    });

    const std::array<std::pair<float Config::*, std::pair<float, float>>, 7> part_ranges{{
        {&Config::tire_grip, {0.7f, 1.4f}}, {&Config::tire_width_scale, {0.75f, 1.4f}},
        {&Config::suspension_travel, {0.12f, 0.4f}}, {&Config::final_drive, {0.8f, 1.5f}},
        {&Config::front_accessory_mass, {0, 100}}, {&Config::roof_accessory_mass, {0, 100}},
        {&Config::tire_pressure, {0.5f, 2.0f}}
    }};
    for (std::size_t i = 0; i < part_ranges.size(); ++i) for (int endpoint = 0; endpoint < 2; ++endpoint) {
        test("part range " + std::to_string(i) + (endpoint ? " maximum" : " minimum"), [&, i, endpoint] {
            SoftRig rig; Config c;
            auto field = part_ranges[i].first;
            c.*field = endpoint ? part_ranges[i].second.second : part_ranges[i].second.first;
            rig.configure(c);
            require(rig.config().*field == c.*field, "legal part endpoint silently clamped");
            simulate(rig, 3, 0, 0, true); simulate(rig, 4, 0.7f, 0.2f);
            require(rig.up().y > 0.95f && rig.damage() == 0, "legal part destabilized ordinary operation");
            healthy(rig);
        });
    }





    test("airborne travel and landing retain momentum and recover suspension support", [] {
        SoftRig rig; rig.reset({0, 3, 8});rig.set_neutral(true);
        for (auto &p : rig.particles) p.velocity = {0, 0, -8};
        int airborne = 0; float minimum_up = 1;
        for (int i = 0; i < 4 * 120; ++i) {
            rig.step(1.0f / 120, 0, 0, i > 120);
            if (rig.contact_count() == 0) ++airborne;
            minimum_up = std::min<float>(minimum_up, rig.up().y);
        }
        require(airborne > 50 && rig.center().z < -2, "jump lost airborne travel or horizontal momentum");
        require(minimum_up > 0.95f && rig.speed() < 0.05f && rig.damage() == 0,
                "ordinary landing failed to settle upright and undamaged");
        for (int w = 0; w < 4; ++w) require(rig.wheel_contact_count(w) > 0, "landing lost a suspension support");
        healthy(rig);
    });

    test("all vehicles hold a 27-percent exploration grade and restart uphill", [] {
        const Vec3 direction = Vec3(65, 0, 93).normalized();
        for (int type = 0; type < 3; ++type) {
            SoftRig rig; Config config; config.vehicle_type = type; rig.configure(config); rig.set_terrain(2);
            const Vec3 origin(-124.5f, rig.terrain_height(-124.5f, 129.5f) + 1.5f, 129.5f);
            rig.reset(origin);
            const float co = -direction.z, si = direction.x;
            for (auto &p : rig.particles) {
                const Vec3 v = p.pos - origin;
                p.pos = origin + Vec3(co * v.x - si * v.z, v.y, si * v.x + co * v.z); p.prev = p.pos;
            }
            for (auto &p : rig.rest_positions) {
                const Vec3 v = p - origin;
                p = origin + Vec3(co * v.x - si * v.z, v.y, si * v.x + co * v.z);
            }
            simulate(rig, 5, 0, 0, true); const Vec3 parked = rig.center();
            const Vec3 normal = rig.terrain_normal(parked.x, parked.z);
            require(-normal.dot(direction) / normal.y > 0.25f, "grade fixture no longer tests a steep hill");
            simulate(rig, 10, 0, 0, true);
            require((rig.center() - parked).length() < 0.02f, "braked tires creep down a supported hill");
            const Vec3 start = rig.center(); simulate(rig, 5, 1);
            require((rig.center() - start).dot(direction) > 15 && rig.center().y - start.y > 4,
                    "vehicle cannot restart and make useful uphill progress");
            simulate(rig, 4, 0, 0, true);
            require(rig.speed() < 0.05f && rig.up().y > 0.90f && rig.damage() == 0,
                    "hill restart or braking damaged, rolled or failed to stop vehicle");
            healthy(rig);
        }
    });

    double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    std::cout << "\n" << passed << " passed, " << failed << " failed; native test runtime "
              << std::fixed << std::setprecision(3) << elapsed << " s\n";
    return failed ? 1 : 0;
}
