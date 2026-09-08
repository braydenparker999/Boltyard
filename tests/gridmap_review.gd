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
	var world := GridmapWorld.new()
	world.configure(truck.core)
	stage.add_child(world)
	world.set_quality(0)
	var camera := Camera3D.new()
	camera.fov=65
	camera.far=3000
	stage.add_child(camera)
	camera.current=true
	for spot in [["spawn",Vector2(19.13,-122.98),0],["offroad",Vector2(132,-24),0],["oval",Vector2(-6.05,640.76),1]]:
		world.set_quality(spot[2])
		var p: Vector2 = spot[1]
		var at := Vector3(p.x,maxf(6.4 if spot[0]=="oval" else -1000.0,truck.core.terrain_height(p.x,p.y))+1.5,p.y)
		truck.reset(at)
		for i in 360: truck.core.step(1.0/120,0,0,true)
		truck._refresh_visuals()
		var stats := truck.get_telemetry()
		world.update_focus(stats.position)
		camera.position=stats.position+Vector3(9,7,12)
		camera.look_at(stats.position+Vector3(-7,0,-13))
		while not world.scenery.pending.is_empty():world.scenery._process(0)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/grid-%s.png" % spot[0])
		print("GRID VIEW ",spot[0]," ",world.get_metrics(), " drawn_triangles ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " draws ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	stage.queue_free()
	await process_frame
	quit()
