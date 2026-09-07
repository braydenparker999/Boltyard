extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://offroad_main.tscn").instantiate()
	root.add_child(game)
	game.select_map("utah")
	var core = game.truck.core
	assert(core.get_terrain_mode() == 7)
	assert(game.map_canvas.extent == 1024)
	assert(game.map_canvas.trails.size() == 16)
	assert(game.world.get_metrics().scenery.placements == 124212)
	assert(core.get_expedition_obstacles().is_empty())
	assert(core.get_dynamic_objects().is_empty())
	assert(game.world.get_metrics().chunks == 64)
	var results: Array = []
	for p in [Vector2(-561.099121,238.796906),Vector2(-386.088074,-306.108032),Vector2(-719.364685,-710.897034)]:
		var at := Vector3(p.x,core.terrain_height(p.x,p.y)+1.5,p.y)
		core.reset(at)
		for i in 360: core.step(1.0/120,0,0,true)
		var start: Dictionary = core.get_stats()
		assert(start.up.y > .8)
		assert(start.wheels_grounded >= 3)
		assert(absf(start.position.y-core.terrain_height(start.position.x,start.position.z))<3)
		for i in 720: core.step(1.0/120,.25,.04,false)
		var end: Dictionary = core.get_stats()
		assert(end.position.is_finite())
		assert(end.rejected_states==0 and end.safety_clamps==0)
		assert(start.position.distance_to(end.position)>1)
		assert(core.recover_near(at,Vector3(0,0,-1)))
		assert(Vector2(core.get_stats().position.x-p.x,core.get_stats().position.z-p.y).length()<15)
		results.append({"start":str(start.position),"end":str(end.position),"grounded":start.wheels_grounded,"recovery":str(core.get_stats().position)})
	# Fine mesh cells must agree with native contact heights at their centroids.
	var a: Array = core.get_imported_chunk(1,4,1)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ids: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for i in range(0,128*128*6,123):
		var p: Vector3 = (v[ids[i]]+v[ids[i+1]]+v[ids[i+2]])/3.0
		assert(absf(core.terrain_height(p.x,p.z)-p.y)<.002)
	game.select_map("canyon")
	assert(core.get_terrain_mode()==6)
	game.select_map("utah")
	assert(core.get_terrain_mode()==7)
	assert(core.get_dynamic_objects().is_empty())
	print("UTAH PASS ",JSON.stringify({"drives":results,"terrain":game.world.get_metrics()}))
	game.queue_free()
	await process_frame
	quit()
