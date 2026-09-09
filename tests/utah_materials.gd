extends SceneTree
func _initialize():
 for kind in ["color","normal"]:
  var path="res://assets/utah/materials/"+kind+".res"
  assert(ResourceLoader.get_dependencies(path).is_empty(),"Ground array must embed its images")
  var array=load(path)
  assert(array is Texture2DArray and array.get_layers()==14)
  assert(array.get_width()==512 and array.get_height()==512)
 var report=JSON.parse_string(FileAccess.get_file_as_string("res://data/utah/roads_report.json"))
 assert(report.restored_records==3252)
 for z in 8:
  for x in 8:
   var road=load("res://assets/utah/roads/road_%d_%d.png"%[x,z])
   assert(road!=null and road.get_width()==1024)
 print("PASS: 14 embedded ground material layers; 64 road tiles; 3252 original decal records")
 quit()
