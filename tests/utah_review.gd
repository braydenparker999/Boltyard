extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(720,1280)
	var stage := Node3D.new()
	root.add_child(stage)
	var truck := OffroadTruck.new()
	truck.configure(VehicleCatalog.compose(VehicleCatalog.default_build("pickup")))
	stage.add_child(truck)
	truck.set_physics_process(false)
	var world := ImportedUtahWorld.new()
	world.configure(truck.core)
	stage.add_child(world)
	world.set_quality(0)
	var camera := Camera3D.new()
	camera.fov=65
	camera.far=3000
	stage.add_child(camera)
	camera.current=true
	for spot in [["trailhead",Vector2(-561.1,238.8)],["ridge",Vector2(-386.1,-306.1)]]:
		var p: Vector2 = spot[1]
		var at := Vector3(p.x,truck.core.terrain_height(p.x,p.y)+1.5,p.y)
		truck.reset(at)
		for i in 360: truck.core.step(1.0/120,0,0,true)
		truck._refresh_visuals()
		var stats := truck.get_telemetry()
		world.update_focus(stats.position)
		camera.position=stats.position+Vector3(9,7,12)
		camera.look_at(stats.position+Vector3(-7,0,-13))
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/utah-%s.png" % spot[0])
		print("UTAH VIEW ",spot[0]," ",world.get_metrics())
	stage.queue_free()
	await process_frame
	quit()
