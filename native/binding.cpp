#include "soft_rig.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <chrono>
#include <cmath>
#include <algorithm>

using namespace godot;

class SoftBodyRig : public RefCounted {
    GDCLASS(SoftBodyRig, RefCounted)
    boltyard::SoftRig rig;
    double sim_ms = 0.0;
    static Vector3 gv(const boltyard::Vec3 &p) { return Vector3(p.x, p.y, p.z); }
    static boltyard::Vec3 cv(const Vector3 &p) { return {(float)p.x, (float)p.y, (float)p.z}; }
    static float number(const Dictionary &d, const char *key, float fallback, float lo, float hi) {
        if (!d.has(key)) return fallback;
        Variant v = d[key];
        if (v.get_type() != Variant::INT && v.get_type() != Variant::FLOAT) return fallback;
        double n = v;
        return std::isfinite(n) ? (float)std::clamp(n, (double)lo, (double)hi) : fallback;
    }

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "settings"), &SoftBodyRig::configure);
        ClassDB::bind_method(D_METHOD("reset", "origin"), &SoftBodyRig::reset, DEFVAL(Vector3(0,1.5,8)));
        ClassDB::bind_method(D_METHOD("recover_near", "origin", "heading"), &SoftBodyRig::recover_near);
        ClassDB::bind_method(D_METHOD("step", "dt", "throttle", "steer", "brake"), &SoftBodyRig::step);
        ClassDB::bind_method(D_METHOD("set_terrain", "mode"), &SoftBodyRig::set_terrain);
        ClassDB::bind_method(D_METHOD("get_terrain_mode"), &SoftBodyRig::get_terrain_mode);
        ClassDB::bind_method(D_METHOD("get_expedition_heightfield", "mode"), &SoftBodyRig::get_expedition_heightfield, DEFVAL(-1));
        ClassDB::bind_method(D_METHOD("get_expedition_rocks", "mode"), &SoftBodyRig::get_expedition_rocks, DEFVAL(-1));
        ClassDB::bind_method(D_METHOD("get_expedition_obstacles", "mode"), &SoftBodyRig::get_expedition_obstacles, DEFVAL(-1));
        ClassDB::bind_method(D_METHOD("get_expedition_landmarks", "mode"), &SoftBodyRig::get_expedition_landmarks, DEFVAL(-1));
        ClassDB::bind_method(D_METHOD("get_expedition_trails", "mode"), &SoftBodyRig::get_expedition_trails, DEFVAL(-1));
        ClassDB::bind_method(D_METHOD("get_expedition_routes", "mode"), &SoftBodyRig::get_expedition_routes, DEFVAL(-1));
        ClassDB::bind_method(D_METHOD("get_expedition_water", "mode"), &SoftBodyRig::get_expedition_water, DEFVAL(-1));
        ClassDB::bind_method(D_METHOD("set_drivetrain", "low_range", "locked_diffs"), &SoftBodyRig::set_drivetrain);
        ClassDB::bind_method(D_METHOD("set_axle_drivetrain", "low_range", "front_locked", "rear_locked"), &SoftBodyRig::set_axle_drivetrain);
        ClassDB::bind_method(D_METHOD("get_wheel_visuals"), &SoftBodyRig::get_wheel_visuals);
        ClassDB::bind_method(D_METHOD("get_tire_contacts"), &SoftBodyRig::get_tire_contacts);
        ClassDB::bind_method(D_METHOD("get_dynamic_objects"), &SoftBodyRig::get_dynamic_objects);
        ClassDB::bind_method(D_METHOD("get_dynamic_object_poses"), &SoftBodyRig::get_dynamic_object_poses);
        ClassDB::bind_method(D_METHOD("camera_safe_position", "anchor", "desired", "radius"), &SoftBodyRig::camera_safe_position);
        ClassDB::bind_method(D_METHOD("terrain_height", "x", "z"), &SoftBodyRig::terrain_height);
        ClassDB::bind_method(D_METHOD("terrain_normal", "x", "z"), &SoftBodyRig::terrain_normal);
        ClassDB::bind_method(D_METHOD("terrain_surface", "x", "z"), &SoftBodyRig::terrain_surface);
        ClassDB::bind_method(D_METHOD("get_crawl_rocks"), &SoftBodyRig::get_crawl_rocks);
        ClassDB::bind_method(D_METHOD("get_obstacles"), &SoftBodyRig::get_obstacles);
        ClassDB::bind_method(D_METHOD("get_terrain_samples"), &SoftBodyRig::get_terrain_samples);
        ClassDB::bind_method(D_METHOD("get_rest_nodes"), &SoftBodyRig::get_rest_nodes);
        ClassDB::bind_method(D_METHOD("get_nodes"), &SoftBodyRig::get_nodes);
        ClassDB::bind_method(D_METHOD("get_beams"), &SoftBodyRig::get_beams);
        ClassDB::bind_method(D_METHOD("get_beam_kinds"), &SoftBodyRig::get_beam_kinds);
        ClassDB::bind_method(D_METHOD("get_broken"), &SoftBodyRig::get_broken);
        ClassDB::bind_method(D_METHOD("get_strains"), &SoftBodyRig::get_strains);
        ClassDB::bind_method(D_METHOD("get_wheel_hubs"), &SoftBodyRig::get_wheel_hubs);
        ClassDB::bind_method(D_METHOD("get_stats"), &SoftBodyRig::get_stats);
        ClassDB::bind_method(D_METHOD("apply_impact", "impulse"), &SoftBodyRig::apply_impact);
        ClassDB::bind_method(D_METHOD("displace_node", "index", "offset"), &SoftBodyRig::displace_node);
    }

public:
    void configure(const Dictionary &d) {
        boltyard::Config c;
        c.tire_radius = number(d,"tire_radius",0.46f,0.32f,0.65f);
        c.tire_pressure = number(d,"tire_pressure",1.0f,0.5f,2.0f);
        c.spring_rate = number(d,"spring_rate",30000,15000,65000);
        c.damping = number(d,"damping",3000,1000,7000);
        c.ride_height = number(d,"ride_height",0.35f,0.15f,0.65f);
        c.engine_torque = number(d,"engine_torque",450,150,900);
        c.mass = number(d,"mass",1200,900,2000);
        c.track_width = number(d,"track_width",1.9f,1.6f,2.3f);
        c.wheelbase = number(d,"wheelbase",2.7f,2.3f,3.3f);
        c.body_stiffness = number(d,"body_stiffness",1.0f,0.5f,2.0f);
        c.vehicle_type = (int)number(d,"vehicle_type",0,0,2);
        c.tire_grip = number(d,"tire_grip",1,0.7f,1.4f);
        c.tire_width_scale = number(d,"tire_width_scale",1,0.75f,1.4f);
        c.suspension_travel = number(d,"suspension_travel",0.22f,0.12f,0.4f);
        c.final_drive = number(d,"final_drive",1,0.8f,1.5f);
        c.front_accessory_mass = number(d,"front_accessory_mass",0,0,100);
        c.roof_accessory_mass = number(d,"roof_accessory_mass",0,0,100);
        c.wheel_accessory_mass = number(d,"wheel_accessory_mass",0,-40,80);
        c.compression_damping = number(d,"compression_damping",0,0,7000);
        c.rebound_damping = number(d,"rebound_damping",0,0,7000);
        c.compression_travel = number(d,"compression_travel",0,0,.45f);
        c.low_range = d.get("low_range",true);
        c.locked_diffs = d.get("locked_diffs",true);
        c.front_locked = d.get("front_locked",c.locked_diffs);
        c.rear_locked = d.get("rear_locked",c.locked_diffs);
        // Dictionary callers have explicit axle choices; the native legacy
        // master switch must not erase a mixed front/rear setup.
        c.locked_diffs = true;
        c.solid_axles = d.get("solid_axles",true);
        rig.configure(c);
    }
    void reset(const Vector3 &origin) { rig.reset(cv(origin)); }
    bool recover_near(const Vector3 &origin, const Vector3 &heading) { return rig.recover_near(cv(origin), cv(heading)); }
    void step(double dt, double throttle, double steer, bool brake) {
        if (!std::isfinite(dt) || dt <= 0.0) return;
        auto start = std::chrono::steady_clock::now();
        // SoftRig owns the only accumulator. Ordinary 10-120 Hz frame cadence
        // advances all supplied time; a long pause is bounded inside the core.
        rig.step((float)dt, (float)throttle, (float)steer, brake);
        auto end = std::chrono::steady_clock::now();
        sim_ms = std::chrono::duration<double,std::milli>(end-start).count();
    }
    void set_terrain(int mode) { rig.set_terrain(std::clamp(mode,0,6)); }
    int get_terrain_mode() const { return rig.get_terrain_mode(); }
    int expedition_mode(int mode) const { return std::clamp(mode < 0 ? get_terrain_mode() : mode, 4, 6); }
    Dictionary get_expedition_heightfield(int mode) const {
        const auto &data=boltyard::expedition_detail::cache(expedition_mode(mode));
        PackedFloat32Array heights,surfaces,gravel;PackedColorArray materials;
        heights.resize(data.height.size());surfaces.resize(data.height.size());materials.resize(data.height.size());gravel.resize(data.height.size());
        for(int i=0;i<(int)data.height.size();++i){const auto&m=data.material[i];heights.set(i,data.height[i]);surfaces.set(i,data.surface[i]);materials.set(i,Color(m.rock,m.dirt,m.grass,m.wet));gravel.set(i,data.gravel[i]);}
        Dictionary out;out["heights"]=heights;out["surfaces"]=surfaces;out["materials"]=materials;out["gravel"]=gravel;
        out["side"]=321;out["spacing"]=2.0;out["origin"]=-320.0;out["mode"]=expedition_mode(mode);return out;
    }
    Array get_expedition_rocks(int mode) const {
        Array out;for(const auto&r:boltyard::expedition_rocks(expedition_mode(mode))){PackedVector3Array vertices;for(auto t:r.triangles)for(int i:t)vertices.push_back(gv(r.vertices[i]));out.push_back(vertices);}return out;
    }
    Array get_expedition_obstacles(int mode) const {
        Array out;for(const auto&o:boltyard::expedition_obstacles(expedition_mode(mode))){Dictionary d;d["x"]=o.x;d["z"]=o.z;d["radius"]=o.radius;d["height"]=o.height;d["type"]=o.type;out.push_back(d);}return out;
    }
    Array get_expedition_landmarks(int mode) const {
        const int m=expedition_mode(mode);Array out;int i=0;
        for(const auto&l:boltyard::expedition_landmarks(m)){Dictionary d;d["id"]=String(m==6?"canyon_":(m==5?"russia_":"rockies_"))+String::num_int64(i++);d["name"]=l.name;d["description"]=l.detail;d["position"]=Vector3(l.x,boltyard::expedition_height(m,l.x,l.z),l.z);d["radius"]=18.0;out.push_back(d);}return out;
    }
    Array get_expedition_trails(int mode) const {
        if(mode<0&&get_terrain_mode()<4)return Array();
        Array out;for(const auto&p:boltyard::expedition_trail_points(expedition_mode(mode))){Dictionary d;d["position"]=Vector3(p.x,p.h,p.z);d["width"]=p.width;d["route"]=p.route;out.push_back(d);}return out;
    }
    Array get_expedition_routes(int mode) const {
        Array out;int route=-1;PackedVector3Array points;
        for(const auto&p:boltyard::expedition_trail_points(expedition_mode(mode))){if(p.route!=route){if(!points.is_empty())out.push_back(points);points=PackedVector3Array();route=p.route;}points.push_back(Vector3(p.x,p.h,p.z));}
        if(!points.is_empty())out.push_back(points);return out;
    }
    Dictionary get_expedition_water(int mode) const {
        const auto&w=boltyard::expedition_water(expedition_mode(mode));Dictionary d;d["x"]=w.x;d["z"]=w.z;d["rx"]=w.rx;d["rz"]=w.rz;d["height"]=w.height;return d;
    }
    void set_drivetrain(bool low, bool locked) { rig.set_drivetrain(low,locked); }
    void set_axle_drivetrain(bool low, bool front, bool rear) { rig.set_drivetrain(low,front,rear); }
    Array get_tire_contacts() const {
        Array wheels;
        for(int w=0;w<4;++w){
            Array contacts;
            for(const auto &p:rig.wheel_contact_patches(w)){
                Dictionary d;d["normal"]=gv(p.normal);d["point"]=gv(p.point);d["shear"]=gv(p.shear);
                d["load"]=p.load;d["compression"]=p.compression;d["half_length"]=p.half_length;
                d["half_width"]=p.half_width;d["friction"]=p.friction;d["surface"]=p.surface;d["dynamic_body"]=p.dynamic_body;
                contacts.push_back(d);
            }
            wheels.push_back(contacts);
        }
        return wheels;
    }
    Dictionary get_wheel_visuals() const {
        Dictionary d;
        PackedVector3Array axes, normals, points, link_starts, link_ends;
        PackedColorArray patch_planes,patch_centers,shock_dimensions;
        patch_planes.resize(24);patch_centers.resize(24);
        for(int i=0;i<24;++i){patch_planes.set(i,Color(0,0,0,0));patch_centers.set(i,Color(0,0,0,0));}
        PackedFloat32Array phases, compression;
        for (int w=0;w<4;++w) {
            shock_dimensions.push_back(Color(rig.shock_rest_length(w),rig.shock_min_length(w),rig.shock_max_length(w),rig.shock_body_length(w)));
            axes.push_back(gv(rig.wheel_axle_direction(w)));
            normals.push_back(gv(rig.wheel_contact_normal(w)));
            points.push_back(gv(rig.wheel_contact_point(w)));
            phases.push_back(rig.wheel_rotation_angle(w));
            compression.push_back(rig.wheel_compression(w));
            link_starts.push_back(gv(rig.suspension_link_start(w)));
            link_ends.push_back(gv(rig.suspension_link_end(w)));
            int i=0;
            for(const auto&p:rig.wheel_contact_patches(w)){
                if(i>=6)break;
                const float radius=std::hypot(p.half_length,p.half_width)+rig.config().tire_radius*.18f;
                patch_planes.set(w*6+i,Color(p.normal.x,p.normal.y,p.normal.z,p.normal.dot(p.point)));
                patch_centers.set(w*6+i,Color(p.point.x,p.point.y,p.point.z,radius));++i;
            }
        }
        for(int w=0;w<4;++w){link_starts.push_back(gv(rig.upper_link_start(w)));link_ends.push_back(gv(rig.upper_link_end(w)));}
        for(int w=0;w<4;++w){link_starts.push_back(gv(rig.shock_start(w)));link_ends.push_back(gv(rig.shock_end(w)));}
        for(int a=0;a<2;++a){link_starts.push_back(gv(rig.transfer_case(a)));link_ends.push_back(gv(rig.axle_pinion(a)));}
        d["axes"]=axes;d["normals"]=normals;d["points"]=points;d["phases"]=phases;d["compression"]=compression;
        d["patch_planes"]=patch_planes;d["patch_centers"]=patch_centers;
        d["link_starts"]=link_starts;d["link_ends"]=link_ends;d["shock_dimensions"]=shock_dimensions;
        d["up"]=gv(rig.up());
        PackedVector3Array axle_ups;for(int a=0;a<2;++a)axle_ups.push_back(gv(rig.axle_up(a)));d["axle_ups"]=axle_ups;
        return d;
    }
    double terrain_height(double x, double z) const { return rig.terrain_height((float)x,(float)z); }
    Vector3 terrain_normal(double x, double z) const { return gv(rig.terrain_normal((float)x,(float)z)); }
    double terrain_surface(double x, double z) const { return rig.terrain_surface((float)x,(float)z); }
    Dictionary get_terrain_samples() const {
        if(get_terrain_mode()>=4)return get_expedition_heightfield(-1);
        const auto &terrain = boltyard::exploration_detail::cache();
        PackedFloat32Array heights, surfaces;
        heights.resize(terrain.height.size()); surfaces.resize(terrain.surface.size());
        for (int i = 0; i < (int)terrain.height.size(); ++i) {
            heights.set(i, terrain.height[i]); surfaces.set(i, terrain.surface[i]);
        }
        Dictionary out;
        out["heights"] = heights; out["surfaces"] = surfaces;
        out["side"] = 385; out["spacing"] = 2.0; out["origin"] = -384.0;
        return out;
    }
    Array get_crawl_rocks() const {
        Array out;for(const auto&r:boltyard::crawl_course()){PackedVector3Array verts;for(auto t:r.triangles)for(int i:t)verts.push_back(gv(r.vertices[i]));out.push_back(verts);}return out;
    }
    Array get_dynamic_objects() const {
        Array out;
        for(const auto &b:rig.dynamic_objects().bodies()){
            Dictionary d;PackedVector3Array triangles;
            for(auto t:b.shape.triangles)for(int i:t)triangles.push_back(gv(b.shape.vertices[i]));
            d["kind"]=b.kind;d["triangles"]=triangles;d["position"]=gv(b.position);
            d["rotation"]=Quaternion(b.rotation.x,b.rotation.y,b.rotation.z,b.rotation.w);d["sleeping"]=b.sleeping;
            out.push_back(d);
        }
        return out;
    }
    Array get_dynamic_object_poses() const {
        Array out;
        for(const auto &b:rig.dynamic_objects().bodies())out.push_back(Transform3D(Basis(Quaternion(b.rotation.x,b.rotation.y,b.rotation.z,b.rotation.w)),gv(b.position)));
        return out;
    }
    Vector3 camera_safe_position(const Vector3 &anchor, const Vector3 &desired, double radius) const {
        if(!anchor.is_finite()||!desired.is_finite())return anchor;
        const auto start=cv(anchor);
        auto candidate=cv(desired);
        const float padding=std::isfinite(radius)?std::clamp((float)radius,.05f,.5f):.22f;
        constexpr float gap=.012f;
        const auto &rocks=get_terrain_mode()>=4?boltyard::expedition_rocks(get_terrain_mode()):boltyard::crawl_course();
        std::vector<const boltyard::CrawlRock*> nearby;
        const auto initial_delta=candidate-start;const float initial_length=std::max(.00001f,initial_delta.length_squared());
        for(const auto&r:rocks){const auto closest=start+initial_delta*std::clamp((r.center-start).dot(initial_delta)/initial_length,0.f,1.f);if((closest-r.center).length_squared()<(r.reach+padding+.5f)*(r.reach+padding+.5f))nearby.push_back(&r);}
        auto face_normal=[](const boltyard::CrawlRock &shape,size_t i){
            const auto &t=shape.triangles[i];const auto a=shape.vertices[t[0]];
            return shape.triangle_normals.size()==shape.triangles.size()?shape.triangle_normals[i]:(shape.vertices[t[1]]-a).cross(shape.vertices[t[2]]-a).normalized();
        };
        auto escape=[&](const boltyard::CrawlRock &shape,const boltyard::Vec3 &local_start,const boltyard::Vec3 &local_end){
            float nearest=-std::numeric_limits<float>::infinity();boltyard::Vec3 normal;
            for(size_t i=0;i<shape.triangles.size();++i){
                const auto a=shape.vertices[shape.triangles[i][0]],n=face_normal(shape,i);
                const float from=(local_start-a).dot(n)-padding,to=(local_end-a).dot(n)-padding;
                if(from>0||to>0)return boltyard::Vec3{};
                if(to>nearest){nearest=to;normal=n;}
            }
            // An embedded anchor may look out of its supporting rock. If the
            // eye is also inside, first move it beyond the nearest padded face.
            return normal*(gap-nearest);
        };
        for(int pass=0;pass<3;++pass){
            const auto before=candidate;
            for(const auto*r:nearby)candidate+=escape(*r,start,candidate);
            for(const auto&b:rig.dynamic_objects().bodies())
                candidate+=b.rotation.rotate(escape(b.shape,b.local_point(start),b.local_point(candidate)));
            const auto delta=candidate-start;float fraction=1.f;
            auto clip=[&](const boltyard::CrawlRock &shape,const boltyard::Vec3 &local_start,const boltyard::Vec3 &local_delta){
                float enter=0,leave=fraction;bool inside=true;
                for(size_t i=0;i<shape.triangles.size();++i){
                    const auto a=shape.vertices[shape.triangles[i][0]],n=face_normal(shape,i);
                    const float distance=(local_start-a).dot(n)-padding,speed=local_delta.dot(n);
                    if(distance>0)inside=false;
                    if(std::abs(speed)<1e-7f){if(distance>0)return;continue;}
                    const float hit=-distance/speed;
                    if(speed<0)enter=std::max(enter,hit);else leave=std::min(leave,hit);
                    if(enter>leave)return;
                }
                if(!inside&&enter>=0&&enter<fraction)fraction=std::max(0.f,enter-gap/std::max(.01f,delta.length()));
            };
            for(const auto*r:nearby)clip(*r,start,delta);
            if(get_terrain_mode()>=4){
                // Camera sphere versus upright collidable tree trunks; leaves
                // do not trap the camera. Trunk radius matches native contact.
                for(const auto&o:boltyard::expedition_obstacles(get_terrain_mode())){
                    const float ox=start.x-o.x,oz=start.z-o.z,radius=o.radius+padding;
                    const float a=delta.x*delta.x+delta.z*delta.z,b=2*(ox*delta.x+oz*delta.z),c=ox*ox+oz*oz-radius*radius;
                    if(a<1e-7f||c<=0)continue;
                    const float disc=b*b-4*a*c;if(disc<0)continue;
                    const float t=(-b-std::sqrt(disc))/(2*a);
                    if(t<=0||t>=fraction)continue;
                    const float y=start.y+delta.y*t,base=rig.terrain_height(o.x,o.z);
                    if(y>=base-padding&&y<=base+o.height+padding)fraction=std::max(0.f,t-gap/std::max(.01f,delta.length()));
                }
            }
            for(const auto&b:rig.dynamic_objects().bodies())
                clip(b.shape,b.local_point(start),b.rotation.conjugate().rotate(delta));
            candidate=start+delta*fraction;
            // A correction may enter a neighboring solid or pull the eye back
            // into the anchor's support; revisit the bounded scene next pass.
            if((candidate-before).length_squared()<1e-10f)break;
        }
        return gv(candidate);
    }
    Array get_obstacles() const {
        Array out;
        for (const auto &o : boltyard::exploration_obstacles()) {
            Dictionary item;
            item["x"]=o.x; item["z"]=o.z; item["radius"]=o.radius;
            item["height"]=o.height; item["type"]=o.type;
            out.push_back(item);
        }
        return out;
    }
    PackedVector3Array get_rest_nodes() const {
        PackedVector3Array a; a.resize(std::min(100,(int)rig.rest_positions.size()));
        for (int i=0;i<a.size();++i) a.set(i,gv(rig.rest_positions[i]));
        return a;
    }
    PackedVector3Array get_nodes() const {
        PackedVector3Array a; a.resize(std::min(100,(int)rig.particles.size()));
        for (int i=0;i<a.size();++i) a.set(i,gv(rig.particles[i].pos));
        return a;
    }
    PackedInt32Array get_beams() const {
        PackedInt32Array a; a.resize(rig.beams.size()*2);
        for (int i=0;i<(int)rig.beams.size();++i) { a.set(i*2,rig.beams[i].a); a.set(i*2+1,rig.beams[i].b); }
        return a;
    }
    PackedInt32Array get_beam_kinds() const {
        PackedInt32Array a; a.resize(rig.beams.size());
        for (int i=0;i<(int)rig.beams.size();++i) a.set(i,rig.beams[i].kind);
        return a;
    }
    PackedByteArray get_broken() const {
        PackedByteArray a; a.resize(rig.beams.size());
        for (int i=0;i<(int)rig.beams.size();++i) a.set(i,rig.beams[i].broken?1:0);
        return a;
    }
    PackedFloat32Array get_strains() const {
        PackedFloat32Array a; a.resize(rig.beams.size());
        for (int i=0;i<(int)rig.beams.size();++i) {
            const auto &b = rig.beams[i];
            a.set(i,(rig.particles[b.a].pos-rig.particles[b.b].pos).length()/std::max(0.001f,b.original_rest)-1.0f);
        }
        return a;
    }
    PackedInt32Array get_wheel_hubs() const {
        PackedInt32Array a; for (int id : rig.wheel_hubs) a.push_back(id); return a;
    }
    Dictionary get_stats() const {
        Dictionary d;
        d["speed"]=rig.speed(); d["damage"]=rig.damage();
        d["broken_beams"]=rig.broken_count(); d["contacts"]=rig.contact_count();
        int wheels_grounded=0;
        for (int w=0;w<4;++w) if (rig.wheel_contact_count(w)>0) ++wheels_grounded;
        d["wheels_grounded"]=wheels_grounded;
        d["nodes"]=rig.node_count(); d["beams"]=rig.beam_count();
        d["physical_nodes"]=rig.physical_node_count(); d["render_nodes"]=rig.render_node_count();
        d["physical_beams"]=rig.physical_beam_count();
        d["velocity"]=gv(rig.linear_velocity()); d["steering_angle"]=rig.steering_angle();
        PackedFloat32Array wheel_spin, suspension, loads, rock_loads, slip;
        for (int w=0; w<4; ++w) { loads.push_back(rig.wheel_load(w));rock_loads.push_back(rig.wheel_rock_load(w));slip.push_back(rig.wheel_slip(w));wheel_spin.push_back(rig.wheel_angular_velocity(w)); suspension.push_back(rig.suspension_travel(w)); }
        d["wheel_loads"]=loads;d["rock_loads"]=rock_loads;d["wheel_slip"]=slip;d["wheel_spin"]=wheel_spin; d["suspension"]=suspension;
        PackedFloat32Array compression, normal_loads, patches, unsprung, articulation, clearance;
        for(int w=0;w<4;++w){compression.push_back(rig.wheel_compression(w));normal_loads.push_back(rig.wheel_normal_load(w));patches.push_back(rig.wheel_contact_patch_length(w));unsprung.push_back(rig.wheel_unsprung_mass(w));}
        for(int a=0;a<2;++a){articulation.push_back(rig.axle_articulation(a));clearance.push_back(rig.axle_clearance(a));}
        d["wheel_compression"]=compression;d["wheel_normal_loads"]=normal_loads;d["wheel_contact_patch"]=patches;
        d["wheel_unsprung_mass"]=unsprung;d["axle_articulation"]=articulation;d["axle_clearance"]=clearance;
        PackedFloat32Array axle_pitch;for(int a=0;a<2;++a)axle_pitch.push_back(rig.axle_pitch(a));d["axle_pitch"]=axle_pitch;
        d["position"]=gv(rig.center()); d["forward"]=gv(rig.forward()); d["up"]=gv(rig.up());
        d["sim_ms"]=sim_ms;
        d["safety_clamps"]=rig.safety_clamp_count();
        d["rejected_states"]=rig.rejected_state_count();
        d["dropped_time"]=rig.time_dropped();
        d["dynamic_objects"]=rig.dynamic_objects().body_count();
        d["awake_objects"]=rig.dynamic_objects().awake_count();
        d["object_contacts"]=rig.dynamic_objects().contact_count();
        return d;
    }
    void apply_impact(const Vector3 &impulse) { rig.apply_impact(cv(impulse)); }
    void displace_node(int index,const Vector3 &offset) { rig.displace_node(index,cv(offset)); }
};

void initialize_boltyard(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<SoftBodyRig>();
}
void uninitialize_boltyard(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT boltyard_library_init(GDExtensionInterfaceGetProcAddress address,const GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(address,library,initialization);
    init.register_initializer(initialize_boltyard);
    init.register_terminator(uninitialize_boltyard);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
