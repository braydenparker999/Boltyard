shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 paint_color : source_color = vec4(0.78, 0.42, 0.22, 1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D palette_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D opacity_texture : filter_linear_mipmap_anisotropic;
void fragment() {
    vec3 palette = texture(palette_texture, UV2).rgb;
    palette /= max(dot(palette, vec3(1.0)), 0.001);
    vec3 secondary = mix(paint_color.rgb, vec3(0.48), 0.38);
    vec3 paint = paint_color.rgb * palette.r + secondary * palette.g + vec3(0.28) * palette.b;
    vec3 base = texture(base_texture, UV).rgb;
    float opacity = texture(opacity_texture, UV).r;
    vec3 orm = texture(orm_texture, UV).rgb;
    ALBEDO = mix(base, paint, opacity);
    METALLIC = mix(orm.b, 0.12, opacity);
    ROUGHNESS = mix(orm.g, clamp(orm.g, 0.32, 0.70), opacity);
    AO = orm.r;
    NORMAL_MAP = texture(normal_texture, UV).rgb;
    CLEARCOAT = 0.25 * opacity;
    CLEARCOAT_ROUGHNESS = 0.35;
}
