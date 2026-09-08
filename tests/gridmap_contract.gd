extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://offroad_main.tscn").instantiate()
	root.add_child(game)
	game.select_map("gridmap")
	game.truck.set_physics_process(false)
	var core = game.truck.core
	assert(core.get_terrain_mode() == 7)
	assert(not game.automatic_recovery_needed(Vector3(370,-80,183),"gridmap"))
	assert(game.automatic_recovery_needed(Vector3(0,-121,0),"gridmap"))
	assert(game.world.get_metrics().scenery.colliders == 860)
	var layers: PackedByteArray = game.world.surface_data
	var seen := {}
	for i in layers.size():
		var id := int(layers[i])
		if seen.has(id): continue
		var x := i % 1025 - 512
		var z := i / 1025 - 512
		assert(absf(core.terrain_surface(x,z)-game.world.manifest.materials[id].grip)<0.0001)
		seen[id] = true
	assert(seen.size() == 10)
	# Render triangles must use the same one-metre surface as tire contacts.
	var arrays: Array = core.get_imported_chunk(4,3,1)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert(absf(v[1].x-v[0].x-1.0)<0.001)
	for i in range(0,128*128*6,123):
		var p: Vector3 = (v[indices[i]]+v[indices[i+1]]+v[indices[i+2]])/3
		assert(absf(core.terrain_height(p.x,p.z)-p.y)<0.002)
	var spawn: Vector3 = game.world.get_spawn_position()
	var height_before: float = core.terrain_height(132,-24)
	core.reset(spawn)
	for i in 360: core.step(1.0/120,0,0,true)
	var start: Dictionary = core.get_stats()
	assert(start.wheels_grounded >= 3 and start.up.y > .9)
	for i in 600: core.step(1.0/120,.25,0,false)
	var end: Dictionary = core.get_stats()
	assert(end.position.is_finite() and end.rejected_states == 0 and end.safety_clamps == 0)
	assert(start.position.distance_to(end.position)>2)
	assert(not game.automatic_recovery_needed(end.position,"gridmap"))
	assert(core.recover_near(spawn,Vector3(0,0,-1)))
	# Loading another imported map must replace geometry, spacing and material ids.
	game.select_map("utah")
	assert(game.world.get_metrics().scenery.colliders > 100000)
	arrays = core.get_imported_chunk(4,3,1)
	v = arrays[Mesh.ARRAY_VERTEX]
	assert(absf(v[1].x-v[0].x-2.0)<0.001)
	game.select_map("gridmap")
	assert(game.world.get_metrics().scenery.colliders == 860)
	assert(absf(core.terrain_height(132,-24)-height_before)<0.001)
	core.reset(game.world.get_spawn_position())
	for i in 360: core.step(1.0/120,0,0,true)
	assert(core.get_stats().wheels_grounded >= 3)
	print("GRIDMAP PASS: 10 material grips, matching 1m contact mesh, settled drive/recovery, Utah 2m -> Gridmap 1m reload; drive metres ",start.position.distance_to(end.position))
	game.queue_free()
	await process_frame
	quit()
