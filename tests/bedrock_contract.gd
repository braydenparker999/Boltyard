extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var core: RefCounted = ClassDB.instantiate("SoftBodyRig")
	core.configure({})
	core.set_terrain(6)
	var floor_scene := load("res://assets/canyon/bedrock_floor.glb") as PackedScene
	var floor_root := floor_scene.instantiate()
	root.add_child(floor_root)
	var count := 0
	var max_error := 0.0
	for child in floor_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var data := mesh.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
		for i in range(0, verts.size(), 37):
			var p: Vector3 = mesh.global_transform * verts[i]
			max_error = maxf(max_error,absf(core.terrain_height(p.x,p.z)-p.y))
			count += 1
		for i in range(0, indices.size(), 111):
			var p: Vector3 = mesh.global_transform * (verts[indices[i]]*.21+verts[indices[i+1]]*.33+verts[indices[i+2]]*.46)
			max_error = maxf(max_error,absf(core.terrain_height(p.x,p.z)-p.y))
			count += 1
	print("CONTRACT DEBUG count=", count, " error=", max_error)
	if count<=2000 or max_error>=.0001:
		push_error("Blender triangles must match tire support, including triangle interiors")
		quit(1)
		return
	print("BEDROCK CONTRACT: ",count," samples, maximum mesh/contact error ",max_error,"m")
	floor_root.queue_free()
	await process_frame
	quit()
