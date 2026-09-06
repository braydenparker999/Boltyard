shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform bool birch = false;
varying vec3 tree_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() { tree_position=VERTEX; }
void fragment() {
    float stripe=sin(UV.x*135.+sin(UV.y*51.)*.9);
    vec3 bark=mix(vec3(.115,.096,.073),vec3(.25,.205,.147),smoothstep(-.8,.8,stripe));
    if(birch) {
        vec2 cell=floor(UV*vec2(12,38));
        float mark=step(.83,hash(cell))*step(fract(UV.y*38.),.16+hash(cell+1.)*.15);
        bark=mix(vec3(.65,.665,.59),vec3(.11,.12,.102),mark);
        bark*=mix(.78,1.0,clamp(UV.y*3.,0.,1.));
    }
    ALBEDO=bark*COLOR.rgb;
    ROUGHNESS=1.;
}
