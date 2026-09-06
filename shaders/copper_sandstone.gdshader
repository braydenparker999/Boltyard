shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grain : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mineral_noise : repeat_enable, filter_linear_mipmap;
uniform bool detailed_surface = true;
uniform bool material_local = false;
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 material_position;
varying vec3 material_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = MODEL_NORMAL_MATRIX * NORMAL;
    material_position = material_local ? VERTEX : world_position;
    material_normal = material_local ? NORMAL : world_normal;
}

void fragment() {
    vec3 p = material_position;
    vec3 n = normalize(world_normal);
    vec3 weight = pow(abs(normalize(material_normal)), vec3(5.0));
    weight /= dot(weight, vec3(1.0));
    // A complete mineral photograph spans 3.7 m. The world projection joins
    // all convex pieces; medium fractures remain legible at tire scale.
    vec3 photograph = texture(grain, p.zy * .27 + vec2(.17, .09)).rgb * weight.x;
    photograph += texture(grain, p.xz * .27).rgb * weight.y;
    photograph += texture(grain, p.xy * .27 + vec2(.43, .28)).rgb * weight.z;
    vec3 variation = texture(mineral_noise, p.xz * .018 + p.y * .009).rgb;
    float minerals = dot(photograph, vec3(.30, .52, .18));
    float bedding = sin(p.y * 12.0 + p.x * .075 - p.z * .11 + variation.r * 2.8);
    vec3 copper = mix(vec3(.34, .215, .145), vec3(.43, .32, .235), variation.r);
    vec3 stone = copper * (.25 + minerals * 2.20);
    stone *= .94 + bedding * .035;
    // Sparse intersecting filled quartz fractures, with mineral-dependent gaps.
    float vein_phase = p.x * .31 + p.y * 1.12 - p.z * .14 + (variation.g - .5) * .7;
    float vein = abs(sin(vein_phase));
    float vein_filter = max(.009, fwidth(vein_phase) * .7);
    float vein_coverage = .018 / max(.018, vein_filter);
    float quartz = (1.0 - smoothstep(.012 - vein_filter, .023 + vein_filter, vein)) * smoothstep(.38, .60, variation.b) * vein_coverage;
    float edge = (1.0 - smoothstep(.03, .07, vein)) * smoothstep(.38, .60, variation.b);
    stone *= 1.0 - edge * .12;
    stone = mix(stone, vec3(.59, .53, .42), quartz * .66);
    float dust = smoothstep(.62, .96, n.y) * (.11 + variation.b * .08);
    stone = mix(stone, vec3(.43, .33, .225), dust);
    // Vertex alpha carries baked rock-foot contact shade.
    ALBEDO = stone * COLOR.rgb * mix(.74, 1.0, COLOR.a);
    ROUGHNESS = mix(.96, .77, quartz);
    SPECULAR = .24;
    if (detailed_surface) {
        // Shading relief only; contact silhouettes are exported native faces.
        float relief = minerals * .004;
        vec3 dpdx = dFdx(world_position), dpdy = dFdy(world_position);
        vec3 r1 = cross(dpdy, n), r2 = cross(n, dpdx);
        float determinant = dot(dpdx, r1);
        vec3 gradient = sign(determinant) * (dFdx(relief) * r1 + dFdy(relief) * r2);
        vec3 bumped = normalize(abs(determinant) * n - gradient);
        NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
    }
}
