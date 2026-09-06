#pragma once
// Two fictional expedition landscapes. The 2 m cache is the authoritative
// ground mesh: contact heights, normals, materials and rendering share it.
#include "terrain_v03.hpp"

namespace boltyard {
struct ExpeditionMaterial { float rock, dirt, grass, wet; };
struct ExpeditionTrailPoint { float x,z,h,width; int route; };
struct ExpeditionLandmark { float x,z; const char *name,*detail; };
struct ExpeditionWater { float x,z,rx,rz,height; };
namespace expedition_detail {
constexpr float extent=320.f, spacing=2.f;
constexpr int side=321;
using exploration_detail::clamp;
using exploration_detail::smooth;
using exploration_detail::noise;
using exploration_detail::mound;
using exploration_detail::hash;
inline const std::vector<ExpeditionTrailPoint>& trails(int mode) {
    static const std::vector<ExpeditionTrailPoint> mountain{
        {0,8,0,3.6f,0},{-18,-36,2,3.1f,0},{-38,-76,8,3.0f,0},
        {-76,-112,18,3.0f,0},{-110,-148,30,3.0f,0},{-105,-205,44,3.0f,0},
        {-152,-246,56,3.2f,0},{-215,-226,62,3.6f,0},{-252,-157,50,3.2f,0},
        {-237,-90,37,3.1f,0},{-185,-30,24,3.0f,0},{-144,28,16,3.1f,0},
        {-90,56,6,3.2f,0},{-34,46,1,3.4f,0},{0,8,0,3.6f,0},
        {-38,-76,8,3.0f,1},{10,-118,12,3.1f,1},{66,-145,24,3.0f,1},
        {123,-124,32,3.0f,1},{172,-67,23,3.0f,1},{170,4,14,3.1f,1},
        {110,40,6,3.2f,1},{50,22,2,3.2f,1},{0,8,0,3.6f,1},
        {-76,-112,18,2.2f,2},{-57,-160,31,2.1f,2},{-42,-218,48,2.2f,2},
        {-95,-265,57,2.4f,2},{-152,-246,56,3.2f,2},
        {-18,-36,2,2.3f,3},{10,-51,4,2.0f,3},{15,-75,7,2.0f,3},
        {-12,-88,9,2.1f,3},{-38,-76,8,3.0f,3}
    };
    static const std::vector<ExpeditionTrailPoint> taiga{
        {0,8,0,3.6f,0},{-18,-34,1,3.0f,0},{-63,-68,2,2.9f,0},
        {-115,-74,5,2.9f,0},{-168,-42,10,2.8f,0},{-215,8,13,3.0f,0},
        {-225,74,10,3.0f,0},{-176,129,6,3.0f,0},{-108,154,7,3.0f,0},
        {-50,130,4,3.1f,0},{-20,71,2,3.0f,0},{0,8,0,3.6f,0},
        {0,8,0,3.6f,1},{52,-24,1,3.0f,1},{116,-39,3,3.0f,1},
        {171,-19,6,3.0f,1},{213,39,8,3.0f,1},{228,99,12,3.0f,1},
        {194,157,15,3.0f,1},{133,184,18,3.0f,1},{81,175,14,3.0f,1},
        {63,134,9,3.0f,1},{77,76,4,3.0f,1},{50,25,1,3.0f,1},{0,8,0,3.6f,1},
        {-63,-68,2,2.5f,2},{-87,-117,2,2.4f,2},{-101,-169,3,2.4f,2},
        {-54,-213,4,2.4f,2},{18,-225,5,2.4f,2},{82,-211,6,2.4f,2},
        {130,-153,6,2.4f,2},{139,-95,5,2.5f,2},{116,-39,3,3.0f,2},
        {-18,-34,1,2.1f,3},{-40,-20,3,2.1f,3},{-63,-29,5,2.1f,3},
        {-79,-49,4,2.1f,3},{-63,-68,2,2.9f,3}
    };
    return mode==5?taiga:mountain;
}
struct TrailSample { float distance,height,width,along,dx,dz; int route; };
inline TrailSample nearest_trail(int mode,float x,float z) {
    TrailSample result{1e8f,0,3,0,0,-1,0};
    const auto &points=trails(mode); float along=0;
    for(size_t i=1;i<points.size();++i) {
        const auto &a=points[i-1],&b=points[i];
        if(a.route!=b.route){along=0;continue;}
        const float dx=b.x-a.x,dz=b.z-a.z,length=std::sqrt(dx*dx+dz*dz);
        const float t=clamp(((x-a.x)*dx+(z-a.z)*dz)/(length*length),0,1);
        const float px=x-a.x-dx*t,pz=z-a.z-dz*t,d=std::sqrt(px*px+pz*pz);
        if(d<result.distance)result={d,a.h+(b.h-a.h)*t,a.width+(b.width-a.width)*t,along+t*length,dx/length,dz/length,a.route};
        along+=length;
    }
    return result;
}
inline ExpeditionWater water(int mode) { return mode==5?ExpeditionWater{26,-147,83,66,-1.6f}:ExpeditionWater{108,-87,35,28,5}; }
inline float lake_distance(int mode,float x,float z) {
    auto w=water(mode);float dx=(x-w.x)/w.rx,dz=(z-w.z)/w.rz,a=std::atan2(dz,dx);
    const float shore=1+.08f*std::sin(a*3+.6f)+.055f*std::sin(a*7-.4f);
    return std::sqrt(dx*dx+dz*dz)/shore;
}
inline float creek_distance(int mode,float x,float z) {
    // A shallow drainage continues the Russian lake eastwards. The mountain
    // creek is a dry boulder wash; its bed is still solid, fully collidable.
    const float path=mode==5?-169+std::sin((x-95)*.022f)*13:-55+std::sin((x-100)*.018f)*17;
    return std::sqrt((z-path)*(z-path)+std::pow(std::max(0.f,(mode==5?95.f:140.f)-x),2.f));
}
inline float authored_height(int mode,float x,float z) {
    float h;
    if(mode==4) {
        // Interlocking ridge spurs wrap around a broad glacial valley. Relief
        // grows coherently towards the massif, rather than random isolated hills.
        h=5+noise(x*.008f,z*.008f)*8+noise(x*.027f,z*.027f)*2.4f;
        h+=mound(x,z,-178,-234,115,125,69)+mound(x,z,-270,-45,91,149,61);
        h+=mound(x,z,145,-206,124,98,75)+mound(x,z,287,-129,74,126,104);
        h+=mound(x,z,-121,269,146,70,77)+mound(x,z,235,253,102,80,117);
        h+=mound(x,z,12,-319,115,53,75);
        float ridge=1-std::abs(noise(x*.023f+noise(x*.005f,z*.005f),z*.023f));
        float relief=smooth(15,80,h);
        h+=relief*(ridge*ridge*12+noise(x*.080f,z*.080f)*2.2f);
        // Glacial scouring leaves coherent smooth shoulders with short rough
        // steps. Larger exposed ledges are exact convex hulls in the rock cache.
        h+=noise(x*.16f,z*.16f)*(.16f+relief*.55f);
        h+=smooth(277,340,std::max(std::abs(x),std::abs(z)))*29;
    } else {
        // Low, elongated glacial ridges, damp hollows and rounded granite knobs.
        float warp=noise(x*.008f,z*.008f)*.6f;
        h=3.2f+noise(x*.009f,z*.014f)*3.0f+noise(x*.032f,z*.023f)*1.2f;
        h+=mound(x,z,-223,5,67,143,12)+mound(x,z,144,203,119,70,17);
        h+=mound(x,z,-152,-231,95,59,11)+mound(x,z,245,-120,68,127,17);
        h+=std::pow(1-std::abs(noise(x*.025f+warp,z*.012f)),3.f)*2.8f;
        h+=noise(x*.13f,z*.13f)*.19f;
        h+=smooth(279,350,std::max(std::abs(x),std::abs(z)))*16;
    }
    const auto lake=water(mode);const float d=lake_distance(mode,x,z);
    const float blend=smooth(.90f,1.27f,d);
    const float bed=lake.height-1.7f+smooth(.30f,1.03f,d)*2.8f+noise(x*.09f,z*.09f)*.11f;
    const float shore_raise=(std::max(h,lake.height+1.1f)-h)*(1-smooth(1.25f,1.75f,d));
    h=bed*(1-blend)+(h+shore_raise)*blend;
    if(mode==5) {
        const float c=creek_distance(mode,x,z);
        float bed=lake.height+.16f+std::max(0.f,x-95)*.006f;
        h=bed*(1-smooth(2.8f,10,c))+h*smooth(2.8f,10,c);
    }
    auto r=nearest_trail(mode,x,z);
    // Trail surface blends through a graded shoulder into native landform.
    // Technical branches retain coherent exposed-rock undulations, while the
    // main forest track has shallow paired wheel ruts and a subtle crown.
    // A trail follows a broad drainage or contour shoulder. Its adjacent
    // landscape must not become a narrow, mechanically excavated trench when
    // a route elevation differs from the broad ridge field. Wider relief
    // transitions retain woodland and asymmetry around the actual wheel track.
    float shoulder=clamp(15.f+std::abs(h-r.height)*1.8f,20.f,66.f);
    shoulder*=.94f+.12f*noise(x*.019f,z*.019f);
    const float blend_trail=smooth(r.width,r.width+shoulder,r.distance);
    const float rough=r.route>=2?.085f:.025f;
    float trail_h=r.height+noise(x*.14f,z*.14f)*rough;
    const float rut=std::exp(-std::pow((r.distance-0.87f)/.29f,2.f));
    trail_h-=(mode==5?.065f:.035f)*rut;
    h=trail_h*(1-blend_trail)+h*blend_trail;
    // The camp, garage and map handoff are the same level on both maps.
    float camp=std::sqrt(x*x+(z-8)*(z-8));
    float camp_blend=smooth(12,40,camp);
    camp_blend+=(smooth(12,22,camp)-camp_blend)*(1-smooth(r.width,r.width+8,r.distance));
    return h*camp_blend;
}
inline ExpeditionMaterial authored_material(int mode,float x,float z,float h) {
    const auto r=nearest_trail(mode,x,z);
    const float trail=1-smooth(r.width-.5f,r.width+2.1f,r.distance);
    const float wet=(mode==5?.86f:.48f)*(1-smooth(.88f,1.20f,lake_distance(mode,x,z)));
    const float creek=mode==5?.7f*(1-smooth(3,11,creek_distance(mode,x,z))):0;
    const float slopes=std::abs(authored_height(mode,x+1,z)-authored_height(mode,x-1,z))+
                       std::abs(authored_height(mode,x,z+1)-authored_height(mode,x,z-1));
    float rock=clamp(smooth(.55f,2.8f,slopes)*.86f+(mode==4?smooth(44,87,h)*.64f:0),0,.94f);
    if(r.route>=2)rock=std::max(rock,trail*(mode==4?.64f:.42f));
    float dirt=trail*(1-rock)*.90f;
    return {rock,dirt,1-rock-dirt,std::max(wet,creek)};
}
struct Cache {
    std::vector<float> height,surface;
    std::vector<ExpeditionMaterial> material;
    explicit Cache(int mode):height(side*side),surface(side*side),material(side*side) {
        for(int iz=0;iz<side;++iz)for(int ix=0;ix<side;++ix) {
            float x=-extent+ix*spacing,z=-extent+iz*spacing;size_t i=size_t(iz)*side+ix;
            height[i]=authored_height(mode,x,z);
        }
        for(int iz=0;iz<side;++iz)for(int ix=0;ix<side;++ix) {
            float x=-extent+ix*spacing,z=-extent+iz*spacing;size_t i=size_t(iz)*side+ix;
            const auto r=nearest_trail(mode,x,z);
            float slope=std::abs(height[size_t(iz)*side+std::min(side-1,ix+1)]-height[size_t(iz)*side+std::max(0,ix-1)])*.25f+
                        std::abs(height[size_t(std::min(side-1,iz+1))*side+ix]-height[size_t(std::max(0,iz-1))*side+ix])*.25f;
            float trail=1-smooth(r.width-.5f,r.width+2.1f,r.distance);
            float rock=clamp(smooth(.28f,1.40f,slope)*.86f+(mode==4?smooth(44,87,height[i])*.64f:0),0,.94f);
            if(r.route>=2)rock=std::max(rock,trail*(mode==4?.64f:.42f));
            float dirt=trail*(1-rock)*.9f;
            float wet=(mode==5?.86f:.48f)*(1-smooth(.88f,1.20f,lake_distance(mode,x,z)));
            if(mode==5)wet=std::max(wet,.7f*(1-smooth(3,11,creek_distance(mode,x,z))));
            if(mode==5&&r.route==0)wet=std::max(wet,trail*.18f*(.5f+.5f*noise(x*.038f,z*.038f)));
            material[i]={rock,dirt,1-rock-dirt,wet};
            surface[i]=clamp(rock*1.08f+dirt*.91f+(1-rock-dirt)*.83f-wet*.28f,.52f,1.12f);
        }
    }
};
inline const Cache& cache(int mode) { if(mode==5){static const Cache c(5);return c;}static const Cache c(4);return c; }
inline float sample(const std::vector<float>&data,float x,float z) {
    float gx=clamp((x+extent)/spacing,0,float(side-1)),gz=clamp((z+extent)/spacing,0,float(side-1));
    int ix=std::min(side-2,int(gx)),iz=std::min(side-2,int(gz));float tx=gx-ix,tz=gz-iz;size_t i=size_t(iz)*side+ix;
    if(tx+tz<=1)return data[i]+tx*(data[i+1]-data[i])+tz*(data[i+side]-data[i]);
    return data[i+side+1]+(1-tx)*(data[i+side]-data[i+side+1])+(1-tz)*(data[i+1]-data[i+side+1]);
}
}
inline float expedition_height(int mode,float x,float z) {
    if(!std::isfinite(x)||!std::isfinite(z))return 0;
    return expedition_detail::sample(expedition_detail::cache(mode).height,x,z)+
        std::max(0.f,std::max(std::abs(x),std::abs(z))-expedition_detail::extent)*.65f;
}
inline ExplorationNormal expedition_normal(int mode,float x,float z) {
    if(!std::isfinite(x)||!std::isfinite(z))return {0,1,0};
    using namespace expedition_detail;const auto&data=cache(mode).height;
    float gx=clamp((x+extent)/spacing,0,float(side-1)),gz=clamp((z+extent)/spacing,0,float(side-1));
    int ix=std::min(side-2,int(gx)),iz=std::min(side-2,int(gz));size_t i=size_t(iz)*side+ix;
    float dx,dz;
    if(gx-ix+gz-iz<=1){dx=(data[i+1]-data[i])/spacing;dz=(data[i+side]-data[i])/spacing;}
    else{dx=(data[i+side+1]-data[i+side])/spacing;dz=(data[i+side+1]-data[i+1])/spacing;}
    if(std::abs(x)>extent&&std::abs(x)>=std::abs(z))dx+=x>0?.65f:-.65f;
    if(std::abs(z)>extent&&std::abs(z)>std::abs(x))dz+=z>0?.65f:-.65f;
    float length=std::sqrt(dx*dx+dz*dz+1);return {-dx/length,1/length,-dz/length};
}
inline float expedition_surface(int mode,float x,float z) {
    if(!std::isfinite(x)||!std::isfinite(z))return .85f;
    return expedition_detail::sample(expedition_detail::cache(mode).surface,x,z);
}
inline ExpeditionMaterial expedition_material(int mode,float x,float z) {
    using namespace expedition_detail;
    if(!std::isfinite(x)||!std::isfinite(z))return {0,0,1,0};
    int ix=int(clamp(std::round((x+extent)/spacing),0,float(side-1)));
    int iz=int(clamp(std::round((z+extent)/spacing),0,float(side-1)));
    return cache(mode).material[size_t(iz)*side+ix];
}
inline float expedition_trail_distance(int mode,float x,float z){return expedition_detail::nearest_trail(mode,x,z).distance;}
inline const std::vector<ExpeditionTrailPoint>& expedition_trail_points(int mode){return expedition_detail::trails(mode);}
inline ExpeditionWater expedition_water(int mode){return expedition_detail::water(mode);}
inline const std::vector<ExpeditionLandmark>& expedition_landmarks(int mode) {
    static const std::vector<ExpeditionLandmark> mountain{
        {0,8,"Silverpine Basecamp","Forest roads and granite lines"},
        {15,-75,"Split Granite","Short bedrock crawl above camp"},
        {-57,-160,"Moraine Steps","Exposed ridge with technical ledges"},
        {-215,-226,"Eagle Overlook","High pass above the glacial valley"},
        {123,-124,"Mirror Tarn","Granite shoreline and lake view"},
        {-144,28,"Pine Hollow","Sheltered forest return trail"}
    };
    static const std::vector<ExpeditionLandmark> taiga{
        {0,8,"Karelia Field Camp","Northern forest expedition"},
        {-63,-29,"Old Granite Cut","Weathered slabs beneath the birches"},
        {-215,8,"Birch Ridge","Glacial rock spine in mixed woodland"},
        {-101,-169,"Lake Vetra Shore","Granite shoreline and wet tracks"},
        {133,184,"Northern Lookout","Forest road over the long ridge"},
        {130,-153,"Stony Ford","Shallow drainage and loose stones"}
    };
    return mode==5?taiga:mountain;
}
inline const std::vector<ExplorationObstacle>& expedition_obstacles(int mode) {
    auto make=[](int m) {
        std::vector<ExplorationObstacle> out;
        using namespace expedition_detail;
        // Spatially staggered woodland creates real clearings and irregular
        // stands. Every rendered trunk has the same cylinder in native contact.
        for(int iz=-37;iz<=37;++iz)for(int ix=-37;ix<=37;++ix) {
            float x=ix*8.15f+(hash(ix+213+m,iz-94)-.5f)*6.7f;
            float z=iz*8.15f+(hash(ix-57,iz+184+m)-.5f)*6.7f;
            float density=.60f+.22f*noise(x*.026f,z*.026f);
            if(hash(ix*7+m*53,iz*11-19)>density)continue;
            const auto trail=nearest_trail(m,x,z);float h=expedition_height(m,x,z);
            if(trail.distance<trail.width+1.7f||x*x+(z-8)*(z-8)<21*21)continue;
            if(lake_distance(m,x,z)<1.14f||(m==5&&creek_distance(m,x,z)<7))continue;
            if(expedition_normal(m,x,z).y<.78f||(m==4&&h>79))continue;
            float v=hash(ix+73,iz-17),height=(m==5?9.f:11.f)+v*(m==5?9.f:12.f);
            int type=m==5&&hash(ix-387,iz+22)>.54f?3:0;
            if(type==3)height*=.82f;
            out.push_back({x,z,(type==3?.17f:.22f)+v*.18f,height,type});
        }
        return out;
    };
    if(mode==5){static const auto trees=make(5);return trees;}static const auto trees=make(4);return trees;
}
} // namespace boltyard
