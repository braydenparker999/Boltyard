#include "soft_rig.hpp"
#include "expedition_terrain.hpp"
namespace boltyard {
#include "expedition_rocks.hpp"
}
#include <cstdio>
#include <cstdlib>
#include <map>
using namespace boltyard;
static int checks=0;
static void require(bool value,const char*name){++checks;if(!value){std::fprintf(stderr,"FAIL %s\n",name);std::exit(1);}}
int main(){
    float ranges[2];
    for(int mode:{4,5}){
        using namespace expedition_detail;
        const auto &map=cache(mode);
        require(map.height.size()==size_t(side)*side,"complete map cache");
        require(std::abs(expedition_height(mode,0,8))<1e-6f,"camp is level at origin");
        auto limits=std::minmax_element(map.height.begin(),map.height.end());
        ranges[mode-4]=*limits.second-*limits.first;
        require(ranges[mode-4]>(mode==4?80.f:18.f),"landscape has intended alpine or lowland relief");
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
        require(curvature99<(mode==4?.10f:.075f),"eroded terrain avoids pervasive sharp changes of grade");
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
        if(mode==4){
            require(surface_count[ExpeditionWetRock]>25,"wet exposed rock exists at the alpine shore");
            require(mean_grip(ExpeditionDryRock)>mean_grip(ExpeditionWetRock)+.15f,"wet bedrock has meaningfully lower friction");
        }
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
                require(grade<(a.route>=2?.49f:.39f),"graded connected trail remains climbable");
                if(x*x+(z-8)*(z-8)>24*24){
                    float error=std::abs(expedition_height(mode,x,z)-(a.h+(b.h-a.h)*t));
                    if(error>=.35f)std::fprintf(stderr,"route height mismatch mode=%d route=%d x=%.3f z=%.3f error=%.3f\n",mode,a.route,x,z,error);
                    require(error<.35f,"heightfield preserves authored trail elevation");
                }
            }
        }
        require(route_checks>600&&curved_spans>80,"route slope checks cover the winding network");
        require(total_length>1700,"substantial connected exploration route network");
        const auto &trees=expedition_obstacles(mode);
        require(trees.size()>1000,"dense native forest");
        int birches=0;
        for(auto &tree:trees){
            auto trail=nearest_trail(mode,tree.x,tree.z);
            require(trail.distance>=trail.width+1.7f,"tree collider clears route");
            require(expedition_normal(mode,tree.x,tree.z).y>=.78f,"trees rooted on suitable slope");
            require(lake_distance(mode,tree.x,tree.z)>=1.14f,"tree root outside lake");
            if(tree.type==3)++birches;
        }
        require(mode==4?birches==0:birches>400,"map specific forest species");
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
        std::printf("MAP %d height=%.1f..%.1f route=%.0fm max_grade=%.3f curvature_p99=%.4f curvature_max=%.4f trees=%zu birches=%d rock_hulls=%zu convex_error=%.7f\n",mode,*limits.first,*limits.second,total_length,max_grade,curvature99,curvature.back(),trees.size(),birches,rocks.size(),max_violation);
    }
    require(ranges[0]>ranges[1]*2.5f,"alpine relief distinct from glacial taiga");
    std::printf("PASS expedition %d checks\n",checks);
}
