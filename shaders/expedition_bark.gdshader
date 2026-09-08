shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform bool birch = false;
uniform bool desert = false;
varying vec3 tree_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() { tree_position=VERTEX; }
void fragment() {
    float stripe=sin(UV.x*135.+sin(UV.y*51.)*.9);
    vec3 bark=mix(vec3(.115,.096,.073),vec3(.25,.205,.147),smoothstep(-.8,.8,stripe));
    // Juniper sheds its bark in long fibrous strips rather than plates.
    if(desert) {
        float strip=sin(UV.x*84.+sin(UV.y*17.)*2.4);
        bark=mix(vec3(.225,.140,.098),vec3(.435,.320,.240),smoothstep(-.7,.7,strip));
        bark*=mix(.86,1.05,fract(UV.y*4.));
    }
    if(birch) {
        vec2 cell=floor(UV*vec2(12,38));
        float mark=step(.83,hash(cell))*step(fract(UV.y*38.),.16+hash(cell+1.)*.15);
        bark=mix(vec3(.65,.665,.59),vec3(.11,.12,.102),mark);
        bark*=mix(.78,1.0,clamp(UV.y*3.,0.,1.));
    }
    ALBEDO=bark*COLOR.rgb;
    ROUGHNESS=1.;
}
