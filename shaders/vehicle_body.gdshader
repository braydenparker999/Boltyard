shader_type spatial;
render_mode cull_disabled;
#include "vehicle_skin.gdshaderinc"
uniform vec4 surface_color : source_color = vec4(1.0);
uniform float material_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float paint_coat : hint_range(0.0, 1.0) = 0.0;
uniform float lamp_energy : hint_range(0.0, 3.0) = 0.0;
void fragment() {
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    ALBEDO = surface_color.rgb * COLOR.rgb;
    ROUGHNESS = material_roughness;
    METALLIC = material_metallic;
    SPECULAR = 0.55;
    CLEARCOAT = paint_coat;
    CLEARCOAT_ROUGHNESS = 0.22;
    EMISSION = surface_color.rgb * lamp_energy;
}
