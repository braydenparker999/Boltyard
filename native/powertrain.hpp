#pragma once
#include <algorithm>
#include <array>
#include <cmath>

namespace boltyard {
// SI shaft model. Positive wheel rates here mean forward rolling.
// Automatic converter, selectable low range, finite lock-up and engine inertia.
// Parameters describe a reference gasoline crawler, not a measured Ford engine.
struct Powertrain {
    float engine_speed=850.f*0.104719755f;
    float ratio=34.12512f, output_torque=0, converter_ratio=1;
    float shift_timer=0;
    int gear=1, direction=1;
    bool locked=false, neutral=false;
    static constexpr float engine_inertia=.65f;
    void reset(){*this=Powertrain{};}
    float rpm() const {return engine_speed*9.5492966f;}
    float update(float dt,float pedal,bool braking,bool low,float final_scale,
                 float peak_torque,float wheel_speed,float wheel_inertia){
        shift_timer=std::max(0.f,shift_timer-dt);
        if(std::abs(pedal)>.001f && (pedal*direction>0 || std::abs(wheel_speed)<.6f)) direction=pedal<0?-1:1;
        // Service brakes may oppose drive torque for controlled left-foot crawling.
        float demand=(pedal*direction<0&&std::abs(wheel_speed)>=.6f)?0.f:std::abs(pedal);
        if(low||direction<0)gear=1;
        else if(shift_timer==0){
            if(rpm()>3500 && gear<3){++gear;shift_timer=.45f;}
            else if(rpm()<1300 && gear>1){--gear;shift_timer=.45f;}
        }
        const float gears[]={3.06f,1.63f,1.f};
        ratio=gears[gear-1]*4.1f*final_scale*(low?2.72f:1.f);
        float turbine=wheel_speed*direction*ratio;
        const float torque_curve=std::clamp(1.f-std::pow((rpm()-2800.f)/4300.f,2.f),.35f,1.f);
        const float losses=peak_torque*(.045f+.00012f*engine_speed+.0000008f*engine_speed*engine_speed);
        const float idle=std::clamp((89.012f-engine_speed)*5.f,0.f,peak_torque*.30f);
        const float combustion=(rpm()<5200?peak_torque*std::pow(demand,1.35f)*torque_curve:0.f)+idle;
        engine_speed=std::max(0.f,engine_speed+(combustion-losses)*dt/engine_inertia);
        if(neutral){output_torque=0;locked=false;return 0;}
        // Release lock-up below idle to permit converter slip; engage during
        // low-range overrun, giving finite and gear-dependent engine braking.
        locked=low&&!braking&&turbine>94.f&&(demand<.05f||turbine>160.f);
        const float slip=engine_speed-turbine;
        const float reflected=ratio*ratio/std::max(.1f,wheel_inertia);
        if(locked){
            const float impulse=slip/(1/engine_inertia+reflected);
            const float limit=peak_torque*1.8f*dt;
            const float transmitted=std::clamp(impulse,-limit,limit);
            engine_speed-=transmitted/engine_inertia;
            output_torque=transmitted/dt*ratio*direction;
            converter_ratio=1;
        }else{
            const float speed_ratio=std::clamp(turbine/std::max(20.f,engine_speed),0.f,1.f);
            converter_ratio=1.f+.8f*(1-speed_ratio);
            const float coupling=(peak_torque/450.f)*(slip>=0?.55f:.3f);
            float input=coupling*slip/(1+coupling*dt*(1/engine_inertia+reflected*converter_ratio));
            input=std::clamp(input,-peak_torque*.4f,peak_torque*1.2f);
            engine_speed=std::max(0.f,engine_speed-input*dt/engine_inertia);
            output_torque=input*converter_ratio*ratio*direction;
        }
        return output_torque;
    }
};
}
