shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 deep_color : source_color = vec4(0.055, 0.15, 0.175, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.26, 0.31, 0.22, 1.0);
uniform sampler2D ripple_normal : hint_normal, repeat_enable, filter_linear_mipmap;
varying vec3 lake_position;
void vertex() { lake_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = lake_position.xz;
    // Two advecting, irregular ripple fields avoid repeating sine bands at
    // shallow viewing angles. They perturb the reflected sky, not geometry.
    vec2 a = texture(ripple_normal, p * 0.018 + TIME * vec2(0.003, -0.002)).xy * 2.0 - 1.0;
    vec2 q = vec2(p.x * 0.73 - p.y * 0.68, p.x * 0.68 + p.y * 0.73);
    vec2 b = texture(ripple_normal, q * 0.037 + TIME * vec2(-0.002, 0.003)).xy * 2.0 - 1.0;
    vec2 wave = a * 0.15 + b * 0.075;
    NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-wave.x, 1.0, -wave.y)), 0.0)).xyz);
    float depth = smoothstep(0.0, 0.65, COLOR.r);
    ALBEDO = mix(shallow_color.rgb, deep_color.rgb, depth);
    METALLIC = mix(0.01, 0.06, depth);
    ROUGHNESS = mix(0.36, 0.28, depth);
    SPECULAR = 0.76;
}
