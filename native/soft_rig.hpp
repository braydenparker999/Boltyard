#pragma once

// Bolt Yard's CPU node-and-beam vehicle. SI units throughout.
// This is a deliberately bounded mobile prototype, not a BeamNG reimplementation.
// The chassis, cab and both sidewalls of each tire are simulated mass nodes.
// XPBD distance constraints transmit forces; structural beams can yield and break.
// Wheel-plane guides and prismatic suspension approximate knuckles/control arms.
// There is no rigid-body stand-in, canned driving force or cosmetic crash pose.
// Limitations: one vehicle, heightfield contact, no self-contact, heat, fluid mud,
// carcass hysteresis, clutch/gearbox transients, or full suspension link geometry.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>

namespace boltyard {

struct Vec3 {
    float x = 0, y = 0, z = 0;
    constexpr Vec3() = default;
    constexpr Vec3(float px, float py, float pz) : x(px), y(py), z(pz) {}
    Vec3 operator+(Vec3 v) const { return {x + v.x, y + v.y, z + v.z}; }
    Vec3 operator-(Vec3 v) const { return {x - v.x, y - v.y, z - v.z}; }
    Vec3 operator-() const { return {-x, -y, -z}; }
    Vec3 operator*(float s) const { return {x * s, y * s, z * s}; }
    Vec3 operator/(float s) const { return *this * (1.0f / s); }
    Vec3 &operator+=(Vec3 v) { x += v.x; y += v.y; z += v.z; return *this; }
    Vec3 &operator-=(Vec3 v) { x -= v.x; y -= v.y; z -= v.z; return *this; }
    Vec3 &operator*=(float s) { x *= s; y *= s; z *= s; return *this; }
    float dot(Vec3 v) const { return x * v.x + y * v.y + z * v.z; }
    Vec3 cross(Vec3 v) const { return {y * v.z - z * v.y, z * v.x - x * v.z, x * v.y - y * v.x}; }
    float length_squared() const { return dot(*this); }
    float length() const { return std::sqrt(length_squared()); }
    Vec3 normalized() const { float l = length(); return l > 1e-8f ? *this / l : Vec3{}; }
    bool finite() const { return std::isfinite(x) && std::isfinite(y) && std::isfinite(z); }
};
inline Vec3 operator*(float s, Vec3 v) { return v * s; }
inline float dot(Vec3 a, Vec3 b) { return a.dot(b); }
inline Vec3 cross(Vec3 a, Vec3 b) { return a.cross(b); }
inline float length(Vec3 v) { return v.length(); }
inline Vec3 normalized(Vec3 v) { return v.normalized(); }

struct Config {
    float tire_radius = 0.46f;       // m, overall unloaded radius
    float tire_pressure = 1.0f;     // relative pressure, 1 = trail baseline (uncalibrated)
    float spring_rate = 30000.0f;   // N/m per corner
    float damping = 3000.0f;        // N s/m damping coefficient per corner
    float ride_height = 0.35f;      // m from frame underside to unloaded hub
    float engine_torque = 450.0f;  // N m total torque before low-range ratio
    bool low_range = true;
    bool locked_diffs = true;
    float mass = 1200.0f;           // kg, entire vehicle including wheels
    float track_width = 1.90f;      // m between hub centers
    float wheelbase = 2.70f;        // m
    float body_stiffness = 1.0f;    // dimensionless structural stiffness scale
};

enum BeamKind { CHASSIS = 0, CAB = 1, SUSPENSION = 2, TIRE = 3 };
struct Particle {
    Vec3 pos, prev, velocity;
    float inv_mass = 1;
    float radius = 0.07f;
    int wheel = -1;
    bool tire = false;
};
struct Beam {
    int a = 0, b = 0;
    float rest = 0, original_rest = 0;
    bool broken = false;
    int kind = CHASSIS;
    float compliance = 0;
    float lambda = 0;
    float peak_delta = 0;
    float plastic_strain = 0;
};

class SoftRig {
public:
    static constexpr int tire_segments = 10;
    static constexpr int nodes_per_wheel = 1 + 2 * tire_segments;
    static constexpr float fixed_dt = 1.0f / 240.0f;
    std::vector<Particle> particles;
    std::vector<Beam> beams;
    std::array<int, 4> wheel_hubs{{16, 37, 58, 79}};

    SoftRig() { configure(Config{}); }

    void configure(const Config &input) {
        cfg_ = input;
        cfg_.tire_radius = safe_clamp(input.tire_radius, 0.32f, 0.65f, 0.46f);
        cfg_.tire_pressure = safe_clamp(input.tire_pressure, 0.5f, 2.0f, 1.0f);
        cfg_.spring_rate = safe_clamp(input.spring_rate, 15000, 65000, 30000);
        cfg_.damping = safe_clamp(input.damping, 1000, 7000, 3000);
        cfg_.ride_height = safe_clamp(input.ride_height, 0.15f, 0.65f, 0.35f);
        cfg_.engine_torque = safe_clamp(input.engine_torque, 150, 900, 450);
        cfg_.mass = safe_clamp(input.mass, 900, 2000, 1200);
        cfg_.track_width = safe_clamp(input.track_width, 1.6f, 2.3f, 1.9f);
        cfg_.wheelbase = safe_clamp(input.wheelbase, 2.3f, 3.3f, 2.7f);
        cfg_.body_stiffness = safe_clamp(input.body_stiffness, 0.5f, 2.0f, 1.0f);
        reset();
    }
    const Config &config() const { return cfg_; }
    void set_drivetrain(bool low_range, bool locked_diffs) {
        cfg_.low_range = low_range;
        cfg_.locked_diffs = locked_diffs;
    }

    void reset(Vec3 origin = {0, 1.5f, 8}) {
        if (!origin.finite()) origin = {0, 1.5f, 8};
        particles.clear(); beams.clear();
        accumulator_ = 0; steering_ = 0; contact_count_ = 0;
        velocity_limit_count_ = 0; nonfinite_count_ = 0; dropped_time_ = 0;
        wheel_contact_counts_.fill(0);
        const float frame_x = cfg_.track_width * 0.38f;
        const float frame_z = cfg_.wheelbase * 0.50f;
        add_box(origin, frame_x, -frame_z, frame_z, 0, 0.30f, cfg_.mass * 0.60f);
        add_box(origin, cfg_.track_width * 0.32f, -cfg_.wheelbase * 0.30f,
                cfg_.wheelbase * 0.12f, 0.32f, 1.02f, cfg_.mass * 0.18f);
        brace_box(0, CHASSIS, 1.0f / (2800000.0f * cfg_.body_stiffness));
        brace_box(8, CAB, 1.0f / (950000.0f * cfg_.body_stiffness));
        // Cab-floor attachments are triangulated. They bend/yield with the cab.
        for (int i = 0; i < 4; ++i) {
            add_beam(i + 8, i, CAB, 1.0f / (1700000.0f * cfg_.body_stiffness));
            add_beam(i + 8, i + 4, CAB, 1.0f / (1700000.0f * cfg_.body_stiffness));
            add_beam(i + 8, (i ^ 1) + 4, CAB, 1.0f / (1700000.0f * cfg_.body_stiffness));
        }
        const float tire_node_mass = cfg_.mass * 0.22f / (4 * nodes_per_wheel);
        tire_width_ = cfg_.tire_radius * 0.58f;
        for (int w = 0; w < 4; ++w) {
            const float sx = w % 2 == 0 ? -1.0f : 1.0f;
            const float sz = w < 2 ? -1.0f : 1.0f;
            Vec3 hub = origin + Vec3(sx * cfg_.track_width * 0.5f,
                                    -cfg_.ride_height, sz * cfg_.wheelbase * 0.5f);
            wheel_hubs[w] = add_particle(hub, tire_node_mass, 0.075f, w, false);
            for (int side = 0; side < 2; ++side) {
                for (int j = 0; j < tire_segments; ++j) {
                    float theta = 6.283185307179586f * j / tire_segments;
                    Vec3 p = hub + Vec3((side == 0 ? -0.5f : 0.5f) * tire_width_,
                        cfg_.tire_radius * 0.88f * std::cos(theta),
                        cfg_.tire_radius * 0.88f * std::sin(theta));
                    add_particle(p, tire_node_mass, cfg_.tire_radius * 0.12f, w, true);
                }
            }
            const int first = wheel_hubs[w] + 1;
            const float pressure = cfg_.tire_pressure;
            for (int side = 0; side < 2; ++side) {
                for (int j = 0; j < tire_segments; ++j) {
                    int a = first + side * tire_segments + j;
                    add_beam(wheel_hubs[w], a, TIRE, 1.0f / (155000.0f * pressure));
                    add_beam(a, first + side * tire_segments + (j + 1) % tire_segments,
                             TIRE, 1.0f / (340000.0f * std::sqrt(pressure)));
                    add_beam(a, first + side * tire_segments + (j + 2) % tire_segments,
                             TIRE, 1.0f / (65000.0f * pressure));
                    if (side == 0) {
                        add_beam(a, a + tire_segments, TIRE, 1.0f / (220000.0f * pressure));
                        add_beam(a, first + tire_segments + (j + 1) % tire_segments,
                                 TIRE, 1.0f / (95000.0f * pressure));
                    }
                }
            }
            // These observable spring beams are solved along the suspension axis,
            // not as free distance links; this avoids hidden rigid-body suspension.
            add_beam(w, wheel_hubs[w], SUSPENSION, 1.0f / cfg_.spring_rate);
        }
        contact_lambdas_.assign(particles.size(), 0);
        friction_offsets_.assign(particles.size(), Vec3{});
        contact_normals_.assign(particles.size(), Vec3(0, 1, 0));
        wheel_plane_lambdas_.assign(particles.size(), 0);
    }

    void step(float dt, float throttle, float steer, bool brake) {
        if (!std::isfinite(dt) || dt <= 0) return;
        throttle = safe_clamp(throttle, -1, 1, 0);
        steer = safe_clamp(steer, -1, 1, 0);
        // Long frame stalls shed wall-clock time instead of expanding solver dt.
        dropped_time_ += std::max(0.0f, dt - 0.1f);
        accumulator_ += std::min(dt, 0.1f);
        int count = 0;
        while (accumulator_ + 1e-8f >= fixed_dt && count < 24) {
            substep(throttle, steer, brake);
            accumulator_ -= fixed_dt;
            ++count;
        }
        accumulator_ = std::max(0.0f, std::min(accumulator_, fixed_dt));
    }

    void set_terrain(int mode) { terrain_mode_ = mode == 0 ? 0 : 1; }
    float terrain_height(float x, float z) const {
        if (terrain_mode_ == 0 || !std::isfinite(x) || !std::isfinite(z)) return 0;
        const float d = -z;
        const float active = smoothstep(0, 12, d);
        const float banks = 0.011f * std::min(x * x, 800.0f);
        float h = active * (0.85f * std::sin(d * 0.13f) +
            0.24f * std::sin(d * 0.34f + 0.4f) * std::cos(x * 0.58f) + banks);
        float ruts = smoothstep(3, 8, d) * (1 - smoothstep(28, 33, d));
        h -= ruts * 0.16f * (gaussian(x - 0.83f, 0.24f) + gaussian(x + 0.83f, 0.24f));
        h += 0.47f * gaussian(d - 12.5f, 1.35f) * gaussian(x + 0.75f, 0.60f);
        float rock = smoothstep(16, 18, d) * (1 - smoothstep(27, 29, d));
        h += rock * (0.16f + 0.14f * std::sin(d * 2.2f)) *
             (0.70f + 0.30f * std::cos(x * 2.4f));
        h += (smoothstep(35, 36.1f, d) - smoothstep(43, 46, d)) *
              0.55f * (0.85f + 0.15f * std::cos(x * 0.70f));
        return h;
    }
    Vec3 terrain_normal(float x, float z) const {
        if (terrain_mode_ == 0) return {0, 1, 0};
        constexpr float e = 0.035f;
        return Vec3(terrain_height(x - e, z) - terrain_height(x + e, z),
                    2 * e, terrain_height(x, z - e) - terrain_height(x, z + e)).normalized();
    }

    Vec3 center() const {
        Vec3 result;
        for (int i = 0; i < 8 && i < int(particles.size()); ++i) result += particles[i].pos;
        return result / 8.0f;
    }
    Vec3 forward() const {
        if (particles.size() < 8) return {0, 0, -1};
        Vec3 f = (particles[0].pos + particles[1].pos + particles[4].pos + particles[5].pos)
               - (particles[2].pos + particles[3].pos + particles[6].pos + particles[7].pos);
        return f.length_squared() > 1e-6f ? f.normalized() : Vec3(0, 0, -1);
    }
    Vec3 up() const {
        Vec3 r = right_raw();
        Vec3 u = r.cross(forward());
        return u.length_squared() > 1e-6f ? u.normalized() : Vec3(0, 1, 0);
    }
    float speed() const { return linear_velocity().length(); }
    Vec3 linear_velocity() const {
        Vec3 v;
        for (int i = 0; i < 8 && i < int(particles.size()); ++i) v += particles[i].velocity;
        return v / 8.0f;
    }
    float damage() const {
        float sum = 0; int count = 0;
        for (const auto &b : beams) if (b.kind == CHASSIS || b.kind == CAB) {
            sum += b.broken ? 1.0f : std::min(1.0f, b.plastic_strain * 4.0f);
            ++count;
        }
        return count ? sum / count : 0;
    }
    int broken_count() const {
        int n = 0; for (const auto &b : beams) if (b.broken) ++n; return n;
    }
    int safety_clamp_count() const { return velocity_limit_count_; }
    int rejected_state_count() const { return nonfinite_count_; }
    float time_dropped() const { return dropped_time_; }
    int contact_count() const { return contact_count_; }
    int wheel_contact_count(int wheel) const { return wheel >= 0 && wheel < 4 ? wheel_contact_counts_[wheel] : 0; }
    int node_count() const { return int(particles.size()); }
    int beam_count() const { return int(beams.size()); }
    float wheel_angular_velocity(int wheel) const {
        if (wheel < 0 || wheel > 3) return 0;
        return angular_velocity(wheel, wheel_axis(wheel));
    }
    float suspension_travel(int wheel) const {
        if (wheel < 0 || wheel > 3) return 0;
        return (particles[wheel_hubs[wheel]].pos - particles[wheel].pos).dot(up()) + cfg_.ride_height;
    }
    void apply_impact(Vec3 impulse) {
        // A localized impulse, in N s, useful for reproducing crash response.
        // Uniform impulses would change total momentum without bending anything.
        if (!impulse.finite() || particles.size() < 8) return;
        float mag = impulse.length();
        if (mag > 45000) impulse *= 45000.0f / mag;
        particles[4].velocity += impulse * particles[4].inv_mass;
        limit_velocity(particles[4].velocity);
    }
    void displace_node(int node, Vec3 displacement) {
        if (node < 0 || node >= int(particles.size()) || !displacement.finite()) return;
        float l = displacement.length();
        if (l > 5) displacement *= 5 / l;
        particles[node].pos += displacement;
        particles[node].prev += displacement;
    }

private:
    Config cfg_;
    int terrain_mode_ = 0;
    float accumulator_ = 0, steering_ = 0, tire_width_ = 0.28f;
    int contact_count_ = 0;
    int velocity_limit_count_ = 0, nonfinite_count_ = 0;
    float dropped_time_ = 0;
    std::array<int, 4> wheel_contact_counts_{};
    std::vector<float> contact_lambdas_, wheel_plane_lambdas_;
    std::vector<Vec3> friction_offsets_, contact_normals_;
    std::array<std::array<float, 3>, 4> suspension_lambdas_{};

    static float safe_clamp(float x, float lo, float hi, float fallback) {
        return std::isfinite(x) ? std::clamp(x, lo, hi) : fallback;
    }
    static float smoothstep(float a, float b, float x) {
        float t = std::clamp((x - a) / (b - a), 0.0f, 1.0f);
        return t * t * (3 - 2 * t);
    }
    static float gaussian(float x, float width) { float v = x / width; return std::exp(-v * v); }
    void limit_velocity(Vec3 &v) {
        if (!v.finite()) { v = {}; ++nonfinite_count_; return; }
        float s2 = v.length_squared();
        if (s2 > 240 * 240) { v *= 240.0f / std::sqrt(s2); ++velocity_limit_count_; }
    }
    int add_particle(Vec3 p, float mass, float radius, int wheel = -1, bool tire = false) {
        Particle n; n.pos = n.prev = p; n.inv_mass = 1.0f / mass;
        n.radius = radius; n.wheel = wheel; n.tire = tire;
        particles.push_back(n); return int(particles.size()) - 1;
    }
    void add_box(Vec3 origin, float hx, float front_z, float rear_z,
                 float lower_y, float upper_y, float mass) {
        for (int layer = 0; layer < 2; ++layer) for (int corner = 0; corner < 4; ++corner)
            add_particle(origin + Vec3(corner % 2 ? hx : -hx,
                         layer ? upper_y : lower_y, corner < 2 ? front_z : rear_z), mass / 8.0f, 0.075f);
    }
    void add_beam(int a, int b, int kind, float compliance) {
        Beam beam; beam.a = a; beam.b = b; beam.kind = kind;
        beam.rest = beam.original_rest = (particles[b].pos - particles[a].pos).length();
        beam.compliance = compliance; beams.push_back(beam);
    }
    void brace_box(int first, int kind, float compliance) {
        // Fully braced eight-node cell: edges, face diagonals and internal diagonals.
        // This modest complete graph eliminates cube shear/hinge mechanisms.
        for (int a = 0; a < 8; ++a) for (int b = a + 1; b < 8; ++b)
            add_beam(first + a, first + b, kind, compliance);
    }
    Vec3 right_raw() const {
        if (particles.size() < 8) return {1, 0, 0};
        Vec3 r = (particles[1].pos + particles[3].pos + particles[5].pos + particles[7].pos)
               - (particles[0].pos + particles[2].pos + particles[4].pos + particles[6].pos);
        return r.length_squared() > 1e-6f ? r.normalized() : Vec3(1, 0, 0);
    }
    Vec3 right() const { return forward().cross(up()).normalized(); }
    Vec3 wheel_axis(int wheel) const {
        Vec3 r = right(), f = forward();
        // Positive steering turns right. Positive axle rotation rolls backward.
        float angle = wheel < 2 ? steering_ : 0;
        return (r * std::cos(angle) - f * std::sin(angle)).normalized();
    }
    float angular_velocity(int wheel, Vec3 axis) const {
        const auto &hub = particles[wheel_hubs[wheel]];
        float numerator = 0, denominator = 0;
        for (int j = 1; j < nodes_per_wheel; ++j) {
            const auto &p = particles[wheel_hubs[wheel] + j];
            Vec3 r = p.pos - hub.pos;
            Vec3 tangent = axis.cross(r);
            float m = 1 / p.inv_mass;
            numerator += m * tangent.dot(p.velocity - hub.velocity);
            denominator += m * tangent.length_squared();
        }
        return denominator > 1e-5f ? numerator / denominator : 0;
    }
    float wheel_inertia(int w, Vec3 axis) const {
        float result = 0;
        const Vec3 hub = particles[wheel_hubs[w]].pos;
        for (int j = 1; j < nodes_per_wheel; ++j) {
            const auto &p = particles[wheel_hubs[w] + j];
            result += axis.cross(p.pos - hub).length_squared() / p.inv_mass;
        }
        return std::max(0.1f, result);
    }
    void wheel_torque(int w, Vec3 axis, float torque) {
        float inertia = wheel_inertia(w, axis);
        const Vec3 hub = particles[wheel_hubs[w]].pos;
        Vec3 tire_impulse;
        for (int j = 1; j < nodes_per_wheel; ++j) {
            auto &p = particles[wheel_hubs[w] + j];
            Vec3 dv = axis.cross(p.pos - hub) * (torque / inertia * fixed_dt);
            p.velocity += dv;
            tire_impulse += dv / p.inv_mass;
        }
        // Remove tiny net force from asymmetric carcass, conserving drive momentum.
        particles[wheel_hubs[w]].velocity -= tire_impulse * particles[wheel_hubs[w]].inv_mass;
        // Engine/axle reaction torque is transmitted to the chassis node network.
        Vec3 c = center();
        float body_inertia = 0;
        for (int i = 0; i < 8; ++i)
            body_inertia += axis.cross(particles[i].pos - c).length_squared() / particles[i].inv_mass;
        if (body_inertia > 1e-5f) for (int i = 0; i < 8; ++i)
            particles[i].velocity -= axis.cross(particles[i].pos - c) * (torque / body_inertia * fixed_dt);
    }
    void apply_drivetrain(float throttle, bool brake) {
        std::array<Vec3, 4> axes;
        std::array<float, 4> omega;
        float mean = 0, fastest = 0;
        for (int w = 0; w < 4; ++w) {
            axes[w] = wheel_axis(w); omega[w] = angular_velocity(w, axes[w]);
            mean += omega[w] * 0.25f; fastest = std::max(fastest, std::abs(omega[w]));
        }
        const float ratio = cfg_.low_range ? 2.65f : 1.0f;
        const float wheel_limit = (cfg_.low_range ? 10.5f : 26.0f) / cfg_.tire_radius;
        const float limiter = std::clamp(1.0f - std::pow(fastest / wheel_limit, 2.0f), 0.0f, 1.0f);
        for (int w = 0; w < 4; ++w) {
            float inertia = wheel_inertia(w, axes[w]);
            float drive = -throttle * cfg_.engine_torque * ratio * 0.25f * limiter;
            // Equal torque for open diffs; a finite torsional coupling for lockers.
            float locking = cfg_.locked_diffs ? (mean - omega[w]) * inertia * 13.0f : 0;
            locking = std::clamp(locking, -1500.0f, 1500.0f);
            float rolling_loss = -omega[w] * 0.65f;
            float braking = brake ? std::clamp(-omega[w] * inertia / fixed_dt, -2300.0f, 2300.0f) : 0;
            if (brake) drive = 0;
            wheel_torque(w, axes[w], drive + locking + rolling_loss + braking);
        }
    }

    void solve_beam(Beam &b) {
        if (b.broken || b.kind == SUSPENSION) return;
        auto &a = particles[b.a]; auto &c = particles[b.b];
        Vec3 delta = c.pos - a.pos; float len = delta.length();
        if (len < 1e-7f) return;
        float error = len - b.rest;
        if (std::abs(error) > std::abs(b.peak_delta)) b.peak_delta = error;
        float alpha = b.compliance / (fixed_dt * fixed_dt);
        float dl = (-error - alpha * b.lambda) / (a.inv_mass + c.inv_mass + alpha);
        b.lambda += dl;
        Vec3 corr = delta * (dl / len);
        a.pos -= corr * a.inv_mass; c.pos += corr * c.inv_mass;
    }
    void solve_axis(int a_idx, int b_idx, Vec3 axis, float target,
                    float compliance, float &lambda) {
        auto &a = particles[a_idx]; auto &b = particles[b_idx];
        float error = (b.pos - a.pos).dot(axis) - target;
        float alpha = compliance / (fixed_dt * fixed_dt);
        float dl = (-error - alpha * lambda) / (a.inv_mass + b.inv_mass + alpha);
        lambda += dl;
        a.pos -= axis * (dl * a.inv_mass); b.pos += axis * (dl * b.inv_mass);
    }
    void solve_suspension() {
        Vec3 u = up(), r = right(), f = forward();
        for (int w = 0; w < 4; ++w) {
            const int hub = wheel_hubs[w];
            const float sign = w % 2 ? 1.0f : -1.0f;
            solve_axis(w, hub, r, sign * cfg_.track_width * 0.12f,
                       1.0f / 2500000.0f, suspension_lambdas_[w][0]);
            solve_axis(w, hub, f, 0, 1.0f / 2500000.0f, suspension_lambdas_[w][1]);
            solve_axis(w, hub, u, -cfg_.ride_height, 1.0f / cfg_.spring_rate,
                       suspension_lambdas_[w][2]);
            const float vertical = (particles[hub].pos - particles[w].pos).dot(u);
            const float lower = -cfg_.ride_height - 0.22f;
            const float upper = -cfg_.ride_height + std::min(0.28f, cfg_.ride_height * 0.72f);
            if (vertical < lower || vertical > upper) {
                float stop_lambda = 0;
                solve_axis(w, hub, u, std::clamp(vertical, lower, upper), 1.0f / 4500000.0f, stop_lambda);
            }
            Vec3 axis = wheel_axis(w);
            for (int side = 0; side < 2; ++side) for (int j = 0; j < tire_segments; ++j) {
                int n = hub + 1 + side * tire_segments + j;
                solve_axis(hub, n, axis, (side == 0 ? -0.5f : 0.5f) * tire_width_,
                           1.0f / (480000.0f * cfg_.tire_pressure), wheel_plane_lambdas_[n]);
            }
        }
    }
    void solve_contacts() {
        for (std::size_t i = 0; i < particles.size(); ++i) {
            auto &p = particles[i];
            float h = terrain_height(p.pos.x, p.pos.z);
            if (p.pos.y - h > p.radius + 0.04f && contact_lambdas_[i] <= 0) continue;
            Vec3 normal = terrain_normal(p.pos.x, p.pos.z);
            float C = (p.pos.y - h) * normal.y - p.radius;
            // A stiff contact foundation; pressure works through the actual carcass.
            float alpha = 1.0f / (4500000.0f * fixed_dt * fixed_dt);
            float dl = (-C - alpha * contact_lambdas_[i]) / (p.inv_mass + alpha);
            float new_lambda = std::max(0.0f, contact_lambdas_[i] + dl);
            dl = new_lambda - contact_lambdas_[i]; contact_lambdas_[i] = new_lambda;
            p.pos += normal * (dl * p.inv_mass);
            contact_normals_[i] = normal;
            if (new_lambda <= 0) continue;
            Vec3 displacement = p.pos - p.prev;
            Vec3 slip = displacement - normal * displacement.dot(normal);
            Vec3 proposed = friction_offsets_[i] + slip;
            float mu = p.tire ? 1.20f : 0.45f;
            if (terrain_mode_ == 1 && p.pos.z < -7 && p.pos.z > -15) mu *= 0.72f;
            // Simplified pressure/contact-patch grip; it is intentionally bounded.
            if (p.tire) mu *= std::clamp(1.06f - 0.10f * (cfg_.tire_pressure - 1), 0.85f, 1.14f);
            float bound = mu * new_lambda * p.inv_mass;
            float l = proposed.length();
            if (l > bound && l > 1e-8f) proposed *= bound / l;
            p.pos -= proposed - friction_offsets_[i];
            friction_offsets_[i] = proposed;
        }
    }
    void material_damping() {
        // Pair impulses remove axial vibration while preserving pair momentum and
        // rigid translation/rotation. They cannot arbitrarily damp the whole car.
        for (const auto &b : beams) {
            if (b.broken || b.kind == SUSPENSION) continue;
            auto &a = particles[b.a]; auto &c = particles[b.b];
            Vec3 n = (c.pos - a.pos).normalized();
            float rel = (c.velocity - a.velocity).dot(n);
            float amount = b.kind == TIRE ? 0.026f : 0.018f;
            float impulse = -rel * amount / (a.inv_mass + c.inv_mass);
            a.velocity -= n * (impulse * a.inv_mass); c.velocity += n * (impulse * c.inv_mass);
        }
        Vec3 u = up();
        for (int w = 0; w < 4; ++w) {
            auto &a = particles[w];
            const int hub = wheel_hubs[w];
            // Implicit damper on the unsprung assembly; distributing its equal
            // velocity increment avoids treating the light hub as the whole wheel.
            Vec3 assembly_velocity;
            for (int j = 0; j < nodes_per_wheel; ++j) assembly_velocity += particles[hub + j].velocity;
            assembly_velocity *= 1.0f / nodes_per_wheel;
            float unsprung_inv_mass = particles[hub].inv_mass / nodes_per_wheel;
            float inv_mass_sum = a.inv_mass + unsprung_inv_mass;
            float rel = (assembly_velocity - a.velocity).dot(u);
            float chm = cfg_.damping * fixed_dt * inv_mass_sum;
            float blend = chm / (1.0f + chm);
            float impulse = -rel * blend / inv_mass_sum;
            a.velocity -= u * (impulse * a.inv_mass);
            for (int j = 0; j < nodes_per_wheel; ++j)
                particles[hub + j].velocity += u * (impulse * unsprung_inv_mass);
        }
    }
    void update_damage() {
        for (auto &b : beams) {
            if (b.broken || (b.kind != CHASSIS && b.kind != CAB)) continue;
            float trial = std::abs(b.peak_delta) / std::max(0.02f, b.original_rest);
            const float yield = b.kind == CHASSIS ? 0.115f : 0.095f;
            // Plastic rest length records real permanent shape changes in the
            // same constraints that carry the vehicle's loads after a collision.
            if (trial > yield) {
                float plastic = std::copysign((trial - yield) * 0.22f, b.peak_delta);
                plastic = std::clamp(plastic, -0.025f, 0.025f);
                float before = b.rest;
                b.rest = std::clamp(b.rest + b.original_rest * plastic,
                                   b.original_rest * 0.45f, b.original_rest * 1.65f);
                b.plastic_strain = std::min(1.0f, b.plastic_strain + std::abs(b.rest - before) / b.original_rest);
            }
            if (trial > 0.72f || (b.plastic_strain > 0.50f && trial > yield * 1.5f)) b.broken = true;
        }
    }
    void substep(float throttle, float steer, bool brake) {
        const float target = steer * 0.54f / (1.0f + speed() * 0.027f);
        steering_ += (target - steering_) * std::min(1.0f, fixed_dt * 8.0f);
        apply_drivetrain(throttle, brake);
        for (auto &p : particles) {
            p.velocity.y -= 9.81f * fixed_dt;
            p.velocity *= 1.0f - 0.010f * fixed_dt;
            limit_velocity(p.velocity);
            p.prev = p.pos;
            p.pos += p.velocity * fixed_dt;
        }
        for (auto &b : beams) { b.lambda = 0; b.peak_delta = 0; }
        std::fill(contact_lambdas_.begin(), contact_lambdas_.end(), 0);
        std::fill(friction_offsets_.begin(), friction_offsets_.end(), Vec3{});
        std::fill(wheel_plane_lambdas_.begin(), wheel_plane_lambdas_.end(), 0);
        for (auto &l : suspension_lambdas_) l.fill(0);
        constexpr int iterations = 9;
        for (int iteration = 0; iteration < iterations; ++iteration) {
            if (iteration % 2 == 0) for (auto &b : beams) solve_beam(b);
            else for (auto it = beams.rbegin(); it != beams.rend(); ++it) solve_beam(*it);
            solve_suspension();
            solve_contacts();
        }
        update_damage();
        contact_count_ = 0; wheel_contact_counts_.fill(0);
        for (std::size_t i = 0; i < particles.size(); ++i) {
            auto &p = particles[i];
            if (!p.pos.finite()) { p.pos = p.prev; p.velocity = {}; ++nonfinite_count_; }
            p.velocity = (p.pos - p.prev) / fixed_dt;
            if (contact_lambdas_[i] > 1e-7f) {
                ++contact_count_;
                if (p.tire) ++wheel_contact_counts_[p.wheel];
                // Inelastic normal response avoids point-contact chatter.
                float vn = p.velocity.dot(contact_normals_[i]);
                if (vn < 0) p.velocity -= contact_normals_[i] * vn;
            }
            limit_velocity(p.velocity);
        }
        material_damping();
    }
};

} // namespace boltyard
