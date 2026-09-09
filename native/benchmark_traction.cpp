// Reproduce lateral creep independently of imported map assets.
// g++ -std=c++17 -O2 -I native native/benchmark_traction.cpp -o /tmp/traction
// Representative heavy crawler; this is not a captured live phone configuration.
#include "soft_rig.hpp"
#include <cstdio>
using namespace boltyard;
int main(){
 for(float grip:{.12f,1.1f,2.2f})for(int brake:{0,1})for(int side:{1})for(float angle:{20.f})for(float throttle:{0.f}){
 imported_terrain::spacing=1;imported_terrain::extent=512;imported_terrain::surface_grip={grip};imported_terrain::surface_ids={1};
 std::vector<float> h(1025*1025);std::vector<uint8_t> m(h.size(),0);
 float slope=std::tan(angle*3.14159265f/180);
 for(int z=0;z<1025;++z)for(int x=0;x<1025;++x)h[z*1025+x]=side?(x-512)*slope:-(z-512)*slope;
 imported_terrain::load(h.data(),h.size(),m.data(),m.size());
 SoftRig r;Config cfg;cfg.mass=1675;cfg.tire_grip=1.3;cfg.tire_pressure=.55;cfg.tire_radius=.48;cfg.engine_torque=900;cfg.final_drive=.82;cfg.ride_height=.45;cfg.spring_rate=16000;cfg.damping=2250;cfg.suspension_travel=.34;r.configure(cfg);r.set_terrain(7);r.reset({0,2,0});
 for(int i=0;i<360;++i)r.step(1.f/120,0,0,true);
 auto start=r.center();float load=0;for(int w=0;w<4;++w)load+=r.wheel_normal_load(w);
 for(int i=0;i<600;++i)r.step(1.f/120,throttle,0,brake);
 auto d=r.center()-start;float slip=0;for(int w=0;w<4;++w)slip+=r.wheel_slip(w)/4;
 printf("grip=%.2f brake=%d side=%d deg=%.0f throttle=%.1f dx=%.3f forward=%.3f speed=%.3f slip=%.3f normal_load=%.0f up=%.3f\n",grip,brake,side,angle,throttle,d.x,-d.z,r.speed(),slip,load,r.up().y);
 }
}
