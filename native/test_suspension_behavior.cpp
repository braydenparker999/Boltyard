#include "soft_rig.hpp"
#include <iostream>
#include <stdexcept>
using namespace boltyard;
void check(bool b,const char*m){if(!b)throw std::runtime_error(m);}
int main(){
    float sag[2];
    for(int tuning=0;tuning<2;++tuning){
        Config c;c.ride_height=.45f;c.suspension_travel=.35f;c.spring_rate=tuning?40000:20000;
        SoftRig r;r.configure(c);r.set_terrain(3);r.set_test_rocks({});r.reset({0,1.5f,0});r.dynamic_objects().clear();
        for(int i=0;i<600;++i)r.step(1.f/120,0,0,false);
        sag[tuning]=0;
        for(int w=0;w<4;++w){
            sag[tuning]+=(r.shock_rest_length(w)-r.shock_length(w))*.25f;
            check(r.shock_length(w)>r.shock_min_length(w)+.025f,"static sag rests on bump stops");
            check(r.shock_max_length(w)-r.shock_min_length(w)+.06f<=r.shock_body_length(w),"stroke does not fit damper body");
        }
        check(r.speed()<.015f&&r.suspension_link_error()<.004f,"suspension fails to settle without stretched links");
        check(r.safety_clamp_count()==0&&r.rejected_state_count()==0,"suspension needs emergency repair");
    }
    check(sag[0]>sag[1]*1.65f&&sag[0]<sag[1]*2.35f,"spring rate does not control static sag");
    std::cout<<"SUSPENSION BEHAVIOR: soft/firm mean sag="<<sag[0]<<"/"<<sag[1]<<" m; settling and stroke packaging pass\n";
}
