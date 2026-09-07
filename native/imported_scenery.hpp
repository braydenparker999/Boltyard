#pragma once
// All imported authored collision meshes are shared. Instances own transforms
// and world bounds only; the fixed grid keeps broad phase local to the rig.
namespace imported_scenery {
inline std::vector<CrawlRock> meshes,instances;
inline std::unordered_map<int64_t,std::vector<int>> cells;
inline int64_t key(int x,int z){return int64_t((uint64_t(uint32_t(x))<<32)|uint32_t(z));}
inline bool load(const uint8_t* data,size_t size) {
    if(!instances.empty())return true; // Geometry is immutable across map switches.
    size_t offset=0;bool valid=true;
    auto u32=[&](){uint32_t v=0;if(offset+4>size){valid=false;return v;}std::memcpy(&v,data+offset,4);offset+=4;return v;};
    auto f32=[&](){uint32_t u=u32();float v;std::memcpy(&v,&u,4);if(!std::isfinite(v))valid=false;return v;};
    auto vec=[&](){float x=f32(),y=f32(),z=f32();return Vec3{x,y,z};};
    auto fail=[](){meshes.clear();instances.clear();cells.clear();return false;};
    if(u32()!=0x33545542)return false;
    uint32_t count=u32();if(count>1000)return false;meshes.resize(count);
    for(auto& mesh:meshes){
        uint32_t vertices=u32(),faces=u32();if(vertices>1000000||faces>1000000)return fail();
        mesh.surface_mesh=true;mesh.vertices.reserve(vertices);mesh.triangles.reserve(faces);
        for(uint32_t i=0;i<vertices;++i)mesh.vertices.push_back(vec());
        for(uint32_t i=0;i<faces;++i){std::array<int,3> t;for(auto& v:t){v=int(u32());if(v<0||v>=int(vertices))valid=false;}mesh.triangles.push_back(t);}
        if(!valid)return fail();
        for(auto t:mesh.triangles)mesh.triangle_normals.push_back((mesh.vertices[t[1]]-mesh.vertices[t[0]]).cross(mesh.vertices[t[2]]-mesh.vertices[t[0]]).normalized());
        mesh.rebuild_queries();
    }
    count=u32();if(count>250000)return fail();instances.reserve(count);
    for(uint32_t i=0;i<count;++i){
        uint32_t model=u32();if(model>=meshes.size()||meshes[model].query_nodes.empty())return fail();
        CrawlRock r;r.source=&meshes[model];r.surface_mesh=true;
        for(auto& b:r.basis)b=vec();r.origin=vec();
        float det=r.basis[0].dot(r.basis[1].cross(r.basis[2]));if(!valid||std::abs(det)<1e-10f)return fail();
        r.inverse[0]=r.basis[1].cross(r.basis[2])/det;r.inverse[1]=r.basis[2].cross(r.basis[0])/det;r.inverse[2]=r.basis[0].cross(r.basis[1])/det;
        r.minimum_scale_squared=1.f/(r.inverse[0].length_squared()+r.inverse[1].length_squared()+r.inverse[2].length_squared());
        const auto& local=r.source->query_nodes[0].bounds;CrawlRock::QueryNode node;
        for(int k=0;k<8;++k)node.bounds.add(r.world({k&1?local.high.x:local.low.x,k&2?local.high.y:local.low.y,k&4?local.high.z:local.low.z}));
        r.query_nodes.push_back(node);r.center=(node.bounds.low+node.bounds.high)*.5f;r.reach=(node.bounds.high-r.center).length();
        const auto& b=node.bounds;
        int x0=int(std::floor(b.low.x/32)),x1=int(std::floor(b.high.x/32)),z0=int(std::floor(b.low.z/32)),z1=int(std::floor(b.high.z/32));
        if((int64_t(x1)-x0+1)*(int64_t(z1)-z0+1)>100000)return fail();
        instances.push_back(std::move(r));
        for(int z=z0;z<=z1;++z)for(int x=x0;x<=x1;++x)cells[key(x,z)].push_back(i);
    }
    if(!valid||offset!=size)return fail();return true;
}
inline void near(Vec3 p,float radius,std::vector<const CrawlRock*>& out){
    out.clear();
    const int x0=int(std::floor((p.x-radius)/32)),x1=int(std::floor((p.x+radius)/32));
    const int z0=int(std::floor((p.z-radius)/32)),z1=int(std::floor((p.z+radius)/32));
    for(int z=z0;z<=z1;++z)for(int x=x0;x<=x1;++x){auto found=cells.find(key(x,z));if(found==cells.end())continue;
        for(int id:found->second){const auto& r=instances[id];if(r.query_nodes[0].bounds.distance_squared(p)>radius*radius)continue;
            if(std::find(out.begin(),out.end(),&r)==out.end())out.push_back(&r);
        }
    }
}
}
