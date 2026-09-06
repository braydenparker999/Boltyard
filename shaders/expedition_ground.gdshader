shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D forest_floor : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D trail_gravel : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D granite : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform bool detailed_surface = true;
uniform float taiga = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 p) { p = fract(p * vec2(123.34, 345.45)); p += dot(p, p + 34.345); return fract(p.x * p.y); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1)).xyz;
    world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec2 p = world_position.xz;
    float broad = noise(p * 0.035);
    float grains = noise(p * 1.1);
    vec3 floor_a = texture(forest_floor, p * 0.22).rgb;
    vec3 floor_b = texture(forest_floor, vec2(p.y,-p.x) * 0.071 + vec2(0.27)).rgb;
    vec3 floor_color = mix(floor_a, floor_b, 0.20) * mix(vec3(.50,.62,.40), vec3(.76,.75,.55), broad);
    float moss_island=smoothstep(.38,.68,noise(p*.13)+noise(p*.037)*.20);
    vec3 moss=texture(forest_floor,p*.40).rgb*vec3(.32,.58,.25);
    floor_color=mix(floor_color,moss,moss_island*mix(.40,.68,taiga));
    vec3 dirt = texture(trail_gravel, p * .46).rgb;
    dirt = mix(dirt, vec3(dot(dirt,vec3(.3,.5,.2))), .26) * mix(vec3(.82,.84,.82),vec3(.70,.72,.66),taiga);
    vec3 weights = pow(abs(n),vec3(5)); weights /= max(dot(weights,vec3(1)),.001);
    vec3 stone = texture(granite,p*.37).rgb;
    if (detailed_surface) {
        stone = stone * weights.y + texture(granite,world_position.zy*.37).rgb * weights.x
            + texture(granite,world_position.xy*.37).rgb * weights.z;
        stone = mix(stone,texture(granite,p*.075).rgb,.13);
    }
    float rock = clamp(COLOR.r + (1.0-n.y)*.7 + (grains-.5)*.13,0.,1.);
    float dirt_amount = clamp(COLOR.g + (grains-.5)*.12,0.,1.);
    vec3 base = mix(floor_color,dirt,dirt_amount);
    base = mix(base,stone * mix(.41,.55,broad),rock);
    base *= mix(1.0,.57,COLOR.a);
    ALBEDO = base;
    ROUGHNESS = mix(.97,.60,COLOR.a);
    SPECULAR = mix(.12,.28,COLOR.a);
    if (detailed_surface) {
        vec3 fine = texture(detail_normal,p*.52).rgb*2.-1.;
        vec3 bumped = normalize(n + vec3(fine.x,0,-fine.y)*mix(.30,.48,rock));
        NORMAL = normalize((VIEW_MATRIX*vec4(bumped,0)).xyz);
    }
}
