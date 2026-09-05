shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D rock_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap;
varying vec3 position_world;
varying vec3 normal_world;
void vertex() {
    position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    normal_world = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
    vec3 n = normalize(normal_world);
    vec3 w = pow(abs(n), vec3(4.0));
    w /= max(w.x + w.y + w.z, 0.001);
    vec3 rock = texture(rock_albedo, position_world.zy * 0.45).rgb * w.x
              + texture(rock_albedo, position_world.xz * 0.45).rgb * w.y
              + texture(rock_albedo, position_world.xy * 0.45).rgb * w.z;
    ALBEDO = rock * COLOR.rgb * 0.92;
    ROUGHNESS = 0.94;
    SPECULAR = 0.16;
    vec2 fine = texture(rock_normal, position_world.xz * 0.45).xy * 2.0 - 1.0;
    NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + vec3(fine.x, 0, -fine.y) * 0.45), 0.0)).xyz);
}
