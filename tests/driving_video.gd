extends SceneTree

# Fixed-rate movie capture exercises live controls, suspension and body skins.
# Run with --fixed-fps 30; --headless retains the same motion acceptance.
# A rendered run may additionally use --write-movie build/driving-review.avi.
const SAVE = "user://offroad_garage_v3.json"
const SAVE_FILES = [SAVE, SAVE + ".tmp", "user://offroad_setup.json"]
var save_backups: Dictionary = {}
var rendered = false
var scene
var output_dir: String
var path = [Vector3(0, 0, -36), Vector3(-43, 0, -74), Vector3(-90, 0, -105), Vector3(-143, 0, -75), Vector3(-176, 0, 8)]
var path_index = 0
var peak_speed = 0.0
var worst_up = 1.0
var max_damage = 0.0
var trace: Array = []
var frame_costs: Array[float] = []
var peak_draw_calls = 0
var peak_primitives = 0

func _initialize() -> void:
	call_deferred("run")

func release_controls() -> void:
	for action in ["off_go", "off_reverse", "off_left", "off_right", "off_brake"]:
		Input.action_release(action)

func steer_along_trail() -> void:
	var stats: Dictionary = scene.truck.get_telemetry()
	var position: Vector3 = stats.position
	var to_point: Vector3 = path[path_index] - position
	to_point.y = 0
	if to_point.length() < 9.0 and path_index < path.size() - 1:
		path_index += 1
		to_point = path[path_index] - position
		to_point.y = 0
	var forward: Vector3 = stats.forward
	var angle = wrapf(atan2(to_point.x, -to_point.z) - atan2(forward.x, -forward.z), -PI, PI)
	var speed: float = absf(float(stats.speed))
	var desired_speed = lerpf(11.0, 5.0, clampf(absf(angle) / 0.9, 0, 1))
	release_controls()
	var steer = clampf(angle * 1.7, -1, 1)
	if absf(steer) > 0.01:
		Input.action_press("off_right" if steer > 0 else "off_left", absf(steer))
	if speed < desired_speed:
		Input.action_press("off_go", clampf((desired_speed - speed) * 0.5, 0.15, 1.0))
	elif speed > desired_speed + 2.0:
		Input.action_press("off_brake")

func save_frame(name: String) -> void:
	if not rendered:
		return
	var error = root.get_texture().get_image().save_png(output_dir.path_join(name + ".png"))
	if error != OK:
		push_error("Could not save motion review " + name)

func preserve_and_seed_garage() -> void:
	for save_path in SAVE_FILES:
		save_backups[save_path] = FileAccess.get_file_as_bytes(save_path) if FileAccess.file_exists(save_path) else null
	var builds: Dictionary = {}
	for id in VehicleCatalog.VEHICLES:
		builds[id] = VehicleCatalog.default_build(id)
	# This is the established Juniper road regression. New region defaults must
	# not silently move the route into a different landscape or collision mode.
	var fixture = {"version": 3, "selected_map": "legacy", "selected_vehicle": "pickup", "builds": builds, "quality": 1, "discovered": [], "destination": "grove", "map_progress": {"legacy": {"discovered": [], "destination": "grove"}}}
	var file = FileAccess.open(SAVE, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(fixture))
	file.close()

func restore_garage() -> void:
	for save_path in SAVE_FILES:
		if save_backups[save_path] == null:
			if FileAccess.file_exists(save_path):
				assert(DirAccess.remove_absolute(save_path) == OK)
			assert(not FileAccess.file_exists(save_path))
		else:
			var file = FileAccess.open(save_path, FileAccess.WRITE)
			assert(file != null)
			file.store_buffer(save_backups[save_path])
			file.flush()
			assert(file.get_error() == OK)
			file.close()
			assert(FileAccess.get_file_as_bytes(save_path) == save_backups[save_path])

func run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	preserve_and_seed_garage()
	root.size = Vector2i(960, 540)
	output_dir = ProjectSettings.globalize_path("res://").path_join("build")
	DirAccess.make_dir_recursive_absolute(output_dir)
	scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.builds.pickup = VehicleCatalog.default_build("pickup")
	scene.select_vehicle("pickup")
	scene.change_quality(1)
	scene.select_destination("grove")
	# Retain the original full-travel road pedal, independent of the adjustable
	# crawling throttle cap introduced in the newer driving UI.
	scene.throttle_limit = 1.0
	scene.toast_remaining = 0.0
	for frame in range(630):
		if frame == 30:
			scene.toggle_mode()
			scene.toast_remaining = 0.0
		if frame >= 30 and frame < 540:
			steer_along_trail()
		elif frame >= 540:
			release_controls()
			Input.action_press("off_brake")
		await process_frame
		if rendered:
			await RenderingServer.frame_post_draw
		if frame >= 30:
			var stats: Dictionary = scene.truck.get_telemetry()
			peak_speed = maxf(peak_speed, absf(float(stats.speed)))
			worst_up = minf(worst_up, stats.up.y)
			max_damage = maxf(max_damage, float(stats.damage))
			frame_costs.append(float(stats.sim_ms))
			peak_draw_calls = maxi(peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			peak_primitives = maxi(peak_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			if frame % 15 == 0:
				trace.append({"time": frame / 30.0, "speed_kmh": stats.speed * 3.6, "position": [stats.position.x, stats.position.y, stats.position.z], "up": stats.up.y, "damage": stats.damage, "wheel_contacts": stats.wheels_grounded, "sim_ms": stats.sim_ms})
		if frame in [120, 270, 420, 600]:
			save_frame("motion-%03d" % frame)
	release_controls()
	var stats: Dictionary = scene.truck.get_telemetry()
	frame_costs.sort()
	var report = {"peak_speed_kmh": peak_speed * 3.6, "minimum_up_y": worst_up, "max_damage": max_damage, "final_speed_kmh": stats.speed * 3.6, "physics_ms_p95": frame_costs[int(frame_costs.size() * 0.95)], "peak_draw_calls": peak_draw_calls, "peak_primitives": peak_primitives, "safety_clamps": stats.safety_clamps, "rejected_states": stats.rejected_states, "dropped_time": stats.dropped_time, "samples": trace}
	var file = FileAccess.open(output_dir.path_join("driving-trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var good: bool = peak_speed > 6.5 and worst_up > 0.70 and max_damage < 0.025 and absf(float(stats.speed)) < 0.8 and stats.rejected_states == 0
	print("DRIVING REVIEW: peak %.1f km/h, minimum up %.3f, damage %.4f, final %.2f km/h, native p95 %.3f ms" % [peak_speed * 3.6, worst_up, max_damage, stats.speed * 3.6, report.physics_ms_p95])
	if not good:
		push_error("Driving review did not meet acceleration, upright, braking or damage acceptance.")
	scene.free()
	restore_garage()
	quit(0 if good else 1)
