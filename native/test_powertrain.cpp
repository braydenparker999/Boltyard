#include "soft_rig.hpp"
#include <cstdio>
#include <stdexcept>
using namespace boltyard;
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
static void run(SoftRig&r,float seconds,float throttle=0,bool brake=false,float steer=0,float dt=1.f/120){for(int i=0;i<int(seconds/dt+.5f);++i)r.step(dt,throttle,steer,brake);}
static void prepare(SoftRig&r){r.set_terrain(3);r.set_test_rocks({});r.reset({0,1.5f,0});r.dynamic_objects().clear();run(r,3,0,true);}
int main(){int failures=0,passed=0;auto test=[&](const char *name,auto fn){try{fn();++passed;printf("PASS %s\n",name);}catch(const std::exception&e){++failures;printf("FAIL %s: %s\n",name,e.what());}};
test("gear ratios independent of map and neutral disconnects torque",[]{
 SoftRig a,b;prepare(a);prepare(b);b.set_terrain(0);run(a,2,.2f);run(b,2,.2f);
 check((a.center()-b.center()).length()<.015f,"map changed vehicle dynamics on identical ground");
 SoftRig n;prepare(n);n.set_neutral(true);SoftRig coast=n;run(n,3,1);run(coast,3);
 check((n.center()-coast.center()).length()<.015f&&n.engine_rpm()>2000,"neutral cannot rev without driving");
 check(a.drive_ratio()>30&&a.drive_ratio()<40,"low range ratio not physically specified");
 a.set_drivetrain(false,true);run(a,.1f);check(a.drive_ratio()>12&&a.drive_ratio()<13,"high range ratio incorrect");
});
test("finite brakes have measurable stopping distance and pedal modulation",[]{
 float distances[2];for(int level=0;level<2;++level){SoftRig r;prepare(r);r.set_neutral(true);
  for(auto&p:r.particles)if(!p.tire)p.velocity={0,0,-6};
  // Accelerate through actual rolling contact first to synchronize rotors.
  run(r,.5f);r.set_brake_pressure(level?1.f:.12f);auto start=r.center();r.step(1.f/240,0,0,true);
  check(r.speed()>4,"brake teleported moving truck to rest");run(r,5,0,true);distances[level]=start.z-r.center().z;
  check(r.speed()<.08f&&r.safety_clamp_count()==0,"brake failed to stop safely");
 }
 printf("  light/full brake distance %.3f / %.3f m\n",distances[0],distances[1]);
 check(distances[0]>distances[1]*1.3f&&distances[1]>.2f,"brake torque ignores pedal modulation");
});
test("longitudinal and lateral contact share one friction budget",[]{
 SoftRig r;prepare(r);for(auto&p:r.particles)if(!p.tire)p.velocity.x=2;
 for(int i=0;i<600;++i){r.step(1.f/120,.65f,.5f,false);for(int w=0;w<4;++w)check(r.wheel_friction_usage(w)<=1.001f,"contact exceeded combined Coulomb cap");}
 check(r.rejected_state_count()==0&&r.safety_clamp_count()==0,"combined drive destabilized solver");
});
test("braked dry incline settles and holds without unlimited brake force",[]{
 SoftRig r;r.set_terrain(3);r.set_test_rocks({crawl_rock(0,0,30,80,10,.3f)});r.reset({0,11.5f,0});r.dynamic_objects().clear();run(r,5,0,true);
 auto start=r.center();run(r,30,0,true);printf("  parked incline drift %.6f m\n",(r.center()-start).length());
 check((r.center()-start).length()<.02f,"persistent braked incline drift");
 r.set_brake_pressure(.01f);r.set_neutral(true);run(r,3,0,true);check((r.center()-start).length()>.10f,"insufficient brake torque glued wheels to hill");
});
test("neutral coast dissipates energy and input cadence preserves trajectory",[]{
 SoftRig r;prepare(r);r.set_neutral(true);for(auto&p:r.particles)if(!p.tire)p.velocity={2,0,-3};
 float start=r.speed();run(r,2);check(r.speed()<start&&r.up().y>.98f,"passive contacts add translational energy");
 SoftRig a,b;prepare(a);prepare(b);run(a,4,.3f,false,.15f,1.f/30);run(b,4,.3f,false,.15f,1.f/120);
 check((a.center()-b.center()).length()<.02f,"render cadence changes physical path");
});
test("engine braking depends on transmission connection",[]{
 SoftRig driven;prepare(driven);run(driven,4,.6f);SoftRig neutral=driven;neutral.set_neutral(true);
 run(driven,2);run(neutral,2);printf("  in gear/neutral coast %.3f / %.3f m/s\n",driven.speed(),neutral.speed());
 check(driven.speed()<neutral.speed()*.9f,"gear connection produces no engine braking");
});
test("parking brake is rear-only and transfer case couples axle carriers",[]{
 SoftRig r;prepare(r);r.set_neutral(true);r.set_parking_brake(true);run(r,.1f);
 check(r.brake_torque(0)==0&&r.brake_torque(1)==0&&r.brake_torque(2)==3000&&r.brake_torque(3)==3000,"parking brake applied service brakes");
 r.set_parking_brake(false);r.set_neutral(false);r.set_drivetrain(true,false);run(r,2,.3f,false,.5f);
 float mismatch=r.wheel_angular_velocity(0)+r.wheel_angular_velocity(1)-r.wheel_angular_velocity(2)-r.wheel_angular_velocity(3);
 check(std::abs(mismatch)<.001f,"4WD transfer case allows front/rear carrier speed mismatch");
 check(std::abs(r.wheel_angular_velocity(0)-r.wheel_angular_velocity(1))>.01f,"open axle cannot differentiate around a turn");
});
test("light brake can meter automatic idle creep without removing drive torque",[]{
 SoftRig a,b;prepare(a);prepare(b);b.set_brake_pressure(.08f);auto start=a.center();
 run(a,3,.04f);run(b,3,.04f,true);
 printf("  idle / metered advance %.3f / %.3f m\n",start.z-a.center().z,start.z-b.center().z);
 check(a.center().z<b.center().z-.2f,"brake cannot meter creep");
 check(a.engine_rpm()>500&&b.engine_rpm()>500,"brake froze engine rotation");
});
printf("POWERTRAIN: %d passed, %d failed\n",passed,failures);return failures?1:0;
}
