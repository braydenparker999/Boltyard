// Crawlworks 2.1 contact-envelope regressions. These demonstrate causal behavior
// of this bounded game model, not measured tire/FEM calibration.
#include "soft_rig.hpp"
#include <iostream>
#include <stdexcept>
using namespace boltyard;
namespace {
void check(bool condition,const char*message){if(!condition)throw std::runtime_error(message);}
void run(SoftRig &rig,int frames,float throttle=0,bool brake=true){for(int i=0;i<frames;++i)rig.step(1.f/120,throttle,0,brake);}
void prepare(SoftRig &rig,const Config&cfg,const std::vector<CrawlRock>&rocks){rig.configure(cfg);rig.set_terrain(3);rig.set_test_rocks(rocks);rig.reset({0,3.5f,0});rig.dynamic_objects().clear();}
void healthy(const SoftRig &rig){check(rig.rejected_state_count()==0&&rig.safety_clamp_count()==0&&rig.damage()<.001f,"ordinary contact required numerical intervention or damaged frame");}
float maximum_width(const SoftRig &r,int wheel){float width=0;Vec3 axis=r.wheel_axle_direction(wheel),hub=r.particles[r.wheel_hubs[wheel]].pos;for(int i=1;i<SoftRig::nodes_per_wheel;++i)width=std::max(width,std::abs((r.particles[r.wheel_hubs[wheel]+i].pos-hub).dot(axis)));return width;}
}
int main(){int failures=0;auto test=[&](const char*name,auto body){try{body();std::cout<<"PASS "<<name<<'\n';}catch(const std::exception&e){++failures;std::cerr<<"FAIL "<<name<<": "<<e.what()<<'\n';}};
 test("pressure changes loaded footprint and shoulder width without a friction bonus",[]{
    float depth[2],length[2],width[2],mu[2];
    for(int setting=0;setting<2;++setting){SoftRig r;Config cfg;cfg.tire_pressure=setting?1.5f:.5f;prepare(r,cfg,{crawl_rock(0,0,14,40,2)});run(r,480);
        const auto patches=r.wheel_contact_patches(0);check(patches.size()==1,"co-planar queries multiplied the physical patch");const auto&p=patches.front();
        depth[setting]=p.compression;length[setting]=p.half_length*2;width[setting]=maximum_width(r,0);mu[setting]=p.friction;
        check(std::abs(p.load-p.compression*300000*cfg.tire_pressure)<1,"pressure deformation is disconnected from normal load");
        check(std::abs(p.point.y-2)<.001f&&p.normal.y>.999f,"patch does not lie on the real elevated rock");
        float support=0;for(int w=0;w<4;++w)support+=r.wheel_load(w);check(std::abs(support-cfg.mass*9.81f)<100,"flat tire loads do not sum to vehicle weight");healthy(r);
    }
    std::cout<<"  pressure .5/1.5 depth="<<depth[0]<<"/"<<depth[1]<<" footprint="<<length[0]<<"/"<<length[1]<<" shoulder="<<width[0]<<"/"<<width[1]<<'\n';
    check(depth[0]>depth[1]*2.8f&&length[0]>length[1]*1.6f,"pressure lacks physical contact-area tradeoff");
    check(width[0]>width[1]+.003f,"rubber guides do not bulge with loaded carcass compression");
    check(std::abs(mu[0]-mu[1])<1e-6f,"pressure was implemented as an arbitrary Coulomb grip bonus");
 });
 test("opposed rock faces independently support one tire and disappear with removed geometry",[]{
    float supported_height=0,unsupported_height=0;
    for(int dual=0;dual<2;++dual){SoftRig r;Config cfg;cfg.tire_pressure=.5f;std::vector<CrawlRock>rocks;
        for(int axle=0;axle<2;++axle){const float z=axle?1.35f:-1.35f;rocks.push_back(crawl_rock(0,z-.235f,5,.5f,2,.5f));if(dual)rocks.push_back(crawl_rock(0,z+.235f,5,.5f,2,-.5f));}
        prepare(r,cfg,rocks);run(r,600,0,false);
        if(dual){supported_height=r.center().y;float support=0;for(int w=0;w<4;++w){const auto patches=r.wheel_contact_patches(w);check(patches.size()<=SoftRig::max_tire_patches,"unbounded contact export");if(w==0)check(patches.size()>=2,"secondary rock plane was discarded");bool positive=false,negative=false;for(const auto&p:patches){positive|=p.normal.z>.35f&&p.load>50;negative|=p.normal.z<-.35f&&p.load>50;check(p.normal.finite()&&p.point.finite()&&p.shear.finite(),"invalid patch telemetry");}if(w==0)check(positive&&negative,"both actual rock faces must carry force");support+=r.wheel_load(w);}
            std::cout<<"  opposing-plane vertical support="<<support<<" N\n";check(std::abs(support-cfg.mass*9.81f)<180,"multi-plane contact invented vertical support");
        }else unsupported_height=r.center().y;
        healthy(r);
    }
    std::cout<<"  supported/removed-face height="<<supported_height<<"/"<<unsupported_height<<'\n';
    check(supported_height>unsupported_height+.6f,"secondary surface has no causal physical support");
 });
 test("surface friction produces measurable acceleration and wheel slip",[]{
    float travel[2],slip[2];for(int material=0;material<2;++material){SoftRig r;auto rock=crawl_rock(0,0,14,40,2);rock.surface=material?1.1f:.1f;prepare(r,Config{},{rock});run(r,360);const Vec3 start=r.center();run(r,60,.65f,false);travel[material]=start.z-r.center().z;slip[material]=r.wheel_slip(0);
        const auto p=r.wheel_contact_patches(0).front();check(std::abs(p.friction-1.18f*rock.surface)<1e-6f,"traction ignores contacted rock material");healthy(r);
    }
    std::cout<<"  slick/dry travel="<<travel[0]<<"/"<<travel[1]<<" slip="<<slip[0]<<"/"<<slip[1]<<'\n';
    check(travel[1]>travel[0]*3&&slip[0]>slip[1]*10,"material coefficients do not change real drive and spin");
 });
 test("longitudinal and lateral contact forces deform rubber tangentially",[]{
    SoftRig r;prepare(r,Config{},{crawl_rock(0,0,14,40,2)});run(r,360);run(r,60,.65f,false);auto patch=r.wheel_contact_patches(0).front();const float driven=std::abs(patch.shear.z);
    check(driven>.001f,"drive shear is missing");check(std::abs(patch.shear.dot(patch.normal))<1e-5f,"shear changes normal compression");
    for(auto&p:r.particles)if(!p.tire)p.velocity.x+=.6f;
    run(r,6,0,false);patch=r.wheel_contact_patches(0).front();
    std::cout<<"  driven shear="<<driven<<" lateral shear="<<patch.shear.x<<'\n';
    check(std::abs(patch.shear.x)>.004f&&patch.shear.length()<r.config().tire_radius*.13f,"lateral force does not create bounded rubber squirm");healthy(r);
 });
 test("one convex ledge supplies simultaneous loaded corner normals while climbing",[]{
    SoftRig r;Config cfg;cfg.tire_radius=.53f;cfg.tire_pressure=.5f;cfg.ride_height=.45f;cfg.suspension_travel=.3f;cfg.spring_rate=25500;
    const auto ledge=crawl_rock(0,-2,8,8,.30f);r.configure(cfg);r.set_terrain(3);r.set_test_rocks({ledge});r.reset({0,1.5f,5});r.dynamic_objects().clear();run(r,360);
    int maximum=0;float normal_difference=0;
    for(int frame=0;frame<480;++frame){r.step(1.f/120,.3f,0,false);const auto patches=r.wheel_contact_patches(0);int loaded=0;
        for(const auto &p:patches)if(p.surface==ExpeditionDryRock&&p.load>20){++loaded;check(std::abs(rock_distance(ledge,p.point).distance)<.002f,"corner plane does not touch the actual convex hull");}
        maximum=std::max(maximum,loaded);
        for(const auto&a:patches)for(const auto&b:patches)if(a.surface==ExpeditionDryRock&&b.surface==ExpeditionDryRock&&a.load>20&&b.load>20)
            normal_difference=std::max(normal_difference,1-a.normal.dot(b.normal));
    }
    std::cout<<"  one-hull loaded planes="<<maximum<<" normal separation="<<normal_difference<<" finish z="<<r.center().z<<'\n';
    check(maximum>=2&&normal_difference>.01f,"single-hull solver still discarded secondary corner support");
    check(r.center().z<-1&&r.up().y>.9f,"multi-plane corner contact blocked or overturned the crawler");healthy(r);
 });
 test("movable timber and stone retain distinct contacted materials",[]{
    DynamicObjects objects;objects.clear();objects.set_terrain(3);const int stone=objects.add_stone({0,2,0},{1,1,1},50),wood=objects.add_crate({3,2,0},{1,1,1},50);
    check(objects.surface_material(stone,{0,2,0})==ExpeditionDryRock&&objects.surface_material(wood,{3,2,0})==ExpeditionWood,"moving hull material identity lost");
    check(objects.tire_surface(stone,{0,2,0})>objects.tire_surface(wood,{3,2,0})+.2f,"all moving surfaces still have a constant tire coefficient");
 });
 std::cout<<"TIRE CONTACTS: 6 scenarios, "<<failures<<" failures\n";return failures?1:0;
}
