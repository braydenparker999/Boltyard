shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec4 puff;
void vertex() { puff = INSTANCE_CUSTOM; }
void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float lobe = sin(p.x * 6.0 + puff.y * 20.0) * sin(p.y * 7.0 - puff.y * 11.0) * 0.09;
    float density = pow(clamp(1.0 - length(p) + lobe, 0.0, 1.0), 1.7);
    ALBEDO = vec3(0.40, 0.32, 0.21);
    ALPHA = density * puff.a;
}
