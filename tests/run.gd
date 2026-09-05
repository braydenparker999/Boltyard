extends SceneTree

var failures = 0
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame

func run() -> void:
	var bp = YardBlueprint.new()
	verify(bp.load_file("res://data/starter.json") == "", "starter parses")
	verify(bp.parts.size() == 21, "starter has 21 parts")
	verify(bp.drive_error() == "", "starter can drive")
	verify(is_equal_approx(bp.total_mass(), 270.0), "part masses sum to 270 kg")
	var original = bp.to_data()
	var copy = YardBlueprint.new()
	verify(copy.from_data(JSON.parse_string(JSON.stringify(original))) == "", "JSON round-trip")
	verify(copy.parts == bp.parts, "round-trip retains cells, kinds, and rotations")
	var malformed = original.duplicate(true)
	malformed.parts[0].x = 0.5
	verify(bp.from_data(malformed) != "", "fractional coordinates rejected")
	verify(bp.to_data() == original, "failed load preserves current build")
	malformed = original.duplicate(true)
	malformed.parts.append(malformed.parts[0].duplicate())
	verify(bp.from_data(malformed) != "", "overlapping parts rejected")
	malformed = original.duplicate(true)
	malformed.parts[0].kind = "unknown"
	verify(bp.from_data(malformed) != "", "unknown parts rejected")
	verify(bp.put(Vector3i(3, 1, 4), "wheel") != "", "elevated wheels rejected")
	bp.put(Vector3i(3, 2, 4), "weight")
	verify(bp.drive_error().contains("Connect"), "detached solids cannot drive")
	bp.from_data(original)
	bp.parts.erase(Vector3i(0, 1, 1))
	verify(bp.drive_error().contains("motor"), "missing motor rejected")
	bp.from_data(original)
	bp.put(Vector3i(1, 1, 0), "seat")
	verify(bp.drive_error().contains("exactly one"), "duplicate seat rejected")
	bp.from_data(original)
	verify(bp.save_file("user://test-blueprint.json") == OK, "save succeeds")
	verify(copy.load_file("user://test-blueprint.json") == "", "saved file loads")
	verify(copy.parts == bp.parts, "save retains full blueprint")
	DirAccess.remove_absolute("user://test-blueprint.json")

	var world = Node3D.new()
	root.add_child(world)
	var floor_body = StaticBody3D.new()
	world.add_child(floor_body)
	var collider = CollisionShape3D.new()
	var floor_shape = BoxShape3D.new()
	floor_shape.size = Vector3(200, 1, 200)
	collider.shape = floor_shape
	collider.position.y = -0.5
	floor_body.add_child(collider)
	var vehicle = YardVehicle.new()
	vehicle.configure(bp)
	vehicle.transform = vehicle.spawn_transform
	world.add_child(vehicle)
	await frames(180)
	verify(vehicle.position.y > 0.25 and vehicle.position.y < 0.85, "car settles above floor")
	verify(vehicle.grounded_wheels == 4, "four suspension rays find the floor")
	verify(vehicle.global_basis.y.dot(Vector3.UP) > 0.9, "starter remains upright at rest")
	var initial = vehicle.position
	vehicle.throttle = 1.0
	await frames(180)
	verify(vehicle.position.z < initial.z - 3.0, "throttle moves the car toward FRONT")
	verify(vehicle.linear_velocity.length() > 1.0, "powered tires accelerate")
	vehicle.throttle = 0.0
	vehicle.braking = true
	await frames(120)
	verify(vehicle.linear_velocity.length() < 1.0, "braking slows the car")
	vehicle.braking = false
	vehicle.throttle = 1.0
	vehicle.steer_input = 0.6
	var old_forward = -vehicle.global_basis.z
	await frames(120)
	verify(old_forward.angle_to(-vehicle.global_basis.z) > 0.08, "steering changes heading")
	vehicle.throttle = 0.0
	vehicle.steer_input = 0.0
	vehicle.request_reset()
	await frames(3)
	verify(vehicle.position.distance_to(vehicle.spawn_transform.origin) < 0.2, "recovery returns to launch pad")
	world.free()

	# Instantiate the actual UI and exercise mode changes, edit, and undo.
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await frames(5)
	scene.starter()
	verify(scene.grid.get_global_rect().end.y < 720, "build grid fits the landscape viewport")
	scene.select_part("weight")
	scene.set_layer(1)
	scene.edit_cell(Vector3i(1, 1, 0))
	verify(scene.blueprint.count_kind("weight") == 1, "grid edit adds chosen part")
	scene.undo()
	verify(scene.blueprint.count_kind("weight") == 0, "undo restores the build")
	scene.toggle_mode()
	await frames(5)
	verify(scene.driving and is_instance_valid(scene.car), "Drive creates the physics vehicle")
	verify(scene.drive_panel.visible and not scene.build_panel.visible, "Drive swaps touch controls")
	scene.toggle_mode()
	verify(not scene.driving and scene.preview.visible, "Build restores preview")
	scene.free()
	print("BOLT YARD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

