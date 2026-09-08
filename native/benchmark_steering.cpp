// Steering sweep on a flat, obstacle-free surface using production acceleration.
// g++ -O2 -std=c++17 -I native native/benchmark_steering.cpp -o /tmp/steering
// This tests a lifted crawler, not measured real-vehicle calibration.
#include "soft_rig.hpp"
#include <cstdio>
using namespace boltyard;
int main(){for(bool locked:{false,true})for(float speed:{2.f,8.f,15.f})for(float steer:{.25f,.65f}){
 SoftRig r;Config c;c.low_range=false;c.locked_diffs=locked;c.tire_grip=1.3;c.ride_height=.45;c.suspension_travel=.3;r.configure(c);r.set_terrain(3);r.set_test_rocks({});r.reset({0,1.5,0});r.dynamic_objects().clear();
 for(int i=0;i<360;++i)r.step(1.f/120,0,0,true);
 // Launch through production drive forces so wheel angular speed is consistent.
 for(int i=0;i<2400&&r.speed()<speed;++i)r.step(1.f/120,1,0,false);
 float initial=r.speed(),minup=1,maxlat=0,maxyaw=0;Vec3 f=r.forward();float yaw=0;
 for(int i=0;i<360;++i){r.step(1.f/120,.2f,steer,false);auto n=r.forward();float dy=std::atan2(f.x*n.z-f.z*n.x,f.dot(n));yaw+=dy;maxyaw=std::max(maxyaw,std::abs(dy)*120);f=n;minup=std::min(minup,r.up().y);auto right=n.cross(r.up()).normalized();maxlat=std::max(maxlat,std::abs(r.velocity().dot(right)));}
 printf("locked=%d entry=%.2f steer=%.2f end=%.2f yaw_deg=%.1f max_yaw=%.2f max_side=%.2f min_up=%.3f damage=%.3f clamps=%d\n",locked,initial,steer,r.speed(),yaw*57.2958,maxyaw,maxlat,minup,r.damage(),r.safety_clamp_count());
}}
