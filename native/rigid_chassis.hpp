#pragma once
// Included after Particle. A mass-weighted rigid cluster preserves the existing
// physical attachment nodes while replacing all frame/cab elastic constraints.
// Shape matching projects their positions onto one rigid transform. Velocity
// projection preserves the cluster's linear and angular momentum.
struct RigidChassis {
    std::array<Vec3,16> local{};
    std::array<double,16> mass{};
    double total_mass=0;
    static double dotd(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
    static Vec3 scale(Vec3 v,double s){return {v.x*s,v.y*s,v.z*s};}
    static Vec3 unit(Vec3 v){const double n=std::sqrt(dotd(v,v));return n>1e-14?scale(v,1/n):Vec3{};}
    struct Matrix {
        Vec3 col[3]{{1,0,0},{0,1,0},{0,0,1}};
        Vec3 apply(Vec3 p) const {return scale(col[0],p.x)+scale(col[1],p.y)+scale(col[2],p.z);}
        Vec3 solve(Vec3 p) const {
            const double det=dotd(col[0],col[1].cross(col[2]));
            if(std::abs(det)<1e-16)return {};
            return {dotd(col[1].cross(col[2]),p)/det,dotd(col[2].cross(col[0]),p)/det,dotd(col[0].cross(col[1]),p)/det};
        }
    };
    Matrix rotation;
    Vec3 center;
    void initialize(const std::vector<Particle>& particles){
        total_mass=0;center={};rotation=Matrix{};
        for(int i=0;i<16;++i){mass[i]=1.0/particles[i].inv_mass;total_mass+=mass[i];center+=scale(particles[i].pos,mass[i]);}
        center=scale(center,1/total_mass);
        for(int i=0;i<16;++i)local[i]=particles[i].pos-center;
    }
    void project_positions(std::vector<Particle>& particles){
        if(total_mass==0)return;
        center={};for(int i=0;i<16;++i)center+=scale(particles[i].pos,mass[i]);center=scale(center,1/total_mass);
        Matrix covariance;for(auto&v:covariance.col)v={};
        for(int i=0;i<16;++i){const Vec3 p=particles[i].pos-center;
            covariance.col[0]+=scale(p,mass[i]*local[i].x);
            covariance.col[1]+=scale(p,mass[i]*local[i].y);
            covariance.col[2]+=scale(p,mass[i]*local[i].z);
        }
        // Current frame edges seed arbitrary editor/recovery rotations as well
        // as ordinary small corrections; no 180-degree polar-fit singularity.
        const Vec3 x=unit(particles[1].pos+particles[3].pos-particles[0].pos-particles[2].pos);
        Vec3 z=particles[2].pos+particles[3].pos-particles[0].pos-particles[1].pos;
        z=unit(z-scale(x,dotd(z,x)));
        if(dotd(x,x)>.5&&dotd(z,z)>.5){
            rotation.col[0]=x;rotation.col[2]=z;rotation.col[1]=unit(z.cross(x));
        }
        // Iterative polar decomposition minimizes mass-weighted displacement.
        for(int k=0;k<16;++k){
            Vec3 torque;double denominator=0;
            for(int j=0;j<3;++j){torque+=rotation.col[j].cross(covariance.col[j]);denominator+=dotd(rotation.col[j],covariance.col[j]);}
            Vec3 omega=scale(torque,1/(std::abs(denominator)+1e-18));
            const double angle=std::sqrt(dotd(omega,omega));if(angle<1e-11)break;
            const Vec3 axis=scale(omega,1/angle);const double c=std::cos(angle),s=std::sin(angle);
            for(auto&v:rotation.col)v=scale(v,c)+scale(axis.cross(v),s)+scale(axis,dotd(axis,v)*(1-c));
        }
        for(int i=0;i<16;++i)particles[i].pos=center+rotation.apply(local[i]);
    }
    void project_velocities(std::vector<Particle>& particles){
        Vec3 velocity,angular_momentum;Matrix inertia;for(auto&v:inertia.col)v={};
        for(int i=0;i<16;++i)velocity+=scale(particles[i].velocity,mass[i]);
        velocity=scale(velocity,1/total_mass);
        for(int i=0;i<16;++i){const Vec3 r=particles[i].pos-center;const double m=mass[i];
            angular_momentum+=scale(r.cross(particles[i].velocity-velocity),m);
            inertia.col[0]+=Vec3{m*(r.y*r.y+r.z*r.z),-m*r.x*r.y,-m*r.x*r.z};
            inertia.col[1]+=Vec3{-m*r.y*r.x,m*(r.x*r.x+r.z*r.z),-m*r.y*r.z};
            inertia.col[2]+=Vec3{-m*r.z*r.x,-m*r.z*r.y,m*(r.x*r.x+r.y*r.y)};
        }
        const Vec3 omega=inertia.solve(angular_momentum);
        for(int i=0;i<16;++i)particles[i].velocity=velocity+omega.cross(particles[i].pos-center);
    }
};
