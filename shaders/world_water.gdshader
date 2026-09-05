shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 lake_position;
void vertex() { lake_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float ripple = sin(lake_position.x * 1.6 + TIME * 0.7) * 0.026 + cos(lake_position.z * 1.9 - TIME * 0.5) * 0.021;
    ALBEDO = vec3(0.055, 0.18, 0.17) + ripple;
    METALLIC = 0.35;
    ROUGHNESS = 0.17;
    SPECULAR = 0.8;
    NORMAL_MAP = normalize(vec3(ripple * 2.0, cos(lake_position.x * 0.8 + lake_position.z + TIME) * 0.045, 1.0)) * 0.5 + 0.5;
}
