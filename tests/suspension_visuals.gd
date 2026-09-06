extends SceneTree
var failures := 0
var checks := 0
var reports: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + text)
func run() -> void:
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var build := VehicleCatalog.default_build("buggy")
	for slot in ["tires", "wheels", "suspension"]:
		build = VehicleCatalog.equip_part(build, slot, {"tires": "rock", "wheels": "beadlock", "suspension": "long_travel"}[slot])
	var truck = load("res://scripts/offroad_truck.gd").new()
	truck.configure(VehicleCatalog.compose(build))
	stage.add_child(truck)
	truck.set_process(false)
	truck.set_physics_process(false)
	var world = load("res://scripts/crawl_world.gd").new()
	world.configure(truck.core)
	stage.add_child(world)
	world.set_quality(1)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.near = .04
	camera.fov = 44
	for pose in ["loaded", "droop", "steering", "cross_axle"]:
		truck.reset(Vector3(-.9, 2.8, -30) if pose == "cross_axle" else Vector3(0, 1.5, 8))
		for i in range(420):
			truck.core.step(1.0 / 120.0, 0.0, 0.8 if pose == "steering" else 0.0, false)
		if pose == "droop":
			truck.reset(Vector3(0, 5, 8))
			for i in range(18):
				truck.core.step(1.0 / 120.0, 0.0, 0.0, false)
		truck._refresh_visuals()
		var visual: Dictionary = truck.core.get_wheel_visuals()
		var maximum_error := 0.0
		for w in range(4):
			var dims: Color = visual.shock_dimensions[w]
			var body_start: Vector3 = truck._debug_vertex(148 + w, Vector3.ZERO)
			var body_end: Vector3 = truck._debug_vertex(148 + w, Vector3(1, 0, 0))
			maximum_error = maxf(maximum_error, absf(body_start.distance_to(body_end) - dims.a))
			var shaft_start: Vector3 = truck._debug_vertex(152 + w, Vector3.ZERO)
			var shaft_end: Vector3 = truck._debug_vertex(152 + w, Vector3(1, 0, 0))
			maximum_error = maxf(maximum_error, absf(shaft_start.distance_to(shaft_end) - (dims.b - dims.g + .06)))
			var top: Vector3 = visual.link_starts[8 + w]
			var bottom: Vector3 = visual.link_ends[8 + w]
			maximum_error = maxf(maximum_error, truck._debug_vertex(120 + w, Vector3.ZERO).distance_to(top))
			maximum_error = maxf(maximum_error, truck._debug_vertex(124 + w, Vector3.ZERO).distance_to(bottom))
			var a: Vector3 = truck._debug_vertex(128 + w, Vector3(.5, .053, 0), .008)
			var b: Vector3 = truck._debug_vertex(128 + w, Vector3(.5, .053, 0), -.008)
			maximum_error = maxf(maximum_error, absf(a.distance_to(b) - .016))
			check(dims.b - dims.g + .06 < dims.a, "%s shaft stroke fits the fixed body" % pose)
			check((minf(top.distance_to(bottom), dims.r) - .17) / 6.0 > .016, "%s spring has clearance between turns" % pose)
		check(maximum_error < .0001, "%s fixed body, shaft, wire and eye attachment" % pose)
		check(truck.get_visual_validation().live_nonfinite_vertices == 0, "%s uploaded mesh deforms to finite geometry" % pose)
		var focus: Vector3 = (visual.link_starts[8] + visual.link_ends[8]) * .5
		camera.position = focus + Vector3(-2.0, .45, -2.5)
		camera.look_at(focus + Vector3(.30, -.05, .10))
		if DisplayServer.get_name() != "headless":
			for i in range(3):
				await process_frame
				await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/suspension-%s.png" % pose)
		reports.append({"pose": pose, "metric_error_m": maximum_error, "triangles": truck.get_telemetry().render_triangles})
	var file := FileAccess.open("res://build/suspension-visuals.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "poses": reports}, "\t"))
	print("SUSPENSION VISUALS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
