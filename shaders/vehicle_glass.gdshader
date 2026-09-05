shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
#include "vehicle_skin.gdshaderinc"
uniform vec4 surface_color : source_color = vec4(0.085, 0.14, 0.17, 0.70);
void fragment() {
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 5.0);
    // Dielectric automotive glass uses the same captured valley/sky radiance
    // as the coated paint. A light tint leaves the cabin visible face-on.
    ALBEDO = surface_color.rgb;
    ROUGHNESS = 0.085;
    METALLIC = 0.0;
    SPECULAR = 0.50;
    CLEARCOAT = 0.20;
    CLEARCOAT_ROUGHNESS = 0.07;
    ALPHA = mix(surface_color.a, 0.97, fresnel);
}
