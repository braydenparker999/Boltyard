shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D rock_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform bool ground_surface = false;
uniform bool detailed_surface = true;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
    world_normal=MODEL_NORMAL_MATRIX*NORMAL;
}
void fragment() {
    vec3 n=normalize(world_normal), p=world_position;
    vec3 w=pow(abs(n),vec3(4.));w/=max(dot(w,vec3(1.)),.001);
    vec3 texture_color=texture(rock_texture,p.xz*.24).rgb*w.y
        +texture(rock_texture,p.zy*.24).rgb*w.x+texture(rock_texture,p.xy*.24).rgb*w.z;
    float grain=dot(texture_color,vec3(.30,.50,.20));
    float macro=texture(rock_texture,p.xz*.027+p.y*.009).r;
    // Sedimentary bedding follows world elevation across neighbouring blocks.
    // Large mineral bands and fine texture read without displacement or parallax.
    float strata=p.y*.83+sin(p.x*.022+p.z*.014)*.7+macro*.8;
    float seam=1.-smoothstep(.018,.082,abs(fract(strata)-.5));
    float band=.88+.12*sin(strata*6.28318);
    vec3 warm=mix(vec3(.47,.245,.135),vec3(.79,.52,.32),clamp(grain*1.6,0.,1.));
    warm*=band*mix(.89,1.10,macro)*mix(1.,.70,seam*(1.-abs(n.y)));
    vec3 sand=vec3(.65,.43,.27)*mix(.83,1.15,grain);
    float stone=ground_surface?clamp(COLOR.r,0.,1.):1.;
    ALBEDO=mix(sand,warm,stone)*(ground_surface?1.:mix(.82,1.,COLOR.a));
    ROUGHNESS=.94;SPECULAR=.16;
    if(detailed_surface) {
        vec2 uv=p.xz;vec3 tangent=vec3(1,0,0),bitangent=vec3(0,0,-1);
        if(w.x>w.y&&w.x>w.z){uv=p.zy;tangent=vec3(0,0,1);bitangent=vec3(0,-1,0);}
        else if(w.z>w.y){uv=p.xy;bitangent=vec3(0,-1,0);}
        vec2 normal_grain=texture(rock_normal,uv*.24).rg*2.-1.;
        vec3 bump=tangent*normal_grain.x+bitangent*normal_grain.y;
        bump-=n*dot(bump,n);
        float near_detail=1.-smoothstep(12.,48.,distance(CAMERA_POSITION_WORLD,p));
        NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+bump*.19*near_detail),0)).xyz);
    }
}
