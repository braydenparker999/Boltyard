shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D forest_floor : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D trail_gravel : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D granite : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D soil_normal : hint_normal, repeat_enable, filter_linear_mipmap;
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
    vec2 rotated = vec2(p.x*.8 + p.y*.6, p.y*.8 - p.x*.6);
    float broad = noise(p*.031);
    float patches = noise(rotated*.14 + vec2(19.7,3.1));
    vec3 floor_a = texture(forest_floor, p*.34).rgb;
    vec3 floor_b = texture(forest_floor, rotated*.117 + vec2(.27,.71)).rgb;
    vec3 floor_color = mix(floor_a, floor_b, .18) * mix(vec3(.82,.82,.68),vec3(.66,.80,.57),broad);
    floor_color *= mix(1.0,.94,taiga);

    // Different, rotated scales break the square repeat without manufacturing
    // rocks or ruts that have no corresponding native contact surface.
    vec3 dirt_a = texture(trail_gravel, rotated*.39).rgb;
    vec3 dirt_b = texture(trail_gravel, vec2(-p.y,p.x)*.143 + vec2(.31,.63)).rgb;
    vec3 dirt = mix(dirt_a,dirt_b,.25 + patches*.13);
    dirt = mix(dirt,vec3(dot(dirt,vec3(.3,.5,.2))),.21);
    dirt *= mix(vec3(.87,.88,.83),vec3(.70,.76,.69),taiga) * mix(.84,1.10,broad);
    float loose_gravel = clamp(UV.x,0.,1.);
    dirt = mix(dirt,dirt*vec3(1.09,1.10,1.12),loose_gravel);
    if (detailed_surface && distance(CAMERA_POSITION_WORLD,world_position) < 42.) {
        float clast = dot(texture(granite,rotated*2.7).rgb,vec3(.30,.50,.20));
        float near_clasts = 1.-smoothstep(12.,42.,distance(CAMERA_POSITION_WORLD,world_position));
        dirt = mix(dirt,vec3(.24,.245,.23),smoothstep(.24,.40,clast)*loose_gravel*.36*near_clasts);
    }

    vec3 weights = pow(abs(n),vec3(4)); weights /= max(dot(weights,vec3(1)),.001);
    vec3 stone = texture(granite,p*.34).rgb;
    if (detailed_surface) {
        stone = stone * weights.y + texture(granite,world_position.zy*.34).rgb * weights.x
            + texture(granite,world_position.xy*.34).rgb * weights.z;
    }
    stone *= mix(vec3(.59,.60,.59),vec3(.68,.67,.62),broad);

    // RGB are the exact native rock/dirt/forest proportions used for grip.
    // Texture variation changes a material's grain, never its classification.
    vec3 material_weights = max(COLOR.rgb,vec3(0));
    material_weights /= max(dot(material_weights,vec3(1)),.001);
    float wet = clamp(COLOR.a,0.,1.);
    vec3 base = stone*material_weights.r + dirt*material_weights.g + floor_color*material_weights.b;
    ALBEDO = base * mix(1.0,.56,wet);
    ROUGHNESS = mix(.96,.57,wet);
    SPECULAR = mix(.14,.30,wet);
    if (detailed_surface) {
        float near_detail = 1.0-smoothstep(9.0,42.0,distance(CAMERA_POSITION_WORLD,world_position));
        vec2 rock_grain = texture(detail_normal,p*.76).rg*2.-1.;
        vec2 soil_grain = texture(soil_normal,rotated*.63).rg*2.-1.;
        soil_grain = vec2(soil_grain.x*.8-soil_grain.y*.6,soil_grain.x*.6+soil_grain.y*.8);
        vec2 grain = mix(soil_grain,rock_grain,material_weights.r);
        vec3 perturbation = vec3(grain.x,0,-grain.y);
        perturbation -= n*dot(perturbation,n);
        vec3 bumped = normalize(n+perturbation*.16*near_detail);
        NORMAL = normalize((VIEW_MATRIX*vec4(bumped,0)).xyz);
    }
}
