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
	for mode in [4, 5]:
		truck.core.set_terrain(mode)
		truck.reset(Vector3(0, 0, 8))
		for i in range(180):
			truck.core.step(1.0 / 120.0, 0.0, 0.0, false)
		truck._refresh_visuals()
		var links: Dictionary = truck.core.get_wheel_visuals()
		check(truck.core.get_nodes().size() == 100 and truck.core.get_rest_nodes().size() == 100 and truck.core.get_stats().physical_nodes == 24, "map %d hides carrier particles from the fixed GPU skin buffer" % mode)
		var endpoint_error := 0.0
		for binding in [100, 101, 102, 103, 104, 105, 106, 107, 110, 111, 112, 113, 114, 115]:
			var slot: int = binding - 92 if binding < 104 else (binding - 104 if binding < 108 else (binding - 106 if binding < 114 else binding - 102))
			endpoint_error = maxf(endpoint_error, truck._debug_vertex(binding, Vector3.ZERO).distance_to(links.link_starts[slot]))
			endpoint_error = maxf(endpoint_error, truck._debug_vertex(binding, Vector3(1, 0, 0)).distance_to(links.link_ends[slot]))
		check(endpoint_error < 0.0001, "map %d draws all links, coilovers and driveshafts at their physical endpoints" % mode)
		check(truck.get_visual_validation().live_nonfinite_vertices == 0, "map %d keeps the articulated skin finite" % mode)
		var tree: Dictionary = truck.core.get_expedition_obstacles()[0]
		var base: float = truck.core.terrain_height(tree.x, tree.z)
		var start := Vector3(tree.x - tree.radius - 2.0, base + 1.0, tree.z)
		var desired := Vector3(tree.x + tree.radius + 2.0, base + 1.0, tree.z)
		var eye: Vector3 = truck.core.camera_safe_position(start, desired, 0.22)
		check(eye.is_finite() and eye.x < tree.x - tree.radius, "map %d camera clips against native tree trunks" % mode)
	truck.free()
	print("CRAWLWORKS VISUALS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
