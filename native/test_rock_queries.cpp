#include "soft_rig.hpp"
#include <iostream>
#include <random>
#include <stdexcept>
using namespace boltyard;
int main(){
    std::mt19937 rng(2209);std::uniform_real_distribution<float> unit(-1.15f,1.15f);
    int checks=0;float worst=0;
    for(int mode:{3,4,5})for(const auto&r:mode==3?crawl_course():expedition_rocks(mode)) {
        auto compare=[&](Vec3 p){
            auto a=rock_distance_reference(r,p),b=rock_distance(r,p);
            float error=std::abs(a.distance-b.distance);worst=std::max(worst,error);++checks;
            if(error>1e-5f||(a.point-b.point).length()>1e-4f||(a.normal-b.normal).length()>1e-4f)
                throw std::runtime_error("accelerated query differs from original convex distance");
        };
        compare(r.center);
        for(int i=0;i<200;++i)compare(r.center+Vec3{unit(rng),unit(rng),unit(rng)}*r.reach);
        for(size_t i=0;i<r.triangles.size();i+=7){auto t=r.triangles[i];Vec3 p=(r.vertices[t[0]]+r.vertices[t[1]]+r.vertices[t[2]])/3;
            compare(p+r.triangle_normals[i]*.0002f);compare(p-r.triangle_normals[i]*.0002f);}
    }
    std::cout<<"ROCK QUERIES: "<<checks<<" exact reference comparisons, max distance error="<<worst<<'\n';
}
