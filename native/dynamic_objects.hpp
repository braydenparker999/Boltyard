#pragma once

// Included inside boltyard, after Vec3 and crawl_rocks.hpp. Small deterministic
// rigid-body XPBD scene. The native convex vertices are also the render mesh;
// broad-phase spheres never act as the actual collision surface.
struct DynamicQuaternion {
    float x=0, y=0, z=0, w=1;
    DynamicQuaternion conjugate() const { return {-x,-y,-z,w}; }
    DynamicQuaternion operator*(DynamicQuaternion q) const {
        return {w*q.x+x*q.w+y*q.z-z*q.y, w*q.y-x*q.z+y*q.w+z*q.x,
                w*q.z+x*q.y-y*q.x+z*q.w, w*q.w-x*q.x-y*q.y-z*q.z};
    }
    DynamicQuaternion normalized() const {
        const float l=std::sqrt(x*x+y*y+z*z+w*w);
        return l>1e-8f?DynamicQuaternion{x/l,y/l,z/l,w/l}:DynamicQuaternion{};
    }
    Vec3 rotate(Vec3 v) const {
        const Vec3 u{x,y,z}; return v+u.cross(v)*(2*w)+u.cross(u.cross(v))*2;
    }
    static DynamicQuaternion rotation_vector(Vec3 a) {
        const float angle=a.length();
        if(angle<1e-7f)return DynamicQuaternion{float(a.x*.5f),float(a.y*.5f),float(a.z*.5f),1}.normalized();
        const float s=std::sin(angle*.5f)/angle;
        return {float(a.x*s),float(a.y*s),float(a.z*s),std::cos(angle*.5f)};
    }
};

struct DynamicBody {
    CrawlRock shape; // local closed convex collision/render vertices
    Vec3 position, velocity, angular_velocity;
    DynamicQuaternion rotation;
    float inv_mass=0;
    Vec3 inv_inertia_local;
    int kind=0; // 0 sandstone, 1 octagonal timber, 2 wooden crate
    bool sleeping=false;
    Vec3 previous_position;
    DynamicQuaternion previous_rotation;
    float quiet_time=0;
    std::vector<Vec3> face_axes, edge_axes;

    Vec3 world_point(Vec3 local) const {return position+rotation.rotate(local);}
    Vec3 local_point(Vec3 world) const {return rotation.conjugate().rotate(world-position);}
    Vec3 inverse_inertia(Vec3 torque) const {
        const Vec3 t=rotation.conjugate().rotate(torque);
        return rotation.rotate({t.x*inv_inertia_local.x,t.y*inv_inertia_local.y,t.z*inv_inertia_local.z});
    }
    Vec3 point_velocity(Vec3 p) const {return velocity+angular_velocity.cross(p-position);}
    float point_inverse_mass(Vec3 point, Vec3 direction) const {
        const Vec3 r=(point-position).cross(direction);
        return inv_mass+r.dot(inverse_inertia(r));
    }
};

class DynamicObjects {
public:
    static constexpr int max_bodies=24;
    DynamicObjects(){reset();}
    const std::vector<DynamicBody>& bodies() const {return bodies_;}
    std::vector<DynamicBody>& bodies() {return bodies_;}
    int body_count() const {return int(bodies_.size());}
    int contact_count() const {return contacts_;}
    int awake_count() const {int n=0;for(const auto&b:bodies_)if(!b.sleeping)++n;return n;}

    void set_terrain(int mode) {
        terrain_mode_=std::clamp(mode,0,7); static_bodies_.clear();
    }
    void clear(){bodies_.clear();pairs_.clear();ground_.clear();contacts_=0;}
    void reset(){
        clear();
        if(terrain_mode_==7)return;
        // Accessible optional loose line at x=8..10. The central test course
        // and bypass around x=4.5 remain unobstructed.
        add_stone({8.15f,.24f,-13.2f},{.68f,.46f,.83f},42,.16f);
        add_stone({9.15f,.20f,-13.65f},{.59f,.38f,.67f},29,-.37f);
        add_stone({8.72f,.30f,-15.15f},{.90f,.56f,.75f},68,.32f);
        add_stone({9.62f,.24f,-16.2f},{.66f,.44f,.84f},45,-.2f);
        add_log({8.8f,.255f,-22.3f},2.4f,.25f,95,.13f);
        add_log({9.1f,.225f,-24.1f},1.8f,.22f,65,-.22f);
        add_crate({8.10f,.39f,-31.4f},{.76f,.76f,.76f},55,.22f);
        add_crate({9.18f,.335f,-31.6f},{.64f,.64f,.64f},38,-.13f);
        add_stone({8.66f,.18f,-35.0f},{.56f,.34f,.67f},27,.6f);
        if(terrain_mode_>=4)for(auto &b:bodies_) {
            // Initial placement clears every oriented vertex against the real
            // heightfield, including a log spanning a slope at the trail camp.
            float clearance=1e20f;
            for(auto vertex:b.shape.vertices){Vec3 p=b.world_point(vertex);clearance=std::min<float>(clearance,p.y-ground_height(p.x,p.z));}
            b.position.y+=.012f-clearance;b.previous_position=b.position;
        }
    }

    int add_crate(Vec3 at,Vec3 size,float mass,float yaw=0){
        CrawlRock s;
        for(int z:{-1,1})for(int y:{-1,1})for(int x:{-1,1})
            s.vertices.push_back({size.x*x*.5f,size.y*y*.5f,size.z*z*.5f});
        const int faces[6][4]={{0,1,3,2},{4,6,7,5},{0,4,5,1},{2,3,7,6},{0,2,6,4},{1,5,7,3}};
        for(auto&f:faces){s.triangles.push_back({f[0],f[1],f[2]});s.triangles.push_back({f[0],f[2],f[3]});}
        return add_shape(s,at,size,mass,2,yaw);
    }
    int add_stone(Vec3 at,Vec3 size,float mass,float yaw=0){
        CrawlRock s=crawl_rock(0,0,size.x,size.z,size.y,0,0,0,-size.y*.5f);
        return add_shape(s,at,size,mass,0,yaw);
    }
    int add_log(Vec3 at,float length,float radius,float mass,float yaw=0){
        CrawlRock s;
        for(int side:{-1,1})for(int i=0;i<8;++i){
            const float a=6.28318530718f*i/8;
            s.vertices.push_back({side*length*.5f,std::cos(a)*radius,std::sin(a)*radius});
        }
        for(int i=1;i<7;++i){s.triangles.push_back({0,i,i+1});s.triangles.push_back({8,8+i,9+i});}
        for(int i=0;i<8;++i){const int j=(i+1)%8;s.triangles.push_back({i,j,j+8});s.triangles.push_back({i,j+8,i+8});}
        const int id=add_shape(s,at,{length,radius*2,radius*2},mass,1,yaw);
        if(id>=0){
            // Homogeneous prism inertia: polygonal cross-section approximated
            // by its circumscribed cylinder (collision remains the octagon).
            auto&b=bodies_[id];b.inv_inertia_local={2/(mass*radius*radius),12/(mass*(3*radius*radius+length*length)),12/(mass*(3*radius*radius+length*length))};
        }
        return id;
    }

    RockDistance distance(int body_id,Vec3 p) const {
        if(body_id<0||body_id>=body_count())return {1e20f,{0,1,0},p};
        const auto&b=bodies_[body_id];auto d=rock_distance(b.shape,b.local_point(p));
        d.normal=b.rotation.rotate(d.normal);d.point=b.world_point(d.point);return d;
    }
    int surface_material(int id,Vec3 point) const {
        if(id<0||id>=body_count())return 0;
        if(bodies_[id].kind!=0)return 5;
        return terrain_mode_>=4&&expedition_material(terrain_mode_,point.x,point.z).wet>.30f?2:1;
    }
    float tire_surface(int id,Vec3 point) const {
        if(id<0||id>=body_count())return 1.f;
        const float wet=terrain_mode_>=4?expedition_material(terrain_mode_,point.x,point.z).wet:0.f;
        // The contacted body's actual timber/stone surface determines traction.
        return bodies_[id].kind==0?1.10f-.54f*wet:.82f-.24f*wet;
    }
    float point_inverse_mass(int id,Vec3 p,Vec3 n) const {return bodies_[id].point_inverse_mass(p,n);}
    Vec3 point_velocity(int id,Vec3 p) const {return bodies_[id].point_velocity(p);}
    void apply_position_impulse(int id,Vec3 p,Vec3 impulse){position_impulse(bodies_[id],p,impulse);}
    void apply_impulse(int id,Vec3 p,Vec3 impulse){
        auto&b=bodies_[id];if(!impulse.finite()||b.inv_mass<=0)return;
        if(impulse.length_squared()>1e-9f)wake(b);
        b.velocity+=impulse*b.inv_mass;b.angular_velocity+=b.inverse_inertia((p-b.position).cross(impulse));
    }

    // Call once at 240 Hz before vehicle prediction, solve_world once inside
    // each XPBD iteration, then finish_step BEFORE vehicle tire impulses.
    // Tire drive/brake impulses must call apply_impulse with their opposite.
    void begin_step(float dt,Vec3 gravity={0,-9.81f,0}){
        if(!(dt>0)||!std::isfinite(dt))return;
        if(world_enabled_&&!bodies_.empty()&&static_bodies_.empty())for(const auto&r:world_rocks())static_bodies_.push_back(static_body(r));
        contacts_=0;ground_.clear();pairs_.clear();
        for(auto&b:bodies_){
            b.previous_position=b.position;b.previous_rotation=b.rotation;
            if(!b.sleeping){b.velocity+=gravity*dt;b.position+=b.velocity*dt;
                b.rotation=(DynamicQuaternion::rotation_vector(b.angular_velocity*dt)*b.rotation).normalized();}
            ground_.push_back(std::vector<GroundContact>(b.shape.vertices.size()));
        }
        for(int a=0;a<body_count();++a){
            for(int b=a+1;b<body_count();++b){
                if(bodies_[a].sleeping&&bodies_[b].sleeping)continue;
                if(near(bodies_[a],bodies_[b],.08f))pairs_.push_back({a,b,-1,{}});
            }
            if(!world_enabled_||bodies_[a].sleeping)continue;
            const auto&rocks=world_rocks();
            for(int r=0;r<int(rocks.size());++r)
                if((bodies_[a].position-rocks[r].center).length_squared()<square(bodies_[a].shape.reach+rocks[r].reach+.08f))
                    pairs_.push_back({a,-1,r,{}});
        }
    }
    void solve_world(float dt){
        if(!(dt>0))return;
        if(world_enabled_)for(int i=0;i<body_count();++i){
            auto&b=bodies_[i];if(b.sleeping)continue;
            for(int v=0;v<int(b.shape.vertices.size());++v){
                auto&c=ground_[i][v];Vec3 p=b.world_point(b.shape.vertices[v]);
                const Vec3 n=ground_normal(p.x,p.z);
                const float distance=(p.y-ground_height(p.x,p.z))*n.y;
                if(distance>.01f&&c.lambda<=0)continue;
                const float inv=b.point_inverse_mass(p,n),alpha=ground_compliance_/(dt*dt);
                const float dl=(-distance-alpha*c.lambda)/(inv+alpha),next=std::max(0.f,c.lambda+dl);
                position_impulse(b,p,n*(next-c.lambda),false);c.lambda=next;
                if(next<=0)continue;
                p=b.world_point(b.shape.vertices[v]);
                const Vec3 prev=b.previous_position+b.previous_rotation.rotate(b.shape.vertices[v]);
                solve_static_friction(b,p,p-prev,n,c.lambda,c.friction,.72f*ground_surface(p.x,p.z));
            }
        }
        for(auto&pair:pairs_)solve_pair(pair,dt);
    }
    void finish_step(float dt){
        if(!(dt>0))return;
        contacts_=0;
        for(auto&g:ground_)for(auto&c:g)if(c.lambda>1e-8f)++contacts_;
        for(auto&p:pairs_)for(auto&c:p.contacts)if(c.lambda>1e-8f)++contacts_;
        for(auto&b:bodies_){
            if(b.sleeping)continue;
            b.velocity=(b.position-b.previous_position)/dt;
            DynamicQuaternion q=(b.rotation*b.previous_rotation.conjugate()).normalized();
            if(q.w<0){q.x=-q.x;q.y=-q.y;q.z=-q.z;q.w=-q.w;}
            const float s=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z);
            b.angular_velocity=s>1e-7f?Vec3{q.x,q.y,q.z}*(2*std::atan2(s,q.w)/(s*dt)):Vec3{};
            if(!b.position.finite()||!b.velocity.finite()||!b.angular_velocity.finite()){
                b.position=b.previous_position;b.rotation=b.previous_rotation;b.velocity={};b.angular_velocity={};
            }
            // Sleep only after sustained physical rest. A contacting awake body
            // or nonzero vehicle impulse wakes this body and its gravity.
            const bool supported=world_enabled_&&lowest_ground_clearance(b)<.025f;
            if(supported&&b.velocity.length_squared()<.0009f&&b.angular_velocity.length_squared()<.0036f)b.quiet_time+=dt;
            else b.quiet_time=0;
            if(b.quiet_time>.75f){b.sleeping=true;b.velocity={};b.angular_velocity={};}
        }
    }
    void step(float dt,Vec3 gravity={0,-9.81f,0},int iterations=9){
        begin_step(dt,gravity);for(int i=0;i<iterations;++i)solve_world(dt);finish_step(dt);
    }
    void set_world_enabled(bool enabled){world_enabled_=enabled;}
    void set_static_rocks(const std::vector<CrawlRock>&rocks){test_rocks_=rocks;for(auto&r:test_rocks_)r.rebuild_queries();custom_rocks_=true;static_bodies_.clear();}
    void use_course_rocks(){test_rocks_.clear();custom_rocks_=false;static_bodies_.clear();}

private:
    struct GroundContact {float lambda=0;Vec3 friction;};
    struct PairContact {Vec3 local_a,local_b,normal;float lambda=0;Vec3 friction;};
    struct Pair {int a,b,rock;std::vector<PairContact> contacts;};
    std::vector<DynamicBody>bodies_;
    std::vector<std::vector<GroundContact>>ground_;
    std::vector<Pair>pairs_;
    std::vector<CrawlRock>test_rocks_;
    std::vector<DynamicBody>static_bodies_;
    bool world_enabled_=true,custom_rocks_=false;
    int terrain_mode_=3;
    float ground_height(float x,float z)const{return terrain_mode_>=4?expedition_height(terrain_mode_,x,z):0;}
    Vec3 ground_normal(float x,float z)const{if(terrain_mode_<4)return {0,1,0};auto n=expedition_normal(terrain_mode_,x,z);return {n.x,n.y,n.z};}
    float ground_surface(float x,float z)const{return terrain_mode_>=4?expedition_surface(terrain_mode_,x,z):1.f;}
    float lowest_ground_clearance(const DynamicBody &b)const{float d=1e20f;for(auto v:b.shape.vertices){Vec3 p=b.world_point(v);d=std::min<float>(d,(p.y-ground_height(p.x,p.z))*ground_normal(p.x,p.z).y);}return d;}
    int contacts_=0;
    static constexpr float ground_compliance_=1.f/8000000.f;
    const std::vector<CrawlRock>&world_rocks()const{return custom_rocks_?test_rocks_:(terrain_mode_>=4?expedition_rocks(terrain_mode_):crawl_course());}
    static float square(float x){return x*x;}
    static void wake(DynamicBody&b){b.sleeping=false;b.quiet_time=0;}
    static bool near(const DynamicBody&a,const DynamicBody&b,float margin){return (a.position-b.position).length_squared()<square(a.shape.reach+b.shape.reach+margin);}
    static void unique_axis(std::vector<Vec3>&axes,Vec3 v){
        if(v.length_squared()<1e-10f)return;
        v=v.normalized();
        for(auto n:axes)if(std::abs(n.dot(v))>.9999f)return;
        axes.push_back(v);
    }
    static void build_axes(DynamicBody&b){
        for(auto t:b.shape.triangles)unique_axis(b.face_axes,(b.shape.vertices[t[1]]-b.shape.vertices[t[0]]).cross(b.shape.vertices[t[2]]-b.shape.vertices[t[0]]));
        for(int a=0;a<int(b.shape.vertices.size());++a)for(int c=a+1;c<int(b.shape.vertices.size());++c){
            Vec3 first;bool found=false,crease=false;
            for(auto t:b.shape.triangles){bool ha=false,hc=false;for(int v:t){ha|=v==a;hc|=v==c;}if(!ha||!hc)continue;
                Vec3 n=(b.shape.vertices[t[1]]-b.shape.vertices[t[0]]).cross(b.shape.vertices[t[2]]-b.shape.vertices[t[0]]).normalized();
                if(found&&std::abs(first.dot(n))<.9999f)crease=true;
                first=n;found=true;
            }
            if(crease)unique_axis(b.edge_axes,b.shape.vertices[c]-b.shape.vertices[a]);
        }
    }
    int add_shape(CrawlRock s,Vec3 at,Vec3 size,float mass,int kind,float yaw){
        if(body_count()>=max_bodies||!at.finite()||mass<=0||!std::isfinite(mass))return -1;
        s.center={};s.reach=0;
        for(auto&t:s.triangles){Vec3 a=s.vertices[t[0]],b=s.vertices[t[1]],c=s.vertices[t[2]];if((b-a).cross(c-a).dot(a)<0)std::swap(t[1],t[2]);}
        for(auto v:s.vertices)s.reach=std::max(s.reach,v.length());
        DynamicBody b;b.shape=s;b.position=at;b.previous_position=at;b.inv_mass=1/mass;b.kind=kind;
        b.rotation=DynamicQuaternion::rotation_vector({0,yaw,0});b.previous_rotation=b.rotation;
        b.inv_inertia_local={12/(mass*(size.y*size.y+size.z*size.z)),12/(mass*(size.x*size.x+size.z*size.z)),12/(mass*(size.x*size.x+size.y*size.y))};
        build_axes(b);bodies_.push_back(b);return body_count()-1;
    }
    static void position_impulse(DynamicBody&b,Vec3 p,Vec3 impulse,bool activate=true){
        if(b.inv_mass<=0||!impulse.finite())return;
        if(activate&&impulse.length_squared()>1e-12f)wake(b);
        const Vec3 angular=b.inverse_inertia((p-b.position).cross(impulse));
        b.position+=impulse*b.inv_mass;
        b.rotation=(DynamicQuaternion::rotation_vector(angular)*b.rotation).normalized();
    }
    static void solve_static_friction(DynamicBody&b,Vec3 p,Vec3 displacement,Vec3 normal,float lambda,Vec3&old,float mu){
        Vec3 tangent=displacement-normal*displacement.dot(normal);const float l=tangent.length();
        if(l<1e-9f)return;
        const Vec3 n=tangent/l;const float inv=b.point_inverse_mass(p,n);
        Vec3 next=old-tangent/std::max(inv,1e-8f);const float limit=mu*lambda,nl=next.length();
        if(nl>limit&&nl>0)next*=limit/nl;
        position_impulse(b,p,next-old,false);old=next;
    }
    static DynamicBody static_body(const CrawlRock&s){
        DynamicBody b;b.shape=s;b.position={};b.previous_position={};build_axes(b);return b;
    }
    struct Separation {bool overlap=false;float depth=0;Vec3 normal;};
    static Separation separation(const DynamicBody&a,const DynamicBody&b){
        Separation best{true,1e20f,{0,1,0}};
        auto axis=[&](Vec3 n){
            if(n.length_squared()<1e-9f)return true;
            n=n.normalized();
            float amin=1e20f,amax=-1e20f,bmin=1e20f,bmax=-1e20f;
            for(auto v:a.shape.vertices){float d=a.world_point(v).dot(n);amin=std::min(amin,d);amax=std::max(amax,d);}
            for(auto v:b.shape.vertices){float d=b.world_point(v).dot(n);bmin=std::min(bmin,d);bmax=std::max(bmax,d);}
            float d1=bmax-amin,d2=amax-bmin;if(d1<-.006f||d2<-.006f)return false;
            if(d2<d1){d1=d2;n=-n;}
            if(d1<best.depth){best.depth=d1;best.normal=n;}return true;
        };
        for(auto n:a.face_axes)if(!axis(a.rotation.rotate(n)))return {};
        for(auto n:b.face_axes)if(!axis(b.rotation.rotate(n)))return {};
        for(auto ea:a.edge_axes)for(auto eb:b.edge_axes)if(!axis(a.rotation.rotate(ea).cross(b.rotation.rotate(eb))))return {};
        return best;
    }
    static bool inside(const DynamicBody&b,Vec3 p,float tolerance){
        p=b.local_point(p);
        for(auto t:b.shape.triangles){const Vec3 a=b.shape.vertices[t[0]],n=(b.shape.vertices[t[1]]-a).cross(b.shape.vertices[t[2]]-a).normalized();if((p-a).dot(n)>tolerance)return false;}return true;
    }
    static std::vector<PairContact> manifold(const DynamicBody&a,const DynamicBody&b){
        const auto sat=separation(a,b);if(!sat.overlap)return {};
        const Vec3 n=sat.normal;float amin=1e20f,bmax=-1e20f;
        Vec3 sa,sb;
        for(auto v:a.shape.vertices){const Vec3 p=a.world_point(v);if(p.dot(n)<amin){amin=p.dot(n);sa=p;}}
        for(auto v:b.shape.vertices){const Vec3 p=b.world_point(v);if(p.dot(n)>bmax){bmax=p.dot(n);sb=p;}}
        std::vector<PairContact> c;
        auto add=[&](Vec3 pa,Vec3 pb){
            for(auto&old:c)if((a.world_point(old.local_a)-pa).length_squared()<.0001f)return;
            c.push_back({a.local_point(pa),b.local_point(pb),n,0,{}});
        };
        // Clip the two support faces. Vertex-only contacts miss the overlapping
        // corners of rotated rectangles and make a resting stack tip itself.
        auto polygon=[&](const DynamicBody&body,bool minimum,Vec3&face_normal,float&face_offset){
            // Clip actual support faces. Flattening every corner to the single
            // most penetrating vertex invents contact depth on a tilted box
            // and can pump energy into a resting stack.
            const Vec3 desired=minimum?-n:n;float best=-1;
            for(auto t:body.shape.triangles){
                const Vec3 p=body.world_point(body.shape.vertices[t[0]]);
                const Vec3 normal=body.rotation.rotate((body.shape.vertices[t[1]]-body.shape.vertices[t[0]])
                    .cross(body.shape.vertices[t[2]]-body.shape.vertices[t[0]]).normalized());
                if(normal.dot(desired)>best){best=normal.dot(desired);face_normal=normal;face_offset=normal.dot(p);}
            }
            std::vector<Vec3> points;Vec3 center;
            if(best<.9f)return points;
            for(auto v:body.shape.vertices){Vec3 p=body.world_point(v);
                if(std::abs(p.dot(face_normal)-face_offset)<.001f){p-=n*p.dot(n);points.push_back(p);center+=p;}}
            if(points.size()<3)return points;
            center*=1.f/points.size();const Vec3 u=(std::abs(n.y)<.8f?Vec3{0,1,0}:Vec3{1,0,0}).cross(n).normalized(),v=n.cross(u);
            std::sort(points.begin(),points.end(),[&](Vec3 x,Vec3 y){x-=center;y-=center;return std::atan2(x.dot(v),x.dot(u))<std::atan2(y.dot(v),y.dot(u));});return points;
        };
        Vec3 normal_a,normal_b;float offset_a=0,offset_b=0;
        auto poly_a=polygon(a,true,normal_a,offset_a),poly_b=polygon(b,false,normal_b,offset_b);
        if(poly_a.size()>=3&&poly_b.size()>=3){
            auto clipped=poly_a;
            for(int i=0;i<int(poly_b.size())&&!clipped.empty();++i){
                const Vec3 e0=poly_b[i],e=poly_b[(i+1)%poly_b.size()]-e0;
                std::vector<Vec3> next;Vec3 previous=clipped.back();float before=e.cross(previous-e0).dot(n);
                for(auto current:clipped){float after=e.cross(current-e0).dot(n);
                    if((after>=0)!=(before>=0))next.push_back(previous+(current-previous)*(before/(before-after)));
                    if(after>=0)next.push_back(current);
                    previous=current;before=after;
                }
                clipped=next;
            }
            for(auto p:clipped){
                const Vec3 pa=p+n*((offset_a-p.dot(normal_a))/n.dot(normal_a));
                const Vec3 pb=p+n*((offset_b-p.dot(normal_b))/n.dot(normal_b));
                if((pa-pb).dot(n)<.006f)add(pa,pb);
            }
        }
        if(c.empty())for(auto v:a.shape.vertices){Vec3 pa=a.world_point(v);if(pa.dot(n)>amin+.02f)continue;Vec3 pb=pa+n*(bmax-pa.dot(n));if(inside(b,pb,.009f))add(pa,pb);}
        if(c.empty())for(auto v:b.shape.vertices){Vec3 pb=b.world_point(v);if(pb.dot(n)<bmax-.02f)continue;Vec3 pa=pb+n*(amin-pb.dot(n));if(inside(a,pa,.009f))add(pa,pb);}
        if(c.empty()){
            // Edge/edge support: closest support-feature midpoint gives a
            // common contact lever arm while retaining SAT separation depth.
            Vec3 p=(sa+sb)*.5f;add(p-n*(sat.depth*.5f),p+n*(sat.depth*.5f));
        }
        // At most four spatially spread manifold contacts, bounded per pair.
        if(c.size()>4){std::vector<PairContact> kept{c.front()};while(kept.size()<4){float far=-1;int pick=-1;for(int i=0;i<int(c.size());++i){float closest=1e20f;for(auto&k:kept)closest=std::min(closest,(c[i].local_a-k.local_a).length_squared());if(closest>far){far=closest;pick=i;}}kept.push_back(c[pick]);}return kept;}
        return c;
    }
    void solve_pair(Pair&pair,float dt){
        auto&a=bodies_[pair.a];
        DynamicBody&b=pair.b>=0?bodies_[pair.b]:static_bodies_[pair.rock];
        if(pair.contacts.empty())pair.contacts=manifold(a,b);
        for(auto&c:pair.contacts){
            Vec3 pa=a.world_point(c.local_a),pb=b.world_point(c.local_b),p=(pa+pb)*.5f;
            const Vec3 n=c.normal;float C=(pa-pb).dot(n);
            const float inv=a.point_inverse_mass(p,n)+b.point_inverse_mass(p,n),alpha=ground_compliance_/(dt*dt);
            float dl=(-C-alpha*c.lambda)/(inv+alpha),next=std::max(0.f,c.lambda+dl);dl=next-c.lambda;c.lambda=next;
            position_impulse(a,p,n*dl);position_impulse(b,p,-n*dl);
            if(next<=0)continue;
            pa=a.world_point(c.local_a);pb=b.world_point(c.local_b);p=(pa+pb)*.5f;
            const Vec3 olda=a.previous_position+a.previous_rotation.rotate(c.local_a),oldb=b.previous_position+b.previous_rotation.rotate(c.local_b);
            Vec3 slip=(pa-olda)-(pb-oldb);slip-=n*slip.dot(n);const float length=slip.length();
            if(length>1e-9f){
                Vec3 t=slip/length;float w=a.point_inverse_mass(p,t)+b.point_inverse_mass(p,t);
                Vec3 friction=c.friction-slip/std::max(w,1e-8f);float limit=.62f*next,l=friction.length();if(l>limit&&l>0)friction*=limit/l;
                const Vec3 change=friction-c.friction;position_impulse(a,p,change);position_impulse(b,p,-change);c.friction=friction;
            }
        }
    }
};
