#pragma once
// Juniper Valley: one shared, cached heightfield for tire contacts and scenery.
// Units are metres. The visual 2 m grid samples the exact physics cache vertices.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

namespace boltyard {
struct ExplorationNormal { float x, y, z; };
struct ExplorationObstacle { float x, z, radius, height; int type; };
namespace exploration_detail {
constexpr float extent = 384.0f;
constexpr float spacing = 2.0f;
constexpr int side = 385;
struct RoadPoint { float x, z, h; };
inline constexpr std::array<RoadPoint, 17> road{{
    {0,8,0}, {0,-40,0}, {-45,-75,4}, {-90,-105,7}, {-145,-75,10},
    {-178,12,8}, {-157,83,16}, {-92,176,38}, {-20,205,32}, {75,165,18},
    {157,92,5}, {185,28,9}, {177,-65,18}, {155,-162,34}, {82,-185,23},
    {40,-125,11}, {0,-40,0}
}};
inline float clamp(float v, float lo, float hi) { return std::max(lo, std::min(hi, v)); }
inline float smooth(float lo, float hi, float v) {
    float t = clamp((v-lo)/(hi-lo),0.0f,1.0f); return t*t*(3.0f-2.0f*t);
}
inline float hash(int x, int z) {
    uint32_t n = static_cast<uint32_t>(x)*374761393u + static_cast<uint32_t>(z)*668265263u + 129173u;
    n = (n^(n>>13))*1274126177u; return static_cast<float>((n^(n>>16))&65535u)/65535.0f;
}
inline float noise(float x, float z) {
    int ix = static_cast<int>(std::floor(x)), iz = static_cast<int>(std::floor(z));
    float tx = smooth(0,1,x-ix), tz = smooth(0,1,z-iz);
    float a = hash(ix,iz)*(1-tx)+hash(ix+1,iz)*tx;
    float b = hash(ix,iz+1)*(1-tx)+hash(ix+1,iz+1)*tx;
    return (a*(1-tz)+b*tz)*2-1;
}
inline float mound(float x,float z,float cx,float cz,float sx,float sz,float height) {
    float dx=(x-cx)/sx, dz=(z-cz)/sz; return height*std::exp(-(dx*dx+dz*dz));
}
struct RoadSample { float distance, height; };
inline RoadSample nearest_road(float x, float z) {
    RoadSample result{1e9f,0};
    for (size_t i=1;i<road.size();++i) {
        const auto &a=road[i-1], &b=road[i];
        float dx=b.x-a.x,dz=b.z-a.z;
        float t=clamp(((x-a.x)*dx+(z-a.z)*dz)/(dx*dx+dz*dz),0,1);
        float px=x-a.x-dx*t,pz=z-a.z-dz*t, d=std::sqrt(px*px+pz*pz);
        if(d<result.distance) result={d,a.h+(b.h-a.h)*smooth(0,1,t)};
    }
    return result;
}
inline float lake_distance(float x,float z) {
    float dx=(x-96.0f)/49.0f,dz=(z-81.0f)/42.0f; return std::sqrt(dx*dx+dz*dz);
}
inline float authored_height(float x,float z) {
    float h=4.0f + noise(x*.009f,z*.009f)*9.0f + noise(x*.032f,z*.032f)*2.4f;
    h+=mound(x,z,-95,180,95,90,44)+mound(x,z,155,-175,100,85,37);
    h+=mound(x,z,-286,-158,95,130,70)+mound(x,z,285,220,100,110,85);
    h+=mound(x,z,10,-310,130,75,90)+mound(x,z,-250,282,135,90,76);
    float boundary=std::max(std::abs(x),std::abs(z));
    h+=smooth(285,410,boundary)*48.0f;
    // A terraced quarry, with a smooth entrance preserved by the road below.
    float qx=(x+178)/48.0f,qz=(z-12)/56.0f,q=std::sqrt(qx*qx+qz*qz);
    float quarry=8.0f+smooth(.58f,.68f,q)*4.5f+smooth(.91f,1.01f,q)*6.0f;
    h=h*(smooth(1.03f,1.23f,q))+quarry*(1-smooth(1.03f,1.23f,q));
    // The lake is a shallow basin. Water is an appearance layer; this is the solid bed.
    float lake=lake_distance(x,z);
    h=h*smooth(.80f,1.45f,lake)+(-1.2f+smooth(0,.90f,lake)*2.7f)*(1-smooth(.80f,1.45f,lake));
    RoadSample r=nearest_road(x,z);
    float shoulder=smooth(4.4f,11.0f,r.distance);
    float track_noise=noise(x*.23f,z*.23f)*.065f;
    float road_h=r.height+track_noise;
    h=road_h*(1-shoulder)+h*shoulder;
    // Spawn and garage are exactly flat, and blend into the loop without a lip.
    float spawn=std::sqrt(x*x+(z-8)*(z-8));
    h*=smooth(20.0f,31.0f,spawn);
    return h;
}
struct Cache {
    std::vector<float> height, surface;
    Cache():height(side*side),surface(side*side) {
        for(int iz=0;iz<side;++iz) for(int ix=0;ix<side;++ix) {
            float x=-extent+ix*spacing,z=-extent+iz*spacing;
            size_t i=static_cast<size_t>(iz)*side+ix;
            height[i]=authored_height(x,z);
            float s=.84f;
            if(nearest_road(x,z).distance<4.8f) s=1.0f;
            float qx=(x+178)/48.0f,qz=(z-12)/56.0f;
            if(qx*qx+qz*qz<1) s=.94f;
            if(lake_distance(x,z)<.95f) s=.58f;
            if(x*x+(z-8)*(z-8)<400) s=1.0f;
            surface[i]=s;
        }
    }
};
inline const Cache &cache() { static const Cache c; return c; }
inline float sample(const std::vector<float> &data,float x,float z) {
    float gx=clamp((x+extent)/spacing,0,static_cast<float>(side-1));
    float gz=clamp((z+extent)/spacing,0,static_cast<float>(side-1));
    int ix=std::min(side-2,static_cast<int>(gx)),iz=std::min(side-2,static_cast<int>(gz));
    float tx=gx-ix,tz=gz-iz;
    size_t i=static_cast<size_t>(iz)*side+ix;
    // Match the rendered two triangles exactly: no bilinear saddle discrepancy.
    if(tx+tz<=1) return data[i]+tx*(data[i+1]-data[i])+tz*(data[i+side]-data[i]);
    return data[i+side+1]+(1-tx)*(data[i+side]-data[i+side+1])+(1-tz)*(data[i+1]-data[i+side+1]);
}
} // exploration_detail
inline float exploration_height(float x,float z) {
    if(!std::isfinite(x)||!std::isfinite(z)) return 0;
    float h=exploration_detail::sample(exploration_detail::cache().height,x,z);
    // Natural enclosing mountain slopes continue outside the authored area.
    float outside=std::max(0.0f,std::max(std::abs(x),std::abs(z))-384.0f);
    return h+outside*.8f;
}
inline ExplorationNormal exploration_normal(float x,float z) {
    if(!std::isfinite(x)||!std::isfinite(z)) return {0,1,0};
    const auto &data=exploration_detail::cache().height;
    float gx=exploration_detail::clamp((x+384)/2,0,384),gz=exploration_detail::clamp((z+384)/2,0,384);
    int ix=std::min(383,static_cast<int>(gx)),iz=std::min(383,static_cast<int>(gz));
    size_t i=static_cast<size_t>(iz)*385+ix;
    float dx,dz;
    if(gx-ix+gz-iz<=1) { dx=(data[i+1]-data[i])*.5f; dz=(data[i+385]-data[i])*.5f; }
    else { dx=(data[i+386]-data[i+385])*.5f; dz=(data[i+386]-data[i+1])*.5f; }
    if(std::abs(x)>384 && std::abs(x)>=std::abs(z)) dx+=x>0?.8f:-.8f;
    if(std::abs(z)>384 && std::abs(z)>std::abs(x)) dz+=z>0?.8f:-.8f;
    float l=std::sqrt(dx*dx+1+dz*dz); return {-dx/l,1/l,-dz/l};
}
inline float exploration_surface(float x,float z) {
    if(!std::isfinite(x)||!std::isfinite(z)) return .84f;
    return exploration_detail::sample(exploration_detail::cache().surface,x,z);
}
inline const std::vector<ExplorationObstacle> &exploration_obstacles() {
    static const std::vector<ExplorationObstacle> objects=[] {
        std::vector<ExplorationObstacle> result;
        // Three visible groves, with trunks kept clear of both road lanes.
        constexpr float clusters[6][2]={{-67,-103},{-114,-91},{-131,69},{-29,170},{160,-119},{177,115}};
        for(int c=0;c<6;++c) for(int j=0;j<10;++j) {
            float angle=j*2.399963f+c*.72f, r=8+std::sqrt(static_cast<float>(j))*8;
            float x=clusters[c][0]+std::cos(angle)*r,z=clusters[c][1]+std::sin(angle)*r;
            if(exploration_detail::nearest_road(x,z).distance<7.5f || exploration_detail::lake_distance(x,z)<1.13f) continue;
            float variation=exploration_detail::hash(c*17,j*23);
            result.push_back({x,z,.33f+variation*.23f,8.0f+variation*7.0f,0});
        }
        constexpr float rocks[14][2]={{-165,30},{-190,-8},{-203,24},{-171,-17},{-148,29},{-199,47},{-111,180},
            {-80,187},{149,-149},{172,-175},{129,114},{153,75},{-71,-89},{-103,-119}};
        for(int i=0;i<14;++i) result.push_back({rocks[i][0],rocks[i][1],1.3f+(i%3)*.4f,1.6f+(i%4)*.35f,1});
        // Six wayfinding posts: visible cylinders and native contact proxies match.
        constexpr float posts[6][2]={{-7,8},{-87,-112},{-183,12},{-96,180},{161,95},{160,-165}};
        for(const auto &p:posts) result.push_back({p[0],p[1],.14f,2.3f,2});
        return result;
    }();
    return objects;
}
} // boltyard
