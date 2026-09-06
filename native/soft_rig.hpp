#pragma once

// Bolt Yard v0.4: deformable XPBD frame with four continuous tire contacts.
// SI units. The 16 frame/cab particles and four lumped wheel assemblies carry
// mass, gravity, suspension loads, contact traction and collision impulses.
// The 80 sidewall samples preserve render bindings; they follow the round tire
// contact model and are not independently integrated mass nodes. Structural
// beams still yield and break, so impacts permanently deform the actual body.
// Bounded mobile model: no self-contact, fluid mud, detailed clutch/transmission,
// or independently deformable tire carcass. Pressure changes tire compliance.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>
#include "terrain_v03.hpp"

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

#include "crawl_rocks.hpp"

struct Config {
    float tire_radius = 0.46f;       // m, overall unloaded radius
    float tire_pressure = 1.0f;     // relative pressure, 1 = trail baseline (uncalibrated)
    float spring_rate = 30000.0f;   // N/m per corner
    float damping = 3000.0f;        // N s/m damping coefficient per corner
    float ride_height = 0.35f;      // m from frame underside to unloaded hub
    float engine_torque = 450.0f;   // N m engine torque before reduction
    bool low_range = true;
    bool locked_diffs = true;
    float mass = 1200.0f;           // kg, entire vehicle including wheels
    float track_width = 1.90f;      // m between hub centers
    float wheelbase = 2.70f;        // m
    float body_stiffness = 1.0f;    // dimensionless structural stiffness scale
    int vehicle_type = 0;           // 0 pickup, 1 enclosed SUV, 2 rear-engine buggy
    float tire_grip = 1.0f;         // compound coefficient relative to trail tire
    float tire_width_scale = 1.0f;  // physical sidewall spacing relative to radius
    float suspension_travel = 0.22f;// m droop allowance; compression also bounded by frame clearance
    float final_drive = 1.0f;       // relative reduction: multiplies torque, divides wheel speed limit
    float front_accessory_mass = 0;// kg included in total mass, concentrated at front frame
    float roof_accessory_mass = 0; // kg included in total mass, concentrated at roof corners
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
    std::vector<Vec3> rest_positions; // undeformed world positions for binding each vehicle's render skin
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
        cfg_.vehicle_type = std::clamp(input.vehicle_type, 0, 2);
        cfg_.tire_grip = safe_clamp(input.tire_grip, 0.7f, 1.4f, 1.0f);
        cfg_.tire_width_scale = safe_clamp(input.tire_width_scale, 0.75f, 1.4f, 1.0f);
        cfg_.suspension_travel = safe_clamp(input.suspension_travel, 0.12f, 0.4f, 0.22f);
        cfg_.final_drive = safe_clamp(input.final_drive, 0.8f, 1.5f, 1.0f);
        cfg_.front_accessory_mass = safe_clamp(input.front_accessory_mass, 0, 100, 0);
        cfg_.roof_accessory_mass = safe_clamp(input.roof_accessory_mass, 0, 100, 0);
        reset();
    }
    const Config &config() const { return cfg_; }
    void set_drivetrain(bool low_range, bool locked_diffs) {
        cfg_.low_range = low_range;
        cfg_.locked_diffs = locked_diffs;
    }

    void reset(Vec3 origin = {0, 1.5f, 8}) {
        if (!origin.finite()) origin = {0, 1.5f, 8};
        particles.clear(); beams.clear(); rest_positions.clear();
        accumulator_ = 0; steering_ = 0; contact_count_ = 0;
        velocity_limit_count_ = 0; nonfinite_count_ = 0; dropped_time_ = 0;
        wheel_contact_counts_.fill(0); wheel_spin_.fill(0); wheel_phase_.fill(0); wheel_slip_.fill(0);
        near_rocks_.clear(); rock_lambdas_.clear();
        const float frame_x = cfg_.track_width * 0.38f;
        const float frame_z = cfg_.wheelbase * 0.50f;
        const bool suv = cfg_.vehicle_type == 1;
        const bool buggy = cfg_.vehicle_type == 2;
        const float base_mass = cfg_.mass - cfg_.front_accessory_mass - cfg_.roof_accessory_mass;
        const float frame_share = suv ? 0.54f : (buggy ? 0.59f : 0.60f);
        const float cab_share = suv ? 0.25f : (buggy ? 0.15f : 0.18f);
        const float tire_share = suv ? 0.21f : (buggy ? 0.26f : 0.22f);
        add_box(origin, frame_x, -frame_z, frame_z, 0, suv ? 0.34f : (buggy ? 0.22f : 0.30f), base_mass * frame_share);
        add_box(origin, cfg_.track_width * (buggy ? 0.28f : 0.32f),
                -cfg_.wheelbase * (suv ? 0.37f : (buggy ? 0.22f : 0.30f)),
                cfg_.wheelbase * (suv ? 0.44f : (buggy ? 0.24f : 0.12f)),
                suv ? 0.36f : (buggy ? 0.24f : 0.32f),
                suv ? 1.18f : (buggy ? 0.78f : 1.02f), base_mass * cab_share);
        // Engine location and body construction change actual nodal mass, not
        // just a visual skin. Accessories replace distributed mass within the
        // configured total, then put that same mass at their attachment points.
        for (int i = 0; i < 8; ++i) {
            const bool front = (i % 4) < 2;
            const float bias = suv ? (front ? 1.03f : 0.97f) : (buggy ? (front ? 0.90f : 1.10f) : 1.0f);
            float mass = bias / particles[i].inv_mass;
            if (front) mass += cfg_.front_accessory_mass * 0.25f;
            particles[i].inv_mass = 1.0f / mass;
        }
        for (int i = 12; i < 16; ++i)
            particles[i].inv_mass = 1.0f / (1.0f / particles[i].inv_mass + cfg_.roof_accessory_mass * 0.25f);
        brace_box(0, CHASSIS, 1.0f / (2800000.0f * cfg_.body_stiffness));
        brace_box(8, CAB, 1.0f / (950000.0f * cfg_.body_stiffness));
        // Cab-floor attachments are triangulated. They bend/yield with the cab.
        for (int i = 0; i < 4; ++i) {
            add_beam(i + 8, i, CAB, 1.0f / (1700000.0f * cfg_.body_stiffness));
            add_beam(i + 8, i + 4, CAB, 1.0f / (1700000.0f * cfg_.body_stiffness));
            add_beam(i + 8, (i ^ 1) + 4, CAB, 1.0f / (1700000.0f * cfg_.body_stiffness));
        }
        if (suv || buggy) {
            // SUV pillars tie the long roof into both ends of the frame. The
            // buggy additionally triangulates its low cage across the frame.
            for (int i = 0; i < 4; ++i) {
                add_beam(i + 12, i + 4, CAB, 1.0f / (suv ? 1350000.0f : 2100000.0f) / cfg_.body_stiffness);
                add_beam(i + 12, (i ^ 1) + 4, CAB, 1.0f / (suv ? 1000000.0f : 1700000.0f) / cfg_.body_stiffness);
                if (buggy) add_beam(i + 12, (i ^ 2) + 4, CHASSIS, 1.0f / (2400000.0f * cfg_.body_stiffness));
            }
        }
        const float tire_node_mass = base_mass * tire_share / (4 * nodes_per_wheel);
        tire_width_ = cfg_.tire_radius * 0.58f * cfg_.tire_width_scale;
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
            // Physical prismatic suspension spring, with compression/droop
            // stops and a damper acting on the whole unsprung assembly.
            add_beam(w, wheel_hubs[w], SUSPENSION, 1.0f / cfg_.spring_rate);
        }
        contact_lambdas_.assign(particles.size(), 0);
        friction_offsets_.assign(particles.size(), Vec3{});
        contact_normals_.assign(particles.size(), Vec3(0, 1, 0));
        for (const auto &p : particles) rest_positions.push_back(p.pos);
        nearby_obstacles_.clear(); obstacle_lambdas_.clear(); obstacle_friction_.clear(); obstacle_normals_.clear();
        beam_contact_lambdas_.clear(); beam_contact_t_.clear(); beam_contact_normals_.clear();
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
        accumulator_ = std::clamp(accumulator_, 0.0, double(fixed_dt));
    }

    void set_terrain(int mode) { terrain_mode_ = std::clamp(mode, 0, 3); }
    float terrain_height(float x, float z) const {
        if ((terrain_mode_ == 0 || terrain_mode_ == 3) || !std::isfinite(x) || !std::isfinite(z)) return 0;
        if (terrain_mode_ == 2) return exploration_height(x, z);
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
        if (terrain_mode_ == 0 || terrain_mode_ == 3) return {0, 1, 0};
        if (terrain_mode_ == 2) {
            const auto n = exploration_normal(x, z);
            return {n.x, n.y, n.z};
        }
        constexpr float e = 0.035f;
        return Vec3(terrain_height(x - e, z) - terrain_height(x + e, z),
                    2 * e, terrain_height(x, z - e) - terrain_height(x, z + e)).normalized();
    }
    float terrain_surface(float x, float z) const {
        if (!std::isfinite(x) || !std::isfinite(z)) return 1.0f;
        if (terrain_mode_ == 2) return exploration_surface(x, z);
        if (terrain_mode_ == 1 && z < -7 && z > -15) return 0.72f;
        return 1.0f;
    }

    void set_test_rocks(const std::vector<CrawlRock>& rocks) { test_rocks_=rocks; custom_rocks_=true; }
    float wheel_load(int w) const { float load=0; for(const auto& c: tire_contacts(w)) load += c.normal.y*c.lambda/(fixed_dt*fixed_dt); return load; }
    float wheel_rock_load(int w) const { float load=0; for(const auto& c: tire_contacts(w)) if(c.rock)load += c.normal.y*c.lambda/(fixed_dt*fixed_dt); return load; }
    float wheel_slip(int w) const { return wheel_slip_[w]; }
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
    int physical_node_count() const { return 20; }
    int physical_beam_count() const {
        int count = 0; for (const auto &b : beams) if (b.kind != TIRE) ++count; return count;
    }
    int render_node_count() const { return int(particles.size()); }
    float steering_angle() const { return steering_; }
    Vec3 velocity() const { return linear_velocity(); }
    int beam_count() const { return int(beams.size()); }
    float wheel_angular_velocity(int wheel) const {
        if (wheel < 0 || wheel > 3) return 0;
        return wheel_spin_[wheel];
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
    struct TireContact {Vec3 normal, point; float lambda, mu; bool rock;};
    std::vector<CrawlRock> test_rocks_;
    bool custom_rocks_=false;
    std::vector<const CrawlRock*> near_rocks_;
    std::vector<float> rock_lambdas_,skid_lambdas_;
    std::vector<Vec3> skid_friction_;
    std::vector<Vec3> rock_normals_,rock_points_,rock_friction_;
    std::array<float,4> wheel_slip_{};
    float tire_mu(float surface) const {return 1.18f*cfg_.tire_grip*surface*std::clamp(1.05f-.1f*(cfg_.tire_pressure-1),.88f,1.12f);}
    std::vector<TireContact> tire_contacts(int w) const {
        std::vector<TireContact> out; const int h=wheel_hubs[w];const auto&p=particles[h];
        if(contact_lambdas_[h]>1e-8f)out.push_back({contact_normals_[h],p.pos-contact_normals_[h]*(cfg_.tire_radius-contact_lambdas_[h]/(fixed_dt*fixed_dt*300000*cfg_.tire_pressure)),contact_lambdas_[h],tire_mu(terrain_surface(p.pos.x,p.pos.z)),false});
        for(size_t k=0;k<nearby_obstacles_.size();++k){size_t pair=k*particles.size()+h;if(obstacle_lambdas_[pair]>1e-8f)out.push_back({obstacle_normals_[pair],p.pos-obstacle_normals_[pair]*cfg_.tire_radius,obstacle_lambdas_[pair],tire_mu(1),true});}
        for(size_t k=0;k<near_rocks_.size();++k){size_t pair=k*particles.size()+h;if(rock_lambdas_[pair]>1e-8f)out.push_back({rock_normals_[pair],rock_points_[pair],rock_lambdas_[pair],tire_mu(near_rocks_[k]->surface),true});}
        return out;
    }
    Config cfg_;
    int terrain_mode_ = 0;
    double accumulator_ = 0;
    float steering_ = 0, tire_width_ = 0.28f;
    std::array<float, 4> wheel_spin_{}, wheel_phase_{};
    int contact_count_ = 0;
    int velocity_limit_count_ = 0, nonfinite_count_ = 0;
    float dropped_time_ = 0;
    std::array<int, 4> wheel_contact_counts_{};
    std::vector<float> contact_lambdas_;
    std::vector<Vec3> friction_offsets_, contact_normals_;
    std::array<std::array<float, 3>, 4> suspension_lambdas_{};
    struct NearbyObstacle { Vec3 base; float radius, height; };
    std::vector<NearbyObstacle> nearby_obstacles_;
    std::vector<float> obstacle_lambdas_;
    std::vector<Vec3> obstacle_friction_, obstacle_normals_;
    std::vector<float> beam_contact_lambdas_, beam_contact_t_;
    std::vector<Vec3> beam_contact_normals_;

    float dynamic_inv_mass(const Particle &p) const {
        return p.wheel >= 0 ? p.inv_mass / float(nodes_per_wheel) : p.inv_mass;
    }
    float contact_radius(const Particle &p) const {
        return p.wheel >= 0 ? cfg_.tire_radius : p.radius;
    }
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
    void solve_tire_traction(float throttle, bool brake) {
        const float forward_speed = linear_velocity().dot(forward());
        const float ratio = (cfg_.low_range ? (terrain_mode_==3 ? 22.f : 5.5f) : 3.8f) * cfg_.final_drive;
        const float top_speed = (terrain_mode_==3 && cfg_.low_range ? (throttle<0?1.5f:2.2f) : (throttle < 0 ? 9.0f : (cfg_.low_range ? 16.5f : 31.0f))) / cfg_.final_drive;
        const float demand_speed = std::abs(forward_speed);
        // Flat low-speed torque, then a smooth power/road-speed falloff.
        const float limiter = std::clamp(1.0f - std::pow(demand_speed / top_speed, 3.0f), 0.0f, 1.0f);
        const float engine_force = throttle * cfg_.engine_torque * ratio / (4.0f * cfg_.tire_radius) * limiter;
        std::array<std::vector<TireContact>,4> contacts;
        std::array<float,4> capacity{};
        for(int w=0;w<4;++w){contacts[w]=tire_contacts(w);for(auto c:contacts[w])capacity[w]+=c.mu*c.lambda/(fixed_dt*fixed_dt);}
        for(int w=0;w<4;++w){
            auto&hub=particles[wheel_hubs[w]];float inv=dynamic_inv_mass(hub),inertia=std::max(1.f,.5f/inv*cfg_.tire_radius*cfg_.tire_radius);
            if(brake){wheel_spin_[w]*=std::exp(-24*fixed_dt);if(!contacts[w].empty())wheel_spin_[w]=0;wheel_slip_[w]=0;continue;}
            float axle_cap=cfg_.locked_diffs?capacity[w]:std::min(capacity[w],capacity[w^1]);
            float force=std::clamp(engine_force,-axle_cap,axle_cap);
            // Crawl range couples angular tire speed to contact impulses.
            // Zero-speed slip is expressed in m/s, avoiding slip-ratio singularities.
            if(terrain_mode_==3){
                float rotor_speed=std::abs(wheel_spin_[w])*cfg_.tire_radius;
                float rotor_limiter=std::clamp(1.f-std::pow(rotor_speed/top_speed,3.f),-.5f,1.f);
                float torque=throttle*cfg_.engine_torque*ratio*.25f*rotor_limiter;
                if(!cfg_.locked_diffs)torque=std::clamp(torque,-axle_cap*cfg_.tire_radius,axle_cap*cfg_.tire_radius);
                wheel_spin_[w]-=torque/inertia*fixed_dt;
                if(std::abs(throttle)<.01f){float drag=std::min(std::abs(wheel_spin_[w]),35.f*ratio*.25f/inertia*fixed_dt);wheel_spin_[w]-=std::copysign(drag,wheel_spin_[w]);}
            }
            float spin=0,weight=0;wheel_slip_[w]=0;
            for(auto c:contacts[w]){
                Vec3 rolling=c.normal.cross(wheel_axis(w)).normalized();if(rolling.dot(forward())<0)rolling=-rolling;
                Vec3 lateral=rolling.cross(c.normal).normalized();float v=hub.velocity.dot(rolling),lat=hub.velocity.dot(lateral);
                float share=c.mu*c.lambda/(fixed_dt*fixed_dt*std::max(capacity[w],1e-6f));
                float longitudinal=force*share*fixed_dt;
                float resistance=std::min(std::abs(v)*cfg_.mass*.25f, cfg_.mass*.25f*(.10f+.0012f*v*v)*fixed_dt)*share;
                longitudinal-=std::copysign(resistance,v);
                if(terrain_mode_==3)longitudinal=-(v+wheel_spin_[w]*cfg_.tire_radius)/(inv+cfg_.tire_radius*cfg_.tire_radius/inertia);
                float lateral_impulse=-lat*cfg_.mass*.25f*std::min(1.f,fixed_dt/.065f)*share;
                Vec3 impulse=rolling*longitudinal+lateral*lateral_impulse;
                float limit=c.mu*c.lambda/fixed_dt,requested=impulse.length();if(requested>limit&&requested>1e-7f)impulse*=limit/requested;
                hub.velocity+=impulse*inv;
                if(terrain_mode_==3)wheel_spin_[w]+=impulse.dot(rolling)*cfg_.tire_radius/inertia;
                spin+=(-v/cfg_.tire_radius-std::copysign(std::max(0.f,requested-limit)*cfg_.tire_radius/inertia,throttle))*share;weight+=share;
                wheel_slip_[w]+=std::abs(v+wheel_spin_[w]*cfg_.tire_radius)*share;
            }
            if(terrain_mode_==3)continue;
            if(weight>0)wheel_spin_[w]=spin/weight;
            else{wheel_spin_[w]+=-throttle*cfg_.engine_torque*ratio*.25f/inertia*fixed_dt;wheel_spin_[w]*=std::exp(-.18f*fixed_dt);wheel_spin_[w]=std::clamp(wheel_spin_[w],-top_speed/cfg_.tire_radius,top_speed/cfg_.tire_radius);}
        }
        // Axle coupling is per axle. Front/rear transfer case remains simplified.
        if(cfg_.locked_diffs)for(int axle=0;axle<4;axle+=2){float mean=(wheel_spin_[axle]+wheel_spin_[axle+1])*.5f;for(int w=axle;w<axle+2;++w)wheel_spin_[w]+=(mean-wheel_spin_[w])*std::min(1.f,14*fixed_dt);}
    }
    void update_wheel_skin() {
        const Vec3 u = up();
        for (int w = 0; w < 4; ++w) {
            const auto &hub = particles[wheel_hubs[w]];
            const Vec3 axle = wheel_axis(w);
            const Vec3 radial = axle.cross(u).normalized();
            wheel_phase_[w] = std::remainder(wheel_phase_[w] + wheel_spin_[w] * fixed_dt, 6.28318530718f);
            const auto patches = tire_contacts(w);
            for (int side = 0; side < 2; ++side) for (int j = 0; j < tire_segments; ++j) {
                auto &p = particles[wheel_hubs[w] + 1 + side * tire_segments + j];
                const float theta = 6.28318530718f * j / tire_segments + wheel_phase_[w];
                Vec3 radius = (u * std::cos(theta) + radial * std::sin(theta)) * (cfg_.tire_radius * 0.88f);
                p.prev = p.pos;
                p.pos = hub.pos + axle * ((side == 0 ? -0.5f : 0.5f) * tire_width_) + radius;
                // Pressure/contact compression flattens just the supported patch.
                for(auto c:patches){float distance=(p.pos-c.point).dot(c.normal);if(distance<p.radius*.65f)p.pos+=c.normal*(p.radius*.65f-distance);}
                p.velocity = hub.velocity + axle.cross(radius) * wheel_spin_[w];
            }
        }
    }

    void solve_beam(Beam &b) {
        if (b.broken || b.kind == SUSPENSION || b.kind == TIRE) return;
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
        float ai = dynamic_inv_mass(a), bi = dynamic_inv_mass(b);
        float dl = (-error - alpha * lambda) / (ai + bi + alpha);
        lambda += dl;
        a.pos -= axis * (dl * ai); b.pos += axis * (dl * bi);
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
            const float lower = -cfg_.ride_height - cfg_.suspension_travel;
            const float upper = -cfg_.ride_height + std::min(cfg_.suspension_travel * (0.28f / 0.22f), cfg_.ride_height * 0.72f);
            if (vertical < lower || vertical > upper) {
                float stop_lambda = 0;
                solve_axis(w, hub, u, std::clamp(vertical, lower, upper), 1.0f / 4500000.0f, stop_lambda);
            }

        }
    }
    void solve_contacts(bool brake) {
        for (std::size_t i = 0; i < particles.size(); ++i) {
            auto &p = particles[i];
            if (p.tire) continue;
            const float radius = contact_radius(p);
            const float inv_mass = dynamic_inv_mass(p);
            float h = terrain_height(p.pos.x, p.pos.z);
            if (p.pos.y - h > radius + 0.04f && contact_lambdas_[i] <= 0) continue;
            Vec3 normal = terrain_normal(p.pos.x, p.pos.z);
            float C = (p.pos.y - h) * normal.y - radius;
            // Three support lines across the tire width keep a wide tire from
            // falling into a rut that it physically spans. Body contacts remain
            // point spheres; the round tire has no rotating polygon facets.
            if (p.wheel >= 0 && terrain_mode_ != 0) {
                const Vec3 half_axle = wheel_axis(p.wheel) * (tire_width_ * 0.46f);
                for (float sign : {-1.0f, 1.0f}) {
                    const Vec3 sample = p.pos + half_axle * sign;
                    const float sample_height = terrain_height(sample.x, sample.z);
                    const Vec3 sample_normal = terrain_normal(sample.x, sample.z);
                    const float candidate = (sample.y - sample_height) * sample_normal.y - radius;
                    if (candidate < C) { C = candidate; normal = sample_normal; }
                }
            }
            const float stiffness = p.wheel >= 0 ? 300000.0f * cfg_.tire_pressure : 4500000.0f;
            float alpha = 1.0f / (stiffness * fixed_dt * fixed_dt);
            float dl = (-C - alpha * contact_lambdas_[i]) / (inv_mass + alpha);
            float new_lambda = std::max(0.0f, contact_lambdas_[i] + dl);
            dl = new_lambda - contact_lambdas_[i]; contact_lambdas_[i] = new_lambda;
            p.pos += normal * (dl * inv_mass);
            contact_normals_[i] = normal;
            if (new_lambda <= 0 || (p.wheel >= 0 && !brake)) continue;
            Vec3 displacement = p.pos - p.prev;
            Vec3 slip = displacement - normal * displacement.dot(normal);
            Vec3 proposed = friction_offsets_[i] + slip;
            const float mu = p.wheel >= 0 ? 1.18f * cfg_.tire_grip *
                std::clamp(1.05f - 0.10f * (cfg_.tire_pressure - 1), 0.88f, 1.12f) : 0.45f;
            const float bound = mu * terrain_surface(p.pos.x, p.pos.z) * new_lambda * inv_mass;
            const float l = proposed.length();
            if (l > bound && l > 1e-8f) proposed *= bound / l;
            p.pos -= proposed - friction_offsets_[i];
            friction_offsets_[i] = proposed;
        }
    }
    void find_nearby_obstacles() {
        nearby_obstacles_.clear();
        if (terrain_mode_ == 2) {
            const Vec3 c = center();
            float extent = 0;
            for (const auto &p : particles) {
                const float dx = p.pos.x - c.x, dz = p.pos.z - c.z;
                extent = std::max(extent, std::sqrt(dx * dx + dz * dz));
            }
            // Broad phase runs once per substep, rather than testing the whole
            // forest against every mass node in each constraint iteration.
            for (const auto &o : exploration_obstacles()) {
                const float dx = o.x - c.x, dz = o.z - c.z;
                const float reach = extent + o.radius + 1.5f;
                if (dx * dx + dz * dz <= reach * reach)
                    nearby_obstacles_.push_back({{o.x, exploration_height(o.x, o.z), o.z}, o.radius, o.height});
            }
        }
        near_rocks_.clear();
        const auto& rocks = custom_rocks_ ? test_rocks_ : crawl_course();
        if(custom_rocks_ || terrain_mode_==3) for(const auto&r:rocks) if((r.center-center()).length()<r.reach+7)near_rocks_.push_back(&r);
        skid_lambdas_.assign(near_rocks_.size()*9,0);skid_friction_.assign(near_rocks_.size()*9,{});
        size_t rock_pairs=near_rocks_.size()*particles.size();
        rock_lambdas_.assign(rock_pairs,0); rock_normals_.assign(rock_pairs,{});rock_points_.assign(rock_pairs,{});rock_friction_.assign(rock_pairs,{});
        const std::size_t pairs = nearby_obstacles_.size() * particles.size();
        obstacle_lambdas_.assign(pairs, 0);
        obstacle_friction_.assign(pairs, Vec3{});
        obstacle_normals_.assign(pairs, Vec3{});
        const std::size_t beam_pairs = nearby_obstacles_.size() * beams.size();
        beam_contact_lambdas_.assign(beam_pairs, 0);
        beam_contact_t_.assign(beam_pairs, 0);
        beam_contact_normals_.assign(beam_pairs, Vec3{});
    }
    void solve_obstacle_contacts(bool brake) {
        for (std::size_t k = 0; k < nearby_obstacles_.size(); ++k) {
            const auto &o = nearby_obstacles_[k];
            for (std::size_t i = 0; i < particles.size(); ++i) {
                auto &p = particles[i];
                if (p.tire) continue;
                const float radius = contact_radius(p);
                const float inv_mass = dynamic_inv_mass(p);
                const std::size_t pair = k * particles.size() + i;
                const Vec3 relative = p.pos - o.base;
                const float radial_sq = relative.x * relative.x + relative.z * relative.z;
                const float broad_radius = o.radius + radius + 0.04f;
                if (obstacle_lambdas_[pair] <= 0 &&
                    (radial_sq > broad_radius * broad_radius || relative.y < -radius - 0.04f ||
                     relative.y > o.height + radius + 0.04f)) continue;
                const float radial = std::sqrt(radial_sq);
                const float qr = radial - o.radius;
                const float center_y = relative.y - o.height * 0.5f;
                const float qy = std::abs(center_y) - o.height * 0.5f;
                const Vec3 nr = radial > 1e-7f ? Vec3(relative.x / radial, 0, relative.z / radial) : Vec3(1, 0, 0);
                const Vec3 ny(0, center_y >= 0 ? 1.0f : -1.0f, 0);
                Vec3 normal;
                float distance;
                if (qr > 0 && qy > 0) {
                    distance = std::sqrt(qr * qr + qy * qy);
                    normal = (nr * qr + ny * qy) / distance;
                } else if (qr > qy) { distance = qr; normal = nr; }
                else { distance = qy; normal = ny; }
                const float C = distance - radius;
                const float alpha = 1.0f / ((p.wheel >= 0 ? 300000.0f * cfg_.tire_pressure : 4500000.0f) * fixed_dt * fixed_dt);
                float dl = (-C - alpha * obstacle_lambdas_[pair]) / (inv_mass + alpha);
                const float next_lambda = std::max(0.0f, obstacle_lambdas_[pair] + dl);
                dl = next_lambda - obstacle_lambdas_[pair];
                obstacle_lambdas_[pair] = next_lambda;
                obstacle_normals_[pair] = normal;
                p.pos += normal * (dl * inv_mass);
                if (next_lambda <= 0 || (p.wheel >= 0 && !brake)) continue;
                const Vec3 displacement = p.pos - p.prev;
                Vec3 proposed = obstacle_friction_[pair] + displacement - normal * displacement.dot(normal);
                const float bound = (p.wheel >= 0 ? tire_mu(1) : 0.45f) * next_lambda * inv_mass;
                const float l = proposed.length();
                if (l > bound && l > 1e-8f) proposed *= bound / l;
                p.pos -= proposed - obstacle_friction_[pair];
                obstacle_friction_[pair] = proposed;
            }
        }
    }
    void solve_rock_contacts(bool brake) {
        for(size_t k=0;k<near_rocks_.size();++k) for(size_t i=0;i<particles.size();++i){
            auto&p=particles[i];if(p.tire)continue;const auto&r=*near_rocks_[k];float radius=contact_radius(p);size_t pair=k*particles.size()+i;
            if((p.pos-r.center).length_squared()>(r.reach+radius+.04f)*(r.reach+radius+.04f))continue;
            auto hit=rock_distance(r,p.pos);
            if(p.wheel>=0){
                const Vec3 axle=wheel_axis(p.wheel),side=axle*(tire_width_*.46f);
                // Radial tread support is a disc, not a full-radius sphere on
                // the sidewall. A small rounded shoulder supplies edge support.
                auto support=[&](Vec3 n){float a=n.dot(axle);return std::max(.055f,cfg_.tire_radius*std::sqrt(std::max(0.f,1-a*a)));};
                float best=hit.distance-support(hit.normal);radius=support(hit.normal);
                for(float sign:{-1.f,1.f}){auto sample=rock_distance(r,p.pos+side*sign);float rad=support(sample.normal);float c=sample.distance-rad;if(c<best){best=c;hit=sample;radius=rad;}}
            }
            if(hit.distance>radius+.04f&&rock_lambdas_[pair]==0)continue;
            const float inv=dynamic_inv_mass(p),alpha=1/((p.wheel>=0?300000*cfg_.tire_pressure:4500000)*fixed_dt*fixed_dt);
            float dl=(-(hit.distance-radius)-alpha*rock_lambdas_[pair])/(inv+alpha),next=std::max(0.f,rock_lambdas_[pair]+dl);dl=next-rock_lambdas_[pair];rock_lambdas_[pair]=next;
            rock_normals_[pair]=hit.normal;rock_points_[pair]=hit.point;p.pos+=hit.normal*(dl*inv);
            if(next<=0||(p.wheel>=0&&!brake))continue;
            Vec3 displacement=p.pos-p.prev;Vec3 proposed=rock_friction_[pair]+displacement-hit.normal*displacement.dot(hit.normal);
            float bound=(p.wheel>=0?tire_mu(r.surface):.45f)*next*inv;float l=proposed.length();if(l>bound&&l>1e-8f)proposed*=bound/l;
            p.pos-=proposed-rock_friction_[pair];rock_friction_[pair]=proposed;
        }
    }
    void solve_skid_contacts() {
        // Nine support points span the existing frame underside. Each reaction
        // acts through bilinear weights on its four deforming attachment nodes.
        for(size_t k=0;k<near_rocks_.size();++k)for(int iz=0;iz<3;++iz)for(int ix=0;ix<3;++ix){
            float x=(ix+1)*.25f,z=(iz+1)*.25f;float weights[4]={(1-x)*(1-z),x*(1-z),(1-x)*z,x*z};
            Vec3 p,prev;float inv=0;for(int j=0;j<4;++j){p+=particles[j].pos*weights[j];prev+=particles[j].prev*weights[j];inv+=particles[j].inv_mass*weights[j]*weights[j];}
            const auto&r=*near_rocks_[k];if((p-r.center).length_squared()>(r.reach+.08f)*(r.reach+.08f))continue;
            auto hit=rock_distance(r,p);size_t pair=k*9+iz*3+ix;float C=hit.distance-.04f;if(C>.025f&&skid_lambdas_[pair]==0)continue;
            float alpha=1/(4500000.f*fixed_dt*fixed_dt);float dl=(-C-alpha*skid_lambdas_[pair])/(inv+alpha),next=std::max(0.f,skid_lambdas_[pair]+dl);dl=next-skid_lambdas_[pair];skid_lambdas_[pair]=next;
            Vec3 slip=p-prev;slip-=hit.normal*slip.dot(hit.normal);Vec3 proposed=skid_friction_[pair]+slip/inv;float bound=.45f*next;float l=proposed.length();if(l>bound&&l>1e-8f)proposed*=bound/l;
            Vec3 correction=hit.normal*dl-(proposed-skid_friction_[pair]);skid_friction_[pair]=proposed;
            for(int j=0;j<4;++j)particles[j].pos+=correction*(particles[j].inv_mass*weights[j]);
        }
    }
    void solve_structural_obstacle_contacts() {
        // The load-bearing frame/cab beams also contact cylinder sides, closing
        // gaps through which a narrow tree could otherwise miss every node.
        // Contact forces use interpolated endpoint masses, never a rigid hull.
        for (std::size_t k = 0; k < nearby_obstacles_.size(); ++k) {
            const auto &o = nearby_obstacles_[k];
            for (std::size_t j = 0; j < beams.size(); ++j) {
                const auto &beam = beams[j];
                if (beam.broken || beam.kind > CAB) continue;
                auto &a = particles[beam.a]; auto &b = particles[beam.b];
                const Vec3 d = b.pos - a.pos;
                const Vec3 start = a.pos - o.base;
                constexpr float beam_radius = 0.025f;
                const float reach = o.radius + beam_radius;
                if (std::min(a.pos.x, b.pos.x) > o.base.x + reach ||
                    std::max(a.pos.x, b.pos.x) < o.base.x - reach ||
                    std::min(a.pos.z, b.pos.z) > o.base.z + reach ||
                    std::max(a.pos.z, b.pos.z) < o.base.z - reach) continue;
                float t_lo = 0, t_hi = 1;
                if (std::abs(d.y) > 1e-7f) {
                    float t0 = -start.y / d.y, t1 = (o.height - start.y) / d.y;
                    if (t0 > t1) std::swap(t0, t1);
                    t_lo = std::max(0.0f, t0); t_hi = std::min(1.0f, t1);
                    if (t_lo > t_hi) continue;
                } else if (start.y < 0 || start.y > o.height) continue;
                const float horizontal = d.x * d.x + d.z * d.z;
                const float t = horizontal > 1e-8f ?
                    std::clamp(-(start.x * d.x + start.z * d.z) / horizontal, t_lo, t_hi) :
                    (t_lo + t_hi) * 0.5f;
                Vec3 radial = start + d * t; radial.y = 0;
                const float distance = radial.length();
                const std::size_t pair = k * beams.size() + j;
                if (distance > reach + 0.02f && beam_contact_lambdas_[pair] <= 0) continue;
                Vec3 normal;
                if (distance > 1e-7f) normal = radial / distance;
                else {
                    Vec3 previous = a.prev * (1 - t) + b.prev * t - o.base; previous.y = 0;
                    normal = previous.length_squared() > 1e-10f ? previous.normalized() : Vec3(1, 0, 0);
                }
                const float wa = 1 - t, wb = t;
                const float inverse_mass = wa * wa * a.inv_mass + wb * wb * b.inv_mass;
                const float alpha = 1.0f / (4500000.0f * fixed_dt * fixed_dt);
                float dl = (-(distance - reach) - alpha * beam_contact_lambdas_[pair]) / (inverse_mass + alpha);
                const float next_lambda = std::max(0.0f, beam_contact_lambdas_[pair] + dl);
                dl = next_lambda - beam_contact_lambdas_[pair];
                beam_contact_lambdas_[pair] = next_lambda;
                beam_contact_t_[pair] = t; beam_contact_normals_[pair] = normal;
                a.pos += normal * (dl * wa * a.inv_mass);
                b.pos += normal * (dl * wb * b.inv_mass);
            }
        }
    }
    void material_damping() {
        // Pair impulses remove axial vibration while preserving pair momentum and
        // rigid translation/rotation. They cannot arbitrarily damp the whole car.
        for (const auto &b : beams) {
            if (b.broken || b.kind == SUSPENSION || b.kind == TIRE) continue;
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
            auto &wheel = particles[hub];
            const float unsprung_inv_mass = dynamic_inv_mass(wheel);
            const float inv_mass_sum = a.inv_mass + unsprung_inv_mass;
            const float rel = (wheel.velocity - a.velocity).dot(u);
            const float chm = cfg_.damping * fixed_dt * inv_mass_sum;
            const float blend = chm / (1.0f + chm);
            const float impulse = -rel * blend / inv_mass_sum;
            a.velocity -= u * (impulse * a.inv_mass);
            wheel.velocity += u * (impulse * unsprung_inv_mass);
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
        // A direction change first uses the tire brakes, then engages reverse
        // near walking speed. It must not wait for a reverse speed limiter to
        // coast the vehicle down from forward trail speed.
        const bool braking = brake || throttle * linear_velocity().dot(forward()) < -0.35f;
        find_nearby_obstacles();
        const float target = steer * 0.60f / (1.0f + std::pow(speed() / 10.0f, 1.5f));
        steering_ += (target - steering_) * std::min(1.0f, fixed_dt * 8.0f);
        for (auto &p : particles) {
            if (p.tire) continue;
            p.velocity.y -= 9.81f * fixed_dt;
            p.velocity *= 1.0f - 0.010f * fixed_dt;
            limit_velocity(p.velocity);
            p.prev = p.pos;
            p.pos += p.velocity * fixed_dt;
        }
        for (auto &b : beams) { b.lambda = 0; b.peak_delta = 0; }
        std::fill(contact_lambdas_.begin(), contact_lambdas_.end(), 0);
        std::fill(friction_offsets_.begin(), friction_offsets_.end(), Vec3{});
        for (auto &l : suspension_lambdas_) l.fill(0);
        constexpr int iterations = 9;
        for (int iteration = 0; iteration < iterations; ++iteration) {
            if (iteration % 2 == 0) for (auto &b : beams) solve_beam(b);
            else for (auto it = beams.rbegin(); it != beams.rend(); ++it) solve_beam(*it);
            solve_suspension();
            solve_contacts(braking);
            solve_obstacle_contacts(braking);
            solve_rock_contacts(braking);
            solve_skid_contacts();
            solve_structural_obstacle_contacts();
        }
        update_damage();
        contact_count_ = 0; wheel_contact_counts_.fill(0);
        for (std::size_t i = 0; i < particles.size(); ++i) {
            auto &p = particles[i];
            if (p.tire) continue;
            if (!p.pos.finite()) { p.pos = p.prev; p.velocity = {}; ++nonfinite_count_; }
            p.velocity = (p.pos - p.prev) / fixed_dt;
            if (contact_lambdas_[i] > 1e-7f) {
                ++contact_count_;
                if (p.wheel >= 0) ++wheel_contact_counts_[p.wheel];
                // Inelastic normal response avoids point-contact chatter.
                float vn = p.velocity.dot(contact_normals_[i]);
                if (vn < 0) p.velocity -= contact_normals_[i] * vn;
            }
            for (std::size_t k = 0; k < nearby_obstacles_.size(); ++k) {
                const std::size_t pair = k * particles.size() + i;
                if (obstacle_lambdas_[pair] <= 1e-7f) continue;
                ++contact_count_;
                if (p.wheel >= 0) ++wheel_contact_counts_[p.wheel];
                const float vn = p.velocity.dot(obstacle_normals_[pair]);
                if (vn < 0) p.velocity -= obstacle_normals_[pair] * vn;
            }
            for(size_t k=0;k<near_rocks_.size();++k){size_t pair=k*particles.size()+i;if(rock_lambdas_[pair]<=1e-7f)continue;++contact_count_;if(p.wheel>=0)++wheel_contact_counts_[p.wheel];float vn=p.velocity.dot(rock_normals_[pair]);if(vn<0)p.velocity-=rock_normals_[pair]*vn;}
            limit_velocity(p.velocity);
        }
        for (std::size_t k = 0; k < nearby_obstacles_.size(); ++k) for (std::size_t j = 0; j < beams.size(); ++j) {
            const std::size_t pair = k * beams.size() + j;
            if (beam_contact_lambdas_[pair] <= 1e-7f) continue;
            const auto &beam = beams[j];
            if (beam.broken) continue;
            auto &a = particles[beam.a]; auto &b = particles[beam.b];
            const float wb = beam_contact_t_[pair], wa = 1 - wb;
            const Vec3 normal = beam_contact_normals_[pair];
            const float vn = (a.velocity * wa + b.velocity * wb).dot(normal);
            if (vn < 0) {
                const float impulse = -vn / (wa * wa * a.inv_mass + wb * wb * b.inv_mass);
                a.velocity += normal * (impulse * wa * a.inv_mass);
                b.velocity += normal * (impulse * wb * b.inv_mass);
            }
            ++contact_count_;
        }
        material_damping();
        solve_tire_traction(throttle, braking);
        update_wheel_skin();
    }
};

} // namespace boltyard
