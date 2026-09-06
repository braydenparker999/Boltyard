extends SceneTree

const Catalog = preload("res://scripts/vehicle_catalog.gd")
const Truck = preload("res://scripts/offroad_truck.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func run() -> void:
	var build = Catalog.default_build()
	build = Catalog.equip_part(build, "tires", "rock")
	build = Catalog.equip_part(build, "wheels", "beadlock")
	build.tuning.front_locked = true
	build.tuning.rear_locked = false
	var setup = Catalog.compose(build)
	var truck = Truck.new()
	truck.configure(setup)
	root.add_child(truck)
	truck.set_process(false)
	truck.set_physics_process(false)
	truck.core.set_terrain(3)
	for i in range(360):
		truck.core.step(1.0 / 120.0, 0.0, 0.0, true)
	truck._refresh_visuals()
	var visual: Dictionary = truck.core.get_wheel_visuals()
	var nodes: PackedVector3Array = truck.core.get_nodes()
	var radius_error := 0.0
	var penetration := 0.0
	var compression := 0.0
	for w in range(4):
		compression = maxf(compression, visual.compression[w])
		for i in range(72):
			var phase := float(i) / 72.0
			var rim: Vector3 = truck._debug_vertex(200 + w, Vector3(phase, 0.5, 0.545))
			radius_error = maxf(radius_error, absf(rim.distance_to(nodes[16 + 21 * w]) - setup.tire_radius * 0.88 * 0.545))
			var tread: Vector3 = truck._debug_vertex(16 + 21 * w, Vector3(phase, 0.5, 1.065))
			if visual.compression[w] > 0.0001:
				penetration = maxf(penetration, -(tread - visual.points[w]).dot(visual.normals[w]))
	check(compression > 0.005, "loaded soft tires have measured physical compression")
	check(radius_error < 0.0001, "metal rims remain circular around the physical hubs under tire load")
	check(penetration < 0.0001, "outer tread follows the loaded contact plane without sinking through it")
	check(truck.core.get_dynamic_objects().size() == 9, "crawl world exposes nine physical movable bodies")
	var before: Array = truck.core.get_dynamic_object_poses()
	truck.reset()
	var after: Array = truck.core.get_dynamic_object_poses()
	check(before.size() == after.size() and after[0].origin.is_finite(), "recovery returns valid object poses with stable mesh ordering")
	var escaped: Vector3 = truck.core.camera_safe_position(Vector3(0, 0.75, -3), Vector3(0, 0.35, -3), 0.22)
	check(escaped.is_finite() and escaped.y > 0.85, "camera escapes the slab when both anchor padding and desired eye overlap it")
	var clear_eye := Vector3(5, 4, 8)
	var unobstructed: Vector3 = truck.core.camera_safe_position(Vector3(0, 2, 8), clear_eye, 0.22)
	check(unobstructed.distance_to(clear_eye) < 0.0001, "an unobstructed camera ray preserves its desired eye position")
	var stopped: Vector3 = truck.core.camera_safe_position(Vector3(0, 2, -3), Vector3(0, 0.35, -3), 0.22)
	check(stopped.y > 0.85 and stopped.y < 1.0, "an outside camera ray stops before the padded slab surface")
	truck.free()
	print("CRAWLWORKS VISUALS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
