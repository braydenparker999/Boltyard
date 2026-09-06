shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2D mineral_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_grain : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool detailed_surface = true;
varying vec3 p;

void vertex() { p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
    vec3 macro = texture(mineral_noise, p.xz * .021).rgb;
    vec3 aggregate = texture(mineral_noise, p.xz * .48).rgb;
    float grain = texture(stone_grain, p.xz * 1.15).r;
    float meander = sin(p.z * .14) * .16 + sin(p.z * .39) * .08;
    float main_line = 1.0 - smoothstep(1.7, 3.5, abs(p.x - meander));
    float bypass = 1.0 - smoothstep(.70, 1.5, abs(abs(p.x - meander) - 4.8));
    float loose_line = (1.0 - smoothstep(.75, 1.7, abs(p.x - 8.8 - meander * 2.0)))
        * smoothstep(-45.0, -39.0, p.z) * (1.0 - smoothstep(-8.0, -3.0, p.z));
    float worn = max(main_line, max(bypass * .72, loose_line * .72));
    // Silt, weathered gravel islands and worn pale grit; no tiled sand ripples.
    float islands = smoothstep(.36, .68, macro.r + macro.b * .13);
    vec3 earth = mix(vec3(.225, .169, .112), vec3(.38, .287, .184), islands);
    earth = mix(earth, vec3(.425, .34, .244), worn * (.30 + macro.g * .32));
    earth *= .81 + aggregate.r * .22 + grain * .26;
    float small_stones = smoothstep(.61, .77, aggregate.b) * (1.0 - worn * .6);
    earth = mix(earth, vec3(.39, .337, .251) * (.75 + grain * .5), small_stones * .50);
    ALBEDO = earth * COLOR.rgb;
    ROUGHNESS = .97;
    SPECULAR = .12;
    if (detailed_surface) {
        float relief = aggregate.g * .0012 + grain * .0008;
        vec3 dpdx = dFdx(p), dpdy = dFdy(p);
        vec3 n = vec3(0.0, 1.0, 0.0);
        vec3 r1 = cross(dpdy, n), r2 = cross(n, dpdx);
        float determinant = dot(dpdx, r1);
        vec3 gradient = sign(determinant) * (dFdx(relief) * r1 + dFdy(relief) * r2);
        NORMAL = normalize((VIEW_MATRIX * vec4(normalize(abs(determinant) * n - gradient), 0.0)).xyz);
    }
}
