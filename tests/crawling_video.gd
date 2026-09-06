extends SceneTree
var scene
var trace: Array = []
const SAVE = "user://offroad_garage_v3.json"
var backup = null
var temporary_backup = null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	backup = FileAccess.get_file_as_bytes(SAVE) if FileAccess.file_exists(SAVE) else null
	temporary_backup = FileAccess.get_file_as_bytes(SAVE + ".tmp") if FileAccess.file_exists(SAVE + ".tmp") else null
	root.size = Vector2i(960, 540)
	scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.builds.pickup = VehicleCatalog.default_build("pickup")
	scene.select_vehicle("pickup")
	scene.toggle_course()
	scene.fit_crawl_setup()
	scene.change_quality(1)
	scene.toggle_mode()
	scene.throttle_limit = 0.30
	var highest = 0.0
	var peak_speed = 0.0
	var rock_support = 0.0
	for frame in range(450):
		if frame == 60:
			Input.action_press("off_go")
		if frame == 390:
			Input.action_release("off_go")
			Input.action_press("off_brake")
		await process_frame
		await RenderingServer.frame_post_draw
		var stats: Dictionary = scene.truck.get_telemetry()
		highest = maxf(highest, stats.position.y)
		peak_speed = maxf(peak_speed, stats.speed)
		var current_rock_load = 0.0
		for load in stats.rock_loads:
			current_rock_load += load
		rock_support = maxf(rock_support, current_rock_load)
		if frame % 30 == 0:
			trace.append({"time": frame / 30.0, "position": [stats.position.x, stats.position.y, stats.position.z], "speed": stats.speed, "loads": Array(stats.wheel_loads), "rock_loads": Array(stats.rock_loads), "spin": Array(stats.wheel_spin), "slip": Array(stats.wheel_slip), "suspension": Array(stats.suspension), "up": stats.up.y, "sim_ms": stats.sim_ms})
		if frame in [30, 210, 320, 440]:
			root.get_texture().get_image().save_png("res://build/crawl-%03d.png" % frame)
	Input.action_release("off_brake")
	var stats: Dictionary = scene.truck.get_telemetry()
	var good: bool = stats.position.z < -4 and stats.position.z > -22 and highest > 1.1 and rock_support > 5000 and peak_speed < 3.0 and stats.up.y > 0.85 and stats.damage < 0.01 and stats.speed < 0.05 and stats.safety_clamps == 0 and stats.rejected_states == 0
	FileAccess.open("res://build/crawling-trace.json", FileAccess.WRITE).store_string(JSON.stringify(trace, "\t"))
	print("CRAWLING REVIEW: z %.2f, peak frame height %.2f, final speed %.3f, damage %.4f, up %.3f" % [stats.position.z, highest, stats.speed, stats.damage, stats.up.y])
	if not good:
		push_error("Crawling motion did not meet climb, hold or stability acceptance")
	# Begin a clearly identified second demonstration at the loose-object line.
	# The truck is reset once, then real throttle/brake and solved poses drive it.
	scene.clear_controls()
	scene.truck.reset(Vector3(9.1, 1.5, -8.0))
	scene.throttle_limit = .18
	scene.camera_follow = false
	scene.drive_orbit = -2.06
	scene.drive_pitch = .39
	scene.drive_distance = 8.4
	scene.drive_pan = Vector2.ZERO
	scene.did_position_camera = false
	scene.update_camera_tools()
	scene.toast("LOOSE LINE · Stones, timber and crates react to the rig.")
	Input.action_press("off_brake")
	for frame in range(30):
		await process_frame
		await RenderingServer.frame_post_draw
	var before: Array = scene.truck.core.get_dynamic_object_poses()
	Input.action_release("off_brake")
	Input.action_press("off_go")
	for frame in range(180):
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 30 == 0:
			var current: Dictionary = scene.truck.get_telemetry()
			trace.append({"stage": "loose_line", "time": 16.0 + frame / 30.0, "position": [current.position.x, current.position.y, current.position.z], "speed": current.speed, "damage": current.damage})
	Input.action_release("off_go")
	Input.action_press("off_brake")
	for frame in range(30):
		await process_frame
		await RenderingServer.frame_post_draw
	var after: Array = scene.truck.core.get_dynamic_object_poses()
	var moved := 0.0
	var motion: Array = []
	for index in mini(before.size(), after.size()):
		var a: Transform3D = before[index]
		var b: Transform3D = after[index]
		var displacement := a.origin.distance_to(b.origin)
		moved = maxf(moved, displacement)
		motion.append({"index": index, "before": [a.origin.x, a.origin.y, a.origin.z], "after": [b.origin.x, b.origin.y, b.origin.z], "meters": displacement})
	trace.append({"stage": "solved_object_motion", "objects": motion})
	var object_stats: Dictionary = scene.truck.get_telemetry()
	var objects_good: bool = moved > .025 and object_stats.damage < .01 and object_stats.up.y > .78 and object_stats.safety_clamps == 0 and object_stats.rejected_states == 0
	good = good and objects_good
	print("LOOSE LINE REVIEW: solved movement %.3f m, rig z %.2f, damage %.4f, up %.3f" % [moved, object_stats.position.z, object_stats.damage, object_stats.up.y])
	if not objects_good:
		push_error("Loose-object control demonstration did not produce stable physical movement")
	root.get_texture().get_image().save_png("res://build/crawl-loose-objects.png")
	# Demonstrate the Android raw-touch route, including frame-coalesced twist,
	# pinch and pan. No direct camera transform is used for the gesture segment.
	scene.toast("TWO FINGERS · Pinch, twist and pan around the settled rig.")
	scene.camera_pan_mode = false
	scene.update_camera_tools()
	var viewport_size: Vector2 = scene.get_viewport().get_visible_rect().size
	var center := Vector2(viewport_size.x * .58, viewport_size.y * .56)
	var first := center - Vector2(80, 0)
	var second := center + Vector2(80, 0)
	var original_orbit: float = scene.drive_orbit
	var original_distance: float = scene.drive_distance
	touch(4, first, true)
	touch(7, second, true)
	for frame in range(60):
		var t := float(frame + 1) / 60.0
		var span := Vector2(lerpf(80.0, 125.0, t), 0).rotated(t * .72)
		drag(4, center + Vector2(0, t * 22.0) - span)
		drag(7, center + Vector2(0, t * 22.0) + span)
		await process_frame
		await RenderingServer.frame_post_draw
	touch(4, first, false)
	touch(7, second, false)
	scene.toggle_camera_drag()
	touch(4, first, true)
	touch(7, second, true)
	for frame in range(30):
		var offset := Vector2(30, 14) * float(frame + 1) / 30.0
		drag(4, first + offset)
		drag(7, second + offset)
		await process_frame
		await RenderingServer.frame_post_draw
	touch(4, first, false)
	touch(7, second, false)
	var camera_good: bool = absf(scene.drive_orbit - original_orbit) > .2 and absf(scene.drive_distance - original_distance) > .15 and scene.drive_pan.length() > .02
	good = good and camera_good
	print("CAMERA MOVIE REVIEW: raw twist %.3f rad, zoom %.3f m, pan %.3f m" % [scene.drive_orbit - original_orbit, scene.drive_distance - original_distance, scene.drive_pan.length()])
	trace.append({"stage": "raw_touch_camera", "orbit_delta": scene.drive_orbit - original_orbit, "zoom_delta": scene.drive_distance - original_distance, "pan": [scene.drive_pan.x, scene.drive_pan.y]})
	for frame in range(30):
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/crawl-two-finger-view.png")
	Input.action_release("off_brake")
	FileAccess.open("res://build/crawling-trace.json", FileAccess.WRITE).store_string(JSON.stringify(trace, "\t"))
	scene.clear_controls()
	scene.queue_free()
	await process_frame
	await process_frame
	restore_file(SAVE, backup)
	restore_file(SAVE + ".tmp", temporary_backup)
	quit(0 if good else 1)

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

func restore_file(path: String, bytes) -> void:
	if bytes == null:
		DirAccess.remove_absolute(path)
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
