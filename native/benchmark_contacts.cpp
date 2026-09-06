// Deterministic host CPU comparison at 30 Hz, 240 Hz physics, nine iterations.
// Counters compile out of shipping builds. No renderer or Android FPS claims.
#define BOLT_PROFILE_CONTACTS
#include "soft_rig.hpp"
#include <chrono>
#include <iostream>
#include <iomanip>
using namespace boltyard;
int main() {
    std::cout << "scenario,median_ms,p95_ms,p99_ms,worst_ms,over33,wheels_rock_avg,patches_avg,queries_frame,triangles_frame,discarded_s,final_y,damage\n";
    for(int scenario=0;scenario<9;++scenario) {
        const char*names[]={"ground","one","two_same","two_separate","diagonal","four","ledge_roll","silverpine_roll","karelia_roll"};
        SoftRig r; Config cfg;cfg.ride_height=.45f;cfg.suspension_travel=.35f;cfg.spring_rate=25000;
        r.configure(cfg);r.set_terrain(scenario>=7?scenario-3:3);
        if(scenario<7) {
            std::vector<CrawlRock> rocks;
            auto add=[&](float x,float z,float width,float depth) {
                auto rock=expedition_granite(4,x,z,width,depth,.26f,0,138);
                const float ground=expedition_height(4,x,z);
                for(auto&p:rock.vertices)p.y-=ground;
                rock.center.y-=ground;rocks.push_back(rock);
            };
            if(scenario==2)add(0,-1.35f,4,2);
            else if(scenario==6)rocks.push_back(crawl_rock(0,-2,8,8,.3f));
            else for(int w=0;w<4;++w)if(scenario==5||(scenario==4&&(w==0||w==3))||(scenario==3&&w<2)||(scenario==1&&w==0))add(w%2?.95f:-.95f,w<2?-1.35f:1.35f,1.55f,2);
            r.set_test_rocks(rocks);r.reset({0,1.5f,scenario==6?5.f:0.f});r.dynamic_objects().clear();
        } else r.reset(scenario==7?Vec3{11,expedition_height(4,11,-50)+1.5f,-50}:Vec3{-89,expedition_height(5,-89,-119)+1.5f,-119});
        for(int f=0;f<90;++f)r.step(1.f/30,0,0,true);
        rock_query_counters={};std::vector<double> times;double wheels=0,patches=0;int over=0;
        for(int f=0;f<180;++f) {
            auto start=std::chrono::steady_clock::now();r.step(1.f/30,scenario>=6&&f<140?.3f:0,0,scenario<6||f>=140);
            double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();times.push_back(ms);over+=ms>33.333;
            for(int w=0;w<4;++w){wheels+=r.wheel_rock_load(w)>20;patches+=r.wheel_contact_patches(w).size();}
        }
        std::sort(times.begin(),times.end());
        std::cout<<std::fixed<<std::setprecision(5)<<names[scenario]<<','<<times[90]<<','<<times[171]<<','<<times[178]<<','<<times.back()<<','<<over<<','<<wheels/180<<','<<patches/180<<','<<rock_query_counters.calls/180<<','<<rock_query_counters.triangles/180<<','<<r.time_dropped()<<','<<r.center().y<<','<<r.damage()<<std::endl;
    }
}
