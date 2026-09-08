#include "soft_rig.hpp"
#include "expedition_terrain.hpp"
namespace boltyard {
#include "expedition_rocks.hpp"
}
#include <cstdio>
#include <cstdlib>
#include <map>
#include <set>
#include <string>
#include <queue>
using namespace boltyard;
static int checks=0;
static void require(bool value,const char*name){++checks;if(!value){std::fprintf(stderr,"FAIL %s\n",name);std::exit(1);}}
// What each region is supposed to be. Redrock is not a quieter forest: it is
// bare rock with a scatter of pinyon-juniper, so the boreal thresholds would
// be the wrong test rather than a loose one.
struct MapExpectation {
    int mode; const char *id;
    float min_relief,max_relief,max_curvature99,min_route_length;
    size_t min_trees,max_trees; int min_birches,max_birches;
    bool wet_rock,sand;
};
static const MapExpectation expectations[]={
    {4,"rockies", 80.f,190.f,.100f,1700.f,1000,4000,   0,   0,true, false},
    {5,"russia",  18.f, 60.f,.075f,1700.f,1000,4000, 400,2000,false,false},
    {6,"redrock", 55.f,140.f,.145f,2600.f, 150, 700,   0,   0,false,true },
};
int main(){
    std::map<std::string,int> region_ids;
    float relief[3];
    for(const auto &expect:expectations){
        const int mode=expect.mode;
        using namespace expedition_detail;
        require(std::string(expedition_region_id(mode))==expect.id,"region reports its stable save id");
        require(++region_ids[expedition_region_id(mode)]==1,"region ids are unique across the map set");
        // Every route carries a name and a difficulty, and no anchor may name
        // a route the region does not declare.
        require(!routes(mode).empty()&&route_count(mode)<=max_routes,"region declares its routes");
        for(const auto &route:routes(mode))
            require(route.name!=nullptr&&route.name[0]!='\0'&&route.detail!=nullptr,"every route is named");
        for(const auto &anchor:trail_anchors(mode))
            require(anchor.route>=0&&anchor.route<route_count(mode),"anchor belongs to a declared route");
        const auto &map=cache(mode);
        require(map.height.size()==size_t(side)*side,"complete map cache");
        require(std::abs(expedition_height(mode,0,8))<1e-6f,"camp is level at origin");
        auto limits=std::minmax_element(map.height.begin(),map.height.end());
        const float range=*limits.second-*limits.first;
        relief[&expect-expectations]=range;
        require(range>expect.min_relief&&range<expect.max_relief,"landscape has the relief its region intends");
        // Physical curvature catches jagged geometry that smooth shading can
        // hide. Evaluate every interior grid vertex, including route shoulders.
        std::vector<float> curvature;
        for(int iz=1;iz<side-1;++iz)for(int ix=1;ix<side-1;++ix){
            size_t i=size_t(iz)*side+ix;
            curvature.push_back(std::max(std::abs(map.height[i-1]-2*map.height[i]+map.height[i+1]),
                std::abs(map.height[i-side]-2*map.height[i]+map.height[i+side]))/(spacing*spacing));
        }
        std::sort(curvature.begin(),curvature.end());
        float curvature99=curvature[curvature.size()*99/100];
        require(curvature99<expect.max_curvature99,"eroded terrain avoids pervasive sharp changes of grade");
        require(curvature.back()<.60f,"ground has no cliff seams between nearby trail influences");
        for(int i=0;i<180;++i){
            int ix=(i*173+13)%(side-1),iz=(i*97+23)%(side-1);
            float tx=(i%7+.31f)/7.f,tz=(i%11+.21f)/11.f;
            float x=-extent+(ix+tx)*spacing,z=-extent+(iz+tz)*spacing;
            // Use the actual representable coordinates, so the comparison
            // measures geometry rather than independent float-rounding paths.
            tx=(x+extent)/spacing-ix;tz=(z+extent)/spacing-iz;
            size_t n=size_t(iz)*side+ix;float expected;
            if(tx+tz<=1)expected=map.height[n]+tx*(map.height[n+1]-map.height[n])+tz*(map.height[n+side]-map.height[n]);
            else expected=map.height[n+side+1]+(1-tx)*(map.height[n+side]-map.height[n+side+1])+(1-tz)*(map.height[n+1]-map.height[n+side+1]);
            require(std::abs(expected-expedition_height(mode,x,z))<.00001f,"contact is exact rendered triangle");
            auto normal=expedition_normal(mode,x,z);
            require(std::abs(normal.x*normal.x+normal.y*normal.y+normal.z*normal.z-1)<.00001f,"unit terrain normal");
            const auto material=expedition_material(mode,x,z);
            require(std::abs(material.rock+material.dirt+material.grass-1)<.00001f,"material weights partition surface");
            require(expedition_surface(mode,x,z)>=.52f&&expedition_surface(mode,x,z)<=1.12f,"bounded physical surface grip");
        }
        int surface_count[7]={};float surface_sum[7]={};
        for(int iz=0;iz<side;iz+=2)for(int ix=0;ix<side;ix+=2){
            float x=-extent+ix*spacing,z=-extent+iz*spacing;
            int type=expedition_surface_material(mode,x,z);
            require(type>=0&&type<=6,"contact material uses the stable telemetry IDs");
            ++surface_count[type];surface_sum[type]+=expedition_surface(mode,x,z);
        }
        for(int type:{ExpeditionDirt,ExpeditionDryRock,ExpeditionMud,ExpeditionGravel})
            require(surface_count[type]>40,"map has spatially meaningful contact surface regions");
        auto mean_grip=[&](int type){return surface_sum[type]/std::max(1,surface_count[type]);};
        require(mean_grip(ExpeditionDryRock)>mean_grip(ExpeditionGravel)+.10f,"loose gravel has less grip than dry bedrock");
        require(mean_grip(ExpeditionDryRock)>mean_grip(ExpeditionMud)+.12f,"saturated soil reduces actual traction");
        if(expect.wet_rock){
            require(surface_count[ExpeditionWetRock]>25,"wet exposed rock exists at the alpine shore");
            require(mean_grip(ExpeditionDryRock)>mean_grip(ExpeditionWetRock)+.15f,"wet bedrock has meaningfully lower friction");
        }
        if(expect.sand){
            require(surface_count[ExpeditionSand]>300,"wind-blown sand is a real region of the desert map");
            require(mean_grip(ExpeditionDryRock)>mean_grip(ExpeditionSand)+.15f,"dry slickrock grips far better than loose sand");
            require(mean_grip(ExpeditionSand)>mean_grip(ExpeditionMud),"dry sand still beats saturated ground");
        }else require(surface_count[ExpeditionSand]==0,"only the desert map reports a sand contact material");
        float max_grade=0,total_length=0;int curved_spans=0,route_checks=0;
        const auto &path=trails(mode);
        require(path.size()>600,"curved route exports contain meter scale geometry");
        for(const auto&anchor:trail_anchors(mode)){
            bool found=false;
            for(const auto&p:path)if(p.route==anchor.route&&std::hypot(p.x-anchor.x,p.z-anchor.z)<.0001f&&std::abs(p.h-anchor.h)<.0001f)found=true;
            require(found,"smoothing preserves route junctions and authored landmark elevations");
        }
        for(size_t j=1;j<path.size();++j){
            auto a=path[j-1],b=path[j];if(a.route!=b.route)continue;
            float dx=b.x-a.x,dz=b.z-a.z,length=std::sqrt(dx*dx+dz*dz);total_length+=length;
            require(length<3.7f&&length>.25f,"trail centerline has well conditioned dense segments");
            if(j+1<path.size()&&path[j+1].route==b.route){
                const auto&c=path[j+1];float ux=c.x-b.x,uz=c.z-b.z;
                float turn=(dx*ux+dz*uz)/(length*std::hypot(ux,uz));
                if(b.x*b.x+(b.z-8)*(b.z-8)>21*21)
                    require(turn>.94f,"trail bends have continuous gradual headings outside the open camp turnaround");
                if(turn<.9999f)++curved_spans;
            }
            // Dense centerlines need midpoint checks: a previous test starting
            // 3 m into each segment silently skipped all the curved geometry.
            for(float distance=length*.5f;distance<length;distance+=length){
                ++route_checks;
                float t=distance/length,x=a.x+dx*t,z=a.z+dz*t;
                float h1=expedition_height(mode,x-dx/length,z-dz/length);
                float h2=expedition_height(mode,x+dx/length,z+dz/length);
                float grade=std::abs(h2-h1)*.5f;max_grade=std::max(max_grade,grade);
                require(grade<(technical_route(mode,a.route)?.49f:.39f),"graded connected trail remains climbable");
                if(x*x+(z-8)*(z-8)>24*24){
                    float error=std::abs(expedition_height(mode,x,z)-(a.h+(b.h-a.h)*t));
                    if(error>=.35f)std::fprintf(stderr,"route height mismatch mode=%d route=%d x=%.3f z=%.3f error=%.3f\n",mode,a.route,x,z,error);
                    require(error<.35f,"heightfield preserves authored trail elevation");
                }
            }
        }
        require(route_checks>600&&curved_spans>80,"route slope checks cover the winding network");
        require(total_length>expect.min_route_length,"substantial connected exploration route network");
        const auto &trees=expedition_obstacles(mode);
        require(trees.size()>expect.min_trees&&trees.size()<expect.max_trees,"native vegetation matches the region's cover");
        int birches=0;
        for(auto &tree:trees){
            auto trail=nearest_trail(mode,tree.x,tree.z);
            require(trail.distance>=trail.width+1.7f,"tree collider clears route");
            require(expedition_normal(mode,tree.x,tree.z).y>=.78f,"trees rooted on suitable slope");
            require(lake_distance(mode,tree.x,tree.z)>=1.14f,"tree root outside lake");
            if(tree.type==3)++birches;
        }
        require(birches>=expect.min_birches&&birches<=expect.max_birches,"map specific forest species");
        // The routes have to be one network, not a set of separate loops that
        // happen to share a map. Anchors that coincide are junctions; walking
        // those from camp must reach every anchor of every route.
        {
            auto key=[](const ExpeditionTrailPoint &p){
                return std::make_pair(int(std::lround(p.x*8)),int(std::lround(p.z*8)));
            };
            const auto &anchors=trail_anchors(mode);
            std::map<std::pair<int,int>,std::set<size_t>> at;
            for(size_t i=0;i<anchors.size();++i)at[key(anchors[i])].insert(i);
            std::vector<bool> seen(anchors.size(),false);
            std::queue<size_t> pending;
            for(size_t i:at[{0,64}])pending.push(i),seen[i]=true;
            require(!pending.empty(),"the network starts at camp");
            while(!pending.empty()){
                const size_t i=pending.front();pending.pop();
                for(size_t j:at[key(anchors[i])])if(!seen[j]){seen[j]=true;pending.push(j);}
                for(size_t j:{i?i-1:i,i+1<anchors.size()?i+1:i})
                    if(j!=i&&anchors[j].route==anchors[i].route&&!seen[j]){seen[j]=true;pending.push(j);}
            }
            std::set<int> reached;
            for(size_t i=0;i<anchors.size();++i){
                if(!seen[i])std::fprintf(stderr,"unreachable anchor route=%d at %.0f,%.0f\n",anchors[i].route,anchors[i].x,anchors[i].z);
                require(seen[i],"every route is reachable from camp over the shared network");
                reached.insert(anchors[i].route);
            }
            require(int(reached.size())==route_count(mode),"every declared route is present in the network");
            // A route that shares no anchor with another route is a private
            // loop, and the map would advertise a connection it does not have.
            for(int route=0;route<route_count(mode);++route){
                bool shared=false;
                for(size_t i=0;i<anchors.size()&&!shared;++i){
                    if(anchors[i].route!=route)continue;
                    for(size_t j:at[key(anchors[i])])if(anchors[j].route!=route)shared=true;
                }
                if(!shared)std::fprintf(stderr,"route %d of map %d joins nothing\n",route,mode);
                require(shared||route_count(mode)==1,"each route hands off to another route");
            }
        }
        const auto &rocks=expedition_rocks(mode);
        require(rocks.size()>35,"natural bedrock network contains substantial exact rock geometry");
        float max_violation=0;
        for(auto &rock:rocks){
            require(rock.triangles.size()>220,"rounded rock hull has real sub-meter curved geometry");
            std::map<std::pair<int,int>,int>edges;
            for(size_t f=0;f<rock.triangles.size();++f){
                auto tri=rock.triangles[f];auto normal=rock.triangle_normals[f];
                for(auto p:rock.vertices)max_violation=std::max(max_violation,normal.dot(p-rock.vertices[tri[0]]));
                for(int edge=0;edge<3;++edge){int a=tri[edge],b=tri[(edge+1)%3];if(a>b)std::swap(a,b);++edges[{a,b}];}
            }
            for(auto edge:edges){
                if(edge.second!=2)std::fprintf(stderr,"bad hull center %.2f %.2f edge=%d,%d uses=%d faces=%zu\n",rock.center.x,rock.center.z,edge.first.first,edge.first.second,edge.second,rock.triangles.size());
                require(edge.second==2,"rock contact hull is closed manifold");
            }
            require(rock_distance(rock,rock.center).distance<0,"rock center inside collision hull");
            for(size_t sample:{size_t(7),size_t(103),size_t(211)}){
                auto tri=rock.triangles[sample];auto normal=rock.triangle_normals[sample];
                Vec3 face=(rock.vertices[tri[0]]+rock.vertices[tri[1]]+rock.vertices[tri[2]])*(1.f/3);
                auto contact=rock_distance(rock,face+normal*.027f);
                require(std::abs(contact.distance-.027f)<.0005f,"rounded collision distance matches the exact visible triangle");
                require((contact.point-face).length()<.0006f,"rock contact projects onto the exported hull surface");
            }
            float lo=10000;
            for(auto p:rock.vertices)lo=std::min(lo,p.y-expedition_height(mode,p.x,p.z));
            require(lo<-.30f,"rock formation physically buried in ground");
        }
        require(max_violation<.001f,"all hull faces bound convex contact solid");
        int standing=0;
        for(auto &rock:rocks){
            float top=-1e5f;
            for(auto p:rock.vertices)top=std::max(top,p.y-expedition_height(mode,p.x,p.z));
            if(top>2.2f)++standing;
        }
        // The fins are the point of the desert map: walls a rig drives between
        // rather than over, and every one of them an exact convex hull.
        if(expect.sand)require(standing>40,"the fin field stands real sandstone walls");
        std::printf("MAP %d height=%.1f..%.1f route=%.0fm max_grade=%.3f curvature_p99=%.4f curvature_max=%.4f trees=%zu birches=%d rock_hulls=%zu convex_error=%.7f\n",mode,*limits.first,*limits.second,total_length,max_grade,curvature99,curvature.back(),trees.size(),birches,rocks.size(),max_violation);
    }
    require(relief[0]>relief[1]*2.5f,"alpine relief distinct from glacial taiga");
    require(relief[2]>relief[1]*2.f&&relief[2]<relief[0],"redrock stands between the taiga and the alpine massif");
    std::printf("PASS expedition %d checks\n",checks);
}
