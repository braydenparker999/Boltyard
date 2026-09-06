shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;
uniform sampler2D branch_texture : source_color, filter_linear_mipmap;
uniform bool birch = false;
uniform bool leaf_geometry = false;
varying vec3 tree_position;
void vertex() { tree_position=VERTEX; }
void fragment() {
    vec4 branch=texture(branch_texture,UV);
    if(leaf_geometry) { branch=vec4(.23,.34,.105,1.); }
    vec3 tint=birch ? vec3(.86,1.,.73) : vec3(.50,.70,.55);
    ALBEDO=branch.rgb*COLOR.rgb*tint;
    ALPHA=branch.a;
    ALPHA_SCISSOR_THRESHOLD=.43;
    if(!FRONT_FACING) { NORMAL=-NORMAL; }
    ROUGHNESS=1.;
    BACKLIGHT=ALBEDO*mix(.16,.27,float(birch));
}
