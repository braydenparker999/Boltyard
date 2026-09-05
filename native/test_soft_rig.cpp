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
    for (const auto &n : rig.particles) { float m = 1 / n.inv_mass; p += n.velocity * m; total_mass += m; }
    return p / total_mass;
}
float mean_hub_y(const SoftRig &rig) {
    float result = 0;
    for (int hub : rig.wheel_hubs) result += rig.particles[hub].pos.y * 0.25f;
    return result;
}
float angular_variance(const SoftRig &rig) {
    float mean = 0, result = 0;
    for (int w = 0; w < 4; ++w) mean += rig.wheel_angular_velocity(w) / 4;
    for (int w = 0; w < 4; ++w) { float e = rig.wheel_angular_velocity(w) - mean; result += e * e; }
    return result;
}

} // namespace

int main() {
    const auto started = std::chrono::steady_clock::now();
    int passed = 0, failed = 0;
    auto test = [&](const std::string &name, const std::function<void()> &fn) {
        try { fn(); ++passed; std::cout << "PASS  " << name << '\n'; }
        catch (const std::exception &e) { ++failed; std::cerr << "FAIL  " << name << ": " << e.what() << '\n'; }
    };

    test("shipped configuration and load-bearing node topology", [] {
        SoftRig rig;
        const Config &c = rig.config();
        require(c.tire_radius == 0.46f && c.engine_torque == 450 && c.mass == 1200 && c.damping == 3000,
                "native defaults diverged from Android garage defaults");
        require(rig.node_count() == 100 && rig.beam_count() == 392, "unexpected renderer topology");
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

    test("tire torque propels the actual node network forward", [] {
        SoftRig rig; simulate(rig, 4, 0, 0, true); float start_z = rig.center().z;
        simulate(rig, 6, 1);
        require(rig.center().z < start_z - 12, "powered tire contact failed to move the vehicle");
        require(rig.speed() > 4 && rig.speed() < 8, "unexpected low-range cruise response");
        require(std::abs(rig.center().x) < 0.10f, "straight drive drifts excessively");
        require(rig.wheel_angular_velocity(0) < -5, "powered wheels are not physically rotating");
        require(rig.damage() == 0 && rig.up().y > 0.995f, "ordinary acceleration destabilized chassis");
        healthy(rig);
    });

    test("brakes reduce speed through contact and hold the stopped vehicle", [] {
        SoftRig rig; simulate(rig, 4, 0, 0, true); simulate(rig, 6, 1);
        float before = rig.speed(); float z = rig.center().z;
        simulate(rig, 2, 0, 0, true);
        require(rig.speed() < before * 0.03f, "wheel braking did not stop chassis");
        require(std::abs(rig.center().z - z) < 4, "braking distance too long");
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

    test("steering redirects tire contacts and turns the chassis", [] {
        SoftRig rig; simulate(rig, 4, 0, 0, true); simulate(rig, 6, 0.7f, 0.7f);
        require(rig.center().x > 5 && rig.forward().x > 0.65f, "right steering failed to turn right");
        require(rig.up().y > 0.97f && rig.damage() == 0, "moderate steering caused invalid rollover/damage");
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

    test("lower tire pressure physically compresses the carcass under load", [] {
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
        simulate(soft, 6, 0, 0, true); simulate(firm, 6, 0, 0, true);
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

    test("live low-range toggle changes tractive response without rebuilding", [] {
        SoftRig high, low; high.set_drivetrain(false, true); low.set_drivetrain(true, true);
        simulate(high, 4, 0, 0, true); simulate(low, 4, 0, 0, true);
        simulate(high, 2, 1); simulate(low, 2, 1);
        require(low.speed() > high.speed() * 1.5f, "low range did not multiply torque");
        Vec3 before = low.center(); low.set_drivetrain(false, false);
        require((low.center() - before).length() < 1e-6f, "drivetrain toggle reset the simulation");
        healthy(high); healthy(low);
    });

    test("differential lockers equalize physically spinning wheel assemblies", [] {
        SoftRig open, locked; open.set_drivetrain(true, false); locked.set_drivetrain(true, true);
        open.reset({0, 50, 0}); locked.reset({0, 50, 0});
        for (SoftRig *rig : {&open, &locked}) {
            int hub = rig->wheel_hubs[0];
            for (int j = 1; j < SoftRig::nodes_per_wheel; ++j)
                rig->particles[hub + j].velocity = Vec3(1, 0, 0).cross(
                    rig->particles[hub + j].pos - rig->particles[hub].pos) * 10;
            simulate(*rig, 0.5f);
        }
        require(angular_variance(open) > 10, "unlocked test lost its initial wheel-speed difference");
        require(angular_variance(locked) < angular_variance(open) * 0.02f,
                "locked driveline does not transfer angular momentum among tires");
        healthy(open); healthy(locked);
    });

    test("fixed integration is independent of 30/60/120 Hz frame delivery", [] {
        SoftRig a, b, c;
        for (int i = 0; i < 240; ++i) a.step(1.0f / 30, 0.65f, 0.20f, false);
        for (int i = 0; i < 480; ++i) b.step(1.0f / 60, 0.65f, 0.20f, false);
        for (int i = 0; i < 960; ++i) c.step(1.0f / 120, 0.65f, 0.20f, false);
        for (int i = 0; i < a.node_count(); ++i) {
            require((a.particles[i].pos - b.particles[i].pos).length() < 1e-4f, "30 and 60 Hz trajectories diverged");
            require((a.particles[i].pos - c.particles[i].pos).length() < 1e-4f, "30 and 120 Hz trajectories diverged");
        }
        healthy(a); healthy(b); healthy(c);
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
            require(rig.up().y > 0.80f, "default truck rolled on intended easy trail");
        }
        require(rig.center().z < -50, "truck failed to traverse trail features");
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

    double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    std::cout << "\n" << passed << " passed, " << failed << " failed; native test runtime "
              << std::fixed << std::setprecision(3) << elapsed << " s\n";
    return failed ? 1 : 0;
}
