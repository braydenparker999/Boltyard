extends SceneTree

const Catalog = preload("res://scripts/vehicle_catalog.gd")
const MAIN = preload("res://offroad_main.tscn")
const SAVE_PATH = "user://offroad_garage_v3.json"
const SAVE_FILES = [SAVE_PATH, SAVE_PATH + ".tmp", "user://offroad_setup.json"]
var checks = 0
var failures = 0
var backups: Dictionary = {}

# Exercise the scene's real screen-touch routing and per-frame camera consumer.
# Positions are chosen from visible scenery, and GUI ownership is established
# at touchdown even when a finger subsequently slides away from its control.
# These integration checks use the existing native library; they never build it.
# Original garage, temporary-save, and legacy files are restored byte for byte.

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func near(actual: float, expected: float) -> bool:
	return is_finite(actual) and absf(actual - expected) < 0.0001

func save_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var result = file.get_error() == OK
	file.close()
	return result

func backup_saves() -> void:
	for path in SAVE_FILES:
		var existed = FileAccess.file_exists(path)
		backups[path] = {"existed": existed, "bytes": FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()}

func restore_saves() -> void:
	for path in SAVE_FILES:
		if backups[path].existed:
			check(save_bytes(path, backups[path].bytes) and FileAccess.get_file_as_bytes(path) == backups[path].bytes, "restored original " + path)
		elif FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "removed test-created " + path)

func seed_garage() -> Dictionary:
	var builds: Dictionary = {}
	for id in Catalog.VEHICLES:
		builds[id] = Catalog.default_build(id)
	builds.pickup.paint = "ede7d6"
	builds.scout.tuning = {"engine_torque": 575.0, "mass": 1425.0}
	builds.buggy = Catalog.equip_part(builds.buggy, "tires", "rock")
	return {"version": 3, "selected_vehicle": "scout", "builds": builds, "selected_map": "legacy", "map_progress": {"legacy": {"discovered": ["camp", "lake"], "destination": "ridge"}}, "discovered": ["camp", "lake"], "destination": "ridge", "quality": 0}

func settle(scene) -> void:
	for index in range(8):
		scene._process(0.0)
		await process_frame

func open_scene():
	var scene = MAIN.instantiate()
	root.add_child(scene)
	# Keep the truck stationary and sample only when the test finishes its batch.
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.truck.set_physics_process(false)
	await settle(scene)
	return scene

func touch(scene, id: int, position: Vector2, pressed: bool = true, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.index = id
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	scene._input(event)

func drag(scene, id: int, position: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = id
	event.position = position
	scene._input(event)

func scenery_pair(scene) -> Array[Vector2]:
	var extent: Vector2 = scene.get_viewport().get_visible_rect().size
	var span = minf(extent.x, extent.y) * 0.20
	for y in range(140, int(extent.y - 100), 24):
		for x in range(int(span + 24), int(extent.x - span - 24), 24):
			var first = Vector2(x, y)
			var second = first + Vector2(span, 0)
			if not scene.camera_touch_blocked(first) and not scene.camera_touch_blocked(second):
				return [first, second]
	check(false, "the visible scene has room for two scenery contacts")
	return [Vector2(400, 350), Vector2(600, 350)]

func begin_pair(scene) -> Array[Vector2]:
	scene.clear_controls()
	var points = scenery_pair(scene)
	touch(scene, 101, points[0])
	touch(scene, 202, points[1])
	return points

func perform_gesture(scene, movement: Vector2 = Vector2.ZERO, zoom: float = 1.0, twist: float = 0.0) -> void:
	var points = begin_pair(scene)
	var center: Vector2 = (points[0] + points[1]) * 0.5 + movement
	var offset: Vector2 = ((points[1] - points[0]) * 0.5).rotated(twist) * zoom
	drag(scene, 202, center + offset)
	drag(scene, 101, center - offset)
	scene._process(0.0)
	touch(scene, 101, center - offset, false)
	touch(scene, 202, center + offset, false)

func perform_drag(scene, movement: Vector2) -> void:
	scene.clear_controls()
	var point = scenery_pair(scene)[0]
	touch(scene, 101, point)
	drag(scene, 101, point + movement)
	scene._process(0.0)
	touch(scene, 101, point + movement, false)

func test_garage_camera(scene) -> void:
	scene.reset_camera()
	scene.camera_pan_mode = false
	var short_axis = minf(scene.get_viewport().get_visible_rect().size.x, scene.get_viewport().get_visible_rect().size.y)
	perform_drag(scene, Vector2(60, 36))
	check(near(scene.orbit, wrapf(2.24 - 60.0 / short_axis * TAU, -PI, PI)) and near(scene.orbit_pitch, 0.49 + 36.0 / short_axis * PI), "a single scenery finger orbits and tilts the garage")
	check(near(scene.orbit_distance, 9.3), "one-finger garage dragging leaves the zoom distance unchanged")
	scene.reset_camera()
	perform_gesture(scene, Vector2.ZERO, 1.25)
	check(near(scene.orbit_distance, 9.3 / 1.25) and near(scene.orbit, 2.24), "batched raw-touch pinch zooms the garage without unintended orbit")
	perform_drag(scene, Vector2(0, 36))
	check(near(scene.orbit_pitch, 0.49 + 36.0 / short_axis * PI), "vertical one-finger drag changes garage tilt")
	var old_orbit: float = scene.orbit
	perform_drag(scene, Vector2(36, 0))
	check(near(scene.orbit, wrapf(old_orbit - 36.0 / short_axis * TAU, -PI, PI)), "horizontal one-finger drag orbits the garage")
	var before: Dictionary = scene.camera_preferences()
	perform_gesture(scene, Vector2(36, 24))
	check(scene.camera_preferences() == before, "two-finger translation does not orbit, tilt, or pan the garage")
	perform_gesture(scene, Vector2.ZERO, 1.0, 0.15)
	check(scene.camera_preferences() == before, "two-finger twist does not rotate the garage")

	scene.toggle_camera_drag()
	scene.did_position_camera = false
	scene.update_camera(0.0)
	var old_target: Vector3 = scene.camera_target
	old_orbit = scene.orbit
	var old_pitch: float = scene.orbit_pitch
	perform_drag(scene, Vector2(36, 24))
	scene.did_position_camera = false
	scene.update_camera(0.0)
	check(scene.garage_pan.x < 0 and scene.garage_pan.y > 0 and scene.camera_target.distance_to(old_target) > 0.1, "pan mode moves the garage camera target with one finger")
	check(near(scene.orbit, old_orbit) and near(scene.orbit_pitch, old_pitch), "garage pan keeps the orbit and tilt angles")
	before = scene.camera_preferences()
	perform_gesture(scene, Vector2(36, 24))
	check(scene.camera_preferences() == before, "two-finger translation is also silent while garage Pan mode is selected")
	scene.reset_camera()
	check(near(scene.orbit, 2.24) and near(scene.orbit_distance, 9.3) and near(scene.orbit_pitch, 0.49) and scene.garage_pan == Vector2.ZERO, "garage Center restores its center, distance, and tilt")
	scene.camera_pan_mode = false
	scene.update_camera_tools()

func assert_gui_ownership(scene, control: Control, title: String) -> void:
	if scene.driving:
		scene.set_camera_preset("free")
	scene.clear_controls()
	var before: Dictionary = scene.camera_preferences()
	var points = scenery_pair(scene)
	var on_gui = control.get_global_rect().get_center()
	check(scene.camera_touch_blocked(on_gui), title + " is recognized as GUI-owned")
	touch(scene, 101, on_gui)
	# A finger starting on a control stays ineligible after leaving its bounds.
	drag(scene, 101, points[0] + Vector2(36, 36))
	scene._process(0.0)
	check(scene.camera_preferences() == before, title + " retains its touch after dragging onto scenery")
	# The same held control must not suppress an independent scenery finger.
	touch(scene, 202, points[1])
	drag(scene, 202, points[1] + Vector2(36, 24))
	scene._process(0.0)
	var after: Dictionary = scene.camera_preferences()
	check(after != before and near(after.garage_distance, before.garage_distance) and near(after.drive_distance, before.drive_distance), "one scenery finger moves the camera while " + title + " retains its held touch")
	touch(scene, 101, points[0], false)
	touch(scene, 202, points[1], false)

func dispatch_touch(id: int, position: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = id
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func dispatch_drag(id: int, position: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = id
	event.position = position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func test_real_touch_dispatch(scene) -> void:
	# Exercise the viewport dispatcher and native TouchScreenButton together;
	# direct scene._input calls alone cannot prove native pedal ownership.
	scene.clear_controls()
	scene.reset_camera()
	scene.set_camera_preset("free")
	scene.camera_pan_mode = false
	scene.update_camera_tools()
	var pedal: Vector2 = scene.touch_buttons.off_go.panel.get_global_rect().get_center()
	var points = scenery_pair(scene)
	var scenery: Vector2 = points[0]
	for action in ["off_left", "off_right"]:
		var item: Dictionary = scene.touch_buttons[action]
		var visual: Rect2 = item.panel.get_global_rect()
		var expanded_corner: Vector2 = item.touch.global_position + Vector2(50, -50)
		check(not visual.has_point(expanded_corner) and scene.camera_touch_blocked(expanded_corner), action + " expanded corner is outside its visual and excluded from camera gestures")
		dispatch_touch(301, expanded_corner, true)
		await process_frame
		check(Input.is_action_pressed(action), action + " rectangular expanded corner activates through real touch dispatch")
		var before: Dictionary = scene.camera_preferences()
		dispatch_drag(301, scenery)
		await process_frame
		scene._process(0.0)
		check(scene.camera_preferences() == before, action + " owns an expanded-hit contact after it drags onto scenery")
		dispatch_touch(301, scenery, false)
		await process_frame
		check(not Input.is_action_pressed(action), action + " releases its expanded-hit contact normally")

	# A near miss beyond the 108px hit box still belongs to the drive-control
	# guard. Dragging away cannot silently become Free-camera movement.
	var steer_rect: Rect2 = scene.touch_buttons.off_left.panel.get_global_rect()
	var missed_steer = Vector2(steer_rect.get_center().x, steer_rect.position.y - 16)
	check(scene.camera_touch_blocked(missed_steer), "the 18px steering guard excludes a touchdown beyond the expanded hit box")
	var before: Dictionary = scene.camera_preferences()
	dispatch_touch(301, missed_steer, true)
	dispatch_drag(301, scenery + Vector2(48, 24))
	await process_frame
	scene._process(0.0)
	check(not Input.is_action_pressed("off_left") and scene.camera_preferences() == before, "a missed steering press activates neither steering nor Free-camera movement")
	dispatch_touch(302, points[1], true)
	dispatch_drag(302, points[1] + Vector2(36, 18))
	await process_frame
	scene._process(0.0)
	check(scene.camera_preferences() != before, "a separate scenery finger still moves Free camera while the steering near miss remains held")
	dispatch_touch(302, points[1] + Vector2(36, 18), false)
	dispatch_touch(301, scenery + Vector2(48, 24), false)
	await process_frame

	var extent: Vector2 = scene.get_viewport().get_visible_rect().size
	var bottom_clear = Vector2(extent.x * 0.32, extent.y - 60)
	before = scene.camera_preferences()
	dispatch_touch(301, bottom_clear, true)
	dispatch_drag(301, scenery + Vector2(32, 16))
	await process_frame
	scene._process(0.0)
	check(scene.camera_preferences() == before, "the empty bottom control strip cannot start a camera gesture")
	dispatch_touch(301, scenery + Vector2(32, 16), false)
	await process_frame

	# Passby must stay disabled: a camera finger crossing GO cannot become a
	# throttle press, even though touchdown at that same point does press GO.
	dispatch_touch(302, scenery, true)
	dispatch_drag(302, pedal)
	await process_frame
	scene._process(0.0)
	check(not Input.is_action_pressed("off_go"), "a scenery contact crossing GO cannot activate the pedal")
	dispatch_touch(302, pedal, false)
	await process_frame

	var steering: Vector2 = steer_rect.get_center()
	dispatch_touch(300, steering, true)
	dispatch_touch(301, pedal, true)
	await process_frame
	check(Input.is_action_pressed("off_left") and Input.is_action_pressed("off_go"), "real screen-touch dispatch holds steering and GO independently")
	var old_orbit: float = scene.drive_orbit
	dispatch_touch(302, scenery, true)
	dispatch_drag(302, scenery + Vector2(48, 0))
	await process_frame
	scene._process(0.0)
	check(scene.camera_preset == "free" and absf(scene.drive_orbit - old_orbit) > 0.02, "one scenery finger orbits Free camera while steering and GO are held")
	check(Input.is_action_pressed("off_left") and Input.is_action_pressed("off_go"), "camera dragging leaves both independent drive actions pressed")
	dispatch_touch(302, scenery + Vector2(48, 0), false)
	await process_frame
	check(Input.is_action_pressed("off_left") and Input.is_action_pressed("off_go"), "lifting the camera finger does not release either drive action")

	var old_distance: float = scene.drive_distance
	var center: Vector2 = (points[0] + points[1]) * 0.5
	var offset: Vector2 = (points[1] - points[0]) * 0.6
	dispatch_touch(302, points[0], true)
	dispatch_touch(303, points[1], true)
	dispatch_drag(302, center - offset)
	dispatch_drag(303, center + offset)
	await process_frame
	scene._process(0.0)
	check(near(scene.drive_distance, old_distance / 1.2) and Input.is_action_pressed("off_left") and Input.is_action_pressed("off_go"), "two scenery fingers pinch while two drive-control fingers retain their actions")
	dispatch_touch(302, center - offset, false)
	dispatch_touch(303, center + offset, false)
	dispatch_touch(300, steering, false)
	await process_frame
	check(not Input.is_action_pressed("off_left") and Input.is_action_pressed("off_go"), "releasing steering leaves the independently held GO action pressed")
	dispatch_touch(301, pedal, false)
	await process_frame
	check(not Input.is_action_pressed("off_go"), "lifting the pedal finger releases GO through real dispatch")

	dispatch_touch(301, pedal, true)
	dispatch_touch(302, scenery, true)
	dispatch_drag(302, scenery + Vector2(36, 18))
	await process_frame
	before = scene.camera_preferences()
	scene.clear_controls()
	scene._process(0.0)
	check(not Input.is_action_pressed("off_go") and scene.camera_preferences() == before, "clearing controls releases a real held pedal and discards pending camera movement")
	dispatch_touch(302, scenery + Vector2(36, 18), false)
	dispatch_touch(301, pedal, false)
	await process_frame
	dispatch_touch(301, pedal, true)
	await process_frame
	check(Input.is_action_pressed("off_go"), "a fresh pedal contact works after clearing and releasing old contacts")
	dispatch_touch(301, pedal, false)
	await process_frame
	scene.clear_controls()

func test_drive_camera(scene) -> void:
	scene.reset_camera()
	check(scene.camera_preset == "follow" and scene.camera_follow, "driving Center selects locked Follow")
	for preset in ["follow", "trail"]:
		scene.set_camera_preset(preset)
		var default_distance = 8.2 if preset == "follow" else 6.0
		var default_pitch = 0.30 if preset == "follow" else 0.48
		check(near(scene.drive_distance, default_distance) and near(scene.drive_pitch, default_pitch) and scene.camera_follow, preset + " supplies its documented locked distance and pitch")
		scene.camera_pan_mode = false
		var before: Dictionary = scene.camera_preferences()
		perform_drag(scene, Vector2(36, 30))
		check(scene.camera_preferences() == before, preset + " ignores one-finger yaw and tilt without changing preset")
		scene.camera_pan_mode = true
		before = scene.camera_preferences()
		perform_drag(scene, Vector2(36, 30))
		check(scene.camera_preferences() == before, preset + " ignores one-finger pan even if a previous Pan setting remains selected")
		scene.camera_pan_mode = false
		before = scene.camera_preferences()
		perform_gesture(scene, Vector2(36, 24), 1.0, 0.15)
		check(scene.camera_preferences() == before, preset + " ignores two-finger translation and twist")
		perform_gesture(scene, Vector2(20, 12), 1.25, 0.15)
		check(near(scene.drive_distance, default_distance / 1.25) and near(scene.drive_pitch, default_pitch) and scene.camera_preset == preset and scene.camera_follow, preset + " permits pinch zoom without changing pitch, heading, or preset")

	scene.set_camera_preset("follow")
	scene.toggle_camera_follow()
	check(scene.camera_preset == "trail" and near(scene.drive_distance, 6.0) and near(scene.drive_pitch, 0.48), "the camera cycle advances Follow to Trail")
	scene.follow_direction = Vector3(0.6, 0.0, 0.8)
	var current_yaw = atan2(scene.follow_direction.x, scene.follow_direction.z)
	scene.toggle_camera_follow()
	check(scene.camera_preset == "free" and not scene.camera_follow and near(scene.drive_orbit, current_yaw), "the camera cycle explicitly enters Free at the current viewing yaw")
	var old_pitch: float = scene.drive_pitch
	perform_drag(scene, Vector2(36, 30))
	check(scene.camera_preset == "free" and scene.drive_pitch > old_pitch and not near(scene.drive_orbit, current_yaw), "Free enables one-finger orbit and tilt")
	scene.toggle_camera_drag()
	scene.did_position_camera = false
	scene.update_camera(0.0)
	var old_target: Vector3 = scene.camera_target
	old_pitch = scene.drive_pitch
	perform_drag(scene, Vector2(30, 24))
	scene.did_position_camera = false
	scene.update_camera(0.0)
	check(scene.drive_pan.length() > 0.1 and scene.camera_target.distance_to(old_target) > 0.1 and near(scene.drive_pitch, old_pitch), "Free one-finger pan shifts the camera target without tilting")
	var old_pan: Vector2 = scene.drive_pan
	var old_orbit: float = scene.drive_orbit
	var old_distance: float = scene.drive_distance
	perform_gesture(scene, Vector2(24, 24), 1.1, 0.15)
	check(scene.drive_pan == old_pan and near(scene.drive_orbit, old_orbit) and near(scene.drive_pitch, old_pitch) and near(scene.drive_distance, old_distance / 1.1), "Free pinch changes only zoom while Pan is selected")
	scene.toggle_camera_follow()
	check(scene.camera_preset == "follow" and scene.camera_follow and scene.drive_pan == Vector2.ZERO and near(scene.drive_orbit, 0.0) and near(scene.drive_distance, 8.2) and near(scene.drive_pitch, 0.30), "the camera cycle returns Free to centered Follow with its default framing")
	scene.set_camera_preset("free")
	perform_drag(scene, Vector2(24, 24))
	scene.reset_camera()
	check(near(scene.drive_distance, 8.2) and near(scene.drive_pitch, 0.30) and near(scene.drive_orbit, 0.0) and scene.drive_pan == Vector2.ZERO and scene.camera_preset == "follow", "drive Center restores Follow after a manual Free-camera adjustment")
	scene.camera_pan_mode = false
	scene.update_camera_tools()

func stage_pending_motion(scene) -> Array[Vector2]:
	scene.clear_controls()
	var points = scenery_pair(scene)
	touch(scene, 101, points[0])
	drag(scene, 101, points[0] + Vector2(36, 20))
	return points

func assert_stale_contacts_cleared(scene, points: Array[Vector2], before: Dictionary, description: String) -> void:
	drag(scene, 101, points[0] + Vector2(80, 40))
	drag(scene, 202, points[1] + Vector2(80, 40))
	scene._process(0.0)
	check(scene.camera_preferences() == before, description)
	scene.clear_controls()

func test_lifecycle(scene) -> void:
	scene.set_camera_preset("free")
	var before: Dictionary = scene.camera_preferences()
	var points = stage_pending_motion(scene)
	scene.toggle_pause()
	check(paused and scene.pause_overlay.visible, "Pause stops scene camera consumption")
	scene._process(0.0)
	scene.toggle_pause()
	assert_stale_contacts_cleared(scene, points, before, "pause and resume discard an unfinished gesture")

	for notifications in [[Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN], [Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED]]:
		before = scene.camera_preferences()
		points = stage_pending_motion(scene)
		scene._notification(notifications[0])
		check(scene.backgrounded and paused, "application interruption pauses input for notification %d" % notifications[0])
		scene._notification(notifications[1])
		check(not scene.backgrounded and not paused, "application return resumes the active scene for notification %d" % notifications[1])
		assert_stale_contacts_cleared(scene, points, before, "application return discards old contacts for notification %d" % notifications[1])

	before = scene.camera_preferences()
	points = stage_pending_motion(scene)
	scene.layout_ui()
	assert_stale_contacts_cleared(scene, points, before, "viewport layout changes discard partially accumulated gestures")
	before = scene.camera_preferences()
	points = begin_pair(scene)
	drag(scene, 101, points[0] + Vector2(36, 20))
	touch(scene, 202, points[1], false, true)
	scene._process(0.0)
	check(scene.camera_preferences() == before, "a canceled screen touch discards the incomplete pair")
	scene.clear_controls()
	perform_gesture(scene, Vector2.ZERO, 1.1)
	check(scene.drive_distance < float(before.drive_distance), "fresh contacts work after lifecycle interruptions")

func camera_buttons(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is BaseButton and child.is_visible_in_tree():
			result.append(child)
		result.append_array(camera_buttons(child))
	return result

func test_layout(scene, dimensions: Vector2i) -> void:
	root.size = dimensions
	scene.layout_ui()
	await settle(scene)
	var extent: Vector2 = scene.get_viewport().get_visible_rect().size
	var bounds = Rect2(Vector2.ZERO, extent)
	var toolbar: Rect2 = scene.camera_toolbar.get_global_rect()
	var title = ("drive " + scene.camera_preset if scene.driving else "garage") + " " + str(dimensions)
	check(bounds.encloses(toolbar), "camera toolbar stays inside the viewport in " + title)
	var buttons = camera_buttons(scene.camera_toolbar)
	var free_drive = scene.driving and scene.camera_preset == "free"
	check(scene.camera_drag_button.is_visible_in_tree() == (not scene.driving or free_drive) and scene.camera_follow_button.is_visible_in_tree() == scene.driving, "camera tools expose drag only in Garage/Free and the preset cycle in every drive view in " + title)
	var usable = buttons.size() == (3 if free_drive else (1 if scene.driving else 2))
	for index in range(buttons.size()):
		var rect: Rect2 = buttons[index].get_global_rect()
		usable = usable and bounds.encloses(rect) and rect.size.x >= 44 and rect.size.y >= 38
		for other in range(index + 1, buttons.size()):
			usable = usable and not rect.intersects(buttons[other].get_global_rect())
	check(usable, "camera buttons provide separate visible touch targets in " + title)
	var panels: Array[Control] = [scene.header]
	if scene.driving:
		for name in ["Dashboard", "Navigation", "Equipment", "CrawlControls"]:
			panels.append(scene.drive_panel.get_node(name))
		for action in scene.touch_buttons:
			panels.append(scene.touch_buttons[action].panel)
	else:
		panels.append(scene.garage_panel)
		panels.append(scene.garage_overlay.get_node("CameraTools"))
	var separate = true
	for panel in panels:
		if panel.is_visible_in_tree():
			separate = separate and not toolbar.intersects(panel.get_global_rect())
	check(separate, "camera toolbar does not overlap other controls in " + title)
	if scene.driving:
		for action in ["off_left", "off_right"]:
			var item: Dictionary = scene.touch_buttons[action]
			var style: StyleBoxFlat = item.panel.get_theme_stylebox("panel")
			check(item.panel.size == Vector2(92, 80) and style.corner_radius_top_left > 0 and style.corner_radius_top_left < 40, action + " uses a rounded 92×80 rectangular visual in " + title)
			check(item.touch.shape is RectangleShape2D and item.touch.shape.size == Vector2(108, 108), action + " provides its expanded rectangular 108×108 hit target in " + title)
		for action in scene.touch_buttons:
			check(not scene.touch_buttons[action].touch.passby_press, action + " requires touchdown and cannot steal a passing camera finger in " + title)
		var bottom_reserved = true
		for x in range(0, int(extent.x), 24):
			bottom_reserved = bottom_reserved and scene.camera_touch_blocked(Vector2(x, extent.y - 119)) and scene.camera_touch_blocked(Vector2(x, extent.y - 1))
		check(bottom_reserved, "the complete bottom 120px strip excludes camera touchdowns in " + title)

func test_preference_validation(scene) -> void:
	scene.camera_pan_mode = false
	scene.set_camera_preset("follow")
	scene.load_camera_preferences({"preset": "free", "orbit": 99.0, "garage_distance": "4.0", "garage_pitch": -1.0, "drive_distance": INF, "drive_pitch": 99.0, "drive_orbit": -99.0, "garage_pan_x": 99.0, "garage_pan_y": 99.0, "drive_pan_x": -99.0, "drive_pan_y": 99.0, "pan_mode": "true", "follow": 0})
	check(near(scene.orbit, PI) and near(scene.drive_orbit, -PI) and near(scene.orbit_pitch, 0.10) and near(scene.drive_pitch, 1.28), "saved Free-camera angles clamp to supported ranges")
	check(near(scene.orbit_distance, 9.3) and near(scene.drive_distance, 8.2), "incorrectly typed and nonfinite saved distances use safe defaults")
	check(near(scene.garage_pan.length(), 4.0) and near(scene.drive_pan.length(), 5.0), "saved Free-camera pan vectors remain within their radial limits")
	check(not scene.camera_pan_mode and scene.camera_preset == "free" and not scene.camera_follow, "saved Pan accepts only a boolean and explicit Free controls the follow state")
	var before: Dictionary = scene.camera_preferences()
	scene.load_camera_preferences([1, 2, 3])
	check(scene.camera_preferences() == before, "a malformed camera preference container is ignored")
	scene.load_camera_preferences({"preset": "free", "garage_distance": -999.0, "drive_distance": 999.0, "garage_pitch": NAN})
	check(near(scene.orbit_distance, 3.2) and near(scene.drive_distance, 20.0) and near(scene.orbit_pitch, 0.49), "finite distances clamp and nonfinite tilt uses its default")
	scene.load_camera_preferences({"follow": false, "drive_distance": 5.4, "drive_pitch": 0.91, "drive_orbit": 1.8, "drive_pan_x": 2.0, "drive_pan_y": 1.0})
	check(scene.camera_preset == "follow" and scene.camera_follow and near(scene.drive_distance, 8.2) and near(scene.drive_pitch, 0.30) and near(scene.drive_orbit, 0.0) and scene.drive_pan == Vector2.ZERO, "legacy follow=false migrates to locked Follow instead of restoring an accidental orbit")
	for invalid in ["unknown", 7, false]:
		scene.load_camera_preferences({"preset": invalid, "follow": false})
		check(scene.camera_preset == "follow" and scene.camera_follow, "an invalid preset %s selects safe Follow" % str(invalid))
	scene.load_camera_preferences({"preset": "trail", "drive_distance": 5.2, "drive_pitch": 0.48, "drive_orbit": 0.0, "drive_pan_x": 0.0})
	check(scene.camera_preset == "trail" and scene.camera_follow and near(scene.drive_distance, 5.2) and near(scene.drive_pitch, 0.48) and near(scene.drive_orbit, 0.0) and scene.drive_pan == Vector2.ZERO, "saved Trail retains its pinch distance and locked framing")
	scene.load_camera_preferences({"preset": "free", "follow": true, "drive_distance": 6.4, "drive_pitch": 0.72, "drive_orbit": 1.2, "drive_pan_x": 2.0})
	check(scene.camera_preset == "free" and not scene.camera_follow and near(scene.drive_pitch, 0.72) and near(scene.drive_orbit, 1.2) and scene.drive_pan == Vector2(2, 0), "an explicit saved Free preset preserves manual framing even with a stale follow flag")

func inside_expanded_hull(point: Vector3, triangles: PackedVector3Array, center: Vector3, radius: float) -> bool:
	for index in range(0, triangles.size(), 3):
		var a = triangles[index]
		var normal = (triangles[index + 1] - a).cross(triangles[index + 2] - a).normalized()
		if normal.dot(center - a) > 0.0:
			normal = -normal
		if normal.dot(point - a) > radius - 0.005:
			return false
	return true

func test_camera_obstruction(scene) -> void:
	check(scene.truck.core.has_method("camera_safe_position"), "native camera collision query is available")
	if not scene.truck.core.has_method("camera_safe_position"):
		return
	var hull = PackedVector3Array()
	var highest = 0.0
	for candidate in scene.truck.core.get_crawl_rocks():
		var top = 0.0
		for point in candidate:
			top = maxf(top, point.y)
		if top > highest:
			highest = top
			hull = candidate
	check(hull.size() >= 12, "camera collision fixture uses the course's exact convex triangles")
	if hull.is_empty():
		return
	var center = Vector3.ZERO
	var reach = 0.0
	for point in hull:
		center += point
	center /= float(hull.size())
	for point in hull:
		reach = maxf(reach, point.distance_to(center))
	var anchor = center + Vector3(reach + 3.0, 0, 0)
	var safe: Vector3 = scene.truck.core.camera_safe_position(anchor, center, 0.22)
	check(safe.is_finite() and safe.distance_to(center) > 0.22 and not inside_expanded_hull(safe, hull, center, 0.22), "an eye requested inside sandstone stops outside its convex surface")
	var preferences: Dictionary = scene.camera_preferences()
	var telemetry: Dictionary = scene.current_telemetry.duplicate(true)
	var was_portrait: bool = scene.portrait
	scene.portrait = false
	scene.set_camera_preset("free")
	scene.drive_pan = Vector2.ZERO
	scene.current_telemetry.position = anchor - Vector3.UP * 0.6
	var offset = center - (scene.current_telemetry.position + Vector3.UP * 0.3)
	scene.drive_distance = offset.length()
	scene.drive_pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	scene.drive_orbit = atan2(offset.x, offset.z)
	scene.did_position_camera = false
	scene.update_camera(0.0)
	check(not inside_expanded_hull(scene.camera.position, hull, center, 0.22), "scene camera collision protects the desired orbit position")
	scene.camera.position = center
	scene.did_position_camera = true
	scene.update_camera(0.0)
	check(not inside_expanded_hull(scene.camera.position, hull, center, 0.22), "camera smoothing cannot leave the eye embedded in sandstone")
	scene.current_telemetry = telemetry
	scene.load_camera_preferences(preferences)
	scene.portrait = was_portrait
	scene.did_position_camera = false

func test_save_roundtrip(scene, seed: Dictionary):
	var preferences = {"preset": "free", "orbit": -0.75, "garage_distance": 12.0, "garage_pitch": 0.72, "drive_distance": 6.4, "drive_pitch": 0.42, "drive_orbit": 1.10, "pan_mode": true, "follow": false, "garage_pan_x": 0.7, "garage_pan_y": -0.3, "drive_pan_x": -1.2, "drive_pan_y": 0.8}
	scene.load_camera_preferences(preferences)
	check(scene.save_settings(), "camera preferences save successfully with the existing garage payload")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	var preserved = saved is Dictionary
	if preserved:
		for key in ["version", "selected_vehicle", "builds", "discovered", "destination", "quality", "selected_map", "map_progress"]:
			preserved = preserved and saved.get(key) == seed[key]
	check(preserved, "saving camera settings preserves every vehicle build, discovery, destination, and display setting")
	scene.free()
	await process_frame
	scene = await open_scene()
	var actual: Dictionary = scene.camera_preferences()
	var restored = true
	for key in preferences:
		if preferences[key] is bool or preferences[key] is String:
			restored = restored and actual[key] == preferences[key]
		else:
			restored = restored and near(float(actual[key]), float(preferences[key]))
	check(restored, "a newly loaded scene restores all camera preferences")
	check(scene.builds == seed.builds and scene.selected_vehicle == seed.selected_vehicle and scene.discovered == seed.discovered and scene.destination == seed.destination, "the garage and exploration state survive camera preference reload")
	return scene

func run() -> void:
	check(ClassDB.class_exists("SoftBodyRig"), "the existing native vehicle library is available")
	if not ClassDB.class_exists("SoftBodyRig"):
		quit(1)
		return
	backup_saves()
	var seed = seed_garage()
	if not save_bytes(SAVE_PATH, JSON.stringify(seed).to_utf8_buffer()):
		check(false, "integration garage fixture can be written")
		restore_saves()
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var scene = await open_scene()
	test_garage_camera(scene)
	assert_gui_ownership(scene, scene.header, "Header")
	assert_gui_ownership(scene, scene.garage_panel, "Garage settings panel")
	assert_gui_ownership(scene, scene.camera_toolbar, "Camera toolbar")
	for dimensions in [Vector2i(960, 540), Vector2i(720, 1280)]:
		await test_layout(scene, dimensions)
	root.size = Vector2i(1280, 720)
	scene.toggle_mode()
	await settle(scene)
	await test_real_touch_dispatch(scene)
	test_drive_camera(scene)
	assert_gui_ownership(scene, scene.header, "Drive header")
	assert_gui_ownership(scene, scene.touch_buttons.off_go.panel, "GO pedal")
	assert_gui_ownership(scene, scene.touch_buttons.off_left.panel, "Steering pedal")
	test_lifecycle(scene)
	for dimensions in [Vector2i(960, 540), Vector2i(720, 1280)]:
		for preset in ["follow", "trail", "free"]:
			scene.set_camera_preset(preset)
			await test_layout(scene, dimensions)
	# Copperline adds throttle and independent axle controls to the same touch
	# surface. They must keep their own contacts in both phone orientations.
	scene.toggle_mode()
	scene.toggle_course()
	scene.toggle_mode()
	scene.toggle_rig_controls()
	await settle(scene)
	for dimensions in [Vector2i(960, 540), Vector2i(720, 1280)]:
		for preset in ["follow", "trail", "free"]:
			scene.set_camera_preset(preset)
			await test_layout(scene, dimensions)
	assert_gui_ownership(scene, scene.front_diff, "Front axle control")
	assert_gui_ownership(scene, scene.rear_diff, "Rear axle control")
	assert_gui_ownership(scene, scene.crawl_controls.get_child(1), "Throttle limit slider")
	test_camera_obstruction(scene)
	scene.toggle_mode()
	scene.toggle_course()
	scene.toggle_mode()
	await settle(scene)
	test_preference_validation(scene)
	scene = await test_save_roundtrip(scene, seed)
	scene.clear_controls()
	scene.free()
	paused = false
	await process_frame
	restore_saves()
	print("CAMERA INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
