#include "soft_rig.hpp"
#include <fstream>
#include <iostream>
#include <cassert>
using namespace boltyard;
int main(int argc,char**argv){
 assert(argc==2);std::ifstream in(argv[1],std::ios::binary);std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)),{});assert(imported_scenery::load(bytes.data(),bytes.size()));
 unsigned seed=71;auto random=[&](){seed=seed*1664525u+1013904223u;return float(seed&0xffffff)/float(0xffffff);};
 float worst=0;int comparisons=0,closed=0;
 for(size_t i=0;i<imported_scenery::instances.size();i+=317){auto& r=imported_scenery::instances[i];auto& m=*r.source;
  for(int j=0;j<32;++j){auto t=m.triangles[size_t(random()*(m.triangles.size()-1))];Vec3 a=r.world(m.vertices[t[0]]),b=r.world(m.vertices[t[1]]),c=r.world(m.vertices[t[2]]);float u=random(),v=random()*(1-u);if(j%4==0)v=0; // Exact edges as well as face interiors.
   Vec3 q=a+(b-a)*u+(c-a)*v;Vec3 n=(b-a).cross(c-a).normalized();Vec3 p=q+n*((random()-.5f)*1.2f);
   auto cached=instanced_rock_distance(r,p),reference=instanced_rock_distance_uncached(r,p);float error=std::abs(cached.distance-reference.distance);worst=std::max(worst,error);
   if(error>.0005f||(cached.point-reference.point).length()>.003f){std::cerr<<"mismatch instance="<<i<<" query="<<j<<" signed="<<cached.distance<<","<<reference.distance<<"\n";return 1;}
   if(std::abs(reference.distance)>.001f)assert(cached.normal.dot(reference.normal)>.999f);
   ++comparisons;
  }
 }
 assert(instance_query_cache.bytes<=InstanceQueryCache::budget);assert(instance_query_cache.entries.size()<=256);
 std::cout<<"PASS "<<comparisons<<" real Utah face/edge queries, "<<"max signed-distance error="<<worst<<" cache_bytes="<<instance_query_cache.bytes<<"\n";
}
