shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
varying vec3 p;
varying vec3 n;
float noise3(vec3 v) {return sin(v.x*1.8+sin(v.z*1.3))*sin(v.z*2.4+v.y*.7);}
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;n=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment(){
 vec3 normal=normalize(n); vec3 w=pow(abs(normal),vec3(4));w/=w.x+w.y+w.z;
 vec3 detail=texture(grain,p.zy*.65).rgb*w.x+texture(grain,p.xz*.65).rgb*w.y+texture(grain,p.xy*.65).rgb*w.z;
 float bedding=p.y*8.0+p.x*.19+p.z*.1+noise3(p*.55)*.65;
 float strata=sin(bedding)*.5+.5;
 float seam=1.0-smoothstep(.025,.11,abs(sin(p.y*1.7+p.x*.37-p.z*.13+noise3(p*.8)*.45)));
 float mottling=noise3(p*2.1)*.5+.5;
 vec3 stone=mix(vec3(.20,.145,.105),vec3(.34,.255,.19),strata*.45+mottling*.25);
 stone*=.7+detail*1.1;
 stone=mix(stone,vec3(.48,.45,.38),seam*.32);
 float polish=smoothstep(.82,.98,normal.y)*(.5+.5*noise3(p*.8));
 ALBEDO=stone*(1.0-polish*.12);ROUGHNESS=mix(.94,.68,polish);SPECULAR=.24;
 // Submillimetre shading relief only; climbable silhouette is native geometry.
 float relief=dot(detail,vec3(.333))*.012;
 vec3 dx=dFdx(p),dy=dFdy(p);vec3 bump=cross(dy,normal)*dFdx(relief)+cross(normal,dx)*dFdy(relief);
 NORMAL=normalize((VIEW_MATRIX*vec4(normal-bump*12.0,0)).xyz);
}
