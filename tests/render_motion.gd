extends SceneTree
const Pose = preload("res://scripts/vehicle_pose.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
func run() -> void:
	var truck = load("res://scripts/offroad_truck.gd").new()
	truck.configure({"procedural_body": true})
	root.add_child(truck)
	truck.set_process(false)
	truck.set_physics_process(false)
	truck.reset(Vector3(0, 20, 0))
	truck.core.apply_impact(Vector3(5000, 0, 1500))
	var previous := Pose.capture(truck.core)
	truck.core.step(1.0 / 60.0, .4, .7, false)
	var current := Pose.capture(truck.core)
	for alpha in [0.0, .25, .5, .75, 1.0]:
		var sample := Pose.interpolate(previous, current, alpha)
		var error := 0.0
		for i in range(16):
			for j in range(i + 1, 16):
				error = maxf(error, absf(sample.nodes[i].distance_to(sample.nodes[j]) - current.nodes[i].distance_to(current.nodes[j])))
		check(error < .00002, "render interpolation retains rigid body dimensions")
		check(sample.body.basis.is_equal_approx(sample.body.basis.orthonormalized()), "render body axes stay orthonormal")
	# A synthetic half-turn rotor change isolates interpolation from tire forces.
	# The midpoint must remain round, rather than collapse between opposing points.
	previous = Pose.capture(truck.core)
	current = previous.duplicate(true)
	for w in range(4):
		var hub := 16 + w * 21
		var axis: Vector3 = current.wheels.axes[w]
		for i in range(1, 21):
			current.nodes[hub + i] = current.nodes[hub] + (current.nodes[hub + i] - current.nodes[hub]).rotated(axis, PI * .9)
		current.wheels.phases[w] += PI * .9
	var midpoint := Pose.interpolate(previous, current, .5)
	for w in range(4):
		var hub := 16 + w * 21
		check(absf(midpoint.nodes[hub + 1].distance_to(midpoint.nodes[hub]) - previous.nodes[hub + 1].distance_to(previous.nodes[hub])) < .00001, "spinning tire keeps its radius between physics samples")
	truck._physics_process(1.0 / 60.0)
	truck.reset(Vector3(80, 5, -30))
	check(truck._previous_pose.nodes[0].distance_to(truck._current_pose.nodes[0]) == 0.0, "recovery clears old visual history")
	check(truck.get_render_pose().body.origin.distance_to(truck.core.get_nodes()[0]) < .00001, "teleport never blends across the map")
	truck.free()
	print("RENDER MOTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
