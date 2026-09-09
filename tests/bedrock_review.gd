extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(720, 1280)
	var stage := Node3D.new()
	root.add_child(stage)
	var truck := OffroadTruck.new()
	var build := VehicleCatalog.default_build("buggy")
	var config := VehicleCatalog.compose(build)
	config.paint = "e88724"
	truck.configure(config)
	stage.add_child(truck)
	truck.set_physics_process(false)
	var world := ExpeditionWorld.new()
	world.map_mode = 6
	world.configure(truck.core)
	stage.add_child(world)
	world.set_quality(0)
	var camera := Camera3D.new()
	camera.fov = 64
	camera.far = 850
	stage.add_child(camera)
	camera.current = true
	for spot in [["entry",Vector3(8,0,-36)],["shelves",Vector3(8,0,-66)],["arch",Vector3(5,0,-83)]]:
		var at: Vector3 = spot[1]
		at.y = truck.core.terrain_height(at.x,at.z)+1.4
		truck.reset(at)
		for i in range(360): truck.core.step(1.0/120,0,0,true)
		truck._refresh_visuals()
		var stats := truck.get_telemetry()
		world.update_focus(stats.position)
		camera.position = stats.position+Vector3(0,4.6,7.5)
		camera.look_at(stats.position+Vector3(0,.6,-5))
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/bedrock-%s.png"%spot[0])
		print("BEDROCK REVIEW: ",spot[0]," ",stats.position," upright=",stats.up.y," clamps=",stats.safety_clamps)
	quit()
