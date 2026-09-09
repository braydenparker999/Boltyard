extends SceneTree

# Real engine renders and actual native settling; no animated wheel poses.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	var reports: Array = []
	for mode in [6, 4]:
		var stage := Node3D.new()
		root.add_child(stage)
		var truck := OffroadTruck.new()
		var build := VehicleCatalog.default_build("buggy")
		truck.configure(VehicleCatalog.compose(build))
		stage.add_child(truck)
		truck.set_physics_process(false)
		var world := ExpeditionWorld.new()
		world.map_mode = mode
		world.configure(truck.core)
		stage.add_child(world)
		world.set_quality(1)
		var camera := Camera3D.new()
		camera.fov = 51
		camera.far = 850
		stage.add_child(camera)
		camera.current = true
		for id in ["buggy", "pickup"]:
			build = VehicleCatalog.default_build(id)
			for slot in {"tires":"rock", "wheels":"beadlock", "suspension":"long_travel", "gearing":"crawler"}:
				var parts := {"tires":"rock", "wheels":"beadlock", "suspension":"long_travel", "gearing":"crawler"}
				build = VehicleCatalog.equip_part(build,slot,parts[slot])
			var config := VehicleCatalog.compose(build)
			config.paint = "e88724" if id == "buggy" else "28554d"
			truck.configure(config)
			truck.core.set_terrain(mode)
			var at := Vector3(11,0,-50) if mode == 6 else Vector3(11,0,-50)
			at.y = truck.core.terrain_height(at.x,at.z)+1.5
			truck.reset(at)
			for i in range(360):
				truck.core.step(1.0/120.0,0,0,true)
			for i in range(300):
				truck.core.step(1.0/120.0,.20,0,false)
			truck._refresh_visuals()
			var stats := truck.get_telemetry()
			assert(stats.position.is_finite() and stats.up.y > .65, "review rig must settle upright")
			assert(stats.safety_clamps == 0 and stats.rejected_states == 0, "review must use stable solved states")
			world.update_focus(stats.position)
			for shot in [["front",Vector3(5,2.0,-6)], ["rear",Vector3(-5,2.3,6)]]:
				camera.position = stats.position + shot[1]
				camera.position.y = maxf(camera.position.y, truck.core.terrain_height(camera.position.x,camera.position.z)+1)
				camera.look_at(stats.position+Vector3(0,.3,0))
				for i in range(4):
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://build/redstone-%d-%s-%s.png" % [mode,id,shot[0]])
			reports.append({"mode":mode,"vehicle":id,"triangles":truck.get_visual_validation().get("triangles",0),"position":str(stats.position),"up":str(stats.up),"damage":stats.damage})
		stage.queue_free()
		await process_frame
		await process_frame
	print("REDSTONE REVIEW: ", JSON.stringify(reports))
	quit()
