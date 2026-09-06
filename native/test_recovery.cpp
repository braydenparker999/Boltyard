#include "soft_rig.hpp"
#include <cassert>
#include <iostream>
using namespace boltyard;
int main(){
    SoftRig rig; rig.set_terrain(0); rig.reset({25,2,25});
    rig.beams[0].broken=true;rig.beams[1].plastic_strain=.12f;
    auto center=rig.center();
    for(auto&p:rig.particles){Vec3 d=p.pos-center;p.pos=center+Vec3(d.x,-d.y,-d.z);p.prev=p.pos;p.velocity={3,4,5};}
    float damage=rig.damage();int broken=rig.broken_count();
    assert(rig.recover_near({25,0,25},{1,0,0}));
    assert(rig.up().y>.99f&&rig.forward().x>.99f&&rig.speed()<.001f);
    assert(rig.damage()==damage&&rig.broken_count()==broken);
    assert(std::abs(rig.center().x-25)<.01f&&std::abs(rig.center().z-25)<.01f);
    for(const auto&p:rig.particles)assert(p.pos.finite()&&p.pos.y>=rig.terrain_height(p.pos.x,p.pos.z));
    auto before=rig.center();assert(!rig.recover_near({10000,0,10000},{0,0,-1}));
    assert((rig.center()-before).length()<.001f);
    for(int i=0;i<120;i++)rig.step(1.f/60,0,0,true);
    assert(rig.up().y>.8f&&rig.center().finite());
    for(int mode:{3,4,5}){
        SoftRig trail;trail.set_terrain(mode);trail.reset({0,2,8});
        assert(trail.recover_near({0,2,8},{0,0,-1}));
        for(int i=0;i<120;i++)trail.step(1.f/60,0,0,true);
        assert(trail.up().y>.8f&&trail.center().finite());
    }
    std::cout<<"RECOVERY: damage, heading, support, rejection and all trail starts passed\n";
}
