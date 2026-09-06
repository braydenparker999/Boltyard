#pragma once
// Included after Vec3. Convex, closed sandstone pieces: the rendering binding
// exports these exact triangles. No separate visual rock/cylinder approximation.
struct CrawlRock {
    std::vector<Vec3> vertices;
    std::vector<std::array<int,3>> triangles;
    Vec3 center;
    float reach=0, surface=1.15f;
};
inline CrawlRock crawl_rock(float x,float z,float width,float depth,float height,float slope=0,float roll=0,float yaw=0,float base=0) {
    CrawlRock r; r.center={x,base+height*.5f,z};
    constexpr float ring[8][2]={{-.72f,-1},{.72f,-1},{1,-.72f},{1,.72f},{.72f,1},{-.72f,1},{-1,.72f},{-1,-.72f}};
    for(int layer=0;layer<2;++layer) for(auto &p:ring){
        float px=p[0]*width*.5f,pz=p[1]*depth*.5f;
        const float taper=.12f/height;
        const float tilt=-slope*pz+roll*px;
        float py=layer?(height+tilt)/(1+taper*tilt):0;
        float factor=1-taper*py;px*=factor;pz*=factor;
        r.vertices.push_back({x+px*std::cos(yaw)+pz*std::sin(yaw),base+py,z-px*std::sin(yaw)+pz*std::cos(yaw)});
    }
    // Orient each face outward independently, robust to handedness.
    auto face=[&](int a,int b,int c){auto n=(r.vertices[b]-r.vertices[a]).cross(r.vertices[c]-r.vertices[a]);if(n.dot(r.vertices[a]-r.center)<0)std::swap(b,c);r.triangles.push_back({a,b,c});};
    for(int i=1;i<7;++i){face(0,i,i+1);face(8,8+i,9+i);}
    for(int i=0;i<8;++i){int j=(i+1)%8;face(i,j,8+j);face(i,8+j,8+i);}
    for(auto p:r.vertices)r.reach=std::max(r.reach,(p-r.center).length());
    return r;
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
        // The bordering outcrops share collision too, even off the marked line.
        for(int side:{-1,1})for(int i=0;i<10;++i)
            r.push_back(crawl_rock(side*(21.f+(i%3)*3.f),16-i*11.f,10.f+i%4*2,13.f,3.f+i%5,.12f,.08f,side*.32f+i*.28f));
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
inline RockDistance rock_distance(const CrawlRock&r,Vec3 p){
    float closest=1e20f,max_plane=-1e20f;Vec3 q,n,inside_n;
    for(auto t:r.triangles){Vec3 a=r.vertices[t[0]],b=r.vertices[t[1]],c=r.vertices[t[2]];Vec3 face=(b-a).cross(c-a).normalized();float plane=(p-a).dot(face);if(plane>max_plane){max_plane=plane;inside_n=face;}
        Vec3 v=closest_triangle(p,a,b,c);float d=(p-v).length_squared();if(d<closest){closest=d;q=v;n=face;}}
    if(max_plane<=0)return {max_plane,inside_n,p-inside_n*max_plane};
    float d=std::sqrt(closest);return {d,d>1e-7f?(p-q)/d:n,q};
}
