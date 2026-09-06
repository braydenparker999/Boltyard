extends SceneTree

## Actual driven/settled rubber contact, using the same skin mapping as the GPU.
var checks := 0
var failures := 0
var rendered := false
var reports: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 720)
	for pressure in [0.55, 1.65]:
		await contact_case(pressure)
	check(reports[0].compression > reports[1].compression * 1.5, "Lower pressure causes greater physical compression under the same static load")
	var file := FileAccess.open("res://build/tire-contact-trace.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": reports, "checks": checks, "failures": failures}, "\t"))
	file.close()
	print("TIRE CONTACT VISUALS: %d checks, %d failures; %s" % [checks, failures, JSON.stringify(reports)])
	quit(1 if failures else 0)

func contact_case(pressure: float) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var build := VehicleCatalog.default_build("buggy")
	build = VehicleCatalog.equip_part(build, "tires", "rock")
	build = VehicleCatalog.equip_part(build, "wheels", "beadlock")
	var setup := VehicleCatalog.compose(build)
	setup.tire_pressure = pressure
	var truck = load("res://scripts/offroad_truck.gd").new()
	truck.configure(setup)
	stage.add_child(truck)
	truck.set_process(false)
	truck.set_physics_process(false)
	var world = load("res://scripts/crawl_world.gd").new()
	world.configure(truck.core)
	stage.add_child(world)
	world.set_quality(1)
	truck.reset(Vector3(0, 1.5, 8))
	for i in range(480):
		truck.core.step(1.0 / 120.0, 0.0, 0.0, true)
	truck._refresh_visuals()
	var static_compression := 0.0
	for value in truck.core.get_wheel_visuals().compression:
		static_compression = maxf(static_compression, value)
	var maximum_contacts := 0
	var driven := false
	for i in range(1700):
		truck.core.step(1.0 / 120.0, 0.32, 0.0, false)
		var patches: Array = truck.core.get_tire_contacts()
		for wheel: Array in patches:
			if wheel.size() > maximum_contacts:
				maximum_contacts = wheel.size()
		if maximum_contacts >= 2:
			driven = true
			break
	truck._refresh_visuals()
	var visual: Dictionary = truck.core.get_wheel_visuals()
	var contacts: Array = truck.core.get_tire_contacts()
	check(driven, "Pressure %.2f: a driven tire meets multiple real supporting planes" % pressure)
	check(visual.patch_planes.size() == 24 and visual.patch_centers.size() == 24, "All six physical patches per wheel fit the fixed mobile shader buffers")
	var penetration := 0.0
	var rim_error := 0.0
	var plane_error := 0.0
	var inspected := 0
	var selected := 0
	for w in range(4):
		if contacts[w].size() > contacts[selected].size():
			selected = w
		for j in range(contacts[w].size()):
			var patch: Dictionary = contacts[w][j]
			var packed: Color = visual.patch_planes[w * 6 + j]
			plane_error = maxf(plane_error, Vector3(packed.r, packed.g, packed.b).distance_to(patch.normal))
			plane_error = maxf(plane_error, absf(packed.a - patch.normal.dot(patch.point)))
		for k in range(96):
			var phase := k / 96.0
			var rim: Vector3 = truck._debug_vertex(200 + w, Vector3(phase, 0.5, 0.545))
			rim_error = maxf(rim_error, absf(rim.distance_to(truck._nodes[16+w*21]) - setup.tire_radius*.88*.545))
			for across in [.12, .5, .88]:
				var point: Vector3 = truck._debug_vertex(16 + w*21, Vector3(phase, across, 1.065))
				check(point.is_finite(), "Loaded rubber stays finite")
				for j in range(contacts[w].size()):
					var patch: Dictionary = contacts[w][j]
					var radius: float = visual.patch_centers[w*6+j].a
					var delta: Vector3 = point - patch.point
					var tangent: Vector3 = delta - patch.normal * delta.dot(patch.normal)
					if tangent.length() < radius - .004:
						inspected += 1
						penetration = maxf(penetration, -delta.dot(patch.normal))
	check(plane_error < .0001, "Every exported skin plane matches its physical contact")
	check(inspected > 20 and penetration < .005, "Loaded padded tread conforms locally to multiple faces without visible penetration")
	check(rim_error < .0001, "Metal rims stay circular while the rubber deforms")
	var nodes: PackedVector3Array = truck.core.get_nodes()
	var focus: Vector3 = nodes[16+selected*21]
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.near = .06
	camera.fov = 47
	var side := -1.0 if selected % 2 == 0 else 1.0
	camera.position = focus + Vector3(side*2.1,.55,-1.4)
	camera.look_at(focus + Vector3(0,-.12,0))
	if rendered:
		for frame in range(4):
			await process_frame
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/tire-contact-%s.png" % ("soft" if pressure < 1 else "firm"))
	reports.append({"pressure": pressure, "compression": static_compression, "max_contacts": maximum_contacts,
		"penetration": penetration, "rim_error": rim_error, "patch_vertices": inspected})
	stage.queue_free()
	await process_frame
	await process_frame
