extends SceneTree

## Twenty-four-second, deterministic in-game review. Two explicitly labelled trail
## starts, followed by actual throttle/brake simulation and raw camera touches.
## Run at --fixed-fps 30, optionally --write-movie validation/expedition-gameplay.avi.
## --headless also runs the same control/stability gates without captures.
const SAVE := "user://offroad_garage_v3.json"
const LEGACY := "user://offroad_setup.json"
const OUTPUT := "res://build/expedition-trace.json"
var scene
var backups: Dictionary = {}
var trace: Array = []
var reviews: Array = []
var failures: Array[String] = []
var frame_number := 0
var rendered := false
var stage := ""
var last_position := Vector3.ZERO
var total_distance := 0.0
var peak_rock_load := 0.0
var peak_rock_wheels := 0
var peak_flex := 0.0
var peak_speed := 0.0
var peak_compression := 0.0
var lowest_up := 1.0
var peak_damage := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	for path in [SAVE, SAVE + ".tmp", LEGACY]:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		DirAccess.remove_absolute(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	root.size = Vector2i(960, 540)
	scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.builds.buggy = VehicleCatalog.default_build("buggy")
	scene.select_vehicle("buggy")
	scene.select_paint("ede7d6")
	scene.fit_crawl_setup()
	scene.change_quality(1)
	for id in ["rockies", "russia"]:
		await expedition(id)
	check(peak_or_review("rock_wheels") >= 2, "Actual gameplay must show multiple wheels simultaneously loading rock")
	check(peak_or_review("rock_load") > 500.0, "At least one real trail must load the tires against native granite contact")
	check(peak_or_review("articulation") > .025, "Natural trail traversal must produce visible solved axle articulation")
	var report := {"fps": 30, "frames": frame_number, "seconds": frame_number / 30.0,
		"rendered": rendered, "reviews": reviews, "failures": failures, "trace": trace}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("EXPEDITION VIDEO: ", JSON.stringify({"frames": frame_number, "reviews": reviews, "failures": failures}))
	scene.clear_controls()
	scene.queue_free()
	await process_frame
	await process_frame
	for path in backups:
		if backups[path] == null:
			DirAccess.remove_absolute(path)
		else:
			var saved := FileAccess.open(path, FileAccess.WRITE)
			saved.store_buffer(backups[path])
			saved.close()
	quit(0 if failures.is_empty() else 1)

func peak_or_review(key: String) -> float:
	var result := 0.0
	for review in reviews:
		result = maxf(result, float(review[key]))
	return result

func expedition(id: String) -> void:
	if scene.driving:
		scene.toggle_mode()
	scene.select_map(id)
	scene.show_garage_tab("trails")
	# Camera state goes through the same deliberate preset action as the HUD.
	scene.set_camera_preset("follow")
	stage = id + "_region_selection"
	await advance(18, false)
	capture("expedition-%s-garage.png" % id)
	scene.toggle_mode()
	# These are declared scene cuts to two real trail locations. No poses or
	# wheel positions are animated during either driving segment.
	var at := Vector3(11, 0, -50) if id == "rockies" else Vector3(-89, 0, -119)
	at.y = float(scene.truck.core.terrain_height(at.x, at.z)) + 1.5
	scene.truck.reset(at)
	scene.world.update_focus(at)
	scene.did_position_camera = false
	scene.throttle_limit = .35
	scene.toast("SILVERPINE RANGE · Split Granite trail" if id == "rockies" else "KARELIAN TAIGA · Lake Vetra forest trail")
	Input.action_press("off_brake")
	stage = id + "_settle"
	await advance(12, false)
	var viewport_size: Vector2 = scene.get_viewport().get_visible_rect().size
	var center := Vector2(viewport_size.x * .56, minf(viewport_size.y * .4, scene.mobile_controls.bar.position.y - 50))
	var hit: Rect2 = scene.mobile_controls.rects.steer
	var miss: Vector2 = hit.position + Vector2(32, -12)
	check(not hit.has_point(miss) and scene.camera_touch_blocked(miss),
		"%s: a touch just outside steering must belong to its guard band" % id)
	var locked_before: Dictionary = scene.camera_preferences()
	scene.toast("FOLLOW LOCKED · Steering misses keep your driving view")
	scene.toast_remaining = 1.2
	stage = id + "_protected_steering_miss"
	touch(4, miss, true)
	for i in range(6):
		drag(4, miss.lerp(center, float(i + 1) / 6.0))
		await advance(1, false)
	touch(4, center, false)
	var guarded_miss: bool = scene.camera_preferences() == locked_before
	check(guarded_miss, "%s: a missed steering touch cannot move or unlock Follow" % id)
	stage = id + "_locked_follow_drag"
	touch(4, center, true)
	for i in range(6):
		drag(4, center + Vector2(90, -35) * float(i + 1) / 6.0)
		await advance(1, false)
	touch(4, center + Vector2(90, -35), false)
	var locked_drag: bool = scene.camera_preferences() == locked_before and scene.camera_preset == "follow" and scene.camera_follow
	check(locked_drag, "%s: deliberate scenery dragging also leaves Follow locked" % id)
	await advance(12, false)
	reset_metrics()
	var start: Vector3 = scene.truck.get_telemetry().position
	stage = id + "_drive"
	Input.action_release("off_brake")
	Input.action_press("off_go")
	await advance(210)
	Input.action_release("off_go")
	Input.action_press("off_brake")
	stage = id + "_hold"
	await advance(51)
	capture("expedition-%s-articulation.png" % id)
	var stats: Dictionary = scene.truck.get_telemetry()
	var displacement := Vector2(stats.position.x - start.x, stats.position.z - start.z).length()
	check(displacement > 2.0, "%s: actual throttle must move the rig along its natural trail" % id)
	check(peak_speed < 3.0, "%s: the crawl demonstration must remain controlled" % id)
	check(lowest_up > .65 and peak_damage < .02, "%s: the actual trail drive must stay upright without significant damage" % id)
	check(stats.speed < .08, "%s: the brakes must hold before inspecting the suspension" % id)
	var review := {"map": id, "displacement": displacement, "travel": total_distance, "peak_speed": peak_speed,
		"rock_load": peak_rock_load, "rock_wheels": peak_rock_wheels, "articulation": peak_flex, "tire_compression": peak_compression,
		"minimum_up": lowest_up, "damage": peak_damage, "stopped_speed": stats.speed,
		"final_position": vector_values(stats.position)}
	stage = id + "_camera"
	scene.set_camera_preset("free")
	check(scene.camera_preset == "free" and not scene.camera_follow,
		"%s: suspension inspection must explicitly choose Free camera" % id)
	scene.toast("FREE CAMERA · Look around the working suspension")
	scene.toast_remaining = .7
	var first := center - Vector2(55, 0)
	var orbit_before: float = scene.drive_orbit
	var pitch_before: float = scene.drive_pitch
	touch(4, first, true)
	for i in range(15):
		drag(4, first + Vector2(150 if id == "rockies" else -150, -18) * float(i + 1) / 15.0)
		await advance(1)
	touch(4, first, false)
	check(absf(wrapf(scene.drive_orbit - orbit_before, -PI, PI)) > .2 and absf(scene.drive_pitch - pitch_before) > .035,
		"%s: one finger must orbit and tilt through the raw touch handler" % id)
	var angle_after_orbit: float = scene.drive_orbit
	var pitch_after_orbit: float = scene.drive_pitch
	var distance_before: float = scene.drive_distance
	var pan_before: Vector2 = scene.drive_pan
	scene.toast("PINCH · Zoom in on the actual axle mounts and links")
	scene.toast_remaining = .7
	touch(4, center - Vector2(55, 0), true)
	touch(7, center + Vector2(55, 0), true)
	for i in range(15):
		var t := float(i + 1) / 15.0
		# Deliberate rotation and translation ensure the pinch stays zoom-only.
		var span := Vector2(lerpf(55.0, 91.0, t), 0).rotated(t * .34)
		drag(4, center + Vector2(0, t * 7) - span)
		drag(7, center + Vector2(0, t * 7) + span)
		await advance(1)
	touch(4, center, false)
	touch(7, center, false)
	var pinch_only: bool = is_equal_approx(scene.drive_orbit, angle_after_orbit) and is_equal_approx(scene.drive_pitch, pitch_after_orbit) and scene.drive_pan == pan_before
	check(pinch_only and scene.drive_distance < distance_before - 1.0, "%s: two fingers must change only zoom" % id)
	scene.toggle_camera_drag()
	scene.toast("ONE FINGER · Pan to place the tire contact in view")
	scene.toast_remaining = .7
	touch(4, first, true)
	for i in range(15):
		drag(4, first + Vector2(-19, -13) * float(i + 1) / 15.0)
		await advance(1)
	touch(4, first, false)
	check(scene.drive_pan.distance_to(pan_before) > .08, "%s: one finger must pan in Pan mode" % id)
	review.camera = {"guarded_steering_miss": guarded_miss, "follow_drag_locked": locked_drag,
		"inspection_preset": scene.camera_preset, "one_finger_orbit": wrapf(angle_after_orbit - orbit_before, -PI, PI),
		"one_finger_tilt": pitch_after_orbit - pitch_before, "pinch_zoom": scene.drive_distance - distance_before,
		"pinch_only": pinch_only, "one_finger_pan": [scene.drive_pan.x, scene.drive_pan.y]}
	reviews.append(review)
	capture("expedition-%s-suspension-close.png" % id)
	Input.action_release("off_brake")
	scene.clear_controls()

func reset_metrics() -> void:
	last_position = scene.truck.get_telemetry().position
	total_distance = 0.0
	peak_rock_load = 0.0
	peak_rock_wheels = 0
	peak_flex = 0.0
	peak_speed = 0.0
	peak_compression = 0.0
	lowest_up = 1.0
	peak_damage = 0.0

func advance(count: int, measure := true) -> void:
	for i in range(count):
		await process_frame
		if rendered:
			await RenderingServer.frame_post_draw
		frame_number += 1
		if not measure:
			continue
		var stats: Dictionary = scene.truck.get_telemetry()
		var at: Vector3 = stats.position
		if not at.is_finite() or not is_finite(float(stats.speed)):
			check(false, "%s: nonfinite physics state" % stage)
			continue
		total_distance += at.distance_to(last_position)
		last_position = at
		peak_speed = maxf(peak_speed, absf(stats.speed))
		lowest_up = minf(lowest_up, stats.up.y)
		peak_damage = maxf(peak_damage, stats.damage)
		var load := 0.0
		var rock_wheels := 0
		for value in stats.rock_loads:
			load += float(value)
			rock_wheels += int(value > 20.0)
		peak_rock_load = maxf(peak_rock_load, load)
		peak_rock_wheels = maxi(peak_rock_wheels, rock_wheels)
		for value in stats.axle_articulation:
			peak_flex = maxf(peak_flex, absf(float(value)))
		for value in stats.wheel_compression:
			peak_compression = maxf(peak_compression, float(value))
		if frame_number % 30 == 0:
			trace.append({"frame": frame_number, "stage": stage, "position": vector_values(at),
				"speed": stats.speed, "up": stats.up.y, "damage": stats.damage,
				"rock_wheels": rock_wheels, "wheel_loads": Array(stats.wheel_normal_loads), "rock_loads": Array(stats.rock_loads),
				"wheel_compression": Array(stats.wheel_compression), "axle_articulation": Array(stats.axle_articulation),
				"suspension": Array(stats.suspension), "sim_ms": stats.sim_ms,
				"camera_preset": scene.camera_preset, "camera_position": vector_values(scene.camera.position)})
		if stats.safety_clamps != 0 or stats.rejected_states != 0:
			check(false, "%s: physics required an emergency state repair" % stage)

func capture(filename: String) -> void:
	if rendered:
		root.get_texture().get_image().save_png("res://build/" + filename)

func vector_values(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	scene._input(event)

func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	scene._input(event)
