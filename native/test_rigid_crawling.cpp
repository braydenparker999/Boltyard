#include "soft_rig.hpp"
#include <cstdio>
#include <stdexcept>
using namespace boltyard;
static void check(bool ok,const char* message){if(!ok)throw std::runtime_error(message);}
static void run(SoftRig&r,float seconds,float throttle=0,bool brake=false){for(int i=0;i<int(seconds*240+.5f);++i)r.step(1.f/240,throttle,0,brake);}
static void prepare(SoftRig&r){r.set_terrain(3);r.set_test_rocks({});r.reset({0,1.5f,0});r.dynamic_objects().clear();run(r,3,0,true);}
int main(){int passed=0,failed=0;auto test=[&](const char*name,auto fn){try{fn();++passed;printf("PASS %s\n",name);}catch(const std::exception&e){++failed;printf("FAIL %s: %s\n",name,e.what());}};
 test("rigid velocity projection conserves linear and angular momentum",[]{
  SoftRig r;RigidChassis cluster;cluster.initialize(r.particles);cluster.project_positions(r.particles);
  for(int i=0;i<16;++i)r.particles[i].velocity={.13*i,std::sin(i*.7),std::cos(i*.4)};
  auto momentum=[&](){std::array<Vec3,2> p{};for(int i=0;i<16;++i){const double m=1./r.particles[i].inv_mass;p[0]+=RigidChassis::scale(r.particles[i].velocity,m);p[1]+=RigidChassis::scale((r.particles[i].pos-cluster.center).cross(r.particles[i].velocity),m);}return p;};
  auto before=momentum();cluster.project_velocities(r.particles);auto after=momentum();
  check((before[0]-after[0]).length()<1e-7&&(before[1]-after[1]).length()<1e-7,"projection invented momentum");
 });
 test("impact rotates and translates the complete rigid chassis",[]{
  SoftRig r;r.set_terrain(3);r.set_test_rocks({});r.reset({0,60,0});r.dynamic_objects().clear();r.set_neutral(true);
  float distances[16][16];for(int i=0;i<16;++i)for(int j=0;j<16;++j)distances[i][j]=(r.particles[i].pos-r.particles[j].pos).length();
  r.apply_impact({7000,0,1500});float worst=0;
  for(int step=0;step<240;++step){r.step(1.f/240,0,0,false);for(int i=0;i<16;++i)for(int j=0;j<16;++j)worst=std::max(worst,std::abs((r.particles[i].pos-r.particles[j].pos).length()-distances[i][j]));}
  check(worst<2e-6f,"cab/frame flex remains");check(r.center().x>1&&r.damage()==0&&r.broken_count()==0,"impact lost momentum or created damage");
  check(r.rejected_state_count()==0&&r.safety_clamp_count()==0,"ordinary impact required numerical recovery");
 });
 test("mobile auto-hold prevents idle creep and releases into a crawl",[]{
  SoftRig r;Config c;c.inboard_coilovers=true;r.configure(c);r.set_auto_hold(true);prepare(r);auto start=r.center();run(r,15);
  check(r.auto_hold_active()&&(r.center()-start).length()<.01f,"idle creep with auto-hold");
  run(r,3,.18f);check(!r.auto_hold_active()&&r.center().z<start.z-.4f,"throttle cannot release hold");
  run(r,4,0,true);check(r.auto_hold_active()&&r.speed()<.02f,"brake-to-stop did not latch hold");
  start=r.center();run(r,10);check((r.center()-start).length()<.01f,"released brake lost its hold");
 });
 test("auto-hold never glues a truck to an unsupported or slippery slope",[]{
  SoftRig r;r.set_auto_hold(true);r.set_terrain(3);auto rock=crawl_rock(0,0,30,80,10,.5f);rock.surface=.01f;rock.authored_surface=true;
  r.set_test_rocks({rock});r.reset({0,11.5f,0});r.dynamic_objects().clear();auto start=r.center();run(r,4);
  check((r.center()-start).length()>.5f,"hold canceled gravity/friction limits");
  SoftRig airborne;airborne.set_auto_hold(true);airborne.set_terrain(3);airborne.set_test_rocks({});airborne.reset({0,50,0});airborne.dynamic_objects().clear();start=airborne.center();run(airborne,1);
  check(start.y-airborne.center().y>4.5f,"hold suspended truck in air");
 });
 printf("RIGID CRAWLING: %d passed, %d failed\n",passed,failed);return failed?1:0;
}
