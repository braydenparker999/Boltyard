extends SceneTree
## Rendered camera review fixture. Run with a real Compatibility renderer.
## Uses the same raw-touch route as Android and preserves the local garage.

const SAVE = "user://offroad_garage_v3.json"
var backup = null
var temporary_backup = null

func _initialize() -> void:
	call_deferred("run")

func settle(count: int = 12) -> void:
	for index in range(count):
		await process_frame
		await RenderingServer.frame_post_draw

func contact(scene, index: int, point: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	scene._input(event)

func drag(scene, index: int, point: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.index = index
	event.position = point
	scene._input(event)

func capture(filename: String) -> void:
	await settle()
	var image = root.get_texture().get_image()
	assert(image.save_png("res://build/" + filename) == OK)
	print("CAMERA VIEW: " + filename)

func restore_file(path: String, bytes) -> void:
	if bytes == null:
		DirAccess.remove_absolute(path)
	else:
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()

func scenery_pair(scene) -> Array[Vector2]:
	var extent: Vector2 = scene.get_viewport().get_visible_rect().size
	var span = minf(extent.x, extent.y) * 0.20
	for y in range(int(extent.y * 0.40), int(extent.y * 0.70), 24):
		for x in range(int(extent.x * 0.45), int(extent.x - span - 24), 24):
			var a = Vector2(x, y)
			var b = a + Vector2(span, 0)
			if not scene.camera_touch_blocked(a) and not scene.camera_touch_blocked(b):
				return [a, b]
	assert(false, "the visible map must provide room for the camera gesture")
	return [Vector2(400, 350), Vector2(600, 350)]

func run() -> void:
	backup = FileAccess.get_file_as_bytes(SAVE) if FileAccess.file_exists(SAVE) else null
	temporary_backup = FileAccess.get_file_as_bytes(SAVE + ".tmp") if FileAccess.file_exists(SAVE + ".tmp") else null
	DirAccess.make_dir_recursive_absolute("res://build")
	root.size = Vector2i(1280, 720)
	var scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.reset_camera()
	scene.camera_pan_mode = false
	scene.update_camera_tools()
	scene.select_map("rockies")
	scene.fit_crawl_setup()
	scene.toast_remaining = 0.0
	await capture("camera-garage-landscape.png")
	scene.show_garage_tab("rig")
	await capture("camera-equipment-landscape.png")
	scene.show_garage_tab("trails")
	scene.toggle_map()
	await capture("camera-map-landscape.png")
	scene.toggle_map()
	root.size = Vector2i(720, 1280)
	scene.layout_ui()
	await capture("camera-garage-portrait.png")
	scene.show_garage_tab("rig")
	await capture("camera-equipment-portrait.png")
	scene.show_garage_tab("trails")
	scene.toggle_map()
	await capture("camera-map-portrait.png")
	scene.toggle_map()
	scene.toggle_mode()
	for dimensions in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		# Review the taller sandstone and the forest map in both camera styles.
		if dimensions.y > dimensions.x:
			scene.toggle_mode()
			scene.select_map("russia")
			scene.toggle_mode()
		root.size = dimensions
		scene.layout_ui()
		var orientation = "portrait" if dimensions.y > dimensions.x else "landscape"
		for preset in ["follow", "trail", "free"]:
			scene.set_camera_preset(preset)
			scene.camera_pan_mode = false
			scene.update_camera_tools()
			scene.toast_remaining = 0.0
			assert(scene.camera_drag_button.visible == (preset == "free"))
			assert(scene.camera_follow_button.visible)
			await capture("camera-%s-%s.png" % [preset, orientation])
			scene.toggle_rig_controls()
			scene.toast_remaining = 0.0
			await capture("camera-rig-%s-%s.png" % [preset, orientation])
			scene.toggle_rig_controls()
			if preset == "free":
				continue
			var points = scenery_pair(scene)
			var before: Dictionary = scene.camera_preferences()
			contact(scene, 4, points[0], true)
			drag(scene, 4, points[0] + Vector2(70, 28))
			scene._process(0.0)
			assert(scene.camera_preferences() == before, "locked presets ignore a single scenery finger")
			contact(scene, 4, points[0] + Vector2(70, 28), false)
			var center: Vector2 = (points[0] + points[1]) * 0.5
			contact(scene, 4, points[0], true)
			contact(scene, 7, points[1], true)
			var span: Vector2 = ((points[1] - points[0]) * 0.5).rotated(0.30) * 1.40
			drag(scene, 4, center + Vector2(0, 24) - span)
			drag(scene, 7, center + Vector2(0, 24) + span)
			scene._process(0.0)
			assert(scene.camera_preset == preset and scene.camera_follow and is_equal_approx(scene.drive_distance, float(before.drive_distance) / 1.40) and is_equal_approx(scene.drive_pitch, float(before.drive_pitch)))
			contact(scene, 4, center + Vector2(0, 24) - span, false)
			contact(scene, 7, center + Vector2(0, 24) + span, false)
			await capture("camera-%s-pinch-%s.png" % [preset, orientation])

		# Manual movement requires an explicit Free selection. Keep the earlier
		# touch artifact names to make before/after reviews easy to compare.
		scene.set_camera_preset("follow")
		scene.set_camera_preset("free")
		scene.camera_pan_mode = false
		var point: Vector2 = scenery_pair(scene)[0]
		contact(scene, 4, point, true)
		drag(scene, 4, point + Vector2(70, 28))
		scene._process(0.0)
		assert(scene.camera_preset == "free" and not scene.camera_follow and scene.drive_pitch > 0.30)
		contact(scene, 4, point + Vector2(70, 28), false)
		scene.toggle_camera_drag()
		scene.toast_remaining = 0.0
		contact(scene, 4, point, true)
		drag(scene, 4, point + Vector2(22, 12))
		scene._process(0.0)
		assert(scene.drive_pan.length() > 0.0)
		contact(scene, 4, point + Vector2(22, 12), false)
		await capture("camera-touch-%s.png" % orientation)
		scene.camera_pan_mode = false
		scene.update_camera_tools()
		scene.set_camera_preset("follow")
		scene.toggle_rig_controls()
		scene.toast_remaining = 0.0
		await capture("camera-rig-%s.png" % orientation)
		scene.toggle_rig_controls()
	scene.clear_controls()
	scene.free()
	restore_file(SAVE, backup)
	restore_file(SAVE + ".tmp", temporary_backup)
	quit()
