shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 lake_position;
void vertex() { lake_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    // Low-amplitude waves change the reflection normal, not the water's color.
    // An explicit world normal avoids requiring mesh tangent attributes.
    vec2 p = lake_position.xz;
    float dx = sin(dot(p, vec2(0.40, 0.24)) + TIME * 0.60) * 0.035
        + sin(dot(p, vec2(0.70, -0.40)) - TIME * 0.40) * 0.018;
    float dz = cos(dot(p, vec2(0.13, 0.31)) - TIME * 0.45) * 0.024;
    NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-dx, 1.0, -dz)), 0.0)).xyz);
    ALBEDO = vec3(0.035, 0.105, 0.12);
    METALLIC = 0.28;
    ROUGHNESS = 0.28;
    SPECULAR = 0.7;
}
