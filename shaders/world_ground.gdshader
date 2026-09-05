shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grass_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform bool detailed_surface = true;
varying vec3 world_position;
varying vec3 world_normal;
float patch_hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 34.45);
    return fract(p.x * p.y);
}
float patch_noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(patch_hash(i), patch_hash(i + vec2(1.0, 0.0)), f.x),
               mix(patch_hash(i + vec2(0.0, 1.0)), patch_hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
    vec2 p = world_position.xz;
    vec3 n = normalize(world_normal);
    // Source-color samplers perform the sRGB conversion that vertex tinting
    // lacked in v0.3. Terrain vertex colors contain only material weights.
    vec3 grass = texture(grass_albedo, p * 0.25).rgb;
    vec3 dirt = texture(dirt_albedo, p * 0.32).rgb;
    vec3 weights = pow(abs(n), vec3(5.0));
    weights /= max(weights.x + weights.y + weights.z, 0.001);
    vec3 rock;
    if (detailed_surface) {
        rock = texture(rock_albedo, world_position.zy * 0.27).rgb * weights.x
             + texture(rock_albedo, p * 0.27).rgb * weights.y
             + texture(rock_albedo, world_position.xy * 0.27).rgb * weights.z;
    } else {
        vec2 cliff_uv = abs(n.x) > abs(n.z) ? world_position.zy : world_position.xy;
        rock = texture(rock_albedo, (n.y > 0.74 ? p : cliff_uv) * 0.27).rgb;
    }
    // Slow, coherent vegetation islands are distinct from metre-scale worn
    // earth. This prevents the entire valley reading as one noisy green skin.
    float macro = patch_noise(p * 0.024 + vec2(world_position.y * 0.010, 0.0));
    float wear = patch_noise(p * 0.13 + vec2(7.3, 2.8));
    float vegetation = smoothstep(0.24, 0.76, macro + (wear - 0.5) * 0.22);
    vec3 dry_grass = grass * vec3(1.09, 1.00, 0.80);
    vec3 sage_grass = grass * vec3(0.61, 0.76, 0.61);
    grass = mix(dry_grass, sage_grass, vegetation);
    grass = mix(dirt * 0.78, grass, smoothstep(0.20, 0.53, macro + (wear - 0.5) * 0.42));
    rock = mix(rock, vec3(dot(rock, vec3(0.26, 0.54, 0.20))), 0.42) * vec3(0.79, 0.85, 0.89);
    float trail = smoothstep(0.02, 0.95, COLOR.r);
    float stone = smoothstep(0.10, 0.87, COLOR.g * 1.24 + (wear - 0.5) * 0.14);
    stone *= mix(0.72, 1.0, smoothstep(0.10, 0.35, 1.0 - n.y));
    vec3 base = mix(grass, dirt, trail);
    base = mix(base, rock, stone * (1.0 - trail * 0.45));
    base = mix(base, dirt * vec3(0.67, 0.72, 0.69), COLOR.b * 0.84);
    ALBEDO = base;
    ROUGHNESS = mix(0.97, 0.88, stone);
    SPECULAR = 0.13;
    if (detailed_surface) {
        vec3 fine = mix(texture(grass_normal, p * 0.25).rgb,
                        texture(dirt_normal, p * 0.32).rgb, trail) * 2.0 - 1.0;
        vec3 rock_fine = texture(rock_normal, p * 0.27).rgb * 2.0 - 1.0;
        fine = mix(fine, rock_fine, stone);
        vec3 detailed = normalize(n + vec3(fine.x, 0.0, -fine.y) * 0.72);
        NORMAL = normalize((VIEW_MATRIX * vec4(detailed, 0.0)).xyz);
    }
}
