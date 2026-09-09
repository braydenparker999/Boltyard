shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform sampler2D ground_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D road_color : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 road_origin;
uniform sampler2D material_blend : filter_nearest, repeat_disable;
uniform sampler2DArray detail_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_scale[14];
uniform float color_strength[14];
uniform float normal_strength[14];
uniform bool detailed_surface = true;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 vec2 map_uv=(world_position.xz+vec2(1024.0))/2048.0;
 vec3 base=texture(ground_color,map_uv).rgb;
 vec3 blend=texture(material_blend,map_uv).rgb;
 int a=int(round(blend.r*255.0)); int b=int(round(blend.g*255.0));
 vec2 uv=world_position.xz;
 vec3 n=normalize(world_normal);
 vec3 tangent=normalize(vec3(1.0,0.0,0.0)-n*n.x);
 vec3 bitangent=normalize(cross(tangent,n));
 if(abs(n.y)<0.45){
  if(abs(n.x)>abs(n.z)){uv=world_position.zy;tangent=normalize(vec3(0.0,0.0,1.0)-n*n.z);}
  else {uv=world_position.xy;tangent=normalize(vec3(1.0,0.0,0.0)-n*n.x);}
  bitangent=normalize(cross(tangent,n));
 }
 vec3 ca=texture(detail_color,vec3(uv/tile_scale[a],float(a))).rgb;
 vec3 cb=texture(detail_color,vec3(uv/tile_scale[b],float(b))).rgb;
 // Source detail images are neutral modulation; retain the authored full-map
 // albedo rather than replacing it with a repeating texture's average color.
 vec3 da=mix(vec3(1.0),ca*4.0,color_strength[a]);
 vec3 db=mix(vec3(1.0),cb*4.0,color_strength[b]);
 ALBEDO=clamp(base*mix(db,da,blend.b),vec3(0.005),vec3(0.9));
 vec4 road=texture(road_color,(world_position.xz-road_origin)/256.0);
 ALBEDO=mix(ALBEDO,road.rgb,road.a);
 ROUGHNESS=0.94;
 if(detailed_surface){
  vec4 na=texture(detail_normal,vec3(uv/tile_scale[a],float(a)));
  vec4 nb=texture(detail_normal,vec3(uv/tile_scale[b],float(b)));
  vec2 bump=mix((nb.rg*2.0-1.0)*normal_strength[b],(na.rg*2.0-1.0)*normal_strength[a],blend.b);
  NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+tangent*bump.x+bitangent*bump.y),0.0)).xyz);
  ROUGHNESS=clamp(mix(nb.a,na.a,blend.b),0.55,1.0);
 }
}
