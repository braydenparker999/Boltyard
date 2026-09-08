#pragma once
// Three fictional expedition landscapes. The 2 m cache is the authoritative
// ground mesh: contact heights, normals, materials and rendering share it.
#include "terrain_v03.hpp"
#include "imported_terrain.hpp"
#include "generated/canyon_floor.hpp"

namespace boltyard {
struct ExpeditionMaterial { float rock, dirt, grass, wet; };
// Shared with tire telemetry; these describe the contact patch, not the map.
enum ExpeditionSurfaceMaterial { ExpeditionDirt=0, ExpeditionDryRock=1,
    ExpeditionWetRock=2, ExpeditionMud=3, ExpeditionSand=4,
    ExpeditionWood=5, ExpeditionGravel=6 };
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
inline const std::vector<ExpeditionTrailPoint>& trail_anchors(int mode) {
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
    static const std::vector<ExpeditionTrailPoint> canyon{
        {0,8,0,4,0},{-14,-35,2,3.4f,0},{-39,-72,7,3.3f,0},
        {-79,-114,15,3.4f,0},{-127,-151,24,3.4f,0},{-157,-207,38,3.5f,0},
        {-211,-232,45,4,0},{-258,-193,38,3.5f,0},{-255,-125,25,3.5f,0},
        {-206,-64,15,3.4f,0},{-139,-23,8,3.5f,0},{-66,29,2,3.8f,0},{0,8,0,4,0},
        {-39,-72,7,3.3f,1},{8,-106,11,3.4f,1},{63,-119,16,3.5f,1},
        {108,-91,20,3.4f,1},{127,-35,16,3.5f,1},{98,23,8,3.5f,1},
        {49,43,3,3.8f,1},{0,8,0,4,1},
        {-14,-35,2,2.3f,2},{10,-53,4,2.1f,2},{14,-78,8,2.1f,2},
        {-7,-92,10,2.3f,2},{-39,-72,7,3.3f,2},
        {-79,-114,15,2.3f,3},{-57,-158,27,2.3f,3},{-84,-201,38,2.4f,3},
        {-121,-229,43,2.5f,3},{-157,-207,38,3.5f,3}
    };
    return mode==6?canyon:(mode==5?taiga:mountain);
}
inline const std::vector<ExpeditionTrailPoint>& trails(int mode) {
    auto build=[](int map) {
        const auto& anchors=trail_anchors(map);std::vector<ExpeditionTrailPoint> out;
        auto length=[](const ExpeditionTrailPoint&a,const ExpeditionTrailPoint&b){
            return std::hypot(b.x-a.x,b.z-a.z);
        };
        // A distance-parameterized Hermite curve passes through every landmark
        // and junction. Smooth, monotone elevation tangents remove the sharp
        // pitch breaks of the former long straight segments.
        for(size_t first=0;first<anchors.size();) {
            size_t end=first+1;while(end<anchors.size()&&anchors[end].route==anchors[first].route)++end;
            const bool closed=length(anchors[first],anchors[end-1])<.01f;
            auto tangent=[&](size_t i) {
                const auto&p=anchors[i];
                const auto&prev=anchors[i==first?(closed?end-2:first):i-1];
                const auto&next=anchors[i+1==end?(closed?first+1:end-1):i+1];
                float before=length(prev,p),after=length(p,next);
                if(before<.01f)return std::array<float,3>{(next.x-p.x)/after,(next.z-p.z)/after,(next.h-p.h)/after};
                if(after<.01f)return std::array<float,3>{(p.x-prev.x)/before,(p.z-prev.z)/before,(p.h-prev.h)/before};
                float incoming=(p.h-prev.h)/before,outgoing=(next.h-p.h)/after;
                float slope=incoming*outgoing>0?2*incoming*outgoing/(incoming+outgoing):0;
                return std::array<float,3>{(next.x-prev.x)/(before+after),(next.z-prev.z)/(before+after),slope};
            };
            for(size_t i=first;i+1<end;++i) {
                const auto&a=anchors[i];const auto&b=anchors[i+1];
                float span=length(a,b);auto ta=tangent(i),tb=tangent(i+1);
                int steps=int(std::ceil(span/2.8f));
                for(int step=0;step<steps;++step) {
                    float t=float(step)/steps,t2=t*t,t3=t2*t;
                    float p=2*t3-3*t2+1,q=-2*t3+3*t2,u=t3-2*t2+t,v=t3-t2;
                    out.push_back({p*a.x+q*b.x+span*(u*ta[0]+v*tb[0]),
                        p*a.z+q*b.z+span*(u*ta[1]+v*tb[1]),
                        p*a.h+q*b.h+span*(u*ta[2]+v*tb[2]),
                        a.width+(b.width-a.width)*smooth(0,1,t),a.route});
                }
            }
            out.push_back(anchors[end-1]);first=end;
        }
        return out;
    };
    if(mode==6){static const auto points=build(6);return points;}
    if(mode==5){static const auto points=build(5);return points;}
    static const auto points=build(4);return points;
}
struct TrailSample { float distance,height,width,along,dx,dz; int route; };
struct TrailSegment { ExpeditionTrailPoint a,b;float dx,dz,length,along; };
inline const std::vector<TrailSegment>& trail_segments(int mode) {
    auto build=[](int map){
        std::vector<TrailSegment> out;const auto&points=trails(map);float along=0;
        for(size_t i=1;i<points.size();++i){
            const auto&a=points[i-1];const auto&b=points[i];
            if(a.route!=b.route){along=0;continue;}
            float dx=b.x-a.x,dz=b.z-a.z,length=std::hypot(dx,dz);
            out.push_back({a,b,dx,dz,length,along});along+=length;
        }
        return out;
    };
    if(mode==6){static const auto segments=build(6);return segments;}
    if(mode==5){static const auto segments=build(5);return segments;}
    static const auto segments=build(4);return segments;
}
inline std::array<TrailSample,4> nearby_trails(int mode,float x,float z) {
    std::array<TrailSample,4> result;
    std::array<float,4> height_sum{},weight_sum{};
    for(int route=0;route<4;++route)result[route]={1e8f,0,3,0,0,-1,route};
    for(const auto &segment:trail_segments(mode)) {
        const auto &a=segment.a,&b=segment.b;
        const float dx=segment.dx,dz=segment.dz,length=segment.length;
        const float t=clamp(((x-a.x)*dx+(z-a.z)*dz)/(length*length),0,1);
        const float px=x-a.x-dx*t,pz=z-a.z-dz*t,d=px*px+pz*pz;
        float weight=length/((d+36)*(d+36));
        height_sum[a.route]+=(a.h+(b.h-a.h)*t)*weight;weight_sum[a.route]+=weight;
        if(d<result[a.route].distance)result[a.route]={d,a.h+(b.h-a.h)*t,a.width+(b.width-a.width)*t,segment.along+t*length,dx/length,dz/length,a.route};
    }
    for(auto&route:result){
        route.distance=std::sqrt(route.distance);
        // Between two arms of one winding route, the shoulder follows their
        // smoothly integrated contour influence. Retain the exact authored
        // elevation under the track; never create a Voronoi cliff in between.
        float shoulder=smooth(route.width+3,route.width+17,route.distance);
        if(weight_sum[route.route]>1e-12f)route.height+=(height_sum[route.route]/weight_sum[route.route]-route.height)*shoulder;
    }
    return result;
}
inline TrailSample nearest_trail(int mode,float x,float z) {
    const auto nearby=nearby_trails(mode,x,z);auto result=nearby[0];
    for(int route=1;route<4;++route)if(nearby[route].distance<result.distance)result=nearby[route];
    return result;
}
inline ExpeditionWater water(int mode) { return mode==5?ExpeditionWater{26,-147,83,66,-1.6f}:ExpeditionWater{108,-87,35,28,5}; }
inline float lake_distance(int mode,float x,float z) {
    if(mode==6)return 100;
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
    if(mode==6) {
        // Broad eroded mesas around connected contour trails. The exact convex
        // cliff faces and ledges are authored separately in expedition_rocks.
        h=6+noise(x*.009f,z*.009f)*7+noise(x*.026f,z*.026f)*1.8f;
        h+=mound(x,z,-178,-247,117,94,69)+mound(x,z,179,-225,91,118,80);
        h+=mound(x,z,-292,-36,66,127,58)+mound(x,z,285,70,61,155,89);
        h+=mound(x,z,0,268,230,65,67);
        h+=smooth(265,330,std::max(std::abs(x),std::abs(z)))*34;
        h+=noise(x*.072f,z*.072f)*.10f;
    } else if(mode==4) {
        // Interlocking ridge spurs wrap around a broad glacial valley. Relief
        // grows coherently towards the massif, rather than random isolated hills.
        h=5+noise(x*.008f,z*.008f)*8+noise(x*.021f,z*.021f)*1.6f;
        h+=mound(x,z,-178,-234,115,125,69)+mound(x,z,-270,-45,91,149,61);
        h+=mound(x,z,145,-206,124,98,75)+mound(x,z,287,-129,74,126,104);
        h+=mound(x,z,-121,269,146,70,77)+mound(x,z,235,253,102,80,117);
        h+=mound(x,z,12,-319,115,53,75);
        float ridged_noise=noise(x*.016f+noise(x*.005f,z*.005f)*.65f,z*.016f);
        float ridge=1-std::sqrt(ridged_noise*ridged_noise+.10f);
        float relief=smooth(15,80,h);
        h+=relief*(ridge*ridge*11+noise(x*.044f,z*.044f)*.72f);
        // Glacial scouring leaves coherent smooth shoulders with short rough
        // steps. Larger exposed ledges are exact convex hulls in the rock cache.
        h+=noise(x*.083f,z*.083f)*(.045f+relief*.11f);
        h+=smooth(277,340,std::max(std::abs(x),std::abs(z)))*29;
    } else {
        // Low, elongated glacial ridges, damp hollows and rounded granite knobs.
        float warp=noise(x*.008f,z*.008f)*.6f;
        h=3.2f+noise(x*.009f,z*.014f)*3.0f+noise(x*.025f,z*.018f)*.8f;
        h+=mound(x,z,-223,5,67,143,12)+mound(x,z,144,203,119,70,17);
        h+=mound(x,z,-152,-231,95,59,11)+mound(x,z,245,-120,68,127,17);
        float spine=noise(x*.020f+warp,z*.010f);
        h+=std::pow(1-std::sqrt(spine*spine+.08f),3.f)*2.8f;
        h+=noise(x*.075f,z*.075f)*.075f;
        h+=smooth(279,350,std::max(std::abs(x),std::abs(z)))*16;
    }
    const auto lake=water(mode);const float d=lake_distance(mode,x,z);
    const float blend=smooth(.89f,1.40f,d);
    const float bed=lake.height-1.7f+smooth(.30f,1.03f,d)*2.8f+noise(x*.055f,z*.055f)*.07f;
    const float shore_raise=(std::max(h,lake.height+1.1f)-h)*(1-smooth(1.25f,1.75f,d));
    h=bed*(1-blend)+(h+shore_raise)*blend;
    if(mode==5) {
        const float c=creek_distance(mode,x,z);
        float bed=lake.height+.16f+std::max(0.f,x-95)*.006f;
        h=bed*(1-smooth(3.2f,34,c))+h*smooth(3.2f,34,c);
    }
    const auto routes=nearby_trails(mode,x,z);auto r=routes[0];
    for(int route=1;route<4;++route)if(routes[route].distance<r.distance)r=routes[route];
    // Trail surface blends through a graded shoulder into native landform.
    // Technical branches retain coherent exposed-rock undulations, while the
    // main forest track has shallow paired wheel ruts and a subtle crown.
    // A trail follows a broad drainage or contour shoulder. Its adjacent
    // landscape must not become a narrow, mechanically excavated trench when
    // a route elevation differs from the broad ridge field. Wider relief
    // transitions retain woodland and asymmetry around the actual wheel track.
    float influence=0,weighted_height=0,weight_sum=0;
    for(const auto&route:routes) {
        float shoulder=clamp(19.f+std::abs(h-route.height)*2.05f,26.f,86.f);
        shoulder*=.97f+.07f*noise(x*.013f,z*.013f);
        float blend=1-smooth(route.width+1,route.width+shoulder,route.distance);
        float weight=blend/std::pow(1+route.distance*route.distance*.13f,2.f);
        weighted_height+=route.height*weight;weight_sum+=weight;
        influence=std::max(influence,blend);
    }
    // Blend the influences of adjacent contour tracks before grading the
    // shoulder. A hard nearest-route switch previously made false cliff seams.
    float route_h=weight_sum>1e-8f?weighted_height/weight_sum:r.height;
    const float rough=r.route>=2?.065f:.022f;
    float trail_h=route_h+noise(x*.09f,z*.09f)*rough;
    const float rut=std::exp(-std::pow((r.distance-0.87f)/.29f,2.f));
    trail_h-=(mode==5?.065f:.035f)*rut;
    h=trail_h*influence+h*(1-influence);
    if(mode==4) {
        // A shallow, local ford on Split Granite, with a stable 5.3 m water
        // level. Its bed is native terrain; a clipped water mesh adds no floor.
        float ford=std::hypot((x-12)/10.f,(z+61)/6.f);
        h=h*smooth(.38f,1.f,ford)+(5.10f+.04f*noise(x*.3f,z*.3f))*(1-smooth(.38f,1.f,ford));
    }
    // The camp, garage and map handoff are the same level on both maps.
    float camp=std::sqrt(x*x+(z-8)*(z-8));
    float camp_blend=smooth(12,40,camp);
    camp_blend+=(smooth(12,22,camp)-camp_blend)*(1-smooth(r.width,r.width+8,r.distance));
    return h*camp_blend;
}
struct Cache {
    std::vector<float> height,surface,gravel;
    std::vector<ExpeditionMaterial> material;
    explicit Cache(int mode):height(side*side),surface(side*side),gravel(side*side),material(side*side) {
        for(int iz=0;iz<side;++iz)for(int ix=0;ix<side;++ix) {
            float x=-extent+ix*spacing,z=-extent+iz*spacing;size_t i=size_t(iz)*side+ix;
            height[i]=(mode==6 && blender_canyon::contains(x,z))?blender_canyon::sample(x,z):authored_height(mode,x,z);
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
            if(mode==5) {
                float hollow=(1-smooth(.04f,.19f,slope))*(.5f+.5f*noise(x*.028f+3,z*.022f));
                wet=std::max(wet,(.16f+trail*.31f)*hollow);
            }
            // Loose granitic debris collects on lower trail margins and dry
            // shore fans. Fine soil and moss retain less grip when saturated.
            gravel[i]=trail*(1-rock)*(mode==4?.93f:.68f)*
                (.65f+.35f*noise(x*.031f+5,z*.027f))*(1-wet*.65f);
            if(mode==6) {
                rock=clamp(.32f+smooth(.10f,.75f,slope)*.60f+trail*(r.route>=2?.42f:.08f),0,.97f);
                dirt=1-rock;wet=0;gravel[i]=0;
            }
            if(mode==4&&std::hypot((x-12)/10.f,(z+61)/6.f)<.65f)wet=.65f;
            if(mode==6 && blender_canyon::contains(x,z)){rock=blender_canyon::sample(x,z,nullptr,nullptr,blender_canyon::rock_weights);dirt=1-rock;}
            material[i]={rock,dirt,1-rock-dirt,wet};
            surface[i]=clamp(rock*(1.10f-wet*.54f)+dirt*(.89f-wet*.35f)+
                (1-rock-dirt)*(.83f-wet*.31f)-gravel[i]*.12f,.52f,1.12f);
        }
    }
};
inline const Cache& cache(int mode) { if(mode==6){static const Cache c(6);return c;} if(mode==5){static const Cache c(5);return c;}static const Cache c(4);return c; }
inline float sample(const std::vector<float>&data,float x,float z) {
    float gx=clamp((x+extent)/spacing,0,float(side-1)),gz=clamp((z+extent)/spacing,0,float(side-1));
    int ix=std::min(side-2,int(gx)),iz=std::min(side-2,int(gz));float tx=gx-ix,tz=gz-iz;size_t i=size_t(iz)*side+ix;
    if(tx+tz<=1)return data[i]+tx*(data[i+1]-data[i])+tz*(data[i+side]-data[i]);
    return data[i+side+1]+(1-tx)*(data[i+side]-data[i+side+1])+(1-tz)*(data[i+1]-data[i+side+1]);
}
}
inline float expedition_height(int mode,float x,float z) {
    if(mode==7)return imported_terrain::sample(x,z);
    if(!std::isfinite(x)||!std::isfinite(z))return 0;
    if(mode==6 && blender_canyon::contains(x,z))return blender_canyon::sample(x,z);
    return expedition_detail::sample(expedition_detail::cache(mode).height,x,z)+
        std::max(0.f,std::max(std::abs(x),std::abs(z))-expedition_detail::extent)*.65f;
}
inline ExplorationNormal expedition_normal(int mode,float x,float z) {
    if(mode==7){float dx,dz;imported_terrain::sample(x,z,&dx,&dz);float l=std::sqrt(dx*dx+dz*dz+1);return {-dx/l,1/l,-dz/l};}
    if(!std::isfinite(x)||!std::isfinite(z))return {0,1,0};
    if(mode==6 && blender_canyon::contains(x,z)){float dx,dz;blender_canyon::sample(x,z,&dx,&dz);float l=std::sqrt(dx*dx+dz*dz+1);return {-dx/l,1/l,-dz/l};}
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
    if(mode==7)return imported_terrain::grip(x,z);
    if(!std::isfinite(x)||!std::isfinite(z))return .85f;
    if(mode==6 && blender_canyon::contains(x,z)){float rock=blender_canyon::sample(x,z,nullptr,nullptr,blender_canyon::rock_weights);return rock*1.10f+(1-rock)*.78f;}
    return expedition_detail::sample(expedition_detail::cache(mode).surface,x,z);
}
inline ExpeditionMaterial expedition_material(int mode,float x,float z) {
    if(mode==7){int l=imported_terrain::layer(x,z);if(l>=8&&l<=10)return {1,0,0,0};if(l>=4&&l<=7)return {0,.3f,.7f,0};return {0,1,0,l==13?1.f:0.f};}
    using namespace expedition_detail;
    if(!std::isfinite(x)||!std::isfinite(z))return {0,0,1,0};
    if(mode==6 && blender_canyon::contains(x,z)){float r=blender_canyon::sample(x,z,nullptr,nullptr,blender_canyon::rock_weights);return {r,1-r,0,0};}
    const auto&data=cache(mode).material;
    float gx=clamp((x+extent)/spacing,0,float(side-1)),gz=clamp((z+extent)/spacing,0,float(side-1));
    int ix=std::min(side-2,int(gx)),iz=std::min(side-2,int(gz));
    float tx=gx-ix,tz=gz-iz;size_t i=size_t(iz)*side+ix;
    auto blend=[](const ExpeditionMaterial&a,const ExpeditionMaterial&b,const ExpeditionMaterial&c,float wa,float wb,float wc){
        return ExpeditionMaterial{a.rock*wa+b.rock*wb+c.rock*wc,a.dirt*wa+b.dirt*wb+c.dirt*wc,
            a.grass*wa+b.grass*wb+c.grass*wc,a.wet*wa+b.wet*wb+c.wet*wc};
    };
    if(tx+tz<=1)return blend(data[i],data[i+1],data[i+side],1-tx-tz,tx,tz);
    return blend(data[i+side+1],data[i+side],data[i+1],tx+tz-1,1-tx,1-tz);
}
inline int expedition_surface_material(int mode,float x,float z) {
    if(mode==7){int l=imported_terrain::layer(x,z);if(l<int(imported_terrain::surface_ids.size()))return imported_terrain::surface_ids[l];if(l>=8&&l<=10)return ExpeditionDryRock;if(l==1)return ExpeditionGravel;if(l==13)return ExpeditionMud;if(l==11||l==12)return ExpeditionSand;return ExpeditionDirt;}
    const auto m=expedition_material(mode,x,z);
    if(m.rock>=.50f)return m.wet>.30f?ExpeditionWetRock:ExpeditionDryRock;
    if(m.wet>.40f)return ExpeditionMud;
    if(mode==6)return ExpeditionSand;
    if(std::isfinite(x)&&std::isfinite(z)&&
        expedition_detail::sample(expedition_detail::cache(mode).gravel,x,z)>.42f)return ExpeditionGravel;
    return ExpeditionDirt;
}
inline float expedition_trail_distance(int mode,float x,float z){return mode==7?10000.f:expedition_detail::nearest_trail(mode,x,z).distance;}
inline const std::vector<ExpeditionTrailPoint>& expedition_trail_points(int mode){if(mode==7){static const std::vector<ExpeditionTrailPoint> empty;return empty;}return expedition_detail::trails(mode);}
inline ExpeditionWater expedition_water(int mode){if(mode==7)return {0,0,0,0,-10000};return expedition_detail::water(mode);}
inline const std::vector<ExpeditionLandmark>& expedition_landmarks(int mode) {
    if(mode==7){static const std::vector<ExpeditionLandmark> empty;return empty;}
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
    static const std::vector<ExpeditionLandmark> canyon{
        {0,8,"Redstone Trailhead","Sandstone country / choose your line"},
        {8,-40,"Bedrock Narrows","Blender-built rock chute / connected shelves"},
        {8,-70,"Fracture Steps","Choose a line through continuous bedrock"},
        {-57,-158,"Rim Traverse","Narrow elevated line / bypass on main trail"},
        {-121,-229,"Slickrock Rise","Long grippy climb toward the arch"},
        {-211,-232,"Window Arch","Open rock span and a sweeping return trail"}
    };
    return mode==6?canyon:(mode==5?taiga:mountain);
}
inline const std::vector<ExplorationObstacle>& expedition_obstacles(int mode) {
    if(mode==7){static const std::vector<ExplorationObstacle> empty;return empty;}
    auto make=[](int m) {
        std::vector<ExplorationObstacle> out;
        using namespace expedition_detail;
        // Spatially staggered woodland creates real clearings and irregular
        // stands. Every rendered trunk has the same cylinder in native contact.
        for(int iz=-37;iz<=37;++iz)for(int ix=-37;ix<=37;++ix) {
            float x=ix*8.15f+(hash(ix+213+m,iz-94)-.5f)*6.7f;
            float z=iz*8.15f+(hash(ix-57,iz+184+m)-.5f)*6.7f;
            float density=m==6?.025f:(.60f+.22f*noise(x*.026f,z*.026f));
            if(hash(ix*7+m*53,iz*11-19)>density)continue;
            const auto trail=nearest_trail(m,x,z);float h=expedition_height(m,x,z);
            if(trail.distance<trail.width+1.7f||x*x+(z-8)*(z-8)<21*21)continue;
            if(lake_distance(m,x,z)<1.14f||(m==5&&creek_distance(m,x,z)<7))continue;
            if(expedition_normal(m,x,z).y<.78f||(m==4&&h>79))continue;
            float v=hash(ix+73,iz-17),height=(m==5?9.f:11.f)+v*(m==5?9.f:12.f);
            int type=m==5&&hash(ix-387,iz+22)>.54f?3:0;
            if(type==3)height*=.82f;
            if(m==6){height=1.3f+v*2.8f; if(h>58)continue;}
            out.push_back({x,z,(type==3?.17f:.22f)+v*.18f,height,type});
        }
        return out;
    };
    if(mode==6){static const auto trees=make(6);return trees;}
    if(mode==5){static const auto trees=make(5);return trees;}static const auto trees=make(4);return trees;
}
} // namespace boltyard
