// Dry static support and low-grip breakaway regression.
// Uses production solver and synthetic terrain; no external assets.
// Representative heavy crawler; this is not a captured live phone configuration.
#include "soft_rig.hpp"
#include <cstdio>
#include <stdexcept>
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
 r.set_neutral(true);auto start=r.center();float load=0;for(int w=0;w<4;++w)load+=r.wheel_normal_load(w);
 for(int i=0;i<600;++i)r.step(1.f/120,throttle,0,brake);
 auto d=r.center()-start;
 printf("  side drift=%f speed=%f grip=%f brake=%d\n",d.x,r.speed(),grip,brake);
 if(grip>1.f && (std::abs(d.x)>.08f || r.speed()>.015f)) throw std::runtime_error("dry side slope continues creeping");
 if(grip<.2f && (std::abs(d.x)<5 || r.speed()<1)) throw std::runtime_error("friction limit no longer permits sliding");
 if(r.rejected_state_count() || r.safety_clamp_count()) throw std::runtime_error("slope required numerical intervention");float slip=0;for(int w=0;w<4;++w)slip+=r.wheel_slip(w)/4;
 printf("grip=%.2f brake=%d side=%d deg=%.0f throttle=%.1f dx=%.3f forward=%.3f speed=%.3f slip=%.3f normal_load=%.0f up=%.3f\n",grip,brake,side,angle,throttle,d.x,-d.z,r.speed(),slip,load,r.up().y);
 }
 for(float command:{-1.f,1.f}) {
  SoftRig r;r.set_terrain(3);r.set_test_rocks({});r.reset({0,100,0});r.dynamic_objects().clear();r.set_neutral(true);
  for(int i=0;i<60;++i) {
   const float before=r.steering_angle();r.step(1.f/120,0,command,false);
   if(std::abs(r.steering_angle()-before)>1.8f/120+.0001f) throw std::runtime_error("steering exceeds rate limit");
  }
  const Vec3 right=r.forward().cross(r.up()).normalized();
  float angles[2];
  for(int w=0;w<2;++w) angles[w]=std::atan2(-r.wheel_axle_direction(w).dot(r.forward()),r.wheel_axle_direction(w).dot(right));
  const int inner=command>0?1:0;
  if(std::abs(angles[inner])<=std::abs(angles[inner^1])) throw std::runtime_error("inner wheel does not steer farther");
  const float radius_difference=r.config().wheelbase*(1/std::tan(std::abs(angles[inner^1]))-1/std::tan(std::abs(angles[inner])));
  if(std::abs(radius_difference-r.config().track_width)>.03f) throw std::runtime_error("front wheels disagree on turning center");
 }
 puts("STATIC TRACTION: 6 slope controls and 2 steering directions passed");

}
