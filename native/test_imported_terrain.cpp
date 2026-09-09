#include "soft_rig.hpp"
#include <cassert>
#include <iostream>
#include <limits>
int main(){
 using namespace boltyard;
 constexpr int n=imported_terrain::side;
 std::vector<float> h(n*n);std::vector<uint8_t> m(n*n,8);
 for(int z=0;z<n;++z)for(int x=0;x<n;++x)h[z*n+x]=10.f+.01f*x+.02f*z;
 assert(imported_terrain::load(h.data(),h.size(),m.data(),m.size()));
 for(float x:{-1024.f,-500.3f,0.f,756.9f,1024.f})for(float z:{-1024.f,-100.6f,900.1f,1024.f}){
  float expected=10.f+.005f*(x+1024)+.01f*(z+1024);
  assert(std::abs(expedition_height(7,x,z)-expected)<1e-4f);
  auto normal=expedition_normal(7,x,z);
  assert(normal.y>.999f && normal.x<0 && normal.z<0);
  assert(expedition_surface_material(7,x,z)==ExpeditionDryRock);
 }
 float previous=expedition_height(7,0,0);
 h[10]=std::numeric_limits<float>::quiet_NaN();
 assert(!imported_terrain::load(h.data(),h.size(),m.data(),m.size()));
 assert(expedition_height(7,0,0)==previous);
 assert(!imported_terrain::load(nullptr,0,nullptr,0));
 assert(expedition_height(7,std::numeric_limits<float>::infinity(),0)==0);
 assert(expedition_rocks(7).empty() && expedition_obstacles(7).empty());
 SoftRig rig;rig.set_terrain(7);rig.reset({700,expedition_height(7,700,700)+1.5f,700});
 assert(rig.recover_near({700,60,700},{0,0,-1}));
 assert(rig.center().x>680); // recovery no longer clamps to the old 310 m map
 assert(rig.dynamic_objects().body_count()==0);
 std::cout<<"Imported terrain contracts passed\n";
}
