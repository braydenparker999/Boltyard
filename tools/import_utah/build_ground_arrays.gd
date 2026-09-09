extends SceneTree
func _initialize():
 if DisplayServer.get_name()=="headless":
  printerr("Build texture arrays with an OpenGL display; the dummy renderer cannot serialize layer images")
  quit(1)
  return
 for kind in ["color","normal"]:
  var images: Array[Image]=[]
  for i in 14:
   var image=Image.load_from_file("res://assets/utah/materials/%s_%d.png"%[kind,i])
   image.resource_path=""
   image.convert(Image.FORMAT_RGBA8)
   image.generate_mipmaps()
   assert(image.compress(Image.COMPRESS_ETC2)==OK)
   images.append(image)
  var array=Texture2DArray.new()
  assert(array.create_from_images(images)==OK)
  assert(array.get_layer_data(0)!=null)
  assert(ResourceSaver.save(array,"res://assets/utah/materials/"+kind+".res",ResourceSaver.FLAG_COMPRESS)==OK)
 print("Built 14-layer ground color and normal/roughness arrays")
 quit()
