extends SceneTree
# Run with an OpenGL display after importing textures. Dummy rendering cannot save arrays.
func _initialize() -> void:
 if DisplayServer.get_name()=="headless":quit(1);return
 var materials: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/gridmap/manifest.json")).materials
 DirAccess.make_dir_recursive_absolute("res://assets/gridmap/ground")
 for kind in ["base","color","normal"]:
  var images: Array[Image]=[]
  for mat in materials:
   var im=Image.load_from_file(mat[kind]);im.convert(Image.FORMAT_RGBA8)
   im.resize(256 if kind=="base" else 1024,256 if kind=="base" else 1024,Image.INTERPOLATE_LANCZOS)
   if kind=="normal":
    var rough=Image.load_from_file(mat.roughness) if not mat.roughness.is_empty() else null
    if rough!=null:rough.resize(1024,1024)
    for y in 1024:
     for x in 1024:
      var c=im.get_pixel(x,y);c.a=rough.get_pixel(x,y).r if rough!=null else .9;im.set_pixel(x,y,c)
   im.generate_mipmaps()
   var error=im.compress(Image.COMPRESS_ETC2);assert(error==OK)
   images.append(im)
  var tex=Texture2DArray.new();var result=tex.create_from_images(images);assert(result==OK)
  result=ResourceSaver.save(tex,"res://assets/gridmap/ground/"+kind+".res",ResourceSaver.FLAG_COMPRESS);assert(result==OK)
 print("Saved source ground arrays")
 quit()
