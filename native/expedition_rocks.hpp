#pragma once
// Include inside boltyard after CrawlRock and expedition_terrain.hpp. These
// rounded, buried hulls are exported verbatim for visible rock meshes.
// The shell shape. Glaciated granite derives it from the seed alone; layered
// sandstone needs to ask for a specific form, because a fin and a ledge tread
// are the obstacle, not a variation on a boulder.
//   cross_power  2 is an ellipse in plan, higher squares the sides off.
//   crown_power  2 is a dome, higher holds full width up to a flat top.
//   drift        shifts the crown along local z, lengthening one approach.
struct RockProfile { float cross_power,crown_power,drift; bool fracture; };
inline CrawlRock expedition_granite(int mode,float x,float z,float width,float depth,float exposure,float yaw,unsigned seed,int fracture_attempt=0,const RockProfile *profile=nullptr) {
    using namespace expedition_detail;
    CrawlRock rock;std::vector<Vec3> points;
    const float cy=expedition_height(mode,x,z),burial=std::max(1.1f,std::max(width,depth)*.27f);
    auto normal=expedition_normal(mode,x,z);
    const float gx=clamp(-normal.x/std::max(.3f,normal.y),-.55f,.55f);
    const float gz=clamp(-normal.z/std::max(.3f,normal.y),-.55f,.55f);
    const float middle=(exposure-burial)*.5f,radius=(exposure+burial)*.5f;
    constexpr int sectors=20,rings=8;
    const float variant=hash(int(seed)+17,39);
    // Convex superellipsoid sections vary from long whalebacks to broad slabs
    // and rounded joint blocks. Affine crown drift makes the abraded approach
    // longer than the lee shoulder without non-convex contact approximations.
    const float cross_power=profile?profile->cross_power:2.0f+(seed%3)*.36f;
    const float crown_power=profile?profile->crown_power:(seed%5<2?2.0f:(seed%5==2?3.4f:2.65f));
    const float drift=(profile?profile->drift:(seed%2?.16f:-.10f))*depth;
    auto point=[&](float a,float level,float radial) {
        auto signed_power=[](float value,float exponent){return std::copysign(std::pow(std::abs(value),exponent),value);};
        float px=signed_power(std::cos(a),2/cross_power)*width*.5f*radial;
        float pz=signed_power(std::sin(a),2/cross_power)*depth*.5f*radial+level*drift;
        points.push_back({px,middle+radius*level,pz});
    };
    point(0,-1,0);
    const float levels[rings]={-.88f,-.62f,-.28f,.10f,.45f,.70f,.88f,.97f};
    for(int l=0;l<rings;++l)for(int j=0;j<sectors;++j)
        point(j*6.28318530718f/sectors,levels[l],std::pow(1-std::pow(std::abs(levels[l]),crown_power),1/crown_power));
    point(0,1,0);
    using Polygon=std::vector<Vec3>;
    std::vector<Polygon> polygons;
    auto polygon=[&](std::initializer_list<int> indices){
        Polygon face;for(int i:indices)face.push_back(points[i]);polygons.push_back(std::move(face));
    };
    for(int j=0;j<sectors;++j){
        int k=(j+1)%sectors;
        polygon({0,1+k,1+j});polygon({1+rings*sectors,1+(rings-1)*sectors+j,1+(rings-1)*sectors+k});
        for(int ring=0;ring<rings-1;++ring){int a=1+ring*sectors+j,b=1+ring*sectors+k;polygon({a,b,b+sectors,a+sectors});}
    }
    // Selected outcrops expose a plucked joint face. This is a true convex
    // clipping plane, so the abrupt technical edge is both drawn and collided.
    // Low traversable slabs keep the fracture short; larger shoulder blocks
    // can carry the more prominent broken face seen in glaciated bedrock.
    const bool fractured=fracture_attempt<6&&(profile?profile->fracture:(seed%5==2||seed%7==0));
    if(fractured) {
        Vec3 plane{.10f,exposure<.6f?.24f:.12f,seed%2?1.f:-1.f};plane=plane.normalized();
        const float offset=depth*(.22f+variant*.08f+fracture_attempt*.007f);
        std::vector<Polygon> clipped;Polygon cap;
        auto cap_vertex=[&](Vec3 p){for(auto q:cap)if((p-q).length_squared()<1e-9f)return;cap.push_back(p);};
        for(const auto&poly:polygons) {
            Polygon cut;
            for(size_t i=0;i<poly.size();++i) {
                Vec3 a=poly[i],b=poly[(i+1)%poly.size()];float da=plane.dot(a)-offset,db=plane.dot(b)-offset;
                if(da<=0)cut.push_back(a);
                if((da<=0)!=(db<=0)){Vec3 q=a+(b-a)*(da/(da-db));cut.push_back(q);cap_vertex(q);}
            }
            if(cut.size()>=3)clipped.push_back(std::move(cut));
        }
        if(cap.size()>=3) {
            Vec3 center;for(auto p:cap)center+=p;center*=1.f/cap.size();
            Vec3 axis=plane.cross(Vec3{1,0,0}).normalized(),other=plane.cross(axis);
            std::sort(cap.begin(),cap.end(),[&](Vec3 a,Vec3 b){a-=center;b-=center;return std::atan2(a.dot(other),a.dot(axis))<std::atan2(b.dot(other),b.dot(axis));});
            // A center fan retains collinear edge subdivisions shared with the
            // curved shell. Removing them would open microscopic T-junctions.
            for(size_t i=0;i<cap.size();++i)clipped.push_back({center,cap[i],cap[(i+1)%cap.size()]});
        }
        polygons=std::move(clipped);
    }
    auto vertex=[&](Vec3 p){
        for(size_t i=0;i<rock.vertices.size();++i)if((p-rock.vertices[i]).length_squared()<1e-9f)return int(i);
        rock.vertices.push_back(p);return int(rock.vertices.size()-1);
    };
    for(const auto&poly:polygons) {
        int first=vertex(poly[0]);
        for(size_t i=1;i+1<poly.size();++i)if((poly[i]-poly[0]).cross(poly[i+1]-poly[0]).length_squared()>1e-12f)
            rock.triangles.push_back({first,vertex(poly[i]),vertex(poly[i+1])});
    }
    for(auto&p:rock.vertices) {
        float dx=p.x*std::cos(yaw)+p.z*std::sin(yaw),dz=-p.x*std::sin(yaw)+p.z*std::cos(yaw);
        p={x+dx,cy+p.y+gx*dx+gz*dz,z+dz};rock.center+=p;
    }
    rock.center*=1.f/rock.vertices.size();
    for(auto&t:rock.triangles) {
        Vec3 normal=(rock.vertices[t[1]]-rock.vertices[t[0]]).cross(rock.vertices[t[2]]-rock.vertices[t[0]]).normalized();
        if(normal.dot(rock.vertices[t[0]]-rock.center)<0){std::swap(t[1],t[2]);normal=-normal;}
        rock.triangle_normals.push_back(normal);
    }
    for(auto p:rock.vertices)rock.reach=std::max(rock.reach,(p-rock.center).length());
    // Near-coincident cuts can make tiny triangles lose their supporting plane
    // after float world translation, or weld a cap edge onto more than the two
    // faces that may share it. Either way the shell stops being a convex solid
    // the contact solver can trust, so move the geological joint slightly and
    // rebuild rather than shipping it.
    if(fractured) {
        for(size_t f=0;f<rock.triangles.size();++f)for(auto p:rock.vertices)
            if(rock.triangle_normals[f].dot(p-rock.vertices[rock.triangles[f][0]])>.00045f)
                return expedition_granite(mode,x,z,width,depth,exposure,yaw,seed,fracture_attempt+1,profile);
        // This header is included inside the boltyard namespace, so it must
        // not pull in new standard headers; sorting a flat edge list needs
        // nothing beyond what the rock geometry already uses.
        std::vector<std::pair<int,int>> edges;
        edges.reserve(rock.triangles.size()*3);
        for(const auto &t:rock.triangles)for(int e=0;e<3;++e){
            int a=t[e],b=t[(e+1)%3];if(a>b)std::swap(a,b);edges.push_back({a,b});
        }
        std::sort(edges.begin(),edges.end());
        for(size_t i=0;i<edges.size();) {
            size_t j=i;while(j<edges.size()&&edges[j]==edges[i])++j;
            if(j-i!=2)return expedition_granite(mode,x,z,width,depth,exposure,yaw,seed,fracture_attempt+1,profile);
            i=j;
        }
    }
    rock.surface=1.10f-expedition_material(mode,x,z).wet*.54f;
    rock.rebuild_queries();return rock;
}
inline const std::vector<CrawlRock>& expedition_rocks(int mode) {
    auto make=[](int m) {
        using namespace expedition_detail;std::vector<CrawlRock> out;unsigned seed=137;
        auto add=[&](float x,float z,float width,float depth,float exposure,float yaw,const RockProfile *profile=nullptr){
            if(x*x+(z-8)*(z-8)<20*20)return;
            out.push_back(expedition_granite(m,x,z,width,depth,exposure,yaw,seed++,0,profile));
        };
        // Sandstone parts along its bedding and its joints, so redrock asks for
        // three explicit forms where granite takes whatever the seed gives it.
        static const RockProfile fin{4.4f,3.6f,0.f,true};       // standing wall
        static const RockProfile ledge{3.0f,3.3f,.10f,true};    // stepped tread, cut face
        static const RockProfile block{2.4f,2.6f,-.08f,false};  // fallen caprock
        const RockProfile *near_profile=m==6?&ledge:nullptr;
        const RockProfile *far_profile=m==6?&block:nullptr;
        // Technical trails cross the exposed top of a broad bedrock spine.
        // Low, overlapping pieces share a geological orientation and extend
        // into the shoulders. The centre remains passable with a stock crawler.
        const auto &route=trails(m);float along=0,next_rock=8;int placement=0;
        for(size_t i=1;i<route.size();++i){
            auto a=route[i-1],b=route[i];
            if(a.route!=b.route){along=0;next_rock=8;placement=0;continue;}
            float dx=b.x-a.x,dz=b.z-a.z,length=std::hypot(dx,dz),nx=-dz/length,nz=dx/length;
            while(next_rock<=along+length){
                float t=clamp((next_rock-along)/length,0,1),cx=a.x+dx*t,cz=a.z+dz*t;
                float v=hash(a.route*191+placement*19,m*37),side=placement%2?1.f:-1.f;
                float yaw=std::atan2(dx,dz)+(m==5?.15f:-.12f);
                if(technical_route(m,a.route)){
                    // Unevenly spaced slabs meet one wheel first, with a clear
                    // smooth approach between formations and a passable exit.
                    // Sandstone parts into steps rather than glacial pavement,
                    // so redrock's trailside pieces are narrower and taller.
                    if(m==6){
                        add(cx+nx*side*1.55f,cz+nz*side*1.55f,2.8f+v*1.6f,4.4f+v*2.2f,.34f+v*.42f,yaw,near_profile);
                        if(placement%3!=1)add(cx+nx*side*5.4f,cz+nz*side*5.4f,5.0f+v*2.4f,7.0f+v*3.0f,1.5f+v*2.1f,yaw+.13f,far_profile);
                    }else{
                        add(cx+nx*side*1.35f,cz+nz*side*1.35f,4.5f+v*2,6.2f+v*2.4f,.22f+v*.27f,yaw,near_profile);
                        if(placement%3!=1)add(cx+nx*side*5.9f,cz+nz*side*5.9f,8.0f+v*3,10+v*3,1.0f+v*1.6f,yaw+.13f,far_profile);
                    }
                }else{
                    float offset=a.width+4.1f+v*2.0f;
                    if(m==6)add(cx+nx*side*offset,cz+nz*side*offset,3.4f+v*2.6f,4.6f+v*3.4f,1.1f+v*2.4f,yaw,far_profile);
                    else add(cx+nx*side*offset,cz+nz*side*offset,4.5f+v*4,6+v*5,.55f+v*1.7f,yaw,far_profile);
                }
                // Redrock carries a third more route than the boreal maps, so
                // it spaces its trailside rock out to keep the hull count and
                // the drawn triangle budget in the same place they are there.
                const float spacing=technical_route(m,a.route)?(m==6?19.f:11.5f):(m==6?42.f:24.f);
                next_rock+=spacing*(0.78f+v*.55f);++placement;
            }
            along+=length;
        }
        // Weathered granite pavement around the immediate side lines is the
        // first view leaving camp, not a distant test obstacle area.
        const float clusters4[8][2]={{20,-62},{-48,-173},{-92,-248},{-219,-216},{115,-120},{156,-44},{-176,5},{-108,67}};
        const float clusters5[8][2]={{-53,-23},{-220,19},{-189,122},{126,178},{-102,-163},{90,-207},{153,-134},{185,-5}};
        const float clusters6[8][2]={{78,-96},{196,-158},{224,-238},{62,-236},{-118,-30},{-244,-116},{158,150},{-52,236}};
        for(int cluster=0;cluster<8;++cluster)for(int j=0;j<7;++j){
            const float *center=m==6?clusters6[cluster]:(m==5?clusters5[cluster]:clusters4[cluster]);
            float angle=j*2.399963f+cluster*.43f,radius=3+std::sqrt(float(j))*4.8f;
            float x=center[0]+std::cos(angle)*radius,z=center[1]+std::sin(angle)*radius;
            auto trail=nearest_trail(m,x,z);if(trail.distance<trail.width+3.3f)continue;
            if(lake_distance(m,x,z)<1.02f)continue;
            float v=hash(cluster*37+11,j*31+m);
            if(m==6)add(x,z,3.6f+v*3.2f,4.8f+v*4.0f,1.4f+v*3.2f,-.3f+v*.35f,far_profile);
            else add(x,z,4.5f+v*5,6+v*6,.8f+v*2.7f,(m==5?.35f:-.3f)+v*.35f,far_profile);
        }
        // The fin field. Standing walls follow the same north-east bedding the
        // heightfield corrugates, spaced so the gaps between them are the line
        // rather than an obstacle laid across one. Each is a single convex
        // hull, so a wall a tire leans on is exactly the wall that is drawn.
        if(m==6)for(int crest=-4;crest<=4;++crest)for(int step=-4;step<=4;++step){
            const float across=13.7f+crest*27.4f,along=step*28.f;
            const float x=-178+(along+across)*.7071f,z=198+(along-across)*.7071f;
            if(std::hypot((x+178)*.92f,(z-198)*1.05f)>124.f)continue;
            const float v=hash(crest*53+7,step*29+3);
            if(v>.78f)continue;                       // gaps break the walls into runs
            const auto trail=nearest_trail(m,x,z);
            if(trail.distance<trail.width+3.4f)continue;
            add(x+std::cos(v*6.2832f)*2.4f,z+std::sin(v*6.2832f)*2.4f,
                3.4f+v*2.4f,15.f+v*13.f,3.2f+v*3.4f,.7854f+(v-.5f)*.10f,&fin);
        }
        // Low lakeside skerries make the Russian shoreline distinct from the
        // alpine tarn. They merge into its shallows and remain real collision.
        if(m==5)for(int j=0;j<24;++j){
            float a=j*6.28318530718f/24.f,v=hash(j+631,82),radius=1.06f+v*.035f;
            float shore=1+.08f*std::sin(a*3+.6f)+.055f*std::sin(a*7-.4f);
            float x=26+std::cos(a)*83*radius*shore,z=-147+std::sin(a)*66*radius*shore;
            if(nearest_trail(m,x,z).distance<3.9f)continue;
            add(x,z,3+v*3,5+v*4,.35f+v*.45f,.35f);
        }
        // Tree roots and outcrops must not occupy the same above-ground space.
        // Prune the rock (the trees are already a public cached contact list).
        const auto&trees=expedition_obstacles(m);
        out.erase(std::remove_if(out.begin(),out.end(),[&](const CrawlRock&r){
            for(const auto&t:trees){
                float dx=t.x-r.center.x,dz=t.z-r.center.z;if(dx*dx+dz*dz>r.reach*r.reach)continue;
                float ground=expedition_height(m,t.x,t.z);
                if(rock_distance(r,{t.x,ground+.15f,t.z}).distance<t.radius+.18f)return true;
            }
            return false;
        }),out.end());
        return out;
    };
    if(mode==6){static const auto r=make(6);return r;}
    if(mode==5){static const auto r=make(5);return r;}
    static const auto r=make(4);return r;
}
