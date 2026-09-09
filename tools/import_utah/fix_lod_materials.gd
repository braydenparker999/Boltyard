extends SceneTree
func _initialize():
 var changed=0
 for file in DirAccess.get_files_at("res://assets/utah/scenery/"):
  if not file.ends_with(".res"):continue
  var path="res://assets/utah/scenery/"+file
  var mesh=load(path)
  var dirty=false
  for i in mesh.get_surface_count():
   var mat=mesh.surface_get_material(i)
   if mat!=null and mat.albedo_texture==null:
    var arrays=mesh.surface_get_arrays(i)
    var colors=arrays[Mesh.ARRAY_COLOR]
    mat=mat.duplicate()
    mat.vertex_color_use_as_albedo=true
    # Untextured source LODs carry their baked appearance in vertex colors.
    # A neutral sandstone fallback covers source parts without that channel.
    if colors==null or colors.is_empty():mat.albedo_color=Color(0.52,0.44,0.33)
    mesh.surface_set_material(i,mat);dirty=true;changed+=1
  if dirty:ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)
 print("Fixed ",changed," vertex-colored LOD surfaces")
 quit()
