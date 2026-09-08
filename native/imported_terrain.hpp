#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace boltyard { namespace imported_terrain {
// One immutable shared grid, loaded before selecting terrain mode 7.
constexpr int side=1025;
inline float extent=1024.f, spacing=2.f;
inline std::vector<float> surface_grip;
inline std::vector<int> surface_ids;
inline std::vector<float> heights;
inline std::vector<uint8_t> layers;
inline bool ready(){return heights.size()==size_t(side)*side;}
inline bool load(const float *h,size_t nh,const uint8_t *m,size_t nm){
    if(nh!=size_t(side)*side||nm!=nh||!h||!m)return false;
    for(size_t i=0;i<nh;++i)if(!std::isfinite(h[i])||std::abs(h[i])>10000||m[i]>13)return false;
    heights.assign(h,h+nh);layers.assign(m,m+nm);return true;
}
inline float at(int x,int z){return ready()?heights[size_t(std::clamp(z,0,side-1))*side+std::clamp(x,0,side-1)]:0;}
inline float sample(float x,float z,float *dx=nullptr,float *dz=nullptr){
    if(dx)*dx=0;if(dz)*dz=0;
    if(!ready()||!std::isfinite(x)||!std::isfinite(z))return 0;
    float gx=std::clamp((x+extent)/spacing,0.f,float(side-1));
    float gz=std::clamp((z+extent)/spacing,0.f,float(side-1));
    int ix=std::min(side-2,int(gx)),iz=std::min(side-2,int(gz));
    float tx=gx-ix,tz=gz-iz,a=at(ix,iz),b=at(ix+1,iz),c=at(ix,iz+1),d=at(ix+1,iz+1);
    float sx,sz,h;
    if(tx+tz<=1){sx=(b-a)/spacing;sz=(c-a)/spacing;h=a+tx*(b-a)+tz*(c-a);}
    else{sx=(d-c)/spacing;sz=(d-b)/spacing;h=d+(1-tx)*(c-d)+(1-tz)*(b-d);}
    if(std::abs(x)>extent)sx=0;if(std::abs(z)>extent)sz=0;
    if(dx)*dx=sx;if(dz)*dz=sz;return h;
}
inline int layer(float x,float z){
    if(!ready()||!std::isfinite(x)||!std::isfinite(z))return 3;
    int ix=int(std::clamp((x+extent)/spacing,0.f,float(side-1)));
    int iz=int(std::clamp((z+extent)/spacing,0.f,float(side-1)));
    return layers[size_t(iz)*side+ix];
}
inline float grip(float x,float z){
    constexpr float values[]={1.05f,.78f,.78f,.85f,.78f,.78f,.78f,.80f,1.10f,.98f,.95f,.76f,.70f,.55f};
    int id=layer(x,z);return id<int(surface_grip.size())?surface_grip[id]:values[id];
}
} }
