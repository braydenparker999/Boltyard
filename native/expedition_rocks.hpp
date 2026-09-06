#pragma once
// Include inside boltyard after CrawlRock and expedition_terrain.hpp. These
// rounded, buried granite hulls are exported verbatim for visible rock meshes.
inline CrawlRock expedition_granite(int mode,float x,float z,float width,float depth,float exposure,float yaw,unsigned seed) {
    using namespace expedition_detail;
    CrawlRock rock;std::vector<Vec3> points;
    const float cy=expedition_height(mode,x,z),burial=std::max(1.1f,std::max(width,depth)*.24f);
    auto normal=expedition_normal(mode,x,z);
    const float gx=clamp(-normal.x/std::max(.3f,normal.y),-.55f,.55f);
    const float gz=clamp(-normal.z/std::max(.3f,normal.y),-.55f,.55f);
    const float middle=(exposure-burial)*.5f,radius=(exposure+burial)*.5f;
    auto point=[&](float a,float level,float radial) {
        float phase=hash(int(seed)+17,39)*6.28318530718f;
        float stretch=.96f+.035f*std::sin(a*3+phase)+.010f*std::sin(a*5-phase);
        float px=std::cos(a)*width*.5f*radial*stretch,pz=std::sin(a)*depth*.5f*radial*stretch;
        float dx=px*std::cos(yaw)+pz*std::sin(yaw),dz=-px*std::sin(yaw)+pz*std::cos(yaw);
        // A low ellipsoidal crown produces scoured bedrock with a gradual entry.
        // Terrain gradient carries through the entire formation. Preserve a
        // slight crown rather than creating numerically coplanar top points.
        float py=middle+radius*level;
        points.push_back({x+dx,cy+py+gx*dx+gz*dz,z+dz});
    };
    point(0,-1,0);
    const float levels[4]={-.73f,-.20f,.43f,.80f};
    for(unsigned l=0;l<4;++l)for(unsigned j=0;j<12;++j)
        point(j*6.28318530718f/12.f,levels[l],std::sqrt(1-levels[l]*levels[l]));
    point(0,1,0);
    // Homothetic convex rings guarantee a closed hull with no numerical
    // coplanar-face discovery. A low-frequency irregular cross section is
    // shared through the crown; affine terrain tilt preserves convexity.
    std::vector<std::array<int,3>> faces;
    auto face=[&](int a,int b,int c){
        const Vec3 center{x,cy+middle,z};
        if((points[b]-points[a]).cross(points[c]-points[a]).dot(points[a]-center)<0)std::swap(b,c);
        faces.push_back({a,b,c});
    };
    for(int j=0;j<12;++j){
        int k=(j+1)%12;face(0,1+k,1+j);face(49,37+j,37+k);
        for(int ring=0;ring<3;++ring){int a=1+ring*12+j,b=1+ring*12+k,c=a+12,d=b+12;face(a,b,c);face(b,d,c);}
    }
    rock.vertices=std::move(points);rock.triangles=std::move(faces);
    for(auto p:rock.vertices)rock.center+=p;
    rock.center*=1.f/rock.vertices.size();
    for(auto t:rock.triangles)rock.triangle_normals.push_back((rock.vertices[t[1]]-rock.vertices[t[0]]).cross(rock.vertices[t[2]]-rock.vertices[t[0]]).normalized());
    for(auto p:rock.vertices)rock.reach=std::max(rock.reach,(p-rock.center).length());
    rock.surface=mode==5?.98f:1.13f;
    return rock;
}
inline const std::vector<CrawlRock>& expedition_rocks(int mode) {
    auto make=[](int m) {
        using namespace expedition_detail;std::vector<CrawlRock> out;unsigned seed=137;
        auto add=[&](float x,float z,float width,float depth,float exposure,float yaw){
            if(x*x+(z-8)*(z-8)<20*20)return;
            out.push_back(expedition_granite(m,x,z,width,depth,exposure,yaw,seed++));
        };
        // Technical trails cross the exposed top of a broad bedrock spine.
        // Low, overlapping pieces share a geological orientation and extend
        // into the shoulders. The centre remains passable with a stock crawler.
        const auto &route=trails(m);
        for(size_t i=1;i<route.size();++i){
            auto a=route[i-1],b=route[i];if(a.route!=b.route)continue;
            float dx=b.x-a.x,dz=b.z-a.z,length=std::sqrt(dx*dx+dz*dz),nx=-dz/length,nz=dx/length;
            int count=int(length/(a.route>=2?11.f:22.f));
            for(int k=0;k<count;++k){
                float t=(k+.58f)/std::max(1,count),cx=a.x+dx*t,cz=a.z+dz*t;
                float v=hash(int(i)*19,k*37+m),side=(k+int(i))%2?1.f:-1.f;
                float yaw=std::atan2(dx,dz)+(m==5?.15f:-.12f);
                if(a.route>=2){
                    // The low inner shoulder crosses one wheel track; its
                    // broad rounded entry avoids vertical box-shaped steps.
                    add(cx+nx*side*1.25f,cz+nz*side*1.25f,4.2f+v*2,5.5f+v*2,.24f+v*.23f,yaw);
                    add(cx+nx*side*5.4f,cz+nz*side*5.4f,8.0f+v*3,10+v*3,1.1f+v*1.7f,yaw+.13f);
                }else{
                    float offset=a.width+3.6f+v*1.4f;
                    add(cx+nx*side*offset,cz+nz*side*offset,4.5f+v*4,6+v*5,.6f+v*1.9f,yaw);
                }
            }
        }
        // Weathered granite pavement around the immediate side lines is the
        // first view leaving camp, not a distant test obstacle area.
        const float clusters4[8][2]={{20,-62},{-48,-173},{-92,-248},{-219,-216},{115,-120},{156,-44},{-176,5},{-108,67}};
        const float clusters5[8][2]={{-53,-23},{-220,19},{-189,122},{126,178},{-102,-163},{90,-207},{153,-134},{185,-5}};
        for(int cluster=0;cluster<8;++cluster)for(int j=0;j<7;++j){
            const float *center=m==5?clusters5[cluster]:clusters4[cluster];
            float angle=j*2.399963f+cluster*.43f,radius=3+std::sqrt(float(j))*4.8f;
            float x=center[0]+std::cos(angle)*radius,z=center[1]+std::sin(angle)*radius;
            auto trail=nearest_trail(m,x,z);if(trail.distance<trail.width+3.3f)continue;
            if(lake_distance(m,x,z)<1.02f)continue;
            float v=hash(cluster*37+11,j*31+m);
            add(x,z,4.5f+v*5,6+v*6,.8f+v*2.7f,(m==5?.35f:-.3f)+v*.35f);
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
    if(mode==5){static const auto r=make(5);return r;}static const auto r=make(4);return r;
}
