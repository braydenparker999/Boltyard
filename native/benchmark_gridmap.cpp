// Run only in a checkout with the owner's converted Gridmap assets. Compare
// ordinary build with -DBOLT_DISABLE_LOCAL_CULL; trajectory files must match.
#define BOLT_PROFILE_CONTACTS
#include "soft_rig.hpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <iomanip>
using namespace boltyard;
template<class T>std::vector<T> read(const char*path){std::ifstream f(path,std::ios::binary|std::ios::ate);auto n=f.tellg();if(n<0)throw std::runtime_error(path);std::vector<T> v(n/sizeof(T));f.seekg(0);f.read((char*)v.data(),n);return v;}
int main(int argc,char**argv){
 if(argc!=2){std::cerr<<"Pass an output prefix\n";return 2;}
 auto h=read<float>("data/gridmap/height.bin");auto m=read<uint8_t>("data/gridmap/surface.bin");auto rocks=read<uint8_t>("data/gridmap/scenery_collision.bin");
 imported_terrain::spacing=1;imported_terrain::extent=512;
 imported_terrain::surface_grip={1.05f,.78f,1.1f,.55f,.7f,1.05f,.78f,.85f,1.05f,.12f};
 imported_terrain::surface_ids={0,0,1,3,4,0,0,0,0,0};
 if(!imported_terrain::load(h.data(),h.size(),m.data(),m.size())||!imported_scenery::load(rocks.data(),rocks.size()))return 2;
 Config c;c.tire_radius=.54f;c.tire_pressure=.7f;c.tire_grip=1.3f;c.tire_width_scale=1.232f;c.wheelbase=2.75f;c.track_width=2.1f;
 c.spring_rate=20000;c.damping=c.compression_damping=c.rebound_damping=3360;c.ride_height=.45f;c.compression_travel=.324f;c.suspension_travel=.3f;
 c.engine_torque=900;c.final_drive=1.35f;c.front_accessory_mass=75;c.roof_accessory_mass=65;c.wheel_accessory_mass=18;
 std::cout<<"scenario,median_ms,p95_ms,queries_per_tick,drift_m,speed,clamps,rejected,trajectory_hash\n";
 for(int scenario=0;scenario<4;++scenario){
  c.inboard_coilovers=scenario>=2;SoftRig r;r.configure(c);r.set_auto_hold(true);r.set_terrain(7);r.reset({19.1315,1.5,-122.978});r.dynamic_objects().clear();
  if(scenario){Vec3 f=Vec3{.998079,-.057433,-.023234}.normalized(),u{.06195,.9203,.386278};Vec3 right=f.cross(u).normalized();u=right.cross(f).normalized();Vec3 origin=r.center();
   for(auto&p:r.particles){Vec3 q=p.pos-origin;p.pos=p.prev=Vec3{183.874,11.26008,-82.00634}+right*q.x+u*q.y-f*q.z;p.velocity={};}}
  for(int i=0;i<120;++i)r.step(1.f/60,0,0,true);
  auto start=r.center();std::vector<double> times;rock_query_counters={};
  uint64_t hash=14695981039346656037ULL;
  auto consume=[&](const Vec3&v){const auto* bytes=reinterpret_cast<const unsigned char*>(&v);for(size_t i=0;i<sizeof(v);++i){hash^=bytes[i];hash*=1099511628211ULL;}};
  for(int i=0;i<240;++i){auto begin=std::chrono::steady_clock::now();r.step(1.f/60,scenario==3?.22f:0,scenario==3?.12f:0,false);
   times.push_back(std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count());
   for(const auto&p:r.particles){consume(p.pos);consume(p.velocity);}}
  std::sort(times.begin(),times.end());std::cout<<scenario<<","<<std::fixed<<std::setprecision(6)<<times[120]<<","<<times[228]<<","<<rock_query_counters.calls/240.0<<","<<(r.center()-start).length()<<","<<r.speed()<<","<<r.safety_clamp_count()<<","<<r.rejected_state_count()<<","<<hash<<std::endl;
  if(r.safety_clamp_count()||r.rejected_state_count()||(!r.auto_hold_active()&&scenario!=3))return 1;
 }
}
