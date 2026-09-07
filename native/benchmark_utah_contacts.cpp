#define BOLT_PROFILE_CONTACTS
#include "soft_rig.hpp"
#include <fstream>
#include <chrono>
#include <iostream>
using namespace boltyard;
int main(int argc,char**argv){
 if(argc!=2)return 2;
 std::ifstream in(argv[1],std::ios::binary);std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)),{});
 if(!imported_scenery::load(bytes.data(),bytes.size()))return 3;
 CrawlRock mesh=imported_scenery::meshes[42]; // Authored Utah large sandstone rock, 698 collision faces.
 const auto bounds=mesh.query_nodes[0].bounds;
 std::vector<float> heights(1025*1025,0);std::vector<uint8_t> layers(1025*1025,8);
 imported_terrain::load(heights.data(),heights.size(),layers.data(),layers.size());
 for(int rock=0;rock<2;++rock){
  imported_scenery::instances.clear();imported_scenery::cells.clear();
  if(rock){CrawlRock r;r.source=&mesh;r.surface_mesh=true;r.origin={-(bounds.low.x+bounds.high.x)*.5f,-bounds.low.y+.2f,-(bounds.low.z+bounds.high.z)*.5f};r.inverse[0]={1,0,0};r.inverse[1]={0,1,0};r.inverse[2]={0,0,1};r.minimum_scale_squared=1.f/3;
   CrawlRock::QueryNode n;n.bounds.low=bounds.low+r.origin;n.bounds.high=bounds.high+r.origin;r.query_nodes.push_back(n);r.center=(n.bounds.low+n.bounds.high)*.5f;r.reach=(n.bounds.high-r.center).length();imported_scenery::instances.push_back(r);
   for(int z=-3;z<=3;++z)for(int x=-3;x<=3;++x)imported_scenery::cells[imported_scenery::key(x,z)]={0};
  }
  SoftRig rig;rig.set_terrain(7);rig.reset({0,rock?bounds.high.y-bounds.low.y+1.7f:1.5f,0});
  for(int i=0;i<120;++i)rig.step(1.f/30,0,0,true);
  rock_query_counters={};double total=0,wheels=0;std::vector<double> times;
  for(int i=0;i<90;++i){auto a=std::chrono::steady_clock::now();rig.step(1.f/30,0,0,true);times.push_back(std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-a).count());for(int w=0;w<4;++w)wheels+=rig.wheel_rock_load(w)>20;}
  std::sort(times.begin(),times.end());std::cout<<(rock?"authored_rock":"terrain")<<" median_ms="<<times[45]<<" p95_ms="<<times[85]<<" rock_wheels="<<wheels/90<<" queries_per_frame="<<rock_query_counters.calls/90<<" triangles_per_frame="<<rock_query_counters.triangles/90<<"\n";
 }
}
