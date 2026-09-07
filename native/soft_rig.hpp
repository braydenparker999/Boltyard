#pragma once

// Crawlworks Expedition: deformable XPBD frame, compliant tire contacts,
// tetrahedral axle carriers on triangulated four-links, and coupled
// movable convex obstacles. Legacy valley handling remains on its v0.4 guides.
// SI units. The 16 frame/cab particles, four wheel assemblies and four
// internal axle-carrier mass nodes (crawl/exploration modes) carry
// mass, gravity, suspension loads, contact traction and collision impulses.
// The 80 sidewall samples preserve render bindings; they follow the round tire
// contact model and are not independently integrated mass nodes. Structural
// beams still yield and break, so impacts permanently deform the actual body.
// Bounded mobile model: no self-contact, fluid mud, detailed clutch/transmission,
// or full tire finite elements. Bounded contact patches deform a compliant rubber
// envelope; the hub/rim remains rigid. Pressure changes carcass and shear compliance.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>
#include <unordered_map>
#include <cstdint>
#include <cstring>
#include "terrain_v03.hpp"
#include "expedition_terrain.hpp"

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
#include "imported_scenery.hpp"
#include "expedition_rocks.hpp"
#include "dynamic_objects.hpp"

struct Config {
    float tire_radius = 0.46f;       // m, overall unloaded radius
    float tire_pressure = 1.0f;     // relative pressure, 1 = trail baseline (uncalibrated)
    float spring_rate = 30000.0f;   // N/m per corner
    float damping = 3000.0f;        // N s/m damping coefficient per corner
    float ride_height = 0.35f;      // m from frame underside to unloaded hub
    float engine_torque = 450.0f;   // N m engine torque before reduction
    bool low_range = true;
    bool locked_diffs = true;       // compatibility master; set_drivetrain updates both axles
    bool front_locked = true;
    bool rear_locked = true;
    bool solid_axles = true;        // coupled four-link geometry in crawl/exploration modes
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
    float wheel_accessory_mass = 0;// kg included in total mass, divided across unsprung hubs
    float compression_damping = 0; // N s/m; zero inherits damping
    float rebound_damping = 0;     // N s/m; zero inherits damping
    float compression_travel = 0;  // m; zero inherits legacy compression allowance
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
    static constexpr int max_tire_patches = 6;
    struct TirePatch {
        Vec3 normal, point, shear; // world-space plane and elastic tangent displacement
        float load=0, compression=0, half_length=0, half_width=0, friction=0;
        int surface=0, dynamic_body=-1;
    };
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
        cfg_.wheel_accessory_mass = safe_clamp(input.wheel_accessory_mass, -40, 240, 0);
        cfg_.compression_damping = safe_clamp(input.compression_damping, 0, 9000, 0);
        cfg_.rebound_damping = safe_clamp(input.rebound_damping, 0, 12000, 0);
        cfg_.compression_travel = safe_clamp(input.compression_travel, 0, .45f, 0);
        if (!input.locked_diffs && input.front_locked && input.rear_locked) cfg_.front_locked = cfg_.rear_locked = false;
        reset();
    }
    const Config &config() const { return cfg_; }
    void set_drivetrain(bool low_range, bool locked_diffs) {
        cfg_.low_range = low_range;
        cfg_.locked_diffs = locked_diffs;
        cfg_.front_locked = cfg_.rear_locked = locked_diffs;
    }
    void set_drivetrain(bool low_range, bool front_locked, bool rear_locked) {
        cfg_.low_range = low_range;
        cfg_.front_locked = front_locked;
        cfg_.rear_locked = rear_locked;
        cfg_.locked_diffs = front_locked && rear_locked;
    }

    void reset(Vec3 origin = {0, 1.5f, 8}) {
        if (!origin.finite()) origin = {0, 1.5f, 8};
        particles.clear(); beams.clear(); rest_positions.clear();
        accumulator_ = 0; steering_ = 0; contact_count_ = 0;
        velocity_limit_count_ = 0; nonfinite_count_ = 0; dropped_time_ = 0;
        wheel_contact_counts_.fill(0); wheel_spin_.fill(0); wheel_phase_.fill(0); wheel_slip_.fill(0);
        near_rocks_.clear(); rock_lambdas_.clear();
        for(auto &c:wheel_manifolds_)c.clear();
        wheel_shear_.fill({});
        dynamic_objects_.set_terrain(terrain_mode_); dynamic_objects_.reset(); near_dynamic_.clear(); dynamic_lambdas_.clear();
        const float frame_x = cfg_.track_width * 0.38f;
        const float frame_z = cfg_.wheelbase * 0.50f;
        const bool suv = cfg_.vehicle_type == 1;
        const bool buggy = cfg_.vehicle_type == 2;
        const float base_mass = cfg_.mass - cfg_.front_accessory_mass - cfg_.roof_accessory_mass - cfg_.wheel_accessory_mass;
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
        const float tire_node_mass = (base_mass * tire_share + cfg_.wheel_accessory_mass) / (4 * nodes_per_wheel);
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
        if (solid_axles_active()) initialize_axle_carriers();
        contact_lambdas_.assign(particles.size(), 0);
        friction_offsets_.assign(particles.size(), Vec3{});
        contact_normals_.assign(particles.size(), Vec3(0, 1, 0));
        for (const auto &p : particles) rest_positions.push_back(p.pos);
        nearby_obstacles_.clear(); obstacle_lambdas_.clear(); obstacle_friction_.clear(); obstacle_normals_.clear();
        beam_contact_lambdas_.clear(); beam_contact_t_.clear(); beam_contact_normals_.clear();
    }

    // Recovery is a rigid relocation of the existing damaged rig, never reset().
    // Search clear, gently sloped ground near the request; reject occupied sites.
    bool recover_near(Vec3 requested, Vec3 heading) {
        if (!requested.finite() || !heading.finite() || particles.size()<8) return false;
        Vec3 old_center=center(), old_f=forward(), old_r=right_raw().normalized();
        Vec3 old_u=old_r.cross(old_f).normalized(); old_r=old_f.cross(old_u).normalized();
        heading.y=0; if(heading.length_squared()<.01f)heading={0,0,-1};
        Vec3 f=heading.normalized(), u{0,1,0}, r=f.cross(u);
        std::vector<Vec3> offsets; CrawlRock::Bounds local;
        for(const auto&p:particles){Vec3 d=p.pos-old_center;Vec3 q=r*d.dot(old_r)+u*d.dot(old_u)+f*d.dot(old_f);offsets.push_back(q);local.add(q);}
        const float pad=cfg_.tire_radius+.18f;
        const auto& rocks=custom_rocks_?test_rocks_:(terrain_mode_>=4?expedition_rocks(terrain_mode_):crawl_course());
        auto overlaps=[](const CrawlRock::Bounds&a,const CrawlRock::Bounds&b){return a.low.x<=b.high.x&&a.high.x>=b.low.x&&a.low.y<=b.high.y&&a.high.y>=b.low.y&&a.low.z<=b.high.z&&a.high.z>=b.low.z;};
        for(int ring=0;ring<=4;++ring)for(int direction=0;direction<(ring?12:1);++direction){
            float angle=direction*6.2831853f/12;
            Vec3 at=requested+Vec3(std::sin(angle)*ring*3,0,std::cos(angle)*ring*3);
            float limit=terrain_mode_==7?1014.f:(terrain_mode_>=4?310.f:360.f);
            if(std::abs(at.x)>limit||std::abs(at.z)>limit)continue;
            float lo=1e9f,hi=-1e9f;
            // Sample the full footprint, including the spaces between the wheels.
            for(int z=0;z<=6;++z)for(int x=0;x<=4;++x){
                float px=at.x+local.low.x-pad+(local.high.x-local.low.x+2*pad)*x/4;
                float pz=at.z+local.low.z-pad+(local.high.z-local.low.z+2*pad)*z/6;
                float h=terrain_height(px,pz);lo=std::min(lo,h);hi=std::max(hi,h);
            }
            if(!std::isfinite(hi)||hi-lo>.65f)continue;
            at.y=-1e9f;
            for(size_t i=0;i<particles.size();++i){
                float radius=particles[i].wheel>=0&&!particles[i].tire?cfg_.tire_radius:particles[i].radius;
                at.y=std::max(at.y,terrain_height(at.x+offsets[i].x,at.z+offsets[i].z)+radius+.12f-offsets[i].y);
            }
            CrawlRock::Bounds box;
            box.low=at+local.low-Vec3(pad,pad,pad);box.high=at+local.high+Vec3(pad,pad,pad);
            bool occupied=false;
            if(custom_rocks_||terrain_mode_>=3)for(const auto&rock:rocks){
                CrawlRock::Bounds bounds;
                if(!rock.query_nodes.empty())bounds=rock.query_nodes[0].bounds;
                else for(const auto&v:rock.vertices)bounds.add(v);
                if(overlaps(box,bounds)){
                    if(rock.surface_mesh){
                        for(size_t i=0;i<particles.size();++i){float radius=particles[i].wheel>=0?cfg_.tire_radius:particles[i].radius;
                            if(rock_distance(rock,at+offsets[i]).distance<radius+.18f){occupied=true;break;}}
                    }else occupied=true;
                    if(occupied)break;
                }
            }
            if(occupied)continue;
            if(terrain_mode_==2||terrain_mode_>=4){
                const auto&obs=terrain_mode_>=4?expedition_obstacles(terrain_mode_):exploration_obstacles();
                for(const auto&o:obs){float h=terrain_height(o.x,o.z);CrawlRock::Bounds b;b.low={o.x-o.radius,h,o.z-o.radius};b.high={o.x+o.radius,h+o.height,o.z+o.radius};if(overlaps(box,b)){occupied=true;break;}}
            }
            if(occupied)continue;
            for(const auto&body:dynamic_objects_.bodies()){
                CrawlRock::Bounds b;Vec3 extent{body.shape.reach,body.shape.reach,body.shape.reach};b.low=body.position-extent;b.high=body.position+extent;
                if(overlaps(box,b)){occupied=true;break;}
            }
            if(occupied)continue;
            for(size_t i=0;i<particles.size();++i){particles[i].pos=particles[i].prev=at+offsets[i];particles[i].velocity={};}
            accumulator_=0; wheel_spin_.fill(0);wheel_slip_.fill(0);wheel_shear_.fill({});wheel_contact_counts_.fill(0);contact_count_=0;
            for(auto&c:wheel_manifolds_)c.clear();
            find_nearby_obstacles();
            return true;
        }
        return false;
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

    void set_terrain(int mode) {
        const bool was_solid = solid_axles_active();
        terrain_mode_ = std::clamp(mode, 0, 7);
        dynamic_objects_.set_terrain(terrain_mode_);
        for(auto &c:wheel_manifolds_)c.clear();
        wheel_shear_.fill({});
        if (was_solid == solid_axles_active()) return;
        if (solid_axles_active()) initialize_axle_carriers();
        else if (particles.size() > 100) {
            // Return the same allocated axle mass to its wheel assemblies when
            // entering a legacy map; no mass is added or removed by map choice.
            for (int w = 0; w < 4; ++w) {
                float total = 1 / dynamic_inv_mass(particles[wheel_hubs[w]]) + carrier_mass_[w / 2];
                for (int j = 0; j < nodes_per_wheel; ++j) particles[wheel_hubs[w]+j].inv_mass = nodes_per_wheel / total;
            }
            particles.resize(100); rest_positions.resize(100);
        }
        contact_lambdas_.assign(particles.size(), 0); friction_offsets_.assign(particles.size(), {});
        contact_normals_.assign(particles.size(), {0,1,0});
        near_rocks_.clear(); nearby_obstacles_.clear(); near_dynamic_.clear();
    }
    int get_terrain_mode() const { return terrain_mode_; }
    float terrain_height(float x, float z) const {
        if ((terrain_mode_ == 0 || terrain_mode_ == 3) || !std::isfinite(x) || !std::isfinite(z)) return 0;
        if (terrain_mode_ >= 4) return expedition_height(terrain_mode_, x, z);
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
        if (terrain_mode_ >= 4) { const auto n=expedition_normal(terrain_mode_,x,z); return {n.x,n.y,n.z}; }
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
        if (terrain_mode_ >= 4) return expedition_surface(terrain_mode_,x,z);
        if (terrain_mode_ == 2) return exploration_surface(x, z);
        if (terrain_mode_ == 1 && z < -7 && z > -15) return 0.72f;
        return 1.0f;
    }

    void set_test_rocks(const std::vector<CrawlRock>& rocks) {
        test_rocks_=rocks;for(auto&r:test_rocks_)r.rebuild_queries();
        custom_rocks_=true; dynamic_objects_.set_static_rocks(test_rocks_);
    }
    DynamicObjects &dynamic_objects() { return dynamic_objects_; }
    const DynamicObjects &dynamic_objects() const { return dynamic_objects_; }
    std::vector<TirePatch> wheel_contact_patches(int w) const {
        std::vector<TirePatch> out;
        if(!valid_wheel(w))return out;
        for(const auto &c:tire_contacts(w)) {
            const float load=c.lambda/(fixed_dt*fixed_dt), depth=std::min(cfg_.tire_radius*.42f,load/tire_stiffness());
            const float length=std::sqrt(std::max(0.f,2*cfg_.tire_radius*depth-depth*depth));
            Vec3 shear=c.patch_index>=0?c.shear:wheel_shear_[w];
            shear-=c.normal*shear.dot(c.normal);
            out.push_back({c.normal,c.point,shear,load,depth,length,tire_width_*.5f,c.mu,c.surface,c.dynamic_body});
        }
        std::sort(out.begin(),out.end(),[](const TirePatch&a,const TirePatch&b){return a.load>b.load;});
        if(out.size()>max_tire_patches)out.resize(max_tire_patches);
        return out;
    }
    float wheel_load(int w) const { float load=0; for(const auto& c: tire_contacts(w)) load += c.normal.y*c.lambda/(fixed_dt*fixed_dt); return load; }
    float wheel_rock_load(int w) const { float load=0; for(const auto& c: tire_contacts(w)) if(c.rock)load += c.normal.y*c.lambda/(fixed_dt*fixed_dt); return load; }
    float wheel_slip(int w) const { return w >= 0 && w < 4 ? wheel_slip_[w] : 0; }
    float wheel_normal_load(int w) const {
        float load = 0;
        if (w >= 0 && w < 4) for (const auto &c : tire_contacts(w)) load += c.lambda / (fixed_dt * fixed_dt);
        return load;
    }
    float wheel_compression(int w) const {
        // Parallel contacts share one carcass. Report the deepest loaded patch,
        // rather than summing indentations against unrelated surface normals.
        float compression = 0;
        if (w >= 0 && w < 4) for (const auto &c : tire_contacts(w))
            compression = std::max(compression, c.lambda / (fixed_dt * fixed_dt * tire_stiffness()));
        return std::clamp(compression, 0.f, cfg_.tire_radius * .65f);
    }
    float wheel_contact_patch_length(int w) const {
        float d = wheel_compression(w), radius = cfg_.tire_radius;
        return 2 * std::sqrt(std::max(0.f, 2 * radius * d - d * d));
    }
    Vec3 wheel_contact_normal(int w) const {
        Vec3 result(0, 1, 0); float strongest = 0;
        if (w >= 0 && w < 4) for (const auto &c : tire_contacts(w))
            if (c.lambda > strongest) { strongest = c.lambda; result = c.normal; }
        return result;
    }
    Vec3 wheel_contact_point(int w) const {
        if (w < 0 || w > 3) return {};
        Vec3 result = particles[wheel_hubs[w]].pos - up() * cfg_.tire_radius; float strongest = 0;
        for (const auto &c : tire_contacts(w))
            if (c.lambda > strongest) { strongest = c.lambda; result = c.point; }
        return result;
    }
    Vec3 wheel_axle_direction(int w) const { return w >= 0 && w < 4 ? wheel_axis(w) : right(); }
    Vec3 suspension_link_start(int w) const { return valid_wheel(w) ? (solid_axles_active() ? attachment_position(lower_frame_[w]) : particles[w].pos) : Vec3{}; }
    Vec3 suspension_link_end(int w) const { return valid_wheel(w) ? (solid_axles_active() ? attachment_position(lower_axle_[w]) : particles[wheel_hubs[w]].pos) : Vec3{}; }
    Vec3 upper_link_start(int w) const { return valid_wheel(w) ? (solid_axles_active() ? attachment_position(upper_frame_[w]) : particles[w+4].pos) : Vec3{}; }
    Vec3 upper_link_end(int w) const { return valid_wheel(w) ? (solid_axles_active() ? attachment_position(upper_axle_[w]) : particles[wheel_hubs[w]].pos) : Vec3{}; }
    Vec3 shock_start(int w) const { return valid_wheel(w) ? (solid_axles_active() ? attachment_position(shock_frame_[w]) : particles[w+4].pos) : Vec3{}; }
    Vec3 shock_end(int w) const { return valid_wheel(w) ? (solid_axles_active() ? attachment_position(shock_axle_[w]) : particles[wheel_hubs[w]].pos) : Vec3{}; }
    float shock_length(int w) const { return (shock_end(w)-shock_start(w)).length(); }
    float shock_rest_length(int w) const { return valid_wheel(w)&&solid_axles_active()?coilovers_[w].rest:shock_length(w); }
    float shock_max_length(int w) const { return shock_rest_length(w)+cfg_.suspension_travel; }
    float shock_min_length(int w) const {
        // A single telescoping damper must house its whole stroke plus eyes
        // and piston overlap. Limit bump by real packaging, not stretched art.
        return std::max(shock_rest_length(w)-compression_allowance(),(shock_max_length(w)+.18f)*.5f);
    }
    float shock_body_length(int w) const { return shock_min_length(w)-.10f; }
    // Compatibility endpoints: the triangulated upper pair provides lateral
    // location, so the new model does not add an overconstraining Panhard bar.
    Vec3 panhard_start(int axle) const { return upper_link_start(axle*2); }
    Vec3 panhard_end(int axle) const { return upper_link_end(axle*2); }
    Vec3 axle_up(int axle) const {
        if (axle < 0 || axle > 1 || !solid_axles_active()) return up();
        Vec3 center = (particles[wheel_hubs[axle*2]].pos + particles[wheel_hubs[axle*2+1]].pos)*.5f;
        Vec3 lateral = (particles[wheel_hubs[axle*2+1]].pos-particles[wheel_hubs[axle*2]].pos).normalized();
        Vec3 top = particles[100+axle*2].pos-center;
        return (top-lateral*top.dot(lateral)).normalized();
    }
    Vec3 axle_pinion(int axle) const {
        if (axle < 0 || axle > 1) return {};
        Vec3 center = (particles[wheel_hubs[axle*2]].pos+particles[wheel_hubs[axle*2+1]].pos)*.5f;
        Vec3 lateral = (particles[wheel_hubs[axle*2+1]].pos-particles[wheel_hubs[axle*2]].pos).normalized();
        Vec3 rearward = lateral.cross(axle_up(axle)).normalized();
        return center + rearward * (axle==0 ? .24f : -.24f);
    }
    Vec3 transfer_case(int axle) const {
        if(axle<0||axle>1)return {};
        return attachment_position(frame_mount(0,-.045f,axle==0?-.15f:.15f));
    }
    float axle_pitch(int axle) const { Vec3 u=axle_up(axle); return std::atan2(u.dot(forward()),u.dot(up())); }
    float suspension_link_error() const {
        float maximum=0; if (solid_axles_active()) for(const auto &c: four_links_)
            maximum=std::max(maximum,std::abs(constraint_delta(c).length()-c.rest));
        return maximum;
    }
    float wheel_unsprung_mass(int w) const {
        return w >= 0 && w < 4 ? 1 / dynamic_inv_mass(particles[wheel_hubs[w]]) + (solid_axles_active() ? carrier_mass_[w / 2] : 0) : 0;
    }
    float axle_articulation(int axle) const {
        if (axle < 0 || axle > 1) return 0;
        Vec3 axis = (particles[wheel_hubs[axle * 2 + 1]].pos - particles[wheel_hubs[axle * 2]].pos).normalized();
        return std::atan2(axis.dot(up()), axis.dot(right())); // radians relative to frame
    }
    float axle_clearance(int axle) const {
        if (axle < 0 || axle > 1) return 0;
        float clearance = std::numeric_limits<float>::max();
        for (int sample = 0; sample < 5; ++sample) {
            float t = .15f + sample * .175f, radius = sample == 2 ? .13f : .065f;
            Vec3 p = particles[wheel_hubs[axle * 2]].pos * (1 - t) + particles[wheel_hubs[axle * 2 + 1]].pos * t;
            clearance = std::min(clearance, (p.y - terrain_height(p.x, p.z)) * terrain_normal(p.x, p.z).y - radius);
            for (const auto *rock : near_rocks_) clearance = std::min(clearance, rock_distance(*rock, p).distance - radius);
            for (int id : near_dynamic_) clearance = std::min(clearance, dynamic_objects_.distance(id, p).distance - radius);
        }
        return clearance;
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
    int node_count() const { return 100; }
    int physical_node_count() const { return solid_axles_active() ? 24 : 20; }
    int physical_beam_count() const {
        int count = solid_axles_active() ? 20 : 0;
        for (const auto &b : beams) if (b.kind != TIRE) ++count;
        return count;
    }
    int render_node_count() const { return 100; }
    float steering_angle() const { return steering_; }
    Vec3 velocity() const { return linear_velocity(); }
    int beam_count() const { return int(beams.size()); }
    float wheel_angular_velocity(int wheel) const {
        if (wheel < 0 || wheel > 3) return 0;
        return wheel_spin_[wheel];
    }
    float wheel_rotation_angle(int wheel) const { return wheel >= 0 && wheel < 4 ? wheel_phase_[wheel] : 0; }
    float suspension_travel(int wheel) const {
        if (wheel < 0 || wheel > 3) return 0;
        if (solid_axles_active()) return coilovers_[wheel].rest - shock_length(wheel);
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
    struct TireContact {Vec3 normal, point; float lambda, mu; bool rock; int dynamic_body = -1, surface=0; Vec3 shear{}; int patch_index=-1;};
    struct WheelSurfaceContact {
        Vec3 normal, point, friction, shear;
        float lambda=0, gap=0, width_sample=0, longitudinal_sample=0, mu=1;
        int rock=-1, surface=0;
    };
    std::array<std::vector<WheelSurfaceContact>,4> wheel_manifolds_;
    std::array<Vec3,4> wheel_shear_{};
    DynamicObjects dynamic_objects_;
    std::vector<int> near_dynamic_;
    std::vector<float> dynamic_lambdas_;
    std::vector<Vec3> dynamic_normals_, dynamic_points_, dynamic_friction_;
    std::vector<float> moving_support_lambdas_;
    std::vector<Vec3> moving_support_normals_, moving_support_points_, moving_support_friction_;
    std::vector<CrawlRock> test_rocks_;
    bool custom_rocks_=false;
    std::vector<const CrawlRock*> near_rocks_;
    std::vector<float> rock_lambdas_,skid_lambdas_;
    std::vector<Vec3> skid_friction_;
    std::vector<Vec3> rock_normals_,rock_points_,rock_friction_;
    std::array<float,4> wheel_slip_{};
    bool solid_axles_active() const { return terrain_mode_ >= 3 && cfg_.solid_axles; }
    float tire_stiffness() const { return 300000.f * cfg_.tire_pressure; }
    bool axle_locked(int w) const { return w < 2 ? cfg_.front_locked : cfg_.rear_locked; }
    float tire_mu(float surface) const {
        // Rubber compound and the contacted material set Coulomb capacity.
        // Lower pressure changes footprint/shear compliance, never a grip bonus.
        return 1.18f*cfg_.tire_grip*surface*(terrain_mode_>=3?1.f:std::clamp(1.05f-.1f*(cfg_.tire_pressure-1),.88f,1.12f));
    }
    float wood_surface(Vec3 point) const {
        return .82f-(terrain_mode_>=4?.24f*expedition_material(terrain_mode_,point.x,point.z).wet:0.f);
    }
    std::vector<TireContact> tire_contacts(int w) const {
        std::vector<TireContact> out; if(!valid_wheel(w))return out;
        const int h=wheel_hubs[w];const auto&p=particles[h];
        if(terrain_mode_>=3)for(int i=0;i<int(wheel_manifolds_[w].size());++i) {
            const auto &c=wheel_manifolds_[w][i];if(c.lambda>1e-8f)
                out.push_back({c.normal,c.point,c.lambda,c.mu,c.rock>=0,-1,c.surface,c.shear,i});
        }
        if(contact_lambdas_[h]>1e-8f)out.push_back({contact_normals_[h],p.pos-contact_normals_[h]*(cfg_.tire_radius-contact_lambdas_[h]/(fixed_dt*fixed_dt*300000*cfg_.tire_pressure)),contact_lambdas_[h],tire_mu(terrain_surface(p.pos.x,p.pos.z)),false});
        for(size_t k=0;k<nearby_obstacles_.size();++k){size_t pair=k*particles.size()+h;if(obstacle_lambdas_[pair]>1e-8f)out.push_back({obstacle_normals_[pair],p.pos-obstacle_normals_[pair]*cfg_.tire_radius,obstacle_lambdas_[pair],tire_mu(terrain_mode_>=3?wood_surface(p.pos-obstacle_normals_[pair]*cfg_.tire_radius):1.f),true,-1,terrain_mode_>=3?5:0});}
        for(size_t k=0;k<near_rocks_.size();++k){size_t pair=k*particles.size()+h;if(rock_lambdas_[pair]>1e-8f)out.push_back({rock_normals_[pair],rock_points_[pair],rock_lambdas_[pair],tire_mu(near_rocks_[k]->surface),true});}
        for (size_t k = 0; k < near_dynamic_.size(); ++k) {
            const size_t pair = k * particles.size() + h;
            if (dynamic_lambdas_[pair] > 1e-8f)
                out.push_back({dynamic_normals_[pair], dynamic_points_[pair], dynamic_lambdas_[pair], tire_mu(dynamic_objects_.tire_surface(near_dynamic_[k],dynamic_points_[pair])), true, near_dynamic_[k], dynamic_objects_.surface_material(near_dynamic_[k],dynamic_points_[pair])});
        }
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
    // Attachment coordinates are affine combinations of real mass nodes.
    // Every internal constraint therefore applies equal/opposite force and
    // torque at its actual endpoints, including carrier pitch and frame flex.
    struct Attachment { std::array<int,8> nodes{}; std::array<float,8> weights{}; int count=0; };
    struct MountConstraint { std::array<int,12> nodes{}; std::array<float,12> weights{}; int count=0; float rest=0, lambda=0; };
    std::array<float,2> carrier_mass_{};
    std::array<Attachment,4> lower_frame_, lower_axle_, upper_frame_, upper_axle_, shock_frame_, shock_axle_;
    std::array<MountConstraint,8> four_links_;
    std::array<MountConstraint,4> coilovers_;
    std::array<MountConstraint,12> carrier_edges_;
    std::array<float, 4> spring_stop_lambdas_{};
    std::vector<float> axle_contact_lambdas_;
    std::vector<Vec3> axle_contact_friction_;
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
        if (solid_axles_active()) {
            int left = (wheel / 2) * 2;
            r = (particles[wheel_hubs[left + 1]].pos - particles[wheel_hubs[left]].pos).normalized();
            f = axle_up(wheel / 2).cross(r).normalized();
        }
        // Positive steering turns right. Positive axle rotation rolls backward.
        float angle = wheel < 2 ? steering_ : 0;
        return (r * std::cos(angle) - f * std::sin(angle)).normalized();
    }
    void apply_axle_angular_impulse(int axle, Vec3 angular_impulse) {
        if(!solid_axles_active())return;
        const std::array<int,4> ids{wheel_hubs[axle*2],wheel_hubs[axle*2+1],100+axle*2,101+axle*2};
        Vec3 center; float mass=0;
        for(int id:ids){float m=1/dynamic_inv_mass(particles[id]);center+=particles[id].pos*m;mass+=m;} center*=1/mass;
        float xx=0,yy=0,zz=0,xy=0,xz=0,yz=0;
        for(int id:ids){float m=1/dynamic_inv_mass(particles[id]);Vec3 r=particles[id].pos-center;
            xx+=m*(r.y*r.y+r.z*r.z);yy+=m*(r.x*r.x+r.z*r.z);zz+=m*(r.x*r.x+r.y*r.y);
            xy-=m*r.x*r.y;xz-=m*r.x*r.z;yz-=m*r.y*r.z;}
        const Vec3 row0{xx,xy,xz},row1{xy,yy,yz},row2{xz,yz,zz};
        const float determinant=row0.dot(row1.cross(row2));if(std::abs(determinant)<1e-8f)return;
        const Vec3 omega=(row1.cross(row2)*angular_impulse.x+row2.cross(row0)*angular_impulse.y+row0.cross(row1)*angular_impulse.z)/determinant;
        for(int id:ids)particles[id].velocity+=omega.cross(particles[id].pos-center);
    }
    void solve_tire_traction(float throttle, bool brake) {
        const float forward_speed = linear_velocity().dot(forward());
        const float ratio = (cfg_.low_range ? (terrain_mode_>=3 ? 22.f : 5.5f) : 3.8f) * cfg_.final_drive;
        const float top_speed = (terrain_mode_>=3 && cfg_.low_range ? (throttle<0?1.5f:2.2f) : (throttle < 0 ? 9.0f : (cfg_.low_range ? 16.5f : 31.0f))) / cfg_.final_drive;
        const float demand_speed = std::abs(forward_speed);
        // Flat low-speed torque, then a smooth power/road-speed falloff.
        const float limiter = std::clamp(1.0f - std::pow(demand_speed / top_speed, 3.0f), 0.0f, 1.0f);
        const float engine_force = throttle * cfg_.engine_torque * ratio / (4.0f * cfg_.tire_radius) * limiter;
        std::array<std::vector<TireContact>,4> contacts;
        std::array<float,4> capacity{};
        for(int w=0;w<4;++w){contacts[w]=tire_contacts(w);for(auto c:contacts[w])capacity[w]+=c.mu*c.lambda/(fixed_dt*fixed_dt);}
        for(int w=0;w<4;++w){
            auto&hub=particles[wheel_hubs[w]];float inv=dynamic_inv_mass(hub),inertia=std::max(1.f,.5f/inv*cfg_.tire_radius*cfg_.tire_radius);
            if(brake){float before=wheel_spin_[w];wheel_spin_[w]*=std::exp(-24*fixed_dt);if(!contacts[w].empty())wheel_spin_[w]=0;
                apply_axle_angular_impulse(w/2,wheel_axis(w)*(-(wheel_spin_[w]-before)*inertia));wheel_slip_[w]=0;
                Vec3 brake_shear;for(auto &patch:wheel_manifolds_[w]) {
                    Vec3 target=patch.friction/(fixed_dt*fixed_dt*95000.f*std::sqrt(cfg_.tire_pressure));
                    const float magnitude=target.length();if(magnitude>cfg_.tire_radius*.12f)target*=cfg_.tire_radius*.12f/magnitude;
                    patch.shear+=(target-patch.shear)*(1-std::exp(-fixed_dt/.035f));brake_shear+=target;
                }
                const float size=brake_shear.length();if(size>cfg_.tire_radius*.12f)brake_shear*=cfg_.tire_radius*.12f/size;
                wheel_shear_[w]+=(brake_shear-wheel_shear_[w])*(1-std::exp(-fixed_dt/.035f));continue;}
            float axle_cap=axle_locked(w)?capacity[w]:std::min(capacity[w],capacity[w^1]);
            float force=std::clamp(engine_force,-axle_cap,axle_cap);
            // Crawl range couples angular tire speed to contact impulses.
            // Zero-speed slip is expressed in m/s, avoiding slip-ratio singularities.
            if(terrain_mode_>=3){
                float rotor_speed=std::abs(wheel_spin_[w])*cfg_.tire_radius;
                float rotor_limiter=std::clamp(1.f-std::pow(rotor_speed/top_speed,3.f),-.5f,1.f);
                float torque=throttle*cfg_.engine_torque*ratio*.25f*rotor_limiter;
                if(!axle_locked(w))torque=std::clamp(torque,-axle_cap*cfg_.tire_radius,axle_cap*cfg_.tire_radius);
                const float before=wheel_spin_[w];
                wheel_spin_[w]-=torque/inertia*fixed_dt;
                if(std::abs(throttle)<.001f){float drag=std::min(std::abs(wheel_spin_[w]),35.f*ratio*.25f/inertia*fixed_dt);wheel_spin_[w]-=std::copysign(drag,wheel_spin_[w]);}
                apply_axle_angular_impulse(w/2,wheel_axis(w)*(-(wheel_spin_[w]-before)*inertia));
            }
            float spin=0,weight=0;wheel_slip_[w]=0;Vec3 next_shear;
            for(auto c:contacts[w]){
                Vec3 rolling=c.normal.cross(wheel_axis(w)).normalized();if(rolling.dot(forward())<0)rolling=-rolling;
                Vec3 lateral=rolling.cross(c.normal).normalized();
                const Vec3 relative_velocity = hub.velocity - (c.dynamic_body >= 0 ? dynamic_objects_.point_velocity(c.dynamic_body, c.point) : Vec3{});
                const float moving_inv = c.dynamic_body >= 0 ? dynamic_objects_.point_inverse_mass(c.dynamic_body, c.point, rolling) : 0;
                const float v = relative_velocity.dot(rolling), lat = relative_velocity.dot(lateral);
                float share=c.mu*c.lambda/(fixed_dt*fixed_dt*std::max(capacity[w],1e-6f));
                float longitudinal=force*share*fixed_dt;
                float resistance=std::min(std::abs(v)*cfg_.mass*.25f, cfg_.mass*.25f*(.10f+.0012f*v*v)*fixed_dt)*share;
                longitudinal-=std::copysign(resistance,v);
                if (terrain_mode_ >= 3) {
                    // Implicit finite tire shear compliance. Slip velocity stays
                    // well-defined at rest; the regularized denominator does not
                    // divide by near-zero road speed. Wheel inertia and reaction
                    // impulse remain coupled, with one friction budget per patch.
                    const float normal_force = c.lambda / (fixed_dt * fixed_dt);
                    const float contact_speed = std::max(.35f, std::max(std::abs(v), std::abs(wheel_spin_[w] * cfg_.tire_radius)));
                    const float depth=normal_force/tire_stiffness();
                    const float patch_length=2*std::sqrt(std::max(0.f,2*cfg_.tire_radius*depth-depth*depth));
                    const float footprint=std::clamp(patch_length/.14f,.65f,1.65f);
                    const float longitudinal_stiffness = 14.f * normal_force / contact_speed * std::sqrt(footprint);
                    longitudinal = -(v + wheel_spin_[w] * cfg_.tire_radius) /
                        (inv + moving_inv + cfg_.tire_radius * cfg_.tire_radius / inertia + 1 / std::max(.001f, longitudinal_stiffness * fixed_dt));
                }
                float lateral_impulse=-lat*cfg_.mass*.25f*std::min(1.f,fixed_dt/.065f)*share;
                if (c.dynamic_body >= 0) {
                    const float lateral_inv = inv + dynamic_objects_.point_inverse_mass(c.dynamic_body, c.point, lateral);
                    lateral_impulse = -lat / lateral_inv * (fixed_dt / (.065f + fixed_dt)) * share;
                }
                Vec3 impulse=rolling*longitudinal+lateral*lateral_impulse;
                float limit=c.mu*c.lambda/fixed_dt,requested=impulse.length();if(requested>limit&&requested>1e-7f)impulse*=limit/requested;
                // A finite shear stiffness turns the actual tangential contact
                // force into rubber deflection; no torque means no invented squirm.
                const float rubber_stiffness=std::max(20000.f,95000.f*std::sqrt(cfg_.tire_pressure)*std::max(.3f,share));
                Vec3 target_shear=impulse*(-1/(fixed_dt*rubber_stiffness));
                const float shear_size=target_shear.length();if(shear_size>cfg_.tire_radius*.12f)target_shear*=cfg_.tire_radius*.12f/shear_size;
                next_shear+=target_shear*share;
                if(c.patch_index>=0) {
                    auto &patch=wheel_manifolds_[w][c.patch_index];
                    patch.shear+=(target_shear-patch.shear)*(1-std::exp(-fixed_dt/.035f));
                }
                hub.velocity+=impulse*inv;
                if (c.dynamic_body >= 0) dynamic_objects_.apply_impulse(c.dynamic_body, c.point, -impulse);
                if(terrain_mode_>=3)wheel_spin_[w]+=impulse.dot(rolling)*cfg_.tire_radius/inertia;
                spin+=(-v/cfg_.tire_radius-std::copysign(std::max(0.f,requested-limit)*cfg_.tire_radius/inertia,throttle))*share;weight+=share;
                wheel_slip_[w]+=std::abs(v+wheel_spin_[w]*cfg_.tire_radius)*share;
            }
            const float relax=1-std::exp(-fixed_dt/.035f);
            wheel_shear_[w]+=(next_shear-wheel_shear_[w])*relax;
            const float shear_limit=cfg_.tire_radius*.12f;
            if(wheel_shear_[w].length()>shear_limit)wheel_shear_[w]*=shear_limit/wheel_shear_[w].length();
            if(terrain_mode_>=3)continue;
            if(weight>0)wheel_spin_[w]=spin/weight;
            else{wheel_spin_[w]+=-throttle*cfg_.engine_torque*ratio*.25f/inertia*fixed_dt;wheel_spin_[w]*=std::exp(-.18f*fixed_dt);wheel_spin_[w]=std::clamp(wheel_spin_[w],-top_speed/cfg_.tire_radius,top_speed/cfg_.tire_radius);}
        }
        // Axle coupling is per axle. Front/rear transfer case remains simplified.
        for (int axle = 0; axle < 4; axle += 2) if (axle_locked(axle)) {
            // Equal hub masses currently imply equal spin inertia. This angular
            // impulse exchanges wheel momentum internally and locks each axle.
            float mean = (wheel_spin_[axle] + wheel_spin_[axle + 1]) * .5f;
            const float blend = terrain_mode_ >= 3 ? 1.f : std::min(1.f, 14 * fixed_dt);
            wheel_spin_[axle] += (mean - wheel_spin_[axle]) * blend;
            wheel_spin_[axle + 1] += (mean - wheel_spin_[axle + 1]) * blend;
        }
    }
    void update_wheel_skin() {
        for (int w = 0; w < 4; ++w) {
            const auto &hub = particles[wheel_hubs[w]];
            const Vec3 axle = wheel_axis(w);
            const Vec3 u = (up() - axle * up().dot(axle)).normalized();
            const Vec3 radial = axle.cross(u).normalized();
            wheel_phase_[w] = std::remainder(wheel_phase_[w] + wheel_spin_[w] * fixed_dt, 6.28318530718f);
            const auto patches = wheel_contact_patches(w);
            for (int side = 0; side < 2; ++side) for (int j = 0; j < tire_segments; ++j) {
                auto &p = particles[wheel_hubs[w] + 1 + side * tire_segments + j];
                const float theta = 6.28318530718f * j / tire_segments + wheel_phase_[w];
                const Vec3 direction=u*std::cos(theta)+radial*std::sin(theta);
                const float side_sign=side==0?-1.f:1.f;
                const Vec3 shoulder=axle*(side_sign*tire_width_*.5f);
                Vec3 outer=hub.pos+shoulder+direction*cfg_.tire_radius;
                Vec3 deformation;float bulge=0;
                for(const auto &c:patches) {
                    const float facing=std::max(0.f,-direction.dot(c.normal));
                    // The carcass bends beyond the smaller tread contact patch.
                    // Compliance follows load and pressure, and fades smoothly
                    // around the shoulder; this is independent of wheel phase.
                    const float support=std::pow(facing,8.f);
                    const Vec3 tangent=outer-c.point-c.normal*(outer-c.point).dot(c.normal);
                    const float reach=std::sqrt(c.half_length*c.half_length+c.half_width*c.half_width)+cfg_.tire_radius*.18f;
                    const float indentation=tangent.length_squared()<reach*reach?std::max(0.f,-(outer-c.point).dot(c.normal)):0.f;
                    deformation+=c.normal*indentation+c.shear*support;
                    bulge=std::max(bulge,c.compression*.52f*support);
                }
                p.prev=p.pos;
                p.pos=hub.pos+shoulder+direction*(cfg_.tire_radius*.88f)+deformation+axle*(side_sign*bulge);
                // A second projection retains simultaneous oppositely angled
                // contacts after tangential rubber shear around a rock corner.
                for(const auto &c:patches) {
                    const float distance=(p.pos+direction*(cfg_.tire_radius*.12f)-c.point).dot(c.normal);
                    const Vec3 offset=p.pos+direction*(cfg_.tire_radius*.12f)-c.point;
                    const Vec3 tangent=offset-c.normal*distance;
                    const float reach=std::sqrt(c.half_length*c.half_length+c.half_width*c.half_width)+cfg_.tire_radius*.18f;
                    if(distance<0&&tangent.length_squared()<reach*reach)p.pos-=c.normal*distance;
                }
                p.velocity=hub.velocity+axle.cross(direction*cfg_.tire_radius)*wheel_spin_[w];
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
    float compression_allowance() const {
        return cfg_.compression_travel > 0 ? std::min(cfg_.compression_travel, cfg_.ride_height * .80f) :
            std::min(cfg_.suspension_travel * (.28f / .22f), cfg_.ride_height * .72f);
    }
    static bool valid_wheel(int w) { return w >= 0 && w < 4; }
    Vec3 attachment_position(const Attachment &a) const {
        Vec3 result; for(int i=0;i<a.count;++i) result+=particles[a.nodes[i]].pos*a.weights[i]; return result;
    }
    Vec3 constraint_delta(const MountConstraint &c) const {
        Vec3 result; for(int i=0;i<c.count;++i) result+=particles[c.nodes[i]].pos*c.weights[i]; return result;
    }
    Attachment frame_mount(float x, float y, float z) const {
        Attachment result; result.count=8;
        const float tx=(x/(cfg_.track_width*.38f)+1)*.5f;
        const float tz=(z/(cfg_.wheelbase*.5f)+1)*.5f;
        const float frame_height=cfg_.vehicle_type==1?.34f:(cfg_.vehicle_type==2?.22f:.30f);
        const float ty=y/frame_height;
        for(int i=0;i<8;++i) { result.nodes[i]=i;
            result.weights[i]=(i%2?tx:1-tx)*((i%4)>=2?tz:1-tz)*(i>=4?ty:1-ty); }
        return result;
    }
    Attachment axle_mount(int axle,float x,float y,float z) const {
        // Carrier tetrahedron: left/right hubs, upper truss point, pinion mass.
        // Coordinates are local to the axle at its unloaded position.
        const float direction=axle==0?1.f:-1.f;
        const float pin=z/(.24f*direction), top=(y+.10f*pin)/.20f;
        Attachment a; a.count=4; a.nodes={wheel_hubs[axle*2],wheel_hubs[axle*2+1],100+axle*2,101+axle*2};
        a.weights={(1-top-pin)*.5f-x/cfg_.track_width,(1-top-pin)*.5f+x/cfg_.track_width,top,pin};
        return a;
    }
    MountConstraint mount_constraint(const Attachment &a,const Attachment &b) const {
        MountConstraint c;
        for(int endpoint=0;endpoint<2;++endpoint) {
            const auto &v=endpoint?b:a;
            for(int i=0;i<v.count;++i) if(std::abs(v.weights[i])>1e-8f) {
                int j=0; while(j<c.count&&c.nodes[j]!=v.nodes[i])++j;
                if(j==c.count) c.nodes[c.count++]=v.nodes[i];
                c.weights[j]+=v.weights[i]*(endpoint?1.f:-1.f);
            }
        }
        c.rest=constraint_delta(c).length(); return c;
    }
    void initialize_axle_carriers() {
        if(particles.size()>100) return;
        const Vec3 frame_up=up(), rearward=-forward();
        for(int axle=0;axle<2;++axle) {
            int left=wheel_hubs[axle*2], right_hub=wheel_hubs[axle*2+1];
            Vec3 center=(particles[left].pos+particles[right_hub].pos)*.5f;
            const float wheel_mass=1/dynamic_inv_mass(particles[left]);
            carrier_mass_[axle]=(wheel_mass-cfg_.wheel_accessory_mass*.25f)*.24f;
            for(int side=0;side<2;++side) {
                int hub=wheel_hubs[axle*2+side];
                const float remaining=1/dynamic_inv_mass(particles[hub])-carrier_mass_[axle];
                for(int j=0;j<nodes_per_wheel;++j) particles[hub+j].inv_mass=nodes_per_wheel/remaining;
            }
            int top=add_particle(center+frame_up*.20f,carrier_mass_[axle],.055f,-1,false);
            int pin=add_particle(center-frame_up*.10f+rearward*(axle==0?.24f:-.24f),carrier_mass_[axle],.055f,-1,false);
            particles[top].velocity=particles[pin].velocity=(particles[left].velocity+particles[right_hub].velocity)*.5f;
            const std::array<int,4> nodes{left,right_hub,top,pin}; int edge=0;
            for(int i=0;i<4;++i)for(int j=i+1;j<4;++j) {
                Attachment a,b; a.count=b.count=1; a.nodes[0]=nodes[i]; b.nodes[0]=nodes[j]; a.weights[0]=b.weights[0]=1;
                carrier_edges_[axle*6+edge++]=mount_constraint(a,b);
            }
        }
        for(int w=0;w<4;++w) {
            int axle=w/2; const float side=w%2?1.f:-1.f,direction=axle==0?1.f:-1.f;
            float z=-direction*cfg_.wheelbase*.5f;
            lower_frame_[w]=frame_mount(side*cfg_.track_width*.30f,-.015f,z+direction*cfg_.wheelbase*.34f);
            lower_axle_[w]=axle_mount(axle,side*cfg_.track_width*.35f,-.06f,direction*.03f);
            upper_frame_[w]=frame_mount(side*cfg_.track_width*.32f,.145f,z+direction*cfg_.wheelbase*.29f);
            upper_axle_[w]=axle_mount(axle,side*cfg_.track_width*.065f,.17f,0);
            // Raise the actual tower when a long-stroke package needs room. This
            // preserves requested bump/droop instead of silently removing travel.
            const float tower_height=std::max(cfg_.vehicle_type==2?.32f:.40f,
                2*compression_allowance()+cfg_.suspension_travel+.215f-cfg_.ride_height);
            shock_frame_[w]=frame_mount(side*cfg_.track_width*.39f,tower_height,z+direction*.10f);
            shock_axle_[w]=axle_mount(axle,side*cfg_.track_width*.405f,.035f,direction*.02f);
            four_links_[w]=mount_constraint(lower_frame_[w],lower_axle_[w]);
            four_links_[w+4]=mount_constraint(upper_frame_[w],upper_axle_[w]);
            coilovers_[w]=mount_constraint(shock_frame_[w],shock_axle_[w]);
        }
        // reset() fills all rest positions afterward; mode transitions append
        // the four carrier bind positions without changing the skin's first100.
        if(!rest_positions.empty()) for(int i=100;i<104;++i) rest_positions.push_back(particles[i].pos);
    }
    void solve_mount(MountConstraint &c,float target,float compliance,float &lambda,bool compression_only=false) {
        Vec3 delta=constraint_delta(c); const float length=delta.length(); if(length<1e-7f)return;
        float inv=0; for(int i=0;i<c.count;++i)inv+=c.weights[i]*c.weights[i]*dynamic_inv_mass(particles[c.nodes[i]]);
        const float alpha=compliance/(fixed_dt*fixed_dt);
        float dl=(-(length-target)-alpha*lambda)/(inv+alpha);
        if(compression_only)dl=std::max(0.f,lambda+dl)-lambda;
        lambda+=dl; const Vec3 impulse=delta*(dl/length);
        for(int i=0;i<c.count;++i)particles[c.nodes[i]].pos+=impulse*(c.weights[i]*dynamic_inv_mass(particles[c.nodes[i]]));
    }
    void damp_mount(const MountConstraint &c,float damping) {
        const Vec3 axis=constraint_delta(c).normalized(); Vec3 relative; float inv=0;
        for(int i=0;i<c.count;++i) { relative+=particles[c.nodes[i]].velocity*c.weights[i]; inv+=c.weights[i]*c.weights[i]*dynamic_inv_mass(particles[c.nodes[i]]); }
        // Exact viscous decay for this attachment's effective mass, rather
        // than backward-Euler underdamping of stiff rebound settings.
        const float impulse=inv>1e-8f?relative.dot(axis)*std::expm1(-damping*fixed_dt*inv)/inv:0.f;
        for(int i=0;i<c.count;++i)particles[c.nodes[i]].velocity+=axis*(impulse*c.weights[i]*dynamic_inv_mass(particles[c.nodes[i]]));
    }
    void solve_solid_axles() {
        // Six finite-stiffness edges make each four-point carrier rigid in all
        // three axes. Four real links leave heave and articulation free while
        // controlling lateral location, wheelbase motion and pinion rotation.
        for(auto &c:carrier_edges_) solve_mount(c,c.rest,1.f/80000000.f,c.lambda);
        for(auto &c:four_links_) solve_mount(c,c.rest,1.f/18000000.f,c.lambda);
        for(int w=0;w<4;++w) {
            auto &c=coilovers_[w];
            solve_mount(c,c.rest,1.f/cfg_.spring_rate,c.lambda,true);
            const float length=constraint_delta(c).length(), low=shock_min_length(w), high=shock_max_length(w);
            if(length<low || length>high) {
                // Progressive jounce bumper / extension strap, then a firm
                // mechanical stop. The rest length remains the real shock eye
                // distance, not the vertical chassis-to-hub approximation.
                float penetration=length<low?low-length:length-high;
                float rate=180000.f+4320000.f*smoothstep(0,.045f,penetration);
                solve_mount(c,std::clamp(length,low,high),1.f/rate,spring_stop_lambdas_[w]);
            }
        }
    }
    void solve_suspension() {
        if (solid_axles_active()) { solve_solid_axles(); return; }
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
            const float upper = -cfg_.ride_height + compression_allowance();
            if (vertical < lower || vertical > upper) {
                float stop_lambda = 0;
                solve_axis(w, hub, u, std::clamp(vertical, lower, upper), 1.0f / 4500000.0f, stop_lambda);
            }

        }
    }
    WheelSurfaceContact query_wheel_surface(int w,int rock,float across,float along) const {
        WheelSurfaceContact c;c.rock=rock;c.width_sample=across;c.longitudinal_sample=along;
        const auto &hub=particles[wheel_hubs[w]];
        const Vec3 axle=wheel_axis(w), radial_forward=(forward()-axle*forward().dot(axle)).normalized();
        const Vec3 line_center=hub.pos+axle*across;
        const Vec3 query=line_center+radial_forward*along;
        if(rock<0) {
            c.normal=terrain_normal(query.x,query.z);
            c.point={query.x,terrain_height(query.x,query.z),query.z};
            // Circular longitudinal slice: a crest loads the actual tread arc.
            const float support=std::sqrt(std::max(0.f,cfg_.tire_radius*cfg_.tire_radius-along*along));
            c.gap=(query-c.point).dot(c.normal)-support;
            c.mu=tire_mu(terrain_surface(c.point.x,c.point.z));
            c.surface=terrain_mode_>=4?expedition_surface_material(terrain_mode_,c.point.x,c.point.z):0;
        } else {
            const auto &r=*near_rocks_[rock];
            if(r.surface_mesh && r.query_nodes[0].bounds.distance_squared(query)>(cfg_.tire_radius+.1f)*(cfg_.tire_radius+.1f)){c.gap=1.f;return c;}
            auto hit=rock_distance(r,query);
            c.normal=hit.normal;c.point=hit.point;
            // Support of the real radial disc avoids a full-radius side sphere.
            const float axial=c.normal.dot(axle);
            const float support=std::max(.055f,cfg_.tire_radius*std::sqrt(std::max(0.f,1-axial*axial)));
            c.gap=(line_center-hit.point).dot(c.normal)-support;
            // A sampled face cannot act as an infinite plane beyond its hull.
            // Reject it when its radial support point does not meet the convex solid.
            if(std::abs(along)>.001f) {
                const Vec3 radial=(c.normal-axle*axial).normalized();
                const Vec3 support_point=line_center-radial*cfg_.tire_radius;
                if(rock_distance(r,support_point).distance>std::max(.012f,-c.gap))c.gap=1.f;
            }
            const float surface=terrain_mode_>=4&&!custom_rocks_?
                1.10f-.54f*expedition_material(terrain_mode_,hit.point.x,hit.point.z).wet:r.surface;
            c.mu=tire_mu(surface);
            c.surface=terrain_mode_>=4&&expedition_material(terrain_mode_,hit.point.x,hit.point.z).wet>.30f?2:1;
        }
        return c;
    }
    void build_wheel_manifolds() {
        if(terrain_mode_<3)return;
        for(int w=0;w<4;++w) {
            auto &manifold=wheel_manifolds_[w];const auto previous=manifold;manifold.clear();
            auto add=[&](WheelSurfaceContact c) {
                if(c.gap>.045f)return;
                // Co-planar samples describe one patch: do not multiply normal
                // stiffness or available friction by the number of queries.
                for(auto &old:manifold)if(old.rock==c.rock&&old.normal.dot(c.normal)>.985f) {
                    if(c.gap<old.gap-.0001f)old=c;
                    return;
                }
                manifold.push_back(c);
            };
            for(int source=-1;source<int(near_rocks_.size());++source) {
                if(source>=0) {
                    const auto&r=*near_rocks_[source];const float reach=r.reach+cfg_.tire_radius+tire_width_*.5f+.05f;
                    if((particles[wheel_hubs[w]].pos-r.center).length_squared()>reach*reach)continue;
                }
                for(float across:{0.f,-tire_width_*.46f,tire_width_*.46f})
                    for(float along:{0.f,-cfg_.tire_radius*.38f,cfg_.tire_radius*.38f})
                        add(query_wheel_surface(w,source,across,along));
            }
            std::sort(manifold.begin(),manifold.end(),[](const WheelSurfaceContact&a,const WheelSurfaceContact&b){return a.gap<b.gap;});
            if(manifold.size()>max_tire_patches)manifold.resize(max_tire_patches);
            for(auto &c:manifold)for(const auto &old:previous)
                if(old.rock==c.rock&&old.normal.dot(c.normal)>.95f&&(old.point-c.point).length_squared()<.16f) {
                    c.shear=old.shear-c.normal*old.shear.dot(c.normal);break;
                }
        }
    }
    void solve_wheel_manifolds(bool brake) {
        for(int w=0;w<4;++w)for(auto &c:wheel_manifolds_[w]) {
            auto &hub=particles[wheel_hubs[w]];const float inv=dynamic_inv_mass(hub);
            const auto hit=query_wheel_surface(w,c.rock,c.width_sample,c.longitudinal_sample);
            c.normal=hit.normal;c.point=hit.point;c.gap=hit.gap;c.mu=hit.mu;c.surface=hit.surface;
            const float alpha=1/(tire_stiffness()*fixed_dt*fixed_dt);
            const float next=std::max(0.f,c.lambda+(-c.gap-alpha*c.lambda)/(inv+alpha));
            hub.pos+=c.normal*((next-c.lambda)*inv);c.lambda=next;
            if(!brake||next<=0)continue;
            Vec3 slip=hub.pos-hub.prev;slip-=c.normal*slip.dot(c.normal);
            Vec3 proposed=c.friction+slip/std::max(inv,1e-8f);
            const float limit=c.mu*next,magnitude=proposed.length();
            if(magnitude>limit&&magnitude>1e-8f)proposed*=limit/magnitude;
            hub.pos-=(proposed-c.friction)*inv;c.friction=proposed;
        }
    }
    void solve_wheel_contact_velocities() {
        for(int w=0;w<4;++w)for(const auto &c:wheel_manifolds_[w])if(c.lambda>1e-7f) {
            auto &hub=particles[wheel_hubs[w]];++contact_count_;++wheel_contact_counts_[w];
            const float vn=hub.velocity.dot(c.normal);if(vn<0)hub.velocity-=c.normal*vn;
        }
    }
    void solve_contacts(bool brake) {
        for (std::size_t i = 0; i < particles.size(); ++i) {
            auto &p = particles[i];
            if (p.tire || (terrain_mode_>=3 && p.wheel>=0)) continue;
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
        if (terrain_mode_ == 2 || terrain_mode_ >= 4) {
            const Vec3 c = center();
            float extent = 0;
            for (const auto &p : particles) {
                const float dx = p.pos.x - c.x, dz = p.pos.z - c.z;
                extent = std::max(extent, std::sqrt(dx * dx + dz * dz));
            }
            // Broad phase runs once per substep, rather than testing the whole
            // forest against every mass node in each constraint iteration.
            const auto &obstacles=terrain_mode_>=4?expedition_obstacles(terrain_mode_):exploration_obstacles();
            for (const auto &o : obstacles) {
                const float dx = o.x - c.x, dz = o.z - c.z;
                const float reach = extent + o.radius + 1.5f;
                if (dx * dx + dz * dz <= reach * reach)
                    nearby_obstacles_.push_back({{o.x, terrain_height(o.x, o.z), o.z}, o.radius, o.height});
            }
        }
        near_dynamic_.clear();
        if (terrain_mode_ >= 3) for (int id = 0; id < dynamic_objects_.body_count(); ++id) {
            const auto &body = dynamic_objects_.bodies()[id];
            if ((body.position - center()).length() < body.shape.reach + 7) near_dynamic_.push_back(id);
        }
        const size_t moving_pairs = near_dynamic_.size() * particles.size();
        dynamic_lambdas_.assign(moving_pairs, 0); dynamic_normals_.assign(moving_pairs, {});
        dynamic_points_.assign(moving_pairs, {}); dynamic_friction_.assign(moving_pairs, {});
        const size_t support_pairs = near_dynamic_.size() * 19;
        moving_support_lambdas_.assign(support_pairs, 0); moving_support_normals_.assign(support_pairs, {});
        moving_support_points_.assign(support_pairs, {}); moving_support_friction_.assign(support_pairs, {});
        near_rocks_.clear();
        const auto& rocks = custom_rocks_ ? test_rocks_ : (terrain_mode_>=4?expedition_rocks(terrain_mode_):crawl_course());
        if(!custom_rocks_ && terrain_mode_==7) imported_scenery::near(center(),7,near_rocks_);
        else if(custom_rocks_ || terrain_mode_>=3) for(const auto&r:rocks) if((r.center-center()).length()<r.reach+7)near_rocks_.push_back(&r);
        skid_lambdas_.assign(near_rocks_.size()*9,0);skid_friction_.assign(near_rocks_.size()*9,{});
        axle_contact_lambdas_.assign(solid_axles_active() ? (near_rocks_.size() + 1) * 10 : 0, 0);
        axle_contact_friction_.assign(axle_contact_lambdas_.size(), {});
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
                const float bound = (p.wheel >= 0 ? tire_mu(terrain_mode_>=3?wood_surface(p.pos-normal*radius):1.f) : 0.45f) * next_lambda * inv_mass;
                const float l = proposed.length();
                if (l > bound && l > 1e-8f) proposed *= bound / l;
                p.pos -= proposed - obstacle_friction_[pair];
                obstacle_friction_[pair] = proposed;
            }
        }
    }
    void solve_rock_contacts(bool brake) {
        for(size_t k=0;k<near_rocks_.size();++k) for(size_t i=0;i<particles.size();++i){
            auto&p=particles[i];if(p.tire||(terrain_mode_>=3&&p.wheel>=0))continue;const auto&r=*near_rocks_[k];float radius=contact_radius(p);size_t pair=k*particles.size()+i;
            if((p.pos-r.center).length_squared()>(r.reach+radius+.04f)*(r.reach+radius+.04f))continue;
            if(r.surface_mesh && rock_lambdas_[pair]==0 && r.query_nodes[0].bounds.distance_squared(p.pos)>(radius+.04f)*(radius+.04f))continue;
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
    void solve_dynamic_contacts(bool brake) {
        for (size_t k = 0; k < near_dynamic_.size(); ++k) for (size_t i = 0; i < particles.size(); ++i) {
            auto &p = particles[i]; if (p.tire) continue;
            const int id = near_dynamic_[k]; const auto &body = dynamic_objects_.bodies()[id];
            float radius = contact_radius(p); const size_t pair = k * particles.size() + i;
            if ((p.pos - body.position).length_squared() > (body.shape.reach + radius + .04f) * (body.shape.reach + radius + .04f)) continue;
            auto hit = dynamic_objects_.distance(id, p.pos);
            if (p.wheel >= 0) {
                const Vec3 axle = wheel_axis(p.wheel), side = axle * (tire_width_ * .46f);
                auto support = [&](Vec3 n) { float a = n.dot(axle); return std::max(.055f, cfg_.tire_radius * std::sqrt(std::max(0.f, 1-a*a))); };
                radius = support(hit.normal); float best = hit.distance - radius;
                for (float sign : {-1.f, 1.f}) {
                    auto sample = dynamic_objects_.distance(id, p.pos + side * sign);
                    const float rad = support(sample.normal), c = sample.distance - rad;
                    if (c < best) { best = c; hit = sample; radius = rad; }
                }
            }
            if (hit.distance > radius + .04f && dynamic_lambdas_[pair] == 0) continue;
            const float inv = dynamic_inv_mass(p), body_inv = dynamic_objects_.point_inverse_mass(id, hit.point, hit.normal);
            const float alpha = 1 / ((p.wheel >= 0 ? tire_stiffness() : 4500000.f) * fixed_dt * fixed_dt);
            float dl = (-(hit.distance - radius) - alpha * dynamic_lambdas_[pair]) / (inv + body_inv + alpha);
            const float next = std::max(0.f, dynamic_lambdas_[pair] + dl);
            dl = next - dynamic_lambdas_[pair]; dynamic_lambdas_[pair] = next;
            dynamic_normals_[pair] = hit.normal; dynamic_points_[pair] = hit.point;
            const Vec3 local = body.local_point(hit.point);
            const Vec3 previous_point = body.previous_position + body.previous_rotation.rotate(local);
            p.pos += hit.normal * (dl * inv);
            dynamic_objects_.apply_position_impulse(id, hit.point, hit.normal * -dl);
            if (next <= 0 || (p.wheel >= 0 && !brake)) continue;
            Vec3 slip = (p.pos - p.prev) - (hit.point - previous_point);
            slip -= hit.normal * slip.dot(hit.normal);
            const float slip_length = slip.length();
            const Vec3 tangent = slip_length > 1e-8f ? slip / slip_length : Vec3{};
            const float tangent_inv = inv + dynamic_objects_.point_inverse_mass(id, hit.point, tangent);
            Vec3 proposed = dynamic_friction_[pair] + slip / std::max(tangent_inv, 1e-8f);
            const float bound = (p.wheel >= 0 ? tire_mu(dynamic_objects_.tire_surface(id,hit.point)) : .45f) * next, magnitude = proposed.length();
            if (magnitude > bound && magnitude > 1e-8f) proposed *= bound / magnitude;
            const Vec3 correction = proposed - dynamic_friction_[pair]; dynamic_friction_[pair] = proposed;
            p.pos -= correction * inv;
            dynamic_objects_.apply_position_impulse(id, hit.point, correction);
        }
    }
    void moving_support_binding(int sample, std::array<int, 4> &nodes, std::array<float, 4> &weights, float &radius) const {
        if (sample < 9) {
            const float x = (sample % 3 + 1) * .25f, z = (sample / 3 + 1) * .25f;
            nodes = {0, 1, 2, 3}; weights = {(1-x)*(1-z), x*(1-z), (1-x)*z, x*z}; radius = .04f;
        } else {
            const int axle = (sample - 9) / 5, across = (sample - 9) % 5;
            const float t = .15f + across * .175f;
            nodes = {wheel_hubs[axle*2], wheel_hubs[axle*2+1], 0, 0}; weights = {1-t, t, 0, 0};
            radius = across == 2 ? .13f : .065f;
        }
    }
    void solve_moving_support_contacts() {
        // Loose stones and timber also reach the interpolated skid plate and
        // axle housings, instead of slipping through gaps in the nodal frame.
        for (size_t k = 0; k < near_dynamic_.size(); ++k) for (int sample = 0; sample < (solid_axles_active() ? 19 : 9); ++sample) {
            std::array<int, 4> nodes; std::array<float, 4> weights; float radius;
            moving_support_binding(sample, nodes, weights, radius);
            Vec3 p, prev; float inv = 0;
            for (int j = 0; j < 4; ++j) if (weights[j] != 0) {
                const auto &node = particles[nodes[j]]; p += node.pos * weights[j]; prev += node.prev * weights[j];
                inv += weights[j] * weights[j] * dynamic_inv_mass(node);
            }
            const int id = near_dynamic_[k]; const auto &body = dynamic_objects_.bodies()[id];
            const float reach = body.shape.reach + radius + .025f;
            if ((p - body.position).length_squared() > reach * reach) continue;
            auto hit = dynamic_objects_.distance(id, p); const size_t pair = k * 19 + sample;
            if (hit.distance > radius + .02f && moving_support_lambdas_[pair] == 0) continue;
            const float body_inv = dynamic_objects_.point_inverse_mass(id, hit.point, hit.normal);
            const float alpha = 1.f / (4500000.f * fixed_dt * fixed_dt);
            float dl = (-(hit.distance-radius) - alpha*moving_support_lambdas_[pair]) / (inv+body_inv+alpha);
            const float next = std::max(0.f, moving_support_lambdas_[pair]+dl);
            dl = next-moving_support_lambdas_[pair]; moving_support_lambdas_[pair] = next;
            moving_support_normals_[pair]=hit.normal; moving_support_points_[pair]=hit.point;
            const Vec3 local = body.local_point(hit.point);
            const Vec3 previous_point = body.previous_position + body.previous_rotation.rotate(local);
            Vec3 slip = (p-prev)-(hit.point-previous_point); slip -= hit.normal*slip.dot(hit.normal);
            const float magnitude = slip.length();
            const Vec3 tangent = magnitude > 1e-8f ? slip/magnitude : Vec3{};
            const float tangent_inv = inv + dynamic_objects_.point_inverse_mass(id, hit.point, tangent);
            Vec3 proposed = moving_support_friction_[pair]+slip/std::max(tangent_inv,1e-8f);
            const float bound=.45f*next, proposed_length=proposed.length();
            if(proposed_length>bound&&proposed_length>1e-8f) proposed*=bound/proposed_length;
            const Vec3 impulse = hit.normal*dl-(proposed-moving_support_friction_[pair]);
            moving_support_friction_[pair]=proposed;
            for(int j=0;j<4;++j) if(weights[j]!=0)
                particles[nodes[j]].pos += impulse*(weights[j]*dynamic_inv_mass(particles[nodes[j]]));
            dynamic_objects_.apply_position_impulse(id,hit.point,-impulse);
        }
    }
    void solve_dynamic_contact_velocities() {
        for (size_t k = 0; k < near_dynamic_.size(); ++k) for (size_t i = 0; i < particles.size(); ++i) {
            const size_t pair = k * particles.size() + i;
            if (dynamic_lambdas_[pair] <= 1e-7f) continue;
            auto &p = particles[i]; const int id = near_dynamic_[k];
            ++contact_count_; if (p.wheel >= 0) ++wheel_contact_counts_[p.wheel];
            const Vec3 normal = dynamic_normals_[pair], point = dynamic_points_[pair];
            const float vn = (p.velocity - dynamic_objects_.point_velocity(id, point)).dot(normal);
            if (vn >= 0) continue;
            const float inv = dynamic_inv_mass(p);
            const float impulse = -vn / (inv + dynamic_objects_.point_inverse_mass(id, point, normal));
            p.velocity += normal * (impulse * inv);
            dynamic_objects_.apply_impulse(id, point, normal * -impulse);
        }
    }
    void solve_moving_support_velocities() {
        for(size_t k=0;k<near_dynamic_.size();++k) for(int sample=0;sample<(solid_axles_active()?19:9);++sample) {
            const size_t pair=k*19+sample; if(moving_support_lambdas_[pair]<=1e-7f) continue;
            ++contact_count_;
            std::array<int,4> nodes; std::array<float,4> weights; float radius;
            moving_support_binding(sample,nodes,weights,radius);
            Vec3 v; float inv=0;
            for(int j=0;j<4;++j) if(weights[j]!=0) { v+=particles[nodes[j]].velocity*weights[j]; inv+=weights[j]*weights[j]*dynamic_inv_mass(particles[nodes[j]]); }
            const int id=near_dynamic_[k]; const Vec3 normal=moving_support_normals_[pair], point=moving_support_points_[pair];
            const float vn=(v-dynamic_objects_.point_velocity(id,point)).dot(normal); if(vn>=0)continue;
            const Vec3 impulse=normal*(-vn/(inv+dynamic_objects_.point_inverse_mass(id,point,normal)));
            for(int j=0;j<4;++j) if(weights[j]!=0) particles[nodes[j]].velocity+=impulse*(weights[j]*dynamic_inv_mass(particles[nodes[j]]));
            dynamic_objects_.apply_impulse(id,point,-impulse);
        }
    }
    void solve_axle_contacts() {
        if (!solid_axles_active()) return;
        // Five bounded support spheres sample each rigid housing. The center
        // differential is lower than the shafts, and each reaction reaches both
        // wheel assemblies through the same geometric beam axle constraints.
        for (size_t surface = 0; surface <= near_rocks_.size(); ++surface)
            for (int axle = 0; axle < 2; ++axle) for (int sample = 0; sample < 5; ++sample) {
                const float wb = .15f + sample * .175f, wa = 1 - wb;
                const float radius = sample == 2 ? .13f : .065f;
                auto &a = particles[wheel_hubs[axle * 2]], &b = particles[wheel_hubs[axle * 2 + 1]];
                const Vec3 p = a.pos * wa + b.pos * wb, prev = a.prev * wa + b.prev * wb;
                Vec3 normal, point; float distance;
                if (surface == 0) {
                    normal = terrain_normal(p.x, p.z);
                    point = {p.x, terrain_height(p.x, p.z), p.z};
                    distance = (p - point).dot(normal);
                } else {
                    const auto& r=*near_rocks_[surface-1];
                    if(r.surface_mesh && axle_contact_lambdas_[surface*10+axle*5+sample]==0 && r.query_nodes[0].bounds.distance_squared(p)>(radius+.02f)*(radius+.02f))continue;
                    auto hit = rock_distance(r, p);
                    normal = hit.normal; point = hit.point; distance = hit.distance;
                }
                const size_t pair = surface * 10 + axle * 5 + sample;
                if (distance > radius + .02f && axle_contact_lambdas_[pair] == 0) continue;
                const float ai = dynamic_inv_mass(a), bi = dynamic_inv_mass(b), inv = wa * wa * ai + wb * wb * bi;
                const float alpha = 1.f / (4500000.f * fixed_dt * fixed_dt);
                float dl = (-(distance - radius) - alpha * axle_contact_lambdas_[pair]) / (inv + alpha);
                const float next = std::max(0.f, axle_contact_lambdas_[pair] + dl);
                dl = next - axle_contact_lambdas_[pair]; axle_contact_lambdas_[pair] = next;
                Vec3 slip = p - prev; slip -= normal * slip.dot(normal);
                Vec3 proposed = axle_contact_friction_[pair] + slip / inv;
                const float bound = .45f * next, magnitude = proposed.length();
                if (magnitude > bound && magnitude > 1e-8f) proposed *= bound / magnitude;
                Vec3 correction = normal * dl - (proposed - axle_contact_friction_[pair]);
                axle_contact_friction_[pair] = proposed;
                a.pos += correction * (wa * ai); b.pos += correction * (wb * bi);
            }
    }
    void solve_skid_contacts() {
        // Nine support points span the existing frame underside. Each reaction
        // acts through bilinear weights on its four deforming attachment nodes.
        for(size_t k=0;k<near_rocks_.size();++k)for(int iz=0;iz<3;++iz)for(int ix=0;ix<3;++ix){
            float x=(ix+1)*.25f,z=(iz+1)*.25f;float weights[4]={(1-x)*(1-z),x*(1-z),(1-x)*z,x*z};
            Vec3 p,prev;float inv=0;for(int j=0;j<4;++j){p+=particles[j].pos*weights[j];prev+=particles[j].prev*weights[j];inv+=particles[j].inv_mass*weights[j]*weights[j];}
            const auto&r=*near_rocks_[k];if((p-r.center).length_squared()>(r.reach+.08f)*(r.reach+.08f))continue;
            if(r.surface_mesh && skid_lambdas_[k*9+iz*3+ix]==0 && r.query_nodes[0].bounds.distance_squared(p)>.08f*.08f)continue;
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
            if (solid_axles_active()) {
                const auto &c=coilovers_[w]; const Vec3 axis=constraint_delta(c).normalized(); Vec3 relative;
                for(int i=0;i<c.count;++i)relative+=particles[c.nodes[i]].velocity*c.weights[i];
                const float axial_speed=relative.dot(axis);
                const float selected=axial_speed<0?cfg_.compression_damping:cfg_.rebound_damping;
                float damper=selected>0?selected:cfg_.damping;
                // Compression blow-off softens sharp impacts above 0.6 m/s.
                // The independently selected rebound circuit remains linear;
                // sharing blow-off with it undermines extension control.
                const float velocity=std::abs(axial_speed);
                if(axial_speed<-.6f)damper*=.72f+.28f*.6f/velocity;
                // A compressed elastomer bumper dissipates energy on the
                // compression stroke. Without this, the tighter physical
                // damper package behaves like a nearly elastic impact stop.
                if(axial_speed<0)damper+=12000.f*(1-smoothstep(shock_min_length(w)-.01f,shock_min_length(w)+.035f,shock_length(w)));
                damp_mount(c,damper);
                continue;
            }
            const float selected = rel > 0 ? cfg_.compression_damping : cfg_.rebound_damping;
            const float damper = selected > 0 ? selected : cfg_.damping;
            const float chm = damper * fixed_dt * inv_mass_sum;
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
        if (terrain_mode_ >= 3) dynamic_objects_.begin_step(fixed_dt);
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
        for(auto &c:carrier_edges_)c.lambda=0;
        for(auto &c:four_links_)c.lambda=0;
        for(auto &c:coilovers_)c.lambda=0;
        spring_stop_lambdas_.fill(0);
        build_wheel_manifolds();
        constexpr int iterations = 9;
        for (int iteration = 0; iteration < iterations; ++iteration) {
            if (iteration % 2 == 0) for (auto &b : beams) solve_beam(b);
            else for (auto it = beams.rbegin(); it != beams.rend(); ++it) solve_beam(*it);
            solve_suspension();
            solve_contacts(braking);
            solve_obstacle_contacts(braking);
            solve_rock_contacts(braking);
            if (terrain_mode_ >= 3) {
                dynamic_objects_.solve_world(fixed_dt);
                solve_dynamic_contacts(braking);
                solve_wheel_manifolds(braking);
                solve_moving_support_contacts();
            }
            solve_skid_contacts();
            solve_axle_contacts();
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
        if (terrain_mode_ >= 3) {
            dynamic_objects_.finish_step(fixed_dt);
            solve_dynamic_contact_velocities();
            solve_wheel_contact_velocities();
            solve_moving_support_velocities();
        }
        if(solid_axles_active()) {
            for(const auto &c:carrier_edges_)damp_mount(c,650);
            for(const auto &c:four_links_)damp_mount(c,120);
        }
        material_damping();
        solve_tire_traction(throttle, braking);
        update_wheel_skin();
    }
};

} // namespace boltyard
