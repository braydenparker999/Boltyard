shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D granite : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D forest_floor : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform bool detailed_surface = true;
uniform float taiga = 0.0;
uniform float desert = 0.0;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    world_normal=MODEL_NORMAL_MATRIX*NORMAL;
}
void fragment() {
    vec3 n=normalize(world_normal);
    vec3 w=pow(abs(n),vec3(4)); w/=max(dot(w,vec3(1)),.001);
    vec3 base=texture(granite,world_position.xz*.34).rgb*w.y
        +texture(granite,world_position.zy*.34).rgb*w.x
        +texture(granite,world_position.xy*.34).rgb*w.z;
    vec3 large=texture(granite,world_position.xz*.057+world_position.y*.019).rgb;
    // Granite is a massive, scoured rock. Broad mineral variation replaces
    // repeated horizontal stripes that made every hull resemble a staircase.
    float mineral=dot(large,vec3(.30,.50,.20));
    float grain=dot(base,vec3(.30,.52,.18));
    base*=mix(vec3(.60,.61,.60),vec3(.70,.68,.63),smoothstep(.12,.55,mineral))*COLOR.rgb;
    // Redrock reuses the same photographic grain as luminance and re-keys it
    // to sandstone. Bedding follows world height, so a cut face and a fin show
    // their layers running level while the crown stays a single bed.
    if(desert>0.) {
        vec3 sandstone=mix(vec3(.375,.250,.180),vec3(.545,.415,.305),smoothstep(.12,.55,mineral));
        float bed=sin(world_position.y*2.15+mineral*6.4);
        base=mix(base,sandstone*(.64+grain*.80)*(.92+bed*.08)*COLOR.rgb,desert);
    }
    float rooted=1.-COLOR.a;
    float organic=texture(forest_floor,world_position.xz*.15).g;
    float patina=smoothstep(.12,.32,organic)*rooted*smoothstep(.3,.8,n.y)*mix(.05,.14,taiga)*(1.-desert);
    base=mix(base,base*vec3(.72,.82,.63),patina);
    // Desert varnish darkens the weathered faces instead of moss.
    base=mix(base,base*vec3(.62,.52,.46),smoothstep(.2,.55,organic)*smoothstep(.55,.1,n.y)*.34*desert);
    // UV.x is sampled from native wetness, which also reduces rock grip.
    float wet=clamp(UV.x,0.,1.);
    ALBEDO=base*mix(.80,1.,COLOR.a)*mix(1.,.56,wet);
    ROUGHNESS=mix(.92,.54,wet);
    SPECULAR=mix(.15,.30,wet);
    AO=mix(.74,1.,COLOR.a);
    if(detailed_surface) {
        // Select a local projection for the fine normal only. Surface color
        // stays smoothly triplanar; this tiny grain cannot invent a ledge.
        vec2 uv=world_position.xz;
        vec3 tangent=vec3(1,0,0),bitangent=vec3(0,0,-1);
        if(abs(n.x)>abs(n.y)&&abs(n.x)>abs(n.z)) {
            uv=world_position.zy;
            tangent=vec3(0,0,1);bitangent=vec3(0,-1,0);
        } else if(abs(n.z)>abs(n.y)) {
            uv=world_position.xy;
            tangent=vec3(1,0,0);bitangent=vec3(0,-1,0);
        }
        vec2 grain=texture(detail_normal,uv*.76).rg*2.-1.;
        vec3 perturbation=tangent*grain.x+bitangent*grain.y;
        perturbation-=n*dot(perturbation,n);
        float near_detail=1.-smoothstep(8.,40.,distance(CAMERA_POSITION_WORLD,world_position));
        NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+perturbation*.13*near_detail),0)).xyz);
    }
}
