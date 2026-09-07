extends Node3D
# Original placements are retained across the full map. Render batches stream
# by location and use source LODs; collision remains loaded independently.
const DATA := "res://data/utah/"
var models: Array = []
var groups: Array = []
var meshes: Dictionary = {}
var pending: Array = []
var total := 0
var collider_count := 0
func configure() -> void:
 var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA+"scenery.json"))
 models = meta.models
 collider_count = meta.colliders
 var file := FileAccess.open(DATA+"scenery_instances.bin",FileAccess.READ)
 total = file.get_32()
 var buckets: Dictionary = {}
 for i in total:
  var id := file.get_32()
  var values := file.get_buffer(48).to_float32_array()
  var basis := Basis(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]),Vector3(values[6],values[7],values[8]))
  var origin := Vector3(values[9],values[10],values[11])
  var tile := 64.0
  var key := Vector3i(id,floori(origin.x/tile),floori(origin.z/tile))
  if not buckets.has(key):buckets[key] = {"model": id,"transforms": [],"center": Vector3((key.y+0.5)*tile,0,(key.z+0.5)*tile),"tile_radius": tile*0.7072,"radius": 0.0,"node": null,"lod": -1,"wanted": -1}
  buckets[key].transforms.append(Transform3D(basis,origin))
  buckets[key].radius = maxf(buckets[key].radius,models[id].radius*maxf(basis.x.length(),maxf(basis.y.length(),basis.z.length())))
 groups = buckets.values()
func update_focus(at: Vector3, quality: int) -> void:
 pending.clear()
 for g in groups:
  var distance := maxf(0.0,Vector2(at.x-g.center.x,at.z-g.center.z).length()-g.tile_radius)
  var radius: float = g.radius
  # Large canyon formations stay visible to the horizon; small stones need
  # only a short range. High retains original top-detail meshes farther out.
  var end := clampf(radius*[130.0,175.0,230.0][quality],45.0,2800.0)
  var source: String = models[g.model].source.to_lower()
  if source.contains("juniper"):
   end = minf(end, [180.0,260.0,380.0][quality] if source.contains("tree") or source.contains("ancient") else [75.0,110.0,160.0][quality])
  var near_end := clampf(radius*[3.0,5.0,8.0][quality],12.0,[65.0,110.0,200.0][quality])
  var mid_end := maxf(near_end*1.5,radius*[12.0,22.0,40.0][quality])
  var lod := -1 if distance>end else (0 if distance<near_end else (1 if distance<mid_end else 2))
  g.wanted = lod
  if lod==g.lod:continue
  if lod<0:
   if g.node != null:g.node.queue_free();g.node=null
   g.lod=-1
  else:
   g.distance=distance
   pending.append(g)
 pending.sort_custom(func(a,b):return a.distance<b.distance)
 # Populate the nearest terrain immediately; remaining distant scenery is
 # spread over frames to avoid a long pause when entering Utah.
 for i in mini(24,pending.size()):_apply(pending.pop_front())
func _process(_delta: float) -> void:
 for i in mini(6,pending.size()):_apply(pending.pop_front())
func _apply(g: Dictionary) -> void:
 var key := Vector2i(g.model,g.wanted)
 if not meshes.has(key):meshes[key]=load(models[g.model].lods[g.wanted])
 if g.node==null:
  var batch := MultiMesh.new()
  batch.transform_format=MultiMesh.TRANSFORM_3D
  batch.mesh=meshes[key]
  batch.instance_count=g.transforms.size()
  for i in g.transforms.size():batch.set_instance_transform(i,g.transforms[i])
  var visual := MultiMeshInstance3D.new()
  visual.multimesh=batch
  visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(visual)
  g.node=visual
 else:g.node.multimesh.mesh=meshes[key]
 g.lod=g.wanted
func get_metrics() -> Dictionary:
 var visible := 0
 var triangles := 0
 for g in groups:
  if g.lod>=0:
   visible+=g.transforms.size()
   triangles+=int(models[g.model].triangles[g.lod])*g.transforms.size()
 return {"placements":total,"colliders":collider_count,"visible":visible,"triangles":triangles,"pending":pending.size()}
