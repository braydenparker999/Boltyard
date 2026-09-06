#include "soft_rig.hpp"
#include <cstdio>
#include <cstdlib>
#include <map>
using namespace boltyard;
static int checks=0;
static void require(bool v,const char*s){++checks;if(!v){std::fprintf(stderr,"FAIL Redstone: %s\n",s);std::exit(1);}}
int main(){
    using namespace expedition_detail;
    const auto &terrain=cache(6);const auto &rocks=expedition_rocks(6);
    require(terrain.height.size()==321*321,"complete shared terrain");
    require(expedition_height(6,0,8)==0,"level trailhead");
    require(rocks.size()>100&&rocks.size()<500,"bounded authored geology");
    int sand=0,stone=0;float length=0,max_grade=0;
    for(int z=-300;z<=300;z+=8)for(int x=-300;x<=300;x+=8){
        auto m=expedition_material(6,x,z);
        require(std::isfinite(expedition_height(6,x,z)),"finite height");
        require(std::abs(m.rock+m.dirt+m.grass-1)<.0001f&&m.wet==0,"dry partitioned ground");
        sand+=expedition_surface_material(6,x,z)==ExpeditionSand;
        stone+=expedition_surface_material(6,x,z)==ExpeditionDryRock;
    }
    require(sand>50&&stone>50,"physical sandstone and loose sand regions");
    const auto&path=trails(6);
    for(size_t i=1;i<path.size();++i){
        auto a=path[i-1],b=path[i];if(a.route!=b.route)continue;
        float span=std::hypot(a.x-b.x,a.z-b.z);length+=span;
        float grade=std::abs(expedition_height(6,a.x,a.z)-expedition_height(6,b.x,b.z))/span;
        max_grade=std::max(grade,max_grade);require(grade<(blender_canyon::contains(a.x,a.z)||blender_canyon::contains(b.x,b.z)?1.8f:.48f),"connected route grade");
    }
    require(length>1500,"substantial connected network");
    for(const auto &r:rocks){
        std::map<std::pair<int,int>,int> edges;
        if(!r.surface_mesh)require(rock_distance(r,r.center).distance<0,"solid rock center");
        for(size_t i=0;i<r.triangles.size();++i){auto t=r.triangles[i];
            if(!r.surface_mesh)for(auto v:r.vertices)require(r.triangle_normals[i].dot(v-r.vertices[t[0]])<.002f,"convex contact planes");
            for(int k=0;k<3;++k){int a=t[k],b=t[(k+1)%3];if(a>b)std::swap(a,b);++edges[{a,b}];}
        }
        for(auto e:edges)require(e.second==2,"closed manifold hull");
    }
    float archbase=expedition_height(6,-211,-249)-3;
    Vec3 opening{-211,archbase+9,-249};float clearance=1e6;
    for(const auto&r:rocks)clearance=std::min(clearance,rock_distance(r,opening).distance);
    require(clearance>3,"open arch contains no hidden collider");
    std::printf("PASS Redstone %d checks: %.0fm routes, %.3f maximum grade, %zu rocks, %.1fm arch clearance\n",checks,length,max_grade,rocks.size(),clearance);
}
