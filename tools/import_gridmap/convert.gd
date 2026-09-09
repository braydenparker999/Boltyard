extends SceneTree
const OUT = "res://assets/gridmap/scenery/"
var defs: Dictionary
var mats: Dictionary = {}
var report: Array = []
func material(name: String) -> Material:
 if mats.has(name):return mats[name]
 var m=StandardMaterial3D.new()
 m.roughness=0.85
 m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
 var d: Dictionary=defs.get(name,{})
 var tint: Array=d.get("tint",[1,1,1,1])
 m.albedo_color=Color(tint[0],tint[1],tint[2],tint[3])
 m.roughness=float(d.get("roughness_factor",.85))
 if not d.get("roughness","").is_empty():
  m.roughness_texture=load(d.roughness)
  m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
 if not d.get("color","").is_empty():m.albedo_texture=load(d.color.replace("res://tex/",OUT+"tex/"))
 if not d.get("normal","").is_empty():
  m.normal_enabled=true
  m.normal_texture=load(d.normal.replace("res://tex/",OUT+"tex/"))
 if d.get("double",false):m.cull_mode=BaseMaterial3D.CULL_DISABLED
 if d.get("alpha",false):
  m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
  m.alpha_scissor_threshold=d.get("cutoff",0.3)
 if d.is_empty() or d.get("color","").is_empty():
  m.vertex_color_use_as_albedo=true
  m.albedo_color=Color(0.52,0.48,0.4) if name!="lod_vertcol" else Color.WHITE
 mats[name]=m
 return m
func flatten(nodes: Array, visual: bool) -> ArrayMesh:
 var mesh=ArrayMesh.new()
 for node in nodes:
  var tr: Transform3D=node.global_transform
  for surface in node.mesh.get_surface_count():
   var arrays: Array=node.mesh.surface_get_arrays(surface)
   var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
   for i in vertices.size():vertices[i]=tr*vertices[i]
   arrays[Mesh.ARRAY_VERTEX]=vertices
   if arrays[Mesh.ARRAY_NORMAL]!=null:
    var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
    for i in normals.size():normals[i]=(tr.basis.inverse().transposed()*normals[i]).normalized()
    arrays[Mesh.ARRAY_NORMAL]=normals
   arrays[Mesh.ARRAY_TANGENT]=null
   mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
   if visual:mesh.surface_set_material(mesh.get_surface_count()-1,material(node.mesh.surface_get_name(surface)))
 return mesh
func simplified(mesh: ArrayMesh, ratio: float) -> ArrayMesh:
 var importer=ImporterMesh.new()
 for i in mesh.get_surface_count():importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,mesh.surface_get_arrays(i),[],{},mesh.surface_get_material(i))
 importer.generate_lods(60.0,60.0,[])
 var result=ArrayMesh.new()
 for i in importer.get_surface_count():
  var arrays=importer.get_surface_arrays(i)
  var target=arrays[Mesh.ARRAY_INDEX].size()*ratio
  var best=arrays[Mesh.ARRAY_INDEX]
  for j in importer.get_surface_lod_count(i):
   var candidate=importer.get_surface_lod_indices(i,j)
   if absf(candidate.size()-target)<absf(best.size()-target):best=candidate
  arrays[Mesh.ARRAY_INDEX]=best
  result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  result.surface_set_material(i,importer.get_surface_material(i))
 return result
func _initialize():call_deferred("run")
func run():
 defs=JSON.parse_string(FileAccess.get_file_as_string("res://materials.json"))
 var models: Array=JSON.parse_string(FileAccess.get_file_as_string("res://models.json"))
 var data=FileAccess.open("res://data/gridmap/scenery_collision.bin",FileAccess.WRITE)
 data.store_32(0x34545542);data.store_32(models.size())
 var collidable: Array=[]
 var regex=RegEx.new();regex.compile("([0-9]+)$")
 for id in models.size():
  var scene=load("res://model_%d.dae"%id).instantiate()
  root.add_child(scene)
  var levels: Dictionary={};var collisions: Array=[]
  for node in scene.find_children("*","MeshInstance3D",true,false):
   if node.mesh==null:continue
   var n=String(node.name).to_lower()
   if n.contains("colmesh") or n.begins_with("col") or n.contains("collision"):
    collisions.append(node);continue
   if n.contains("loscol") or n.contains("billboard"):continue
   var match=regex.search(n);var lod=int(match.get_string(1)) if match else 100
   if not levels.has(lod):levels[lod]=[]
   levels[lod].append(node)
  var keys=levels.keys();keys.sort();keys.reverse()
  var entry={"source":models[id],"lods":[],"radius":0.0,"triangles":[]}
  if keys.is_empty():printerr("NO VISUAL ",models[id]);quit(1);return
  var selected=[keys[0],keys[keys.size()/2],keys[-1]]
  for li in 3:
   var mesh=flatten(levels[selected[li]],true)
   if li>0 and selected[li]==keys[0]:mesh=simplified(mesh,0.32 if li==1 else 0.1)
   var path=OUT+"model_%d_%d.res"%[id,li]
   ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)
   entry.lods.append(path)
   entry.radius=maxf(entry.radius,mesh.get_aabb().size.length()*0.5)
   var count=0
   for j in mesh.get_surface_count():count+=mesh.surface_get_array_index_len(j)/3
   entry.triangles.append(count)
  # Authored collision parts preserve openings. Rock/cliff assets without an
  # explicit collision part use the highest visible detail; foliage does not.
  var name=String(models[id]).to_lower()
  if collisions.is_empty():collisions=levels[keys[0]]
  var cm=flatten(collisions,false);var vs=PackedVector3Array();var indices=PackedInt32Array()
  for j in cm.get_surface_count():
   var arrays=cm.surface_get_arrays(j);var v:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var ix:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
   if ix.is_empty():for k in v.size():ix.append(k)
   for k in range(0,ix.size(),3):
    var a=v[ix[k]];var b=v[ix[k+1]];var c=v[ix[k+2]]
    if (b-a).cross(c-a).length_squared()<1e-14:continue
    indices.append(vs.size()+ix[k]);indices.append(vs.size()+ix[k+2]);indices.append(vs.size()+ix[k+1])
   vs.append_array(v)
  var surface=1.10 if name.contains("rock") or name.contains("cliff") else 1.05
  var surface_id=1 if name.contains("rock") or name.contains("cliff") else 0
  data.store_float(surface);data.store_32(surface_id)
  data.store_32(vs.size());data.store_32(indices.size()/3)
  data.store_buffer(vs.to_byte_array());data.store_buffer(indices.to_byte_array())
  collidable.append(not indices.is_empty());entry.collision_triangles=indices.size()/3
  report.append(entry);scene.free()
  print("MODEL ",id," ",models[id]," ",entry.triangles," collision ",entry.collision_triangles)
 data.close()
 var meta=FileAccess.open("res://data/gridmap/scenery_models.json",FileAccess.WRITE)
 meta.store_string(JSON.stringify(report,"  "))
 meta.close()
 print("MESH CONVERSION COMPLETE")
 quit()
