// Mechanical geometry regressions for the mass-bearing four-link carriers.
// These tests measure this bounded model; they do not certify a real vehicle.
#include "soft_rig.hpp"
#include <iostream>
#include <chrono>
#include <ctime>
#include <stdexcept>
using namespace boltyard;
namespace {
void require(bool value,const char *message){if(!value)throw std::runtime_error(message);}
float mass(const SoftRig &r){float result=0;for(const auto &p:r.particles)result+=1/p.inv_mass;return result;}
Vec3 momentum(const SoftRig &r){Vec3 result;for(const auto&p:r.particles)if(!p.tire)result+=p.velocity*((p.wheel>=0?SoftRig::nodes_per_wheel:1.f)/p.inv_mass);return result;}
void run(SoftRig&r,float seconds,float throttle=0,bool brake=false){for(int i=0;i<int(seconds*120+.5f);++i)r.step(1.f/120,throttle,0,brake);}
void prepare(SoftRig&r,Vec3 origin={0,1.3f,0}){Config c;c.ride_height=.45f;c.suspension_travel=.35f;c.spring_rate=25000;r.configure(c);r.set_terrain(3);r.set_test_rocks({});r.reset(origin);r.dynamic_objects().clear();}
void healthy(const SoftRig&r){require(r.rejected_state_count()==0&&r.safety_clamp_count()==0,"numerical intervention");require(r.damage()<.001f,"ordinary motion damaged chassis");}
}
int main(){const auto started=std::chrono::steady_clock::now();int passed=0,failed=0;auto test=[&](const char*name,auto fn){try{fn();++passed;std::cout<<"PASS "<<name<<'\n';}catch(const std::exception&e){++failed;std::cerr<<"FAIL "<<name<<": "<<e.what()<<'\n';}};
    test("carrier mass allocation preserves total mass and all first100 skin bindings",[]{
        SoftRig r;prepare(r);const auto hubs=r.wheel_hubs;
        require(r.particles.size()==104&&r.physical_node_count()==24&&r.render_node_count()==100,"carrier and skin counts wrong");
        require(std::abs(mass(r)-r.config().mass)<.025f,"carrier mass was added to configured mass");
        for(int mode:{0,3,2,5,4,1,3}){r.set_terrain(mode);require(std::abs(mass(r)-r.config().mass)<.025f,"map change loses mass");require(r.wheel_hubs==hubs,"map changes hub bindings");}
        healthy(r);
        Config base;SoftRig stock;stock.configure(base);stock.set_terrain(3);
        for(float extra:{-24.f,18.f}) {Config equipped=base;equipped.mass+=extra;equipped.wheel_accessory_mass=extra;SoftRig e;e.configure(equipped);e.set_terrain(3);
            for(int i=100;i<104;++i)require(std::abs(e.particles[i].inv_mass-stock.particles[i].inv_mass)<1e-7f,"wheel equipment leaked into axle housing mass");
            for(int w=0;w<4;++w)require(std::abs(e.wheel_unsprung_mass(w)-stock.wheel_unsprung_mass(w)-extra*.25f)<.005f,"wheel equipment was not placed at its wheel");
        }
    });
    test("lower arms stay on their side and uppers triangulate to the differential truss",[]{
        SoftRig r;prepare(r);
        for(int w=0;w<4;++w){Vec3 lower=r.suspension_link_end(w)-r.suspension_link_start(w),upper=r.upper_link_end(w)-r.upper_link_start(w);
            require(lower.length()>.65f&&lower.length()<1.25f,"lower arm incorrectly reaches opposite end of chassis");
            require(r.suspension_link_start(w).x*r.suspension_link_end(w).x>0,"lower arms cross the centerline");
            require(std::abs(upper.x)>.35f,"upper links lack physical triangulation");
            require(r.shock_length(w)>.65f&&r.shock_length(w)<1.4f,"coilover has implausible eye length");
            require(r.shock_start(w).y>r.shock_end(w).y+.5f,"coilover does not reach its actual tower");}
    });
    test("bump articulation keeps four links within millimeters and rotates pinion carrier",[]{
        SoftRig r;prepare(r,{0,3.2f,0});std::vector<CrawlRock> rocks;
        for(int w=0;w<4;++w)rocks.push_back(crawl_rock(w%2?.95f:-.95f,w<2?-1.35f:1.35f,1.5f,2.f,w==0||w==3?2.34f:2.f));
        r.set_test_rocks(rocks);run(r,5,0,true);
        require(r.axle_articulation(0)*r.axle_articulation(1)<-.006f,"opposed wheel supports fail to articulate");
        require(r.suspension_link_error()<.004f,"joint links stretch under static load");
        require(std::abs(r.axle_pitch(0))>.004f||std::abs(r.axle_pitch(1))>.004f,"carrier pitch still follows a fixed chassis axis");
        for(int a=0;a<2;++a){Vec3 axis=(r.particles[r.wheel_hubs[a*2+1]].pos-r.particles[r.wheel_hubs[a*2]].pos).normalized();require(std::abs(axis.dot(r.axle_up(a)))<.001f,"carrier basis is not orthogonal");}
        std::cout<<"  max link error="<<r.suspension_link_error()<<" pitch="<<r.axle_pitch(0)<<","<<r.axle_pitch(1)<<'\n';healthy(r);
    });
    test("drivetrain reaction moves axle pitch without inventing linear momentum",[]{
        float pitch[2];for(int trial=0;trial<2;++trial){SoftRig r;prepare(r,{0,40,0});
            SoftRig baseline=r;baseline.set_neutral(true);run(baseline,.10f);run(r,.10f,trial?.65f:-.65f);pitch[trial]=r.axle_pitch(0)-baseline.axle_pitch(0);
            Vec3 p=momentum(r);require(std::abs(p.x)<1.5f&&std::abs(p.z)<1.5f,"internal wheel torque creates net horizontal impulse");healthy(r);}
        std::cout<<"  reversing torque pitches="<<pitch[0]<<","<<pitch[1]<<'\n';
        require(pitch[0]*pitch[1]<0&&std::abs(pitch[0]-pitch[1])>.0001f,"rotor torque has no opposite carrier reaction");
    });
    test("new-map loose objects spawn above actual terrain and settle on it",[]{
        for(int mode:{4,5}){DynamicObjects props;props.set_terrain(mode);props.reset();
            for(const auto&b:props.bodies())for(auto v:b.shape.vertices){auto p=b.world_point(v);require(p.y-expedition_height(mode,p.x,p.z)>-.002f,"map prop starts buried");}
            props.clear();props.set_static_rocks({});float h=expedition_height(mode,5,4);int id=props.add_crate({5,h+1.3f,4},{.5f,.5f,.5f},35);
            for(int i=0;i<720;++i)props.step(1.f/240);
            const auto&b=props.bodies()[id];float gap=1e9f;for(auto v:b.shape.vertices){Vec3 p=b.world_point(v);gap=std::min<float>(gap,p.y-expedition_height(mode,p.x,p.z));}
            require(std::abs(gap)<.03f&&b.position.finite()&&b.velocity.length()<.1f,"loose crate did not rest on its map heightfield");}
    });
    // These integration drives retain the complete authored forest, granite
    // contacts and moving objects; they steer through actual course geometry.
    // Timing is informative desktop CPU work, never an Android frame-rate gate.
    for(int mode:{4,5})test(mode==4?"Rockies ninety-second forest route":"Karelia ninety-second forest route",[mode]{
        SoftRig r;Config c;c.ride_height=.45f;c.suspension_travel=.35f;c.spring_rate=25000;
        r.configure(c);r.set_terrain(mode);r.reset({0,1.4f,8});run(r,3,0,true);
        const auto &points=expedition_trail_points(mode);int waypoint=1;
        float minimum_up=1,maximum_speed=0;
        const auto cpu_start=std::clock();
        for(int frame=0;frame<120*90;++frame){
            Vec3 position=r.center();Vec3 delta{points[waypoint].x-position.x,0,points[waypoint].z-position.z};
            if(delta.length()<4&&waypoint<4) {
                ++waypoint;delta={points[waypoint].x-position.x,0,points[waypoint].z-position.z};
            }
            float desired=std::atan2(delta.x,-delta.z),actual=std::atan2(r.forward().x,-r.forward().z);
            float error=std::remainder(desired-actual,6.28318530718f);
            r.step(1.f/120,.24f,std::clamp(error*2.1f,-1.f,1.f),false);
            minimum_up=std::min<float>(minimum_up,r.up().y);maximum_speed=std::max<float>(maximum_speed,r.speed());
        }
        const double cpu_seconds=double(std::clock()-cpu_start)/CLOCKS_PER_SEC;
        std::cout<<"  map="<<mode<<" waypoint="<<waypoint<<" center="<<r.center().x<<","<<r.center().y<<","<<r.center().z
                 <<" minimum_up="<<minimum_up<<" max_speed="<<maximum_speed
                 <<" desktop_CPU_seconds="<<cpu_seconds<<" us/substep="<<cpu_seconds*1e6/(90*240)<<'\n';
        require(waypoint>=3,"vehicle failed to advance through the forest route");
        require(minimum_up>.85f,"ordinary forest driving tipped the vehicle");
        require(maximum_speed<3.f,"low-range speed regulator failed on terrain");
        healthy(r);
    });
    std::cout<<"LINKED SUSPENSION: "<<passed<<" passed, "<<failed<<" failed; wall_seconds="
             <<std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count()<<'\n';
    return failed?1:0;
}
