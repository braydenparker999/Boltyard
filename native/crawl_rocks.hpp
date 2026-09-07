#pragma once
// Included after Vec3. Convex, closed sandstone pieces: the rendering binding
// exports these exact triangles. No separate visual rock/cylinder approximation.
struct RockQueryCounters { unsigned long long calls=0, triangles=0; };
inline thread_local RockQueryCounters rock_query_counters;
#ifdef BOLT_PROFILE_CONTACTS
#define BOLT_ROCK_COUNT(field) (++rock_query_counters.field)
#else
#define BOLT_ROCK_COUNT(field) ((void)0)
#endif
struct CrawlRock {
    const CrawlRock* source=nullptr; // Immutable mesh shared by imported placements.
    Vec3 basis[3]{{1,0,0},{0,1,0},{0,0,1}}, inverse[3], origin;
    float minimum_scale_squared=1;
    Vec3 world(Vec3 p) const {return origin+basis[0]*p.x+basis[1]*p.y+basis[2]*p.z;}
    Vec3 local(Vec3 p) const {p-=origin;return {inverse[0].dot(p),inverse[1].dot(p),inverse[2].dot(p)};}
    std::vector<Vec3> vertices;
    std::vector<std::array<int,3>> triangles;
    Vec3 center;
    float reach=0, surface=1.15f;
    bool surface_mesh=false; // Closed authored concave scenery; convex vehicle shapes keep their fast path.
    // Generated once with the hull; every physics query uses the same faces.
    std::vector<Vec3> triangle_normals;
    struct Bounds {
        Vec3 low{1e20f,1e20f,1e20f}, high{-1e20f,-1e20f,-1e20f};
        void add(Vec3 p) {
            low={std::min(low.x,p.x),std::min(low.y,p.y),std::min(low.z,p.z)};
            high={std::max(high.x,p.x),std::max(high.y,p.y),std::max(high.z,p.z)};
        }
        float distance_squared(Vec3 p) const {
            const Vec3 d{std::max({low.x-p.x,0.f,p.x-high.x}),std::max({low.y-p.y,0.f,p.y-high.y}),std::max({low.z-p.z,0.f,p.z-high.z})};
            return d.length_squared();
        }
    };
    struct QueryNode { Bounds bounds; int left=-1,right=-1,begin=0,end=0; };
    std::vector<QueryNode> query_nodes;
    std::vector<int> query_faces;
    // Geometry is immutable during simulation. Call after any authoring edit.
    void rebuild_queries() {
        query_nodes.clear();query_faces.clear();
        for(int i=0;i<int(triangles.size());++i)query_faces.push_back(i);
        if(triangles.empty())return;
        query_nodes.reserve(triangles.size()*2);
        auto build=[&](auto&&self,int begin,int end)->int {
            const int index=int(query_nodes.size());query_nodes.emplace_back();
            Bounds bounds;for(int k=begin;k<end;++k)for(int v:triangles[query_faces[k]])bounds.add(vertices[v]);
            query_nodes[index].bounds=bounds;query_nodes[index].begin=begin;query_nodes[index].end=end;
            if(end-begin<=4)return index;
            Vec3 extent=bounds.high-bounds.low;int axis=extent.x>extent.y?0:1;if(extent.z>(axis==0?extent.x:extent.y))axis=2;
            auto centroid=[&](int f){Vec3 c;for(int v:triangles[f])c+=vertices[v];return axis==0?c.x:axis==1?c.y:c.z;};
            int mid=(begin+end)/2;
            std::nth_element(query_faces.begin()+begin,query_faces.begin()+mid,query_faces.begin()+end,[&](int a,int b){return centroid(a)<centroid(b);});
            int left=self(self,begin,mid),right=self(self,mid,end);
            query_nodes[index].left=left;query_nodes[index].right=right;return index;
        };
        build(build,0,int(triangles.size()));
    }
};
inline CrawlRock crawl_fractured_rock(float x,float z,float width,float depth,float height,float slope,float roll,float yaw,float base,unsigned fracture_variant) {
    CrawlRock r;
    const unsigned seed=unsigned(int(x*173.f))^unsigned(int(z*367.f))^
        unsigned(int(width*919.f))^unsigned(int(depth*1237.f))^(fracture_variant*2654435761u);
    auto variation=[&](unsigned i){unsigned h=seed+i*374761393u;h=(h^(h>>13))*1274126177u;h^=h>>16;return float(h&65535u)/65535.f;};
    // Unequal corner fractures give each footprint a distinct silhouette while
    // retaining its authored dimensions and broad, driveable central surface.
    float corner[8];for(int i=0;i<8;++i)corner[i]=.19f+.22f*variation(i+1);
    const float ring[8][2]={{-1+corner[0],-1},{1-corner[1],-1},
        {1,-1+corner[2]},{1,1-corner[3]},{1-corner[4],1},
        {-1+corner[5],1},{-1,1-corner[6]},{-1,-1+corner[7]}};
    std::vector<Vec3> original;
    for(int layer=0;layer<2;++layer)for(auto &p:ring){
        float px=p[0]*width*.5f,pz=p[1]*depth*.5f;
        const float taper=.12f/height,tilt=-slope*pz+roll*px;
        float py=layer?(height+tilt)/(1+taper*tilt):0;
        float factor=1-taper*py;
        original.push_back({px*factor,py,pz*factor});
    }
    using Polygon=std::vector<Vec3>;
    std::vector<Polygon> faces;
    faces.emplace_back(original.begin(),original.begin()+8);
    faces.emplace_back(original.begin()+8,original.end());
    for(int i=0;i<8;++i){int j=(i+1)%8;faces.push_back({original[i],original[j],original[8+j],original[8+i]});}
    // Intersect with oblique fracture planes. Clipping a convex solid keeps
    // every resulting facet convex; this is actual wheel/body collision mesh.
    auto clip=[&](Vec3 normal,float offset){
        std::vector<Polygon> result;Polygon cap;
        auto add_cap=[&](Vec3 p){for(auto q:cap)if((p-q).length_squared()<1e-9f)return;cap.push_back(p);};
        for(const auto &poly:faces){
            Polygon cut;
            for(size_t i=0;i<poly.size();++i){
                Vec3 a=poly[i],b=poly[(i+1)%poly.size()];
                float da=normal.dot(a)-offset,db=normal.dot(b)-offset;
                bool ia=da<=0,ib=db<=0;
                if(ia)cut.push_back(a);
                if(ia!=ib){Vec3 q=a+(b-a)*(da/(da-db));cut.push_back(q);add_cap(q);}
            }
            if(cut.size()>=3)result.push_back(cut);
        }
        if(cap.size()>=3){
            Vec3 middle;for(auto p:cap)middle+=p;middle*=1.f/cap.size();
            Vec3 axis=normal.cross(std::abs(normal.y)<.8f?Vec3{0,1,0}:Vec3{1,0,0}).normalized();
            Vec3 other=normal.cross(axis);
            std::sort(cap.begin(),cap.end(),[&](Vec3 a,Vec3 b){a-=middle;b-=middle;return std::atan2(a.dot(other),a.dot(axis))<std::atan2(b.dot(other),b.dot(axis));});
            result.push_back(cap);
        }
        faces=std::move(result);
    };
    const Vec3 top=Vec3{-roll,1,slope}.normalized();
    const float top_offset=height/std::sqrt(1+roll*roll+slope*slope);
    for(int i=0;i<(fracture_variant<8?8:0);++i){
        int j=(i+1)%8;
        Vec3 side=(original[j]-original[i]).cross(original[8+i]-original[i]).normalized();
        if(side.dot(original[i]-Vec3{0,height*.5f,0})<0)side=-side;
        // Big outcrops have broad broken shoulders, not slab-sized edge cuts.
        // Low route slabs keep their validated ledge and wheel-contact profile.
        const bool outcrop=height>2.5f;
        float rim=std::min(width,depth)*(outcrop?(.095f+.115f*variation(i+19)):(.030f+.032f*variation(i+19)));
        float drop=outcrop?height*(.19f+.19f*variation(i+37)):std::min(.58f,height*(.10f+.12f*variation(i+37)));
        // Each rim has its own angle and depth, like broken sedimentary slabs.
        float weight=rim/std::max(.025f,drop);
        Vec3 normal=side+top*weight;
        float offset=side.dot(original[i])+top_offset*weight-rim;
        float magnitude=normal.length();clip(normal/magnitude,offset/magnitude);
    }
    auto vertex=[&](Vec3 p){
        for(size_t i=0;i<r.vertices.size();++i)if((p-r.vertices[i]).length_squared()<1e-9f)return int(i);
        r.vertices.push_back(p);return int(r.vertices.size()-1);
    };
    for(auto &poly:faces){
        // Remove numerical duplicate/collinear corners before fan triangulation.
        bool changed=true;
        while(changed&&poly.size()>3){changed=false;for(size_t i=0;i<poly.size();++i){
            Vec3 a=poly[(i+poly.size()-1)%poly.size()],b=poly[i],c=poly[(i+1)%poly.size()];
            if((a-b).length_squared()<1e-9f||(b-a).cross(c-b).length_squared()<1e-12f){poly.erase(poly.begin()+i);changed=true;break;}
        }}
        int a=vertex(poly[0]);for(size_t i=1;i+1<poly.size();++i){
            if((poly[i]-poly[0]).cross(poly[i+1]-poly[0]).length_squared()>1e-12f)
                r.triangles.push_back({a,vertex(poly[i]),vertex(poly[i+1])});
        }
    }
    for(auto &p:r.vertices){float px=p.x,pz=p.z;p={x+px*std::cos(yaw)+pz*std::sin(yaw),base+p.y,z-px*std::sin(yaw)+pz*std::cos(yaw)};r.center+=p;}
    r.center*=1.f/r.vertices.size();
    for(auto &t:r.triangles){
        Vec3 n=(r.vertices[t[1]]-r.vertices[t[0]]).cross(r.vertices[t[2]]-r.vertices[t[0]]).normalized();
        if(n.dot(r.vertices[t[0]]-r.center)<0){std::swap(t[1],t[2]);n=-n;}
        r.triangle_normals.push_back(n);
    }
    // A cut that almost coincides with another can leave a millimetric edge.
    // Reject that fracture pattern if world-space float precision makes any
    // triangle cease to support the hull. Regeneration is deterministic and
    // happens only once during course construction, never during simulation.
    for(size_t i=0;i<r.triangles.size();++i)for(auto p:r.vertices)
        if((p-r.vertices[r.triangles[i][0]]).dot(r.triangle_normals[i])>.0004f&&fracture_variant<8)
            return crawl_fractured_rock(x,z,width,depth,height,slope,roll,yaw,base,fracture_variant+1);
    for(auto p:r.vertices)r.reach=std::max(r.reach,(p-r.center).length());
    r.rebuild_queries();return r;
}
inline CrawlRock crawl_rock(float x,float z,float width,float depth,float height,float slope=0,float roll=0,float yaw=0,float base=0) {
    return crawl_fractured_rock(x,z,width,depth,height,slope,roll,yaw,base,0);
}
inline const std::vector<CrawlRock>& crawl_course(){
    static const std::vector<CrawlRock> rocks=[] {
        std::vector<CrawlRock> r;
        // Warm-up slab, stepped staircase, staggered garden, off-camber shelf,
        // final climb. Outside lanes remain clear for route choice and recovery.
        r.push_back(crawl_rock(0,-3,7,9,.65f,.12f));
        r.push_back(crawl_rock(0,-16,7,9,.22f));
        r.push_back(crawl_rock(.35f,-18,6.3f,6,.45f));
        r.push_back(crawl_rock(-.2f,-19.6f,5.8f,3,.69f));
        for(int i=0;i<7;++i){float z=-28-i*1.65f;float x=i%2?1.05f:-.95f;r.push_back(crawl_rock(x,z,2.2f,2.4f,.23f+(i%3)*.09f,.03f, .035f,i*.31f));}
        r.push_back(crawl_rock(0,-47,6,8,.72f,.07f,.12f));
        r.push_back(crawl_rock(0,-62,7,12,1.15f,.18f));
        r.push_back(crawl_rock(-1.6f,-64,2.5f,4,.30f,0,0,.1f,1.55f));
        r.push_back(crawl_rock(0,-70.5f,7,8,1.15f,-.27f));
        // Authored canyon shoulders are deliberately asymmetric. Their full
        // footprints clear the bypass lanes and the route markers at x=-4.6.
        r.push_back(crawl_rock(-13.5f,11,10,11,3.8f,.13f,-.07f,.35f));
        r.push_back(crawl_rock(-10.1f,-3,6,8,2.7f,-.09f,.16f,-.18f));
        r.push_back(crawl_rock(-13.8f,-15,10,12,4.8f,.14f,.08f,.28f));
        r.push_back(crawl_rock(-10.2f,-29,6,9,3.5f,-.11f,-.17f,-.25f));
        r.push_back(crawl_rock(-14.8f,-41,12,15,6.2f,.18f,.12f,-.10f));
        r.push_back(crawl_rock(-11.5f,-55,7,10,3.8f,-.13f,.09f,.32f));
        r.push_back(crawl_rock(-14.2f,-68,11,13,5.6f,.14f,-.11f,-.40f));
        r.push_back(crawl_rock(-10.1f,-80,6,9,2.9f,-.08f,.15f,.20f));
        r.push_back(crawl_rock(13,13,10,11,3.8f,-.11f,.09f,-.20f));
        // The movable-object practice area at x=7..11, z=-12..-37 is open.
        r.push_back(crawl_rock(22,-3,10,12,4.4f,.16f,-.14f,.23f));
        r.push_back(crawl_rock(20.5f,-19,8,11,5.5f,-.19f,.10f,-.14f));
        r.push_back(crawl_rock(22,-34,10,13,6.5f,.12f,.18f,.24f));
        r.push_back(crawl_rock(12.5f,-53,9,10,4.2f,-.15f,-.11f,.20f));
        r.push_back(crawl_rock(10.9f,-67,7,8,3.7f,.13f,.17f,-.20f));
        r.push_back(crawl_rock(14,-81,11,12,5.2f,-.12f,.08f,.28f));
        // A few detached, grounded pieces tie the large formations to the trail.
        r.push_back(crawl_rock(-6.8f,1,1.4f,2.4f,.44f,.08f,-.03f,.17f));
        r.push_back(crawl_rock(-7.1f,-21,1.8f,2.8f,.67f,-.10f,.06f,-.21f));
        r.push_back(crawl_rock(-7.2f,-48,2.0f,2.5f,.51f,.07f,.10f,.31f));
        r.push_back(crawl_rock(7.2f,-60,1.8f,2.7f,.62f,-.09f,-.06f,-.28f));
        r.push_back(crawl_rock(7.4f,-76,2.0f,2.9f,.77f,.13f,.07f,.24f));
        // Sparse distant silhouettes, staggered in both distance and elevation.
        for(int side:{-1,1})for(int i=0;i<4;++i)
            r.push_back(crawl_rock(side*(29.f+(i%3)*4.7f),22-i*32.f+side*7.f,
                12.f+(i%3)*3,16.f+(i%2)*5,6.f+(i%3)*2,.17f,-side*.13f,side*.31f+i*.43f));
        // The wash bends beyond the finish. These actual collision shoulders
        // close its distant horizon, leaving every recovery point and route open.
        r.push_back(crawl_rock(12,-121,25,22,11,.19f,-.16f,.22f));
        r.push_back(crawl_rock(-12,-111,19,18,7,-.13f,.17f,-.31f));
        return r;
    }();return rocks;
}
inline Vec3 closest_triangle(Vec3 p,Vec3 a,Vec3 b,Vec3 c){
    Vec3 ab=b-a,ac=c-a,ap=p-a;float d1=ab.dot(ap),d2=ac.dot(ap);
    if(d1<=0&&d2<=0)return a;
    Vec3 bp=p-b;float d3=ab.dot(bp),d4=ac.dot(bp);if(d3>=0&&d4<=d3)return b;
    float vc=d1*d4-d3*d2;if(vc<=0&&d1>=0&&d3<=0)return a+ab*(d1/(d1-d3));
    Vec3 cp=p-c;float d5=ab.dot(cp),d6=ac.dot(cp);if(d6>=0&&d5<=d6)return c;
    float vb=d5*d2-d1*d6;if(vb<=0&&d2>=0&&d6<=0)return a+ac*(d2/(d2-d6));
    float va=d3*d6-d5*d4;if(va<=0&&(d4-d3)>=0&&(d5-d6)>=0)return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)));
    float inv=1/(va+vb+vc);return a+ab*(vb*inv)+ac*(vc*inv);
}
struct RockDistance {float distance;Vec3 normal,point;};
// Closed triangle-mesh inside test, accelerated by the existing face BVH.
// Crossings at a shared edge are counted once. No convex half-space shortcut
// is valid for a concave cliff or an arch opening.
inline bool rock_mesh_inside(const CrawlRock&r,Vec3 p) {
    if(r.query_nodes.empty() || r.query_nodes[0].bounds.distance_squared(p)>0)return false;
    std::vector<double> hits;
    auto visit=[&](auto&&self,int id)->void {
        const auto &node=r.query_nodes[id];const auto &b=node.bounds;
        if(b.high.x<p.x||p.y<b.low.y||p.y>b.high.y||p.z<b.low.z||p.z>b.high.z)return;
        if(node.left>=0){self(self,node.left);self(self,node.right);return;}
        for(int k=node.begin;k<node.end;++k){int i=r.query_faces[k];auto t=r.triangles[i];
            const auto a=r.vertices[t[0]],b=r.vertices[t[1]],c=r.vertices[t[2]];
            // Double-precision barycentrics avoid missed intersections on
            // near-parallel arch faces at large world coordinates.
            const double by=double(b.y)-a.y,bz=double(b.z)-a.z,cy=double(c.y)-a.y,cz=double(c.z)-a.z;
            const double py=double(p.y)-a.y,pz=double(p.z)-a.z,denom=by*cz-bz*cy;
            if(std::abs(denom)<1e-14)continue;
            const double u=(py*cz-pz*cy)/denom,v=(by*pz-bz*py)/denom;
            if(u< -1e-10||v< -1e-10||u+v>1+1e-10)continue;
            const double distance=double(a.x)-p.x+u*(double(b.x)-a.x)+v*(double(c.x)-a.x);
            if(distance>=0)hits.push_back(distance);
        }
    };
    visit(visit,0);std::sort(hits.begin(),hits.end());int crossings=0;double last=-1e20;
    for(double h:hits)if(h-last>1e-7){++crossings;last=h;}
    return crossings%2==1;
}
inline RockDistance rock_distance_reference(const CrawlRock&r,Vec3 p){
    BOLT_ROCK_COUNT(calls);
    float closest=1e20f,max_plane=-1e20f;Vec3 q,n,inside_n;
    for(size_t i=0;i<r.triangles.size();++i){auto t=r.triangles[i];Vec3 a=r.vertices[t[0]],b=r.vertices[t[1]],c=r.vertices[t[2]];Vec3 face=r.triangle_normals.size()==r.triangles.size()?r.triangle_normals[i]:(b-a).cross(c-a).normalized();float plane=(p-a).dot(face);if(plane>max_plane){max_plane=plane;inside_n=face;}
        BOLT_ROCK_COUNT(triangles); Vec3 v=closest_triangle(p,a,b,c);float d=(p-v).length_squared();if(d<closest){closest=d;q=v;n=face;}}
    if(r.surface_mesh){float d=std::sqrt(closest);return rock_mesh_inside(r,p)?RockDistance{-d,n,q}:RockDistance{d,d>1e-7f?(p-q)/d:n,q};}
    if(max_plane<=0)return {max_plane,inside_n,p-inside_n*max_plane};
    float d=std::sqrt(closest);return {d,d>1e-7f?(p-q)/d:n,q};
}
// Exact world-space nearest face under rotation and nonuniform scale. The
// shared local BVH uses a conservative inverse-matrix norm bound for pruning.
inline RockDistance instanced_rock_distance(const CrawlRock& r,Vec3 p) {
    BOLT_ROCK_COUNT(calls);
    const auto& mesh=*r.source;Vec3 local=r.local(p),point,normal;
    float closest=1e20f;
    auto bound=[&](int id){return mesh.query_nodes[id].bounds.distance_squared(local)*r.minimum_scale_squared;};
    auto visit=[&](auto&& self,int id)->void {
        if(bound(id)>closest+1e-5f)return;
        const auto& node=mesh.query_nodes[id];
        if(node.left>=0){int a=node.left,b=node.right;if(bound(a)>bound(b))std::swap(a,b);self(self,a);self(self,b);return;}
        for(int k=node.begin;k<node.end;++k){
            auto t=mesh.triangles[mesh.query_faces[k]];BOLT_ROCK_COUNT(triangles);
            Vec3 a=r.world(mesh.vertices[t[0]]),b=r.world(mesh.vertices[t[1]]),c=r.world(mesh.vertices[t[2]]);
            Vec3 q=closest_triangle(p,a,b,c);float d=(p-q).length_squared();
            if(d<closest){closest=d;point=q;normal=(b-a).cross(c-a).normalized();}
        }
    };
    visit(visit,0);float d=std::sqrt(closest);
    bool inside=mesh.surface_mesh&&rock_mesh_inside(mesh,local);
    if(d>1e-6f)normal=(inside?point-p:p-point)/d;
    return {inside?-d:d,normal,point};
}
inline RockDistance rock_distance(const CrawlRock&r,Vec3 p){
    if(r.source)return instanced_rock_distance(r,p);
    // Unindexed ad-hoc hulls remain correct. Production builders index once.
    if(r.query_nodes.empty() || r.triangle_normals.size()!=r.triangles.size())return rock_distance_reference(r,p);
    BOLT_ROCK_COUNT(calls);
    if(!r.surface_mesh && r.query_nodes[0].bounds.distance_squared(p)==0) {
        float plane=-1e20f;Vec3 normal;bool outside=false;
        for(size_t i=0;i<r.triangles.size();++i) {
            const float d=(p-r.vertices[r.triangles[i][0]]).dot(r.triangle_normals[i]);
            if(d>0){outside=true;break;}
            if(d>plane){plane=d;normal=r.triangle_normals[i];}
        }
        if(!outside)return {plane,normal,p-normal*plane};
    }
    float closest=1e20f;int best=int(r.triangles.size());Vec3 point,normal;
    auto visit=[&](auto&&self,int index)->void {
        const auto&node=r.query_nodes[index];
        // Conservative rounding margin: bounds may only skip impossible faces.
        if(node.bounds.distance_squared(p)>closest+1e-7f)return;
        if(node.left<0) {
            for(int k=node.begin;k<node.end;++k) {
                int i=r.query_faces[k];auto t=r.triangles[i];BOLT_ROCK_COUNT(triangles);
                Vec3 q=closest_triangle(p,r.vertices[t[0]],r.vertices[t[1]],r.vertices[t[2]]);float d=(p-q).length_squared();
                if(d<closest||(d==closest&&i<best)){closest=d;best=i;point=q;normal=r.triangle_normals[i];}
            }
        } else {
            int first=node.left,second=node.right;
            if(r.query_nodes[first].bounds.distance_squared(p)>r.query_nodes[second].bounds.distance_squared(p))std::swap(first,second);
            self(self,first);self(self,second);
        }
    };
    visit(visit,0);float d=std::sqrt(closest);
    if(r.surface_mesh && rock_mesh_inside(r,p))return {-d,normal,point};
    return {d,d>1e-7f?(p-point)/d:normal,point};
}
