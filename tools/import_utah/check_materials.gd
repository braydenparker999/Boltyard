extends SceneTree
func _initialize():
 var models=JSON.parse_string(FileAccess.get_file_as_string("res://models.json"))
 var defs=JSON.parse_string(FileAccess.get_file_as_string("res://materials.json"))
 var missing={}
 for id in models.size():
  var s=load("res://model_%d.dae"%id).instantiate()
  for n in s.find_children("*","MeshInstance3D",true,false):
   if n.mesh==null:continue
   for i in n.mesh.get_surface_count():
    var name=n.mesh.surface_get_name(i)
    if not defs.has(name) or defs[name].color.is_empty():missing[name]=models[id]
  s.free()
 print(JSON.stringify(missing,"  "))
 quit()
