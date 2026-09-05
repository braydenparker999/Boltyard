#include "soft_rig.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <chrono>
#include <cmath>
#include <algorithm>

using namespace godot;

class SoftBodyRig : public RefCounted {
    GDCLASS(SoftBodyRig, RefCounted)
    boltyard::SoftRig rig;
    double sim_ms = 0.0;
    double accumulator = 0.0;
    double dropped_time = 0.0;
    static constexpr double FIXED_DT = 1.0 / 120.0;
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
        ClassDB::bind_method(D_METHOD("step", "dt", "throttle", "steer", "brake"), &SoftBodyRig::step);
        ClassDB::bind_method(D_METHOD("set_terrain", "mode"), &SoftBodyRig::set_terrain);
        ClassDB::bind_method(D_METHOD("set_drivetrain", "low_range", "locked_diffs"), &SoftBodyRig::set_drivetrain);
        ClassDB::bind_method(D_METHOD("terrain_height", "x", "z"), &SoftBodyRig::terrain_height);
        ClassDB::bind_method(D_METHOD("terrain_normal", "x", "z"), &SoftBodyRig::terrain_normal);
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
        c.low_range = d.get("low_range",true);
        c.locked_diffs = d.get("locked_diffs",true);
        rig.configure(c);
        accumulator = 0.0;
        dropped_time = 0.0;
    }
    void reset(const Vector3 &origin) { rig.reset(cv(origin)); accumulator = 0.0; dropped_time = 0.0; }
    void step(double dt, double throttle, double steer, bool brake) {
        if (!std::isfinite(dt) || dt <= 0.0) return;
        auto start = std::chrono::steady_clock::now();
        // Fixed simulation time; bound catch-up after a pause rather than making a giant step.
        dropped_time += std::max(0.0,dt-0.05);
        accumulator += std::min(dt, 0.05);
        while (accumulator + 1e-9 >= FIXED_DT) {
            rig.step((float)FIXED_DT, (float)std::clamp(throttle,-1.0,1.0), (float)std::clamp(steer,-1.0,1.0),brake);
            accumulator -= FIXED_DT;
        }
        auto end = std::chrono::steady_clock::now();
        sim_ms = std::chrono::duration<double,std::milli>(end-start).count();
    }
    void set_terrain(int mode) { rig.set_terrain(mode == 0 ? 0 : 1); }
    void set_drivetrain(bool low, bool locked) { rig.set_drivetrain(low,locked); }
    double terrain_height(double x, double z) const { return rig.terrain_height((float)x,(float)z); }
    Vector3 terrain_normal(double x, double z) const { return gv(rig.terrain_normal((float)x,(float)z)); }
    PackedVector3Array get_nodes() const {
        PackedVector3Array a; a.resize(rig.particles.size());
        for (int i=0;i<(int)rig.particles.size();++i) a.set(i,gv(rig.particles[i].pos));
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
        d["position"]=gv(rig.center()); d["forward"]=gv(rig.forward()); d["up"]=gv(rig.up());
        d["sim_ms"]=sim_ms;
        d["safety_clamps"]=rig.safety_clamp_count();
        d["rejected_states"]=rig.rejected_state_count();
        d["dropped_time"]=rig.time_dropped()+dropped_time;
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
