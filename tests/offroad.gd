extends SceneTree

var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	check(ClassDB.class_exists("SoftBodyRig"), "native soft-body extension is registered")
	if not ClassDB.class_exists("SoftBodyRig"):
		quit(1)
		return
	var core = ClassDB.instantiate("SoftBodyRig")
	core.configure({})
	core.set_terrain(0)
	var nodes: PackedVector3Array = core.get_nodes()
	check(nodes.size() == 100, "vehicle exposes the complete body and wheel render binding")
	check(core.get_stats().physical_nodes < nodes.size(), "telemetry distinguishes dynamic nodes from wheel render guides")
	check(core.get_beams().size() >= 100, "vehicle contains a deformable structural beam network")
	check(core.get_wheel_hubs().size() == 4, "four independent suspension and wheel assemblies")
	for index in range(360):
		core.step(1.0 / 120.0, 0, 0, true)
	var rest: Dictionary = core.get_stats()
	check(rest.contacts > 0, "round wheel contacts support the vehicle")
	check(rest.wheels_grounded == 4, "all four tires carry load after settling")
	check(rest.position.y > 0.2 and rest.position.y < 2.0, "native vehicle settles above ground")
	check(rest.up.dot(Vector3.UP) > 0.7, "native vehicle settles upright")
	var origin: Vector3 = rest.position
	for index in range(480):
		core.step(1.0 / 120.0, 1, 0, false)
	var moving: Dictionary = core.get_stats()
	check(moving.position.z < origin.z - 12.0 and moving.speed > 5.0, "wheel traction produces useful trail acceleration within four seconds")
	core.set_drivetrain(false,false)
	check(core.get_stats().position.distance_to(moving.position) < 0.001, "drivetrain toggle preserves physical state")
	core.set_drivetrain(true,true)
	core.reset(Vector3(0,1.5,8))
	check(core.get_stats().broken_beams == 0, "repair rebuilds damaged connections")
	# Unequal frame partitions must reach the same fixed simulation state.
	var other = ClassDB.instantiate("SoftBodyRig")
	other.configure({})
	other.set_terrain(0)
	other.reset(Vector3(0,1.5,8))
	for index in range(120):
		core.step(1.0 / 60.0, 0, 0, true)
	for index in range(80):
		other.step(1.0 / 40.0, 0, 0, true)
	check(core.get_stats().position.distance_to(other.get_stats().position) < 0.02, "fixed stepping is independent of render cadence")
	core = null
	other = null
	var scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	for index in range(10):
		await physics_frame
	check(is_instance_valid(scene.truck), "off-road garage starts with native truck")
	check(not scene.driving, "garage is initial mode")
	scene.toggle_mode()
	for index in range(4):
		await physics_frame
	check(scene.driving, "garage enters trail mode")
	Input.action_press("off_right")
	Input.action_press("off_go")
	for index in range(3):
		await physics_frame
	check(scene.truck.steering > 0 and scene.truck.throttle > 0, "right and throttle inputs reach native solver with correct signs")
	Input.action_release("off_right")
	Input.action_release("off_go")
	scene.toggle_mode()
	check(not scene.driving, "trail returns to tuning garage")
	scene.free()
	print("OFFROAD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
