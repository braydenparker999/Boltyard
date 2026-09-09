class_name GridmapWorld
extends OffroadWorld
const DATA="res://data/gridmap/"
var manifest: Dictionary
var scenery: Node3D
var surface_data: PackedByteArray
var detail_mats: Dictionary={}
var _road_root: Node3D
func configure(solver: RefCounted) -> void:
 _core=solver
 manifest=JSON.parse_string(FileAccess.get_file_as_string(DATA+"manifest.json"))
 surface_data=FileAccess.get_file_as_bytes(DATA+"surface.bin")
 var grip=PackedFloat32Array();var ids=PackedInt32Array()
 for mat in manifest.materials:grip.append(mat.grip);ids.append(mat.surface)
 _core.configure_imported_surface(1.0,grip,ids)
 var terrain_ok: bool=_core.load_imported_terrain(FileAccess.get_file_as_bytes(DATA+"height.bin").to_float32_array(),surface_data)
 assert(terrain_ok,"Gridmap terrain invalid")
 var scenery_ok: bool=_core.load_imported_scenery(FileAccess.get_file_as_bytes(DATA+"scenery_collision.bin"))
 assert(scenery_ok,"Gridmap scenery invalid")
 _core.set_terrain(7)
 if is_inside_tree() and _course==null:_build_course()
func _make_lighting() -> void:
 super._make_lighting()
 _environment.environment.fog_density=.00012
 _environment.environment.ambient_light_energy=.27
 _sun.rotation_degrees=Vector3(-48,-32,0)
func _build_course() -> void:
 if _course!=null:return
 _course=Node3D.new();add_child(_course)
 _ground_material=ShaderMaterial.new();_ground_material.shader=load("res://shaders/gridmap_ground.gdshader")
 _ground_material.set_shader_parameter("material_blend",load("res://assets/gridmap/ground/blend.png"))
 for pair in [["base_color","base"],["detail_color","color"],["detail_normal","normal"]]:
  _ground_material.set_shader_parameter(pair[0],load("res://assets/gridmap/ground/"+pair[1]+".res"))
 for pair in [["tile_size","scale"],["detail_strength","strength"]]:
  var values=PackedFloat32Array()
  for info in manifest.materials:values.append(info[pair[1]])
  _ground_material.set_shader_parameter(pair[0],values)
 for z in 8:
  for x in 8:
   var visual=MeshInstance3D.new();visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   var mesh=_make_mesh(x,z,8);visual.mesh=mesh;_course.add_child(visual)
   _chunks.append({"x":x,"z":z,"visual":visual,"far":mesh,"step":8})
 scenery=load("res://scripts/utah_scenery.gd").new();scenery.data_path=DATA;_course.add_child(scenery);scenery.configure()
 _build_roads()
 update_focus(get_spawn_position())
func _make_mesh(x: int,z: int,step: int) -> ArrayMesh:
 var arrays: Array=_core.get_imported_chunk(x,z,step)
 var mesh=ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh.surface_set_material(0,_ground_material)
 return mesh
func update_focus(at: Vector3) -> void:
 if Vector2(at.x-_last_focus.x,at.z-_last_focus.z).length_squared()<64:return
 _last_focus=at
 if scenery!=null:scenery.update_focus(at,_quality)
 for c in _chunks:
  var delta=(Vector2(at.x,at.z)-Vector2(c.x*128-448,c.z*128-448)).abs()-Vector2(64,64)
  var distance=Vector2(maxf(delta.x,0),maxf(delta.y,0)).length()
  var step=1 if distance<100 else (4 if distance<250 else 8)
  if step!=c.step:c.visual.mesh=c.far if step==8 else _make_mesh(c.x,c.z,step);c.step=step
func get_spawn_position() -> Vector3:
 return Vector3(manifest.spawn[0],_core.terrain_height(manifest.spawn[0],manifest.spawn[1])+1.5,manifest.spawn[1])
func get_landmarks() -> Array:
 var out: Array=[]
 for l in manifest.landmarks:out.append({"id":l.id,"name":l.name,"position":Vector3(l.x,maxf(l.get("y",0),_core.terrain_height(l.x,l.z)),l.z),"radius":15,"description":l.description})
 return out
func get_map_routes() -> Array:return []
func get_metrics() -> Dictionary:return {"extent":1024,"scenery":scenery.get_metrics() if scenery!=null else {}}
func set_quality(level: int) -> void:
 super.set_quality(level)
 if scenery!=null:scenery.update_focus(_last_focus,_quality)
func _build_roads() -> void:
 var defs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DATA+"materials.json"))
 var objects: Array=JSON.parse_string(FileAccess.get_file_as_string(DATA+"objects.json"))
 _road_root=Node3D.new();_course.add_child(_road_root)
 for o in objects:
  if o.get("class")=="WaterBlock":
   var water=MeshInstance3D.new();var plane=PlaneMesh.new()
   plane.size=Vector2(o.scale[0],o.scale[1]);water.mesh=plane
   water.position=Vector3(o.position[0],o.position[2],-o.position[1])
   var wm=StandardMaterial3D.new();var col=o.get("baseColor",[40,65,70,255])
   wm.albedo_color=Color(col[0]/255.0,col[1]/255.0,col[2]/255.0) if col is Array else Color.from_string(str(col),Color(.15,.22,.24))
   wm.roughness=.28
   water.material_override=wm;water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   _road_root.add_child(water)
   continue
  if o.get("class")!="DecalRoad" or not o.has("nodes"):continue
  var d: Dictionary=defs.get(o.get("material",""),{})
  if d.get("color","").is_empty():continue
  var mat: StandardMaterial3D
  var key: String=o.material
  if not detail_mats.has(key):
   mat=StandardMaterial3D.new();mat.albedo_texture=load(d.color)
   mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;mat.alpha_scissor_threshold=.08
   mat.roughness=.95;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
   mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
   var tint: Array=d.get("tint",[1,1,1,1]);mat.albedo_color=Color(tint[0],tint[1],tint[2],tint[3])
   detail_mats[key]=mat
  mat=detail_mats[key]
  var points: Array=o.nodes
  if points.size()<2:continue
  var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(mat)
  var along=0.0;var tex_length=maxf(float(o.get("textureLength",5)),.1)
  for i in points.size()-1:
   var a=Vector3(points[i][0],points[i][2],-points[i][1]);var b=Vector3(points[i+1][0],points[i+1][2],-points[i+1][1]);var delta=b-a
   var length=Vector2(delta.x,delta.z).length();var count=maxi(1,ceili(length/2))
   var across=Vector3(-delta.z,0,delta.x).normalized()
   for j in count:
    var v: Array=[];var uv: Array=[]
    for end in 2:
     var t=float(j+end)/count;var center=a.lerp(b,t);var width=lerpf(float(points[i][3]),float(points[i+1][3]),t)
     for side in 2:
      var p=center+across*width*(float(side)-.5);p.y=_core.terrain_height(p.x,p.z)+.035+float(o.get("renderPriority",0))*.00005
      v.append(p);uv.append(Vector2(side,(along+t*length)/tex_length))
    for index in [0,2,1,1,2,3]:st.set_uv(uv[index]);st.set_normal(Vector3.UP);st.add_vertex(v[index])
   along+=length
  var visual=MeshInstance3D.new();visual.mesh=st.commit();visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;_road_root.add_child(visual)
