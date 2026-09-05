extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8ea6b1")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bfd1dc")
	environment.environment.ambient_light_energy = 0.35
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -28, 0)
	sun.light_color = Color("ffecd5")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("737b73")
	material.roughness = 0.94
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var truck := OffroadTruck.new()
	truck.configure(VehicleCatalog.compose(VehicleCatalog.default_build("pickup")))
	stage.add_child(truck)
	truck.set_physics_process(false)
	var valley: OffroadWorld
	var world_mode := OS.get_cmdline_user_args().has("--world")
	if world_mode:
		environment.free()
		sun.free()
		floor_mesh.free()
		valley = OffroadWorld.new()
		valley.configure(truck.core)
		valley.set_quality(2)
		stage.add_child(valley)
		root.msaa_3d = Viewport.MSAA_2X
	var camera := Camera3D.new()
	camera.fov = 43
	stage.add_child(camera)
	camera.current = true
	var output_dir := ProjectSettings.globalize_path("res://").path_join("build/vehicle-v04")
	DirAccess.make_dir_recursive_absolute(output_dir)
	for variant in ["pickup", "scout", "buggy", "pickup-fitted", "scout-fitted", "buggy-fitted"]:
		if not OS.get_cmdline_user_args().is_empty() and not OS.get_cmdline_user_args().has(variant):
			continue
		var vehicle: String = variant.split("-")[0]
		var build := VehicleCatalog.default_build(vehicle)
		if variant.ends_with("fitted"):
			for slot in {"tires":"rock", "wheels":"beadlock", "suspension":"long_travel", "roof":"cage_spare" if vehicle == "buggy" else "expedition_rack", "front_bumper":"cage_brace" if vehicle == "buggy" else "armor"}:
				var selected := {"tires":"rock", "wheels":"beadlock", "suspension":"long_travel", "roof":"cage_spare" if vehicle == "buggy" else "expedition_rack", "front_bumper":"cage_brace" if vehicle == "buggy" else "armor"}
				build = VehicleCatalog.equip_part(build, slot, selected[slot])
		truck.configure(VehicleCatalog.compose(build))
		truck.core.set_terrain(2 if world_mode else 0)
		for unused in range(360):
			truck.core.step(1.0 / 120.0, 0, 0, true)
		truck._refresh_visuals()
		var center: Vector3 = truck.get_telemetry().position
		if valley != null:
			valley.update_focus(center)
		for view in [["front",Vector3(5,2.8,-5)], ["rear",Vector3(-5,2.5,5)], ["side",Vector3(-6,1.2,0)]]:
			camera.position = center + view[1]
			camera.look_at(center + Vector3(0, 0.28, 0.0))
			for unused in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output_dir.path_join("%s-%s%s.png" % [variant, view[0], "-world" if world_mode else ""]))
		print("VISUAL: ", variant, " ", truck.get_visual_validation())
	quit()
