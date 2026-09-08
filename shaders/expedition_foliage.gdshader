shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;
uniform sampler2D branch_texture : source_color, filter_linear_mipmap;
uniform bool birch = false;
uniform bool desert = false;
uniform bool leaf_geometry = false;
varying vec3 tree_position;
void vertex() { tree_position=VERTEX; }
void fragment() {
    vec4 branch=texture(branch_texture,UV);
    if(leaf_geometry) { branch=vec4(.23,.34,.105,1.); }
    vec3 tint=birch ? vec3(.86,1.,.73) : (desert ? vec3(1.02,.96,.62) : vec3(.50,.70,.55));
    // The branch photograph is a saturated green frond. Juniper is grey-green,
    // so on the desert map most of that saturation is pulled out before the
    // tint is applied and the photograph is kept for its shape and detail.
    vec3 foliage=desert
        ? mix(branch.rgb, vec3(dot(branch.rgb, vec3(.30,.59,.11))), .62)
        : branch.rgb;
    ALBEDO=foliage*COLOR.rgb*tint;
    ALPHA=branch.a;
    ALPHA_SCISSOR_THRESHOLD=.43;
    if(!FRONT_FACING) { NORMAL=-NORMAL; }
    ROUGHNESS=1.;
    BACKLIGHT=ALBEDO*mix(desert ? .21 : .16,.27,float(birch));
}
