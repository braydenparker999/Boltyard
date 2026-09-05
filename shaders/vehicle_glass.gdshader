shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
#include "vehicle_skin.gdshaderinc"
uniform vec4 surface_color : source_color = vec4(0.12, 0.23, 0.24, 0.56);
void fragment() {
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
    ALBEDO = surface_color.rgb;
    ROUGHNESS = 0.12;
    METALLIC = 0.18;
    SPECULAR = 0.9;
    ALPHA = mix(surface_color.a, 0.88, fresnel);
}
