shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
varying vec3 terrain_position;
void vertex() { terrain_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = terrain_position.xz;
    float broad = texture(grain, p * 0.008).r;
    float grit = texture(grain, p * 0.31).r;
    float grain_fine = texture(grain, p * 1.8).r;
    vec3 ground = COLOR.rgb * (0.78 + broad * 0.24 + grit * 0.16);
    ground += (grain_fine - 0.5) * 0.065;
    ALBEDO = clamp(ground, vec3(0.025), vec3(0.85));
    ROUGHNESS = 0.92;
    SPECULAR = 0.12;
    // Fine surface relief, independent of the metre-scale contact geometry.
    float nx = texture(grain, p * 0.31 + vec2(0.007, 0.0)).r - grit;
    float ny = texture(grain, p * 0.31 + vec2(0.0, 0.007)).r - grit;
    NORMAL_MAP = normalize(vec3(-nx * 3.0, -ny * 3.0, 1.0)) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 0.32;
}
