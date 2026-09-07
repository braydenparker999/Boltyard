shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform sampler2D ground_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rock_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D rock_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool detailed_surface = true;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec2 map_uv = (world_position.xz + vec2(1024.0)) / 2048.0;
    vec3 color = texture(ground_color, map_uv).rgb;
    float rock = texture(rock_mask, map_uv).r;
    vec2 detail_uv = world_position.xz;
    // Avoid stretching on near-vertical slopes without costly triplanar blends.
    if (abs(world_normal.y) < 0.45) {
        detail_uv = abs(world_normal.x) > abs(world_normal.z) ? world_position.zy : world_position.xy;
    }
    vec3 r = texture(rock_detail, detail_uv / 5.0).rgb;
    vec3 d = texture(dirt_detail, detail_uv / 3.0).rgb;
    float variation = mix(dot(d, vec3(0.333)), dot(r, vec3(0.333)), rock);
    ALBEDO = clamp(color * (0.72 + variation * 0.60), vec3(0.015), vec3(0.85));
    ROUGHNESS = 0.94;
}
