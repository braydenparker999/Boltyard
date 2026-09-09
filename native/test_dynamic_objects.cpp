#include "soft_rig.hpp"
namespace boltyard {
#include "dynamic_objects.hpp"
}
#include <cassert>
#include <iostream>

using namespace boltyard;
static constexpr float dt=1.f/240;
static Vec3 momentum(const DynamicObjects&p){Vec3 v;for(const auto&b:p.bodies())v+=b.velocity/b.inv_mass;return v;}
static float energy(const DynamicBody&b){
    Vec3 w=b.rotation.conjugate().rotate(b.angular_velocity);
    return .5f*(b.velocity.length_squared()/b.inv_mass+w.x*w.x/b.inv_inertia_local.x+w.y*w.y/b.inv_inertia_local.y+w.z*w.z/b.inv_inertia_local.z);
}
static float bottom(const DynamicBody&b){float y=1e20f;for(auto v:b.shape.vertices)y=std::min<float>(y,b.world_point(v).y);return y;}
static Vec3 angular_momentum(const DynamicBody&b){
    const Vec3 w=b.rotation.conjugate().rotate(b.angular_velocity);
    return b.rotation.rotate({w.x/b.inv_inertia_local.x,w.y/b.inv_inertia_local.y,w.z/b.inv_inertia_local.z})+b.position.cross(b.velocity/b.inv_mass);
}
static Vec3 rig_momentum(const SoftRig&r){
    Vec3 result;
    for(const auto&p:r.particles)if(!p.tire)result+=p.velocity*((p.wheel>=0?SoftRig::nodes_per_wheel:1.f)/p.inv_mass);
    return result;
}

int main(){
    {
        DynamicObjects p;p.clear();p.set_world_enabled(false);
        int id=p.add_crate({0,2,0},{1,1,1},50);
        auto&b=p.bodies()[id];Vec3 hit{.3f,2.4f,0},impulse{100,0,15};
        p.apply_impulse(id,hit,impulse);
        assert((momentum(p)-impulse).length()<1e-4f);
        assert((angular_momentum(b)-hit.cross(impulse)).length()<1e-4f);
        assert(b.angular_velocity.length()>.2f);
        auto sample=p.distance(id,{0,2.7f,0});assert(std::abs(sample.distance-.2f)<1e-5f);
        b.rotation=DynamicQuaternion::rotation_vector({0,0,.6f});
        Vec3 normal=b.rotation.rotate({0,1,0}),surface=b.world_point({0,.5f,0});
        sample=p.distance(id,surface+normal*.2f);
        assert(std::abs(sample.distance-.2f)<1e-4f&&(sample.normal-normal).length()<1e-4f);
        std::cout<<"impulse: linear/angular momentum and rotated convex mesh agree\n";
    }
    {
        // Isolated unequal-mass impact: no terrain/friction sink. Integrate
        // the same XPBD solve schedule used by the vehicle.
        DynamicObjects p;p.clear();p.set_world_enabled(false);
        p.add_crate({-.55f,3,0},{1,1,1},40);p.add_crate({.55f,3,0},{1,1,1},80);
        p.bodies()[0].velocity={3,0,0};const Vec3 before=momentum(p);
        const float initial=energy(p.bodies()[0])+energy(p.bodies()[1]);
        for(int i=0;i<60;++i)p.step(dt,{});
        float drift=(momentum(p)-before).length();
        std::cout<<"pair momentum drift="<<drift<<" kg m/s, energy="<<energy(p.bodies()[0])+energy(p.bodies()[1])<<" <= "<<initial<<"\n";
        assert(drift<.25f);assert(p.bodies()[1].velocity.x>.5f);
        assert(energy(p.bodies()[0])+energy(p.bodies()[1])<initial*1.02f);
        assert((p.bodies()[1].position-p.bodies()[0].position).length()>.985f);
    }
    {
        // A wheel-sized particle transfers normal load to a loose prop with
        // equal and opposite XPBD impulse, including an off-center moment.
        DynamicObjects p;p.clear();p.set_world_enabled(false);
        p.add_crate({0,3,0},{.8f,.8f,.8f},45);
        Vec3 pos{-.84f,3.25f,0},velocity{2,0,0};const float inverse_mass=1.f/66,radius=.46f;
        Vec3 total=velocity/inverse_mass;float peak_spin=0;
        for(int step=0;step<36;++step){
            p.begin_step(dt,{});Vec3 prev=pos;pos+=velocity*dt;float lambda=0;
            for(int it=0;it<9;++it){
                auto d=p.distance(0,pos);const float inv=inverse_mass+p.point_inverse_mass(0,d.point,d.normal),alpha=1/(300000.f*dt*dt);
                const float next=std::max(0.f,lambda+(-(d.distance-radius)-alpha*lambda)/(inv+alpha));
                const Vec3 impulse=d.normal*(next-lambda);lambda=next;
                pos+=impulse*inverse_mass;p.apply_position_impulse(0,d.point,-impulse);
                p.solve_world(dt);
            }
            velocity=(pos-prev)/dt;p.finish_step(dt);peak_spin=std::max(peak_spin,p.bodies()[0].angular_velocity.length());
        }
        std::cout<<"particle momentum drift="<<(momentum(p)+velocity/inverse_mass-total).length()<<", prop spin="<<peak_spin<<"\n";
        assert((momentum(p)+velocity/inverse_mass-total).length()<.12f);
        assert(peak_spin>.2f);assert(p.bodies()[0].position.x>.1f);
        // Tire torque/friction applies through the moving contact point.
        Vec3 point=p.bodies()[0].position+Vec3{0,.4f,0},j{5,0,0};
        const Vec3 prior=momentum(p)+velocity/inverse_mass;
        velocity+=j*inverse_mass;p.apply_impulse(0,point,-j);
        assert((momentum(p)+velocity/inverse_mass-prior).length()<1e-4f);
    }
    {
        DynamicObjects p;p.clear();p.set_static_rocks({});
        p.add_crate({0,2,0},{.8f,.8f,.8f},55,.2f);
        p.add_log({3,1.5f,0},2,.25f,80,.15f);
        p.add_stone({-3,1,0},{.8f,.5f,.75f},50,.5f);
        float max_speed=0;
        for(int i=0;i<2400;++i){p.step(dt);if(i>1920)for(const auto&b:p.bodies())max_speed=std::max(max_speed,b.velocity.length());}
        for(const auto&b:p.bodies()){
            assert(b.position.finite());assert(bottom(b)>-.008f&&bottom(b)<.008f);
            assert(b.velocity.length()<.035f&&b.angular_velocity.length()<.08f);
        }
        assert(max_speed<.05f);
        const Vec3 asleep=p.bodies()[0].position;
        assert(p.bodies()[0].sleeping);p.apply_impulse(0,asleep+Vec3{0,.3f,0},{250,0,0});
        assert(!p.bodies()[0].sleeping);
        for(int i=0;i<240;++i)p.step(dt);
        assert((p.bodies()[0].position-asleep).length()>.1f);
        std::cout<<"drop/rest: three shapes settle; resting props wake on contact impulse\n";
    }
    {
        DynamicObjects p;p.clear();
        p.set_static_rocks({crawl_rock(0,0,3,3,.75f)});
        p.add_crate({0,2,0},{.8f,.8f,.8f},50,.2f);
        p.add_crate({.05f,3,0},{.7f,.7f,.7f},35,-.1f);
        for(int i=0;i<2400;++i)p.step(dt);
        for(const auto&b:p.bodies())assert(b.position.finite()&&b.velocity.length()<.08f);
        std::cout<<"static ledge / stack final heights="<<p.bodies()[0].position.y<<", "<<p.bodies()[1].position.y<<"\n";
        assert(bottom(p.bodies()[0])>.73f);
        assert(p.bodies()[1].position.y>1.72f);
    }
    {
        // Whole SoftRig over a free-falling movable platform: neither system
        // contacts the fixed world, so horizontal momentum has no ground sink.
        // A slight initial tire compression supplies one measurable load pulse.
        auto airborne=[](){
            SoftRig r;r.set_terrain(3);r.set_test_rocks({});r.reset({0,11.04f,0});
            auto&props=r.dynamic_objects();props.clear();props.set_world_enabled(false);
            props.add_crate({0,10,0},{3.5f,.5f,4.5f},400);
            return r;
        };
        SoftRig drive=airborne(),neutral=airborne();
        drive.step(dt,1,0,false);neutral.step(dt,0,0,false);
        Vec3 total=rig_momentum(drive)+momentum(drive.dynamic_objects());
        const float drive_reaction=drive.dynamic_objects().bodies()[0].velocity.z-neutral.dynamic_objects().bodies()[0].velocity.z;
        std::cout<<"coupled drive: platform reaction="<<drive_reaction<<", horizontal momentum="<<std::hypot(total.x,total.z)<<"\n";
        assert(drive_reaction>.0001f);
        assert(std::hypot(total.x,total.z)<.25f);
        SoftRig braking=airborne(),coasting=airborne();
        for(auto&p:braking.particles)if(!p.tire)p.velocity.z=-2;
        for(auto&p:coasting.particles)if(!p.tire)p.velocity.z=-2;
        const Vec3 before=rig_momentum(braking);
        braking.step(dt,0,0,true);coasting.step(dt,0,0,false);
        total=rig_momentum(braking)+momentum(braking.dynamic_objects());
        const float brake_reaction=braking.dynamic_objects().bodies()[0].velocity.z;
        std::cout<<"coupled brake: platform reaction="<<brake_reaction<<", brake/coast z="<<braking.linear_velocity().z<<"/"<<coasting.linear_velocity().z<<", momentum drift="<<std::hypot(total.x-before.x,total.z-before.z)<<"\n";
        assert(brake_reaction<-.0001f);
        assert(std::hypot(total.x-before.x,total.z-before.z)<1.0f);
        // This one-step load pulse can saturate both contacts with initially
        // stopped rotors. Pedal-dependent stopping is tested with rolling
        // wheels on sustained support in test_powertrain.cpp.
    }
    {
        DynamicObjects a,b;for(int i=0;i<480;++i){a.step(dt);b.step(dt);}
        assert(a.body_count()==9);
        for(int i=0;i<a.body_count();++i){
            assert((a.bodies()[i].position-b.bodies()[i].position).length_squared()==0);
            assert(a.bodies()[i].position.x>7.5f&&a.bodies()[i].position.x<10.5f);
        }
        a.apply_impulse(0,a.bodies()[0].position,{30,0,0});a.step(dt);a.reset();
        DynamicObjects fresh;
        assert((a.bodies()[0].position-fresh.bodies()[0].position).length_squared()==0);
        assert(a.bodies()[0].velocity.length_squared()==0);
        for(int i=a.body_count();i<DynamicObjects::max_bodies;++i)
            assert(a.add_crate({30.f+i,1,0},{.5f,.5f,.5f},20)>=0);
        assert(a.add_crate({80,1,0},{.5f,.5f,.5f},20)==-1);
        assert(a.body_count()==DynamicObjects::max_bodies);
        std::cout<<"authored scene: deterministic, resettable, main line remains clear\n";
    }
    std::cout<<"dynamic object tests passed\n";
}
