#include "soft_rig.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
#include <chrono>
using namespace boltyard;
int main(int argc,char**argv){
    CrawlRock source=crawl_rock(0,0,3,4,2);source.surface_mesh=true;
    CrawlRock r;r.source=&source;r.surface_mesh=true;r.origin={74,13,-231};
    float a=.61f;r.basis[0]={2*std::cos(a),0,-2*std::sin(a)};r.basis[1]={.1f,.7f,0};r.basis[2]={.4f*std::sin(a),0,.4f*std::cos(a)};
    float det=r.basis[0].dot(r.basis[1].cross(r.basis[2]));r.inverse[0]=r.basis[1].cross(r.basis[2])/det;r.inverse[1]=r.basis[2].cross(r.basis[0])/det;r.inverse[2]=r.basis[0].cross(r.basis[1])/det;
    r.minimum_scale_squared=1/(r.inverse[0].length_squared()+r.inverse[1].length_squared()+r.inverse[2].length_squared());
    CrawlRock baked=source;for(auto&v:baked.vertices)v=r.world(v);baked.triangle_normals.clear();for(auto t:baked.triangles)baked.triangle_normals.push_back((baked.vertices[t[1]]-baked.vertices[t[0]]).cross(baked.vertices[t[2]]-baked.vertices[t[0]]).normalized());baked.rebuild_queries();
    for(int i=0;i<4000;++i){Vec3 p=r.origin+Vec3{std::sin(i*1.2f)*5,std::cos(i*.31f)*3,std::sin(i*.43f)*4};auto x=rock_distance(r,p),y=rock_distance_reference(baked,p);assert(std::abs(x.distance-y.distance)<.00015f);assert((x.point-y.point).length()<.002f);}
    if(argc>1){std::ifstream in(argv[1],std::ios::binary);std::vector<uint8_t>bytes((std::istreambuf_iterator<char>(in)),{});assert(imported_scenery::load(bytes.data(),bytes.size()));assert(imported_scenery::instances.size()>100000);
        std::vector<const CrawlRock*> near;
        auto start=std::chrono::steady_clock::now();size_t candidates=0;
        for(int i=0;i<10000;++i){Vec3 p{std::sin(i*.13f)*990,40+std::cos(i*.19f)*40,std::cos(i*.17f)*990};imported_scenery::near(p,7,near);candidates+=near.size();
            if(i<30)for(auto&r:imported_scenery::instances)if(r.query_nodes[0].bounds.distance_squared(p)<=49)assert(std::find(near.begin(),near.end(),&r)!=near.end());}
        std::cout<<"instances="<<imported_scenery::instances.size()<<" candidates="<<candidates<<" grid_ms="<<std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()<<"\n";
    }
    std::cout<<"PASS: 4000 rotated, sheared and nonuniform queries match baked geometry\n";
}
