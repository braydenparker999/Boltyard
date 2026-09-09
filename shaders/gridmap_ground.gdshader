shader_type spatial;
render_mode cull_back, diffuse_burley;
uniform sampler2D material_blend:filter_nearest,repeat_disable;
uniform sampler2DArray base_color:source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2DArray detail_color:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2DArray detail_normal:filter_linear_mipmap_anisotropic,repeat_enable;
uniform float tile_size[10];
uniform float detail_strength[10];
uniform bool detailed_surface=true;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex(){
 world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
vec3 layer_color(int id,vec2 uv){
 vec3 base=texture(base_color,vec3(uv/2048.0,float(id))).rgb;
 vec3 detail=texture(detail_color,vec3(uv/max(tile_size[id],.01),float(id))).rgb;
 // Compatibility requires source modulation to be linearized before lighting.
 if(OUTPUT_IS_SRGB){base=pow(base,vec3(2.2));detail=pow(detail,vec3(2.2));}
 return clamp(base*mix(vec3(1.0),detail*4.0,detail_strength[id]),vec3(0),vec3(1));
}
void fragment(){
 vec3 blend=texture(material_blend,(world_pos.xz+vec2(512.5))/1025.0).rgb;
 int a=int(round(blend.r*255.0));int b=int(round(blend.g*255.0));
 vec2 uv=vec2(world_pos.x,-world_pos.z);
 ALBEDO=mix(layer_color(b,uv),layer_color(a,uv),blend.b);
 ROUGHNESS=a==9?.16:.9;SPECULAR=a==9?.4:.12;
 if(detailed_surface){
  vec4 na=texture(detail_normal,vec3(uv/max(tile_size[a],.01),float(a)));
  vec4 nb=texture(detail_normal,vec3(uv/max(tile_size[b],.01),float(b)));
  vec4 sample_n=mix(nb,na,blend.b);
  vec3 n=normalize(world_normal);
  vec3 tangent=normalize(vec3(1,0,0)-n*n.x);
  vec3 bitangent=normalize(cross(tangent,n));
  vec2 bump=(sample_n.rg*2.0-1.0)*.25;
  NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+tangent*bump.x+bitangent*bump.y),0.0)).xyz);
  ROUGHNESS=a==9?.16:clamp(sample_n.a,.5,1.0);
 }
}
