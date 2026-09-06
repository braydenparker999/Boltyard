shader_type spatial;
render_mode cull_disabled;
#include "vehicle_skin.gdshaderinc"
uniform vec4 surface_color : source_color = vec4(1.0);
uniform float material_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float paint_coat : hint_range(0.0, 1.0) = 0.0;
uniform float lamp_energy : hint_range(0.0, 3.0) = 0.0;
uniform int surface_kind = 0;

float micrograin(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + vec3(33.33));
    return fract((p.x + p.y) * p.z);
}

void fragment() {
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    vec3 finish = surface_color.rgb * COLOR.rgb;
    float roughness = material_roughness;
    float coat = paint_coat;
    float grain_scale = surface_kind == 0 ? 420.0 : 260.0;
    vec3 grain_position = bind_position * grain_scale;
    // Subpixel grain averages away instead of crawling during phone play.
    float grain_filter = 1.0 - smoothstep(0.35, 1.8, length(fwidth(grain_position)));
    float grain = (micrograin(floor(grain_position)) - 0.5) * grain_filter;
    if (surface_kind == 0) {
        float height_m = bind_position.y * body_height;
        float lower_dust = (1.0 - smoothstep(0.035, 0.39, height_m)) * 0.095;
        finish = mix(finish, vec3(0.19, 0.155, 0.105), lower_dust);
        roughness += lower_dust * 0.65 + grain * 0.025;
        coat *= 1.0 - lower_dust * 3.0;
        // Continuous millimetre-scale pressed-sheet crown bends reflected sky
        // highlights across hoods and doors; no displacement or seam movement.
        vec3 rest_normal = normalize(bind_normal);
        float top_panel = pow(abs(rest_normal.y), 8.0);
        float side_panel = pow(abs(rest_normal.x), 8.0);
        float across = clamp((bind_position.x - 0.5) * 2.0, -1.1, 1.1);
        float crown = 0.014 * (1.0 - across*across) * top_panel;
        crown += 0.007 * sin(clamp(height_m / 0.62, 0.0, 1.0) * 3.14159) * side_panel;
        float crease = exp(-pow((height_m - 0.31) / 0.026, 2.0)) * 0.0022 * side_panel;
        float bump = crown + crease;
        vec3 screen_x = dFdx(VERTEX);
        vec3 screen_y = dFdy(VERTEX);
        vec3 r1 = cross(screen_y, NORMAL);
        vec3 r2 = cross(NORMAL, screen_x);
        float determinant = dot(screen_x, r1);
        if (abs(determinant) > 0.00000001) {
            vec3 gradient = sign(determinant) * (dFdx(bump)*r1 + dFdy(bump)*r2);
            NORMAL = normalize(abs(determinant)*NORMAL - gradient);
        }
    } else if (surface_kind == 6 || surface_kind == 7) {
        // Carbon-black rubber has a broad satin response, distinct from paint.
        roughness += grain * 0.055;
        finish *= 1.0 + grain * 0.055;
    } else if (surface_kind == 3 || surface_kind == 8) {
        roughness += grain * 0.045;
    } else if (surface_kind == 4) {
        float fluting = 0.96 + 0.04 * sin(bind_position.x * 320.0);
        finish *= fluting;
    }
    ALBEDO = finish;
    ROUGHNESS = clamp(roughness, 0.06, 1.0);
    METALLIC = material_metallic;
    SPECULAR = surface_kind == 0 ? 0.16 : (surface_kind == 6 || surface_kind == 7 ? 0.38 : 0.50);
    CLEARCOAT = coat;
    CLEARCOAT_ROUGHNESS = 0.20;
    EMISSION = surface_color.rgb * lamp_energy;
}
