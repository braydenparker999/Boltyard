shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;
uniform sampler2D branch_texture : source_color, filter_linear_mipmap;
void fragment() {
    vec4 branch = texture(branch_texture, UV);
    ALBEDO = branch.rgb * COLOR.rgb * vec3(0.83, 0.89, 0.82);
    ALPHA = branch.a;
    ALPHA_SCISSOR_THRESHOLD = 0.44;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    // Two-sided boughs retain a little diffuse fill on their underside.
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    BACKLIGHT = branch.rgb * 0.12;
}
