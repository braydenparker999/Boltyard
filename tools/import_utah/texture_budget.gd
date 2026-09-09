extends SceneTree
func _initialize():
 var used: Dictionary={}
 for file in DirAccess.get_files_at("res://assets/utah/scenery/"):
  if file.ends_with(".res"):
   for dependency in ResourceLoader.get_dependencies("res://assets/utah/scenery/"+file):
    var path=dependency.get_slice("::",2) if dependency.contains("::") else dependency
    used[path]=true
 var changed=0
 for file in DirAccess.get_files_at("res://assets/utah/scenery/tex/"):
  if file.ends_with(".import"):continue
  var path="res://assets/utah/scenery/tex/"+file
  if not used.has(path):
   DirAccess.remove_absolute(path)
   if FileAccess.file_exists(path+".import"):DirAccess.remove_absolute(path+".import")
   continue
  var cfg=ConfigFile.new()
  if cfg.load(path+".import")==OK:
   cfg.set_value("params","compress/mode",2)
   cfg.set_value("params","mipmaps/generate",true)
   cfg.save(path+".import")
   changed+=1
 print("VRAM compression enabled for ",changed," referenced textures")
 quit()
