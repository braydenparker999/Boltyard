shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D granite : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D forest_floor : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform bool detailed_surface = true;
uniform float taiga = 0.0;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    world_normal=MODEL_NORMAL_MATRIX*NORMAL;
}
void fragment() {
    vec3 n=normalize(world_normal);
    vec3 w=pow(abs(n),vec3(4)); w/=max(dot(w,vec3(1)),.001);
    vec3 base=texture(granite,world_position.xz*.42).rgb*w.y
        +texture(granite,world_position.zy*.42).rgb*w.x
        +texture(granite,world_position.xy*.42).rgb*w.z;
    vec3 large=texture(granite,world_position.xz*.076+world_position.y*.035).rgb;
    base=mix(base,large,.16)*COLOR.rgb*.56;
    float stratum=sin(world_position.y*3.7+sin(world_position.x*.16)*.8+world_position.z*.18);
    base*=mix(.86,1.,smoothstep(-.99,-.82,stratum));
    float moist=texture(forest_floor,world_position.xz*.045).g;
    float moss=smoothstep(.25,.46,moist)*smoothstep(.38,.88,n.y)*mix(.10,.46,taiga);
    base=mix(base,texture(forest_floor,world_position.xz*.3).rgb*vec3(.63,.78,.47),moss);
    ALBEDO=base*mix(.76,1.,COLOR.a);
    ROUGHNESS=.94;
    SPECULAR=.15;
    if(detailed_surface) {
        vec3 grain=texture(detail_normal,world_position.xz*.72).rgb*2.-1.;
        NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+vec3(grain.x,0,-grain.y)*.20),0)).xyz);
    }
}
