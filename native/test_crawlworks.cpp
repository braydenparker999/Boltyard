// Crawlworks 1.0 mechanical scenarios. SI-unit thresholds are game-model
// regressions, not claims of calibration against a measured vehicle.
#include "soft_rig.hpp"
#include <iostream>
#include <stdexcept>
using namespace boltyard;
namespace {
void check(bool b, const char *message) { if (!b) throw std::runtime_error(message); }
void run(SoftRig &r, float seconds, float throttle = 0, bool brake = true) {
    for (int i = 0; i < int(seconds * 120 + .5f); ++i) r.step(1.f / 120, throttle, 0, brake);
}
void healthy(const SoftRig &r) {
    check(r.rejected_state_count() == 0 && r.safety_clamp_count() == 0 && r.time_dropped() == 0, "numerical intervention");
    check(r.damage() < .001f, "ordinary scenario damaged frame");
}
Config crawler() { Config c; c.ride_height=.45f; c.suspension_travel=.35f; c.spring_rate=25000; return c; }
void prepare(SoftRig &r, const Config &c, const std::vector<CrawlRock> &rocks, Vec3 origin) {
    r.configure(c); r.set_terrain(3); r.set_test_rocks(rocks); r.reset(origin); r.dynamic_objects().clear();
}
float mass(const SoftRig &r) { float m=0; for (const auto &p:r.particles) m+=1/p.inv_mass; return m; }
}
int main() {
    int passed=0, failed=0;
    auto test=[&](const char *name, auto f) { try { f(); ++passed; std::cout<<"PASS "<<name<<'\n'; }
        catch(const std::exception &e) { ++failed; std::cerr<<"FAIL "<<name<<": "<<e.what()<<'\n'; } };
    test("cross axle terrain rotates coupled housings while maintaining track", [] {
        SoftRig r; auto c=crawler(); std::vector<CrawlRock> rocks;
        for(int w=0;w<4;++w) rocks.push_back(crawl_rock(w%2?.95f:-.95f,w<2?-1.35f:1.35f,1.5f,2.f,
            w==0||w==3?2.32f:2.f));
        prepare(r,c,rocks,{0,3.5f,0}); run(r,6);
        std::cout<<"  articulation="<<r.axle_articulation(0)<<","<<r.axle_articulation(1)<<" up="<<r.up().y<<'\n';
        check(r.axle_articulation(0)*r.axle_articulation(1)<-.004f,"axles failed to counter articulate");
        for(int axle=0;axle<2;++axle) {
            Vec3 span=r.particles[r.wheel_hubs[axle*2+1]].pos-r.particles[r.wheel_hubs[axle*2]].pos;
            check(std::abs(span.length()-c.track_width)<.006f,"beam axle changed track width");
        }
        float minimum_load=1e9f; for(int w=0;w<4;++w) minimum_load=std::min(minimum_load,r.wheel_normal_load(w));
        std::cout<<"  lightest wheel support="<<minimum_load<<" N\n";
        check(minimum_load>100,"articulation lost a supported wheel");
        check(r.up().y>.98f,"axle terrain forced excessive chassis roll"); healthy(r);
    });
    test("wheel equipment places its signed mass in unsprung assemblies", [] {
        SoftRig stock; Config c=stock.config();
        for(float extra:{-24.f,18.f}) {
            c.mass=1200+extra; c.wheel_accessory_mass=extra; SoftRig equipped; equipped.configure(c);
            check(std::abs(mass(equipped)-c.mass)<.025f,"equipment total mass mismatch");
            for(int w=0;w<4;++w) check(std::abs(equipped.wheel_unsprung_mass(w)-stock.wheel_unsprung_mass(w)-extra*.25f)<.005f,"wheel mass diffused into body");
            check(std::abs(equipped.particles[0].inv_mass-stock.particles[0].inv_mass)<1e-7f,"wheel accessory changed sprung mass");
        }
    });
    test("loaded pressure deformation agrees with contact load and patch size", [] {
        float compression[2], patch[2];
        for(int i=0;i<2;++i) {
            SoftRig r; Config c; c.tire_pressure=i?1.5f:.5f;
            prepare(r,c,{crawl_rock(0,0,12,30,2)},{0,3.5f,0}); run(r,5);
            float load=0; for(int w=0;w<4;++w) load+=r.wheel_load(w);
            check(load>c.mass*9.5f&&load<c.mass*10.1f,"support load does not match gravity");
            compression[i]=r.wheel_compression(0); patch[i]=r.wheel_contact_patch_length(0);
            check(std::abs(compression[i]*300000*c.tire_pressure-r.wheel_normal_load(0))<15,"load and deformation disagree");
            check(r.wheel_contact_normal(0).y>.99f,"incorrect support plane"); healthy(r);
        }
        std::cout<<"  compression="<<compression[0]<<","<<compression[1]<<" patch="<<patch[0]<<","<<patch[1]<<'\n';
        check(compression[0]>compression[1]*2.5f&&patch[0]>patch[1]*1.5f,"pressure lacks loaded footprint tradeoff");
    });
    test("rebound tuning suppresses the second motion after a landing", [] {
        float upward_speed[2], rms[2];
        for(int setting=0;setting<2;++setting) {
            SoftRig r; Config c=crawler(); c.spring_rate=18000; c.compression_damping=1400;
            c.rebound_damping=setting?7000.f:1000.f;
            prepare(r,c,{},{0,1.4f,0}); float max_up=0, squared=0; int count=0;
            for(int i=0;i<360;++i) {
                r.step(1.f/120,0,0,true);
                if(i>45&&i<180) { max_up=std::max(max_up,r.velocity().y); squared+=r.velocity().y*r.velocity().y; ++count; }
            }
            upward_speed[setting]=max_up; rms[setting]=std::sqrt(squared/count); healthy(r);
        }
        std::cout<<"  landing rebound peak="<<upward_speed[0]<<","<<upward_speed[1]<<" m/s\n";
        check(upward_speed[1]<upward_speed[0]*.8f&&rms[1]<rms[0]*.92f,"separate rebound damping has no causal settling effect");
    });
    test("front and rear lockers have separate causal traction", [] {
        auto distance=[](bool front, bool rear) {
            SoftRig r; Config c; c.front_locked=front; c.rear_locked=rear;
            std::vector<CrawlRock> rocks;
            for(int w=0;w<4;++w) { auto rock=crawl_rock(w%2?2.f:-2.f,w<2?-6.f:6.f,4,12,2); rock.surface=w==1?1.f:.025f; rocks.push_back(rock); }
            prepare(r,c,rocks,{0,3.5f,0}); run(r,4); Vec3 start=r.center(); run(r,1.5f,.16f,false); healthy(r); return start.z-r.center().z;
        };
        float front=distance(true,false),rear=distance(false,true);
        std::cout<<"  front locker="<<front<<" rear locker="<<rear<<'\n';
        check(front>rear*1.6f&&front>.55f,"locker selection does not control the selected axle");
    });
    test("axle differential housing can high center separately from the frame", [] {
        float front_load[2];
        for(int enabled=0;enabled<2;++enabled) {
            SoftRig r; Config c; c.solid_axles=enabled;
            prepare(r,c,{crawl_rock(0,-1.35f,.6f,.6f,.52f)},{0,1.4f,0}); run(r,5);
            front_load[enabled]=r.wheel_load(0)+r.wheel_load(1);
            if(enabled) check(std::abs(r.axle_clearance(0))<.015f,"differential lacks physical clearance contact");
            healthy(r);
        }
        std::cout<<"  front tire load without/with housing="<<front_load[0]<<","<<front_load[1]<<'\n';
        check(front_load[0]>3000&&front_load[1]<700,"housing did not unload front tires");
    });
    test("very low throttle creeps with finite slip and brakes without drift", [] {
        SoftRig r; prepare(r,Config{},{crawl_rock(0,0,12,40,2)},{0,3.5f,8}); run(r,4);
        Vec3 start=r.center(); float maximum_slip=0;
        for(int i=0;i<600;++i) { r.step(1.f/120,.008f,0,false); for(int w=0;w<4;++w) maximum_slip=std::max(maximum_slip,r.wheel_slip(w)); }
        float distance=start.z-r.center().z; std::cout<<"  creep distance="<<distance<<" slip="<<maximum_slip<<'\n';
        check(distance>.03f&&distance<3.f&&maximum_slip<.7f,"near-rest tire coupling unstable or locked");
        run(r,2); start=r.center(); run(r,5); check((r.center()-start).length()<.006f,"parked brake creep"); healthy(r);
    });
    test("tire pushes a movable obstacle through contact impulses", [] {
        SoftRig r; prepare(r,crawler(),{},{0,1.5f,0}); run(r,4);
        const int id=r.dynamic_objects().add_crate({-.95f,.19f,-2.0f},{.56f,.36f,.5f},24);
        run(r,1); const Vec3 start=r.dynamic_objects().bodies()[id].position;
        run(r,3,.18f,false);
        const auto &body=r.dynamic_objects().bodies()[id];
        std::cout<<"  prop movement="<<(body.position-start).length()<<" car z="<<r.center().z<<'\n';
        check((body.position-start).length()>.3f,"drive failed to move loose obstacle");
        check(body.position.finite()&&body.velocity.length()<8&&body.position.y>-.1f,"loose object escaped physical bounds"); healthy(r);
    });
    std::cout<<"CRAWLWORKS: "<<passed<<" passed, "<<failed<<" failed\n"; return failed?1:0;
}
