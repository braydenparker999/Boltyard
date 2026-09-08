#pragma once
// Two fictional expedition landscapes. The 2 m cache is the authoritative
// ground mesh: contact heights, normals, materials and rendering share it.
#include "terrain_v03.hpp"

namespace boltyard {
struct ExpeditionMaterial { float rock, dirt, grass, wet; };
// Shared with tire telemetry; these describe the contact patch, not the map.
enum ExpeditionSurfaceMaterial { ExpeditionDirt=0, ExpeditionDryRock=1,
    ExpeditionWetRock=2, ExpeditionMud=3, ExpeditionSand=4,
    ExpeditionWood=5, ExpeditionGravel=6 };
struct ExpeditionTrailPoint { float x,z,h,width; int route; };
struct ExpeditionLandmark { float x,z; const char *name,*detail; };
struct ExpeditionWater { float x,z,rx,rz,height; };
// A route is a named way through the region. Difficulty 2 marks a technical
// line: rougher tread, closer rock and a wider grade allowance when tested.
struct ExpeditionRoute { const char *name,*detail; int difficulty; };
namespace expedition_detail {
constexpr float extent=320.f, spacing=2.f;
constexpr int side=321;
// Regions may carry up to this many named routes. Sampling walks the segment
// list once and buckets by route, so the ceiling costs storage, not time.
constexpr int max_routes=6;
// Terrain modes 0-3 are the legacy flat, road and crawl-course fixtures.
// Every mode from here up is an expedition region; adding one means raising
// this bound and giving each per-region selector its branch.
constexpr int first_terrain_mode=4,last_terrain_mode=6;
using exploration_detail::clamp;
using exploration_detail::smooth;
using exploration_detail::noise;
using exploration_detail::mound;
using exploration_detail::hash;
// Stable short name for a region, used for save keys and landmark ids.
inline const char* region_id(int mode) {
    return mode==6?"redrock":mode==5?"russia":"rockies";
}
inline const std::vector<ExpeditionRoute>& routes(int mode) {
    static const std::vector<ExpeditionRoute> mountain{
        {"Valley Loop","Graded forest road around the glacial valley",0},
        {"Tarn Circuit","Eastern loop past the granite shoreline",0},
        {"Moraine Steps","Exposed ridge with technical ledges",2},
        {"Split Granite","Short bedrock crawl above camp",2}};
    static const std::vector<ExpeditionRoute> taiga{
        {"Forest Loop","Western birch and spruce track",0},
        {"Long Ridge","Northern forest road over the rock spine",0},
        {"Lake Vetra","Wet shoreline crawl and stony ford",2},
        {"Old Granite Cut","Weathered slabs beneath the birches",2}};
    // Six connected ways through the redrock basin. Every technical line
    // leaves and rejoins an easier one, so a stuck driver always has an exit.
    static const std::vector<ExpeditionRoute> redrock{
        {"Basin Wash","Sandy drainage loop linking every area",0},
        {"Dome Traverse","Rolling bare slickrock above the basin",1},
        {"The Fins","Narrow corridors between standing sandstone",2},
        {"Devils Staircase","Stacked ledge climb up the mesa flank",2},
        {"Mesa Rim Road","Exposed shelf track along the rim",1},
        {"Pothole Flats","Scoured benches, potholes and short drops",2}};
    if(mode==6)return redrock;
    return mode==5?taiga:mountain;
}
inline int route_count(int mode) { return int(routes(mode).size()); }
inline bool technical_route(int mode,int route) {
    const auto &list=routes(mode);
    return route>=0&&route<int(list.size())&&list[route].difficulty>=2;
}
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
    // Redrock Basin. Route 0 is the sandy wash loop that every other route
    // leaves from and returns to; 3 and 4 hand off at the mesa rim, so the
    // climb and the rim road read as one continuous way up and around.
    // Redrock Basin. Route 0 is the wash loop every other route leaves from
    // and returns to, run as a figure eight through camp so both halves of the
    // basin are one continuous easy way round. Routes 3 and 4 hand off at the
    // mesa rim, so the climb and the rim road read as one way up and around.
    // Anchor elevations were solved against the landform, then relaxed until
    // every span is climbable; they follow the ground rather than cut it.
    static const std::vector<ExpeditionTrailPoint> redrock{
        // Basin Wash
        {0,8,0,3.5f,0},{-46,-34,5,3.5f,0},{-56,-88,3,3.5f,0},
        {-62,-148,3,3.5f,0},{-56,-208,3,3.5f,0},{-18,-250,6,3.5f,0},
        {40,-254,13,3.5f,0},{102,-218,23,3.5f,0},{138,-160,28,3.5f,0},
        {150,-96,28,3.5f,0},{142,-38,20,3.5f,0},{104,-4,12,3.5f,0},
        {52,-8,5,3.5f,0},{0,8,0,3.5f,0},{-52,34,5,3.5f,0},
        {-96,84,11,3.5f,0},{-116,144,16,3.5f,0},{-88,200,16,3.5f,0},
        {-26,224,12,3.5f,0},{44,214,11,3.5f,0},{100,174,12,3.5f,0},
        {128,116,12,3.5f,0},{120,58,7,3.5f,0},{78,44,3,3.5f,0},
        {0,8,0,3.5f,0},
        // Dome Traverse
        {102,-218,23,3.0f,1},{152,-244,24,3.0f,1},{212,-232,24,3.0f,1},
        {244,-182,26,3.0f,1},{238,-124,28,3.0f,1},{196,-92,29,3.0f,1},
        {150,-96,28,3.0f,1},
        // The Fins
        {-116,144,16,2.2f,2},{-172,158,22,2.2f,2},{-224,186,26,2.2f,2},
        {-250,214,28,2.2f,2},{-254,250,28,2.2f,2},{-224,272,27,2.2f,2},
        {-176,278,25,2.2f,2},{-124,258,21,2.2f,2},{-88,200,16,2.2f,2},
        // Devils Staircase
        {-46,-34,5,2.3f,3},{-84,-56,17,2.3f,3},{-116,-84,28,2.3f,3},
        {-138,-118,39,2.3f,3},{-152,-154,50,2.3f,3},{-164,-190,60,2.3f,3},
        {-178,-224,70,2.3f,3},{-207,-226,76,2.3f,3},
        // Mesa Rim Road
        {-207,-226,76,2.9f,4},{-195,-176,73,2.9f,4},{-202,-123,71,2.9f,4},
        {-224,-87,68,2.9f,4},{-254,-82,68,2.9f,4},{-279,-110,70,2.9f,4},
        {-291,-160,72,2.9f,4},{-284,-213,74,2.9f,4},{-262,-249,75,2.9f,4},
        {-232,-254,75,2.9f,4},{-207,-226,76,2.9f,4},
        // Pothole Flats
        {100,174,12,2.4f,5},{146,206,19,2.4f,5},{200,224,23,2.4f,5},
        {248,204,22,2.4f,5},{262,158,18,2.4f,5},{232,118,16,2.4f,5},
        {180,112,14,2.4f,5},{128,116,12,2.4f,5},
    };
    if(mode==6)return redrock;
    return mode==5?taiga:mountain;
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
inline std::array<TrailSample,max_routes> nearby_trails(int mode,float x,float z) {
    std::array<TrailSample,max_routes> result;
    std::array<float,max_routes> height_sum{},weight_sum{};
    const int count=route_count(mode);
    for(int route=0;route<max_routes;++route)result[route]={1e8f,0,3,0,0,-1,route};
    for(const auto &segment:trail_segments(mode)) {
        const auto &a=segment.a,&b=segment.b;
        const float dx=segment.dx,dz=segment.dz,length=segment.length;
        const float t=clamp(((x-a.x)*dx+(z-a.z)*dz)/(length*length),0,1);
        const float px=x-a.x-dx*t,pz=z-a.z-dz*t,d=px*px+pz*pz;
        float weight=length/((d+36)*(d+36));
        height_sum[a.route]+=(a.h+(b.h-a.h)*t)*weight;weight_sum[a.route]+=weight;
        if(d<result[a.route].distance)result[a.route]={d,a.h+(b.h-a.h)*t,a.width+(b.width-a.width)*t,segment.along+t*length,dx/length,dz/length,a.route};
    }
    for(int index=0;index<count;++index){
        auto &route=result[index];
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
    for(int route=1;route<route_count(mode);++route)
        if(nearby[route].distance<result.distance)result=nearby[route];
    return result;
}
inline ExpeditionWater water(int mode) {
    // Redrock holds no lake. Its water is a scoured pothole tank on the
    // south-eastern benches: small, shallow, and the one wet rock on the map.
    if(mode==6)return ExpeditionWater{188,262,34,24,24.f};
    return mode==5?ExpeditionWater{26,-147,83,66,-1.6f}:ExpeditionWater{108,-87,35,28,5};
}
// The redrock basin drains along one sinuous sandy wash, from the mesa foot
// in the north-west out past camp to the eastern rim.
inline float wash_offset(float x,float z) {
    const float path=6.f+x*.27f+13.f*std::sin((x+40)*.0165f);
    return std::abs(z-path);
}
// Layered sandstone erodes into flat treads with short risers. Passing a
// smooth field through this transfer snaps it towards discrete bedding levels.
inline float terrace(float value,float step,float tread) {
    const float k=value/step,level=std::floor(k),f=k-level;
    return step*(level+smooth(tread*.5f,1.f-tread*.5f,f));
}
// A flat-topped upland. A gaussian would dome the summit and leave nowhere
// level for a rim road; this holds its full height inside the footprint and
// puts all of the relief into a flank the routes can traverse.
inline float plateau(float x,float z,float cx,float cz,float rx,float rz,float height,float flank) {
    return height*(1-smooth(1.f,1.f+flank,std::hypot((x-cx)/rx,(z-cz)/rz)));
}
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
// Colorado Plateau country. A broad sandstone platform cut into flat benches,
// raised into a mesa in the north-west, scoured into a dome field in the east
// and drained by one sandy wash. Everything here is landform: the metre-scale
// walls, fins and ledge steps redrock is known for are exact convex hulls in
// the rock cache, so the heightfield stays a surface a tire can read.
// The bedrock platform before bedding is applied: a low sandy basin with
// flat-topped uplands standing over it.
inline float redrock_platform(float x,float z) {
    float h=4.6f+noise(x*.0058f,z*.0058f)*3.4f+noise(x*.017f,z*.017f)*.9f;
    // Benches stack: a smaller platform standing on a larger one is what
    // gives canyon country its tiered skyline and its stepped ways up.
    h+=plateau(x,z,-252,-166, 82, 90,58,1.22f);   // the mesa
    h+=plateau(x,z,-238,-198, 44, 50,10,1.50f);   // its capstone knoll
    h+=plateau(x,z, 176,-146, 98, 96,16, .95f);   // dome swell
    h+=plateau(x,z, 216,-104, 50, 56,11,1.10f);   // upper dome
    h+=plateau(x,z, 108,-196, 52, 46, 9,1.20f);   // south dome
    h+=plateau(x,z,-176, 196, 84, 80,12,1.05f);   // fin platform
    h+=plateau(x,z,-208, 232, 42, 40, 9,1.30f);   // upper fin bench
    h+=plateau(x,z, 176, 202, 88, 84,11,1.00f);   // pothole benches
    h+=plateau(x,z, 210, 226, 46, 42,10,1.25f);   // upper pothole bench
    h+=plateau(x,z,-192,  28, 56, 74, 6,1.30f);   // west bench
    return h;
}
inline float redrock_landform(float x,float z) {
    const float platform=redrock_platform(x,z);
    // Bedding only survives where the platform is close to level. On a flank
    // the risers would stack into a staircase steeper than the cliff they sit
    // on, so the benching fades out as the grade rises.
    const float step=2.f;
    const float gx=(redrock_platform(x+step,z)-redrock_platform(x-step,z))*.25f;
    const float gz=(redrock_platform(x,z+step)-redrock_platform(x,z-step))*.25f;
    const float bench=1-smooth(.09f,.38f,std::hypot(gx,gz));
    float h=platform+(terrace(platform,9.5f,.55f)-platform)*bench;
    // Crossbedded whalebacks in the dome field.
    const float dome=smooth(150.f,54.f,std::hypot((x-178)*.86f,(z+142)*.95f));
    h+=dome*(5.4f*noise(x*.0132f+11,z*.0132f-4)+1.6f*noise(x*.038f,z*.038f));
    // Standing fins run north-east. Rounding the trough removes the cusp a
    // plain sine power leaves at every zero crossing.
    const float fin_field=smooth(126.f,44.f,std::hypot((x+178)*.92f,(z-198)*1.05f));
    const float across=(x+178)*.7071f-(z-198)*.7071f;
    h+=fin_field*3.4f*smooth(0.f,1.f,std::abs(std::sin(across*.1147f)));
    h-=3.3f*(1-smooth(6.5f,23.f,wash_offset(x,z)));
    // Camp occupies a sand flat scoured at the head of the wash. Without it
    // the basin stands several metres above the levelled camp pad and the
    // blend between the two becomes the steepest ground on the map.
    h-=6.4f*(1-smooth(30.f,132.f,std::hypot(x,z-8)));
    h+=noise(x*.088f,z*.088f)*.055f;
    return h+smooth(285,345,std::max(std::abs(x),std::abs(z)))*26;
}
// The surface pass needs the same nearest-route answer the height pass just
// computed. Returning it removes a second full walk of the segment list per
// grid cell, which is the dominant cost of building a region.
inline float authored_height(int mode,float x,float z,TrailSample *nearest_out=nullptr) {
    float h;
    if(mode==4) {
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
    } else if(mode==6) {
        h=redrock_landform(x,z);
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
    const auto near=nearby_trails(mode,x,z);auto r=near[0];
    for(int route=1;route<route_count(mode);++route)if(near[route].distance<r.distance)r=near[route];
    if(nearest_out!=nullptr)*nearest_out=r;
    // Trail surface blends through a graded shoulder into native landform.
    // Technical branches retain coherent exposed-rock undulations, while the
    // main forest track has shallow paired wheel ruts and a subtle crown.
    // A trail follows a broad drainage or contour shoulder. Its adjacent
    // landscape must not become a narrow, mechanically excavated trench when
    // a route elevation differs from the broad ridge field. Wider relief
    // transitions retain woodland and asymmetry around the actual wheel track.
    // Bedrock is not graded. A slickrock line is painted across the rock it
    // crosses, so redrock starts from a much shorter shoulder; six routes
    // sharing one basin would otherwise merge their aprons into one flat
    // plain. It still opens up steeply with the height a shelf road has to
    // make up, because a narrow apron on a mesa flank is a cut edge, not a
    // landform, and the tire reads that edge as a seam.
    const float shoulder_base=mode==6?22.f:19.f,shoulder_gain=mode==6?1.30f:2.05f;
    const float shoulder_min=mode==6?30.f:26.f,shoulder_max=mode==6?86.f:86.f;
    float influence=0,weighted_height=0,weight_sum=0;
    for(int index=0;index<route_count(mode);++index) {
        const auto &route=near[index];
        float shoulder=clamp(shoulder_base+std::abs(h-route.height)*shoulder_gain,shoulder_min,shoulder_max);
        shoulder*=.97f+.07f*noise(x*.013f,z*.013f);
        float blend=1-smooth(route.width+1,route.width+shoulder,route.distance);
        float weight=blend/std::pow(1+route.distance*route.distance*.13f,2.f);
        weighted_height+=route.height*weight;weight_sum+=weight;
        influence=std::max(influence,blend);
    }
    // Blend the influences of adjacent contour tracks before grading the
    // shoulder. A hard nearest-route switch previously made false cliff seams.
    float route_h=weight_sum>1e-8f?weighted_height/weight_sum:r.height;
    const bool hard=technical_route(mode,r.route);
    const float rough=mode==6?(hard?.075f:.030f):(hard?.065f:.022f);
    float trail_h=route_h+noise(x*.09f,z*.09f)*rough;
    const float rut=std::exp(-std::pow((r.distance-0.87f)/.29f,2.f));
    trail_h-=(mode==5?.065f:mode==6?.048f:.035f)*rut;
    h=trail_h*influence+h*(1-influence);
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
        std::vector<TrailSample> route_of_cell(size_t(side)*side);
        for(int iz=0;iz<side;++iz)for(int ix=0;ix<side;++ix) {
            float x=-extent+ix*spacing,z=-extent+iz*spacing;size_t i=size_t(iz)*side+ix;
            height[i]=authored_height(mode,x,z,&route_of_cell[i]);
        }
        for(int iz=0;iz<side;++iz)for(int ix=0;ix<side;++ix) {
            float x=-extent+ix*spacing,z=-extent+iz*spacing;size_t i=size_t(iz)*side+ix;
            const auto r=route_of_cell[i];
            float slope=std::abs(height[size_t(iz)*side+std::min(side-1,ix+1)]-height[size_t(iz)*side+std::max(0,ix-1)])*.25f+
                        std::abs(height[size_t(std::min(side-1,iz+1))*side+ix]-height[size_t(std::max(0,iz-1))*side+ix])*.25f;
            float trail=1-smooth(r.width-.5f,r.width+2.1f,r.distance);
            float rock,dirt,wet;
            if(mode==6) {
                // Redrock inverts the other two maps. Bare sandstone is the
                // default ground and the third material channel carries
                // wind-blown sand instead of forest floor: it collects in the
                // wash, in level lee pockets and low in the basin, and is
                // scoured off the benches, the domes and every steep face.
                float sand=1-smooth(7.f,27.f,wash_offset(x,z));
                sand=std::max(sand,(1-smooth(.035f,.21f,slope))*(.20f+.48f*noise(x*.023f+7,z*.019f)));
                sand=clamp(sand*(1-smooth(28.f,64.f,height[i])),0,.93f);
                // The tank sits in a sand-floored basin, so its margin stays
                // soft: saturated sand, not wet rock, right at the water.
                sand=std::max(sand,.88f*(1-smooth(1.02f,1.62f,lake_distance(mode,x,z))));
                rock=clamp((1-sand)*(.74f+smooth(.05f,.40f,slope)*.24f),0,.94f);
                dirt=trail*(1-rock)*.85f;
                wet=.80f*(1-smooth(1.00f,1.46f,lake_distance(mode,x,z)));
            } else {
                rock=clamp(smooth(.28f,1.40f,slope)*.86f+(mode==4?smooth(44,87,height[i])*.64f:0),0,.94f);
                if(technical_route(mode,r.route))rock=std::max(rock,trail*(mode==4?.64f:.42f));
                dirt=trail*(1-rock)*.9f;
                wet=(mode==5?.86f:.48f)*(1-smooth(.88f,1.20f,lake_distance(mode,x,z)));
                if(mode==5)wet=std::max(wet,.7f*(1-smooth(3,11,creek_distance(mode,x,z))));
                if(mode==5) {
                    float hollow=(1-smooth(.04f,.19f,slope))*(.5f+.5f*noise(x*.028f+3,z*.022f));
                    wet=std::max(wet,(.16f+trail*.31f)*hollow);
                }
            }
            if(mode==6&&technical_route(mode,r.route))rock=std::max(rock,trail*.66f*(1-wet));
            // Loose granitic debris collects on lower trail margins and dry
            // shore fans. Fine soil and moss retain less grip when saturated.
            gravel[i]=trail*(1-rock)*(mode==4?.93f:mode==6?.86f:.68f)*
                (.65f+.35f*noise(x*.031f+5,z*.027f))*(1-wet*.65f);
            // A desert wash floor is a cobble and pea-gravel bar whether or not
            // a route runs down it, and it drives quite differently from the
            // wind-blown sand banked up on either side.
            if(mode==6)gravel[i]=std::max(gravel[i],(1-smooth(4.f,16.f,wash_offset(x,z)))*
                (1-rock)*(.62f+.30f*noise(x*.037f-9,z*.033f))*(1-wet*.65f));
            material[i]={rock,dirt,1-rock-dirt,wet};
            // Dry sandstone is the grippiest surface in the game and dry sand
            // one of the loosest, so redrock separates the two channels wider
            // than the boreal maps separate rock from forest floor.
            const float loose_grip=mode==6?.70f:.83f;
            surface[i]=clamp(rock*(1.10f-wet*.54f)+dirt*(.89f-wet*.35f)+
                (1-rock-dirt)*(loose_grip-wet*.31f)-gravel[i]*.12f,.52f,1.12f);
        }
    }
};
inline const Cache& cache(int mode) {
    if(mode==6){static const Cache c(6);return c;}
    if(mode==5){static const Cache c(5);return c;}
    static const Cache c(4);return c;
}
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
    const auto m=expedition_material(mode,x,z);
    if(m.rock>=.50f)return m.wet>.30f?ExpeditionWetRock:ExpeditionDryRock;
    if(m.wet>.40f)return ExpeditionMud;
    if(std::isfinite(x)&&std::isfinite(z)&&
        expedition_detail::sample(expedition_detail::cache(mode).gravel,x,z)>.42f)return ExpeditionGravel;
    // Redrock's third channel is wind-blown sand. It is a distinct contact
    // material from packed trail dirt and from a gravel wash bar: much looser
    // than either, and it reports as such.
    if(mode==6&&m.grass>=.52f&&m.wet<=.25f)return ExpeditionSand;
    return ExpeditionDirt;
}
inline const char* expedition_region_id(int mode){return expedition_detail::region_id(mode);}
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
    static const std::vector<ExpeditionLandmark> redrock{
        {0,8,"Redrock Basecamp","Sand flat at the head of the wash"},
        {-138,-118,"Devils Staircase","Stacked ledge climb up the mesa flank"},
        {-254,-82,"Mesa Rim","Exposed shelf track along the top"},
        {-224,186,"The Fins","Narrow corridors between standing sandstone"},
        {188,262,"Water Pocket","Scoured tank holding water on the benches"},
        {212,-232,"Slickrock Domes","Rolling bare sandstone above the basin"},
        {150,-96,"Wash Junction","Where the dome traverse rejoins the basin"}
    };
    static const std::vector<ExpeditionLandmark> taiga{
        {0,8,"Karelia Field Camp","Northern forest expedition"},
        {-63,-29,"Old Granite Cut","Weathered slabs beneath the birches"},
        {-215,8,"Birch Ridge","Glacial rock spine in mixed woodland"},
        {-101,-169,"Lake Vetra Shore","Granite shoreline and wet tracks"},
        {133,184,"Northern Lookout","Forest road over the long ridge"},
        {130,-153,"Stony Ford","Shallow drainage and loose stones"}
    };
    if(mode==6)return redrock;
    return mode==5?taiga:mountain;
}
inline const std::vector<ExplorationObstacle>& expedition_obstacles(int mode) {
    auto make=[](int m) {
        std::vector<ExplorationObstacle> out;
        using namespace expedition_detail;
        if(m==6) {
            // Pinyon-juniper, not woodland. Nothing roots in bare sandstone, so
            // the stands follow the sand the surface pass already found: wash
            // margins, lee pockets and the sandy heads of the benches. They are
            // short and open, and each is still an exact native contact cylinder.
            for(int iz=-27;iz<=27;++iz)for(int ix=-27;ix<=27;++ix) {
                float x=ix*11.4f+(hash(ix+409,iz-77)-.5f)*9.4f;
                float z=iz*11.4f+(hash(ix-131,iz+318)-.5f)*9.4f;
                if(std::max(std::abs(x),std::abs(z))>309.f)continue;
                const auto material=expedition_material(6,x,z);
                // Sand is the third channel on this map; deep sand and bare
                // rock are both bare, and the trees live between them.
                float rooting=smooth(.08f,.50f,material.grass);
                float density=1.25f*rooting*(.40f+.90f*noise(x*.019f+31,z*.021f-12));
                if(hash(ix*7+m*53,iz*11-19)>density)continue;
                const auto trail=nearest_trail(6,x,z);
                if(trail.distance<trail.width+1.9f||x*x+(z-8)*(z-8)<21*21)continue;
                if(lake_distance(6,x,z)<1.18f)continue;
                if(expedition_normal(6,x,z).y<.86f)continue;
                float v=hash(ix+73,iz-17);
                out.push_back({x,z,.19f+v*.15f,3.1f+v*3.0f,0});
            }
            return out;
        }
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
    if(mode==6){static const auto trees=make(6);return trees;}
    if(mode==5){static const auto trees=make(5);return trees;}
    static const auto trees=make(4);return trees;
}
} // namespace boltyard
