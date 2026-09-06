extends SceneTree
## Rendered camera review fixture. Run with a real Compatibility renderer.
## Uses the same raw-touch route as Android and preserves the local garage.

const SAVE = "user://offroad_garage_v3.json"
var backup = null
var temporary_backup = null

func _initialize() -> void:
	call_deferred("run")

func settle(count: int = 24) -> void:
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
	scene.toggle_course()
	scene.fit_crawl_setup()
	scene.toast_remaining = 0.0
	await capture("camera-garage-landscape.png")
	root.size = Vector2i(720, 1280)
	scene.layout_ui()
	await capture("camera-garage-portrait.png")
	scene.toggle_mode()
	scene.reset_camera()
	scene.toast_remaining = 0.0
	await capture("camera-follow-portrait.png")
	for dimensions in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		root.size = dimensions
		scene.layout_ui()
		scene.reset_camera()
		scene.toast_remaining = 0.0
		await settle()
		var extent = scene.get_viewport().get_visible_rect().size
		var center = Vector2(extent.x * 0.58, extent.y * 0.56)
		var a = center - Vector2(90, 0)
		var b = center + Vector2(90, 0)
		assert(not scene.camera_touch_blocked(a) and not scene.camera_touch_blocked(b))
		contact(scene, 4, a, true)
		contact(scene, 7, b, true)
		# One finger event at a time; frame aggregation removes order artefacts.
		var span = Vector2(125, 0).rotated(0.68)
		drag(scene, 4, center + Vector2(0, 34) - span)
		drag(scene, 7, center + Vector2(0, 34) + span)
		scene._process(0.0)
		assert(not scene.camera_follow and scene.drive_distance < 7.0)
		contact(scene, 4, a, false)
		contact(scene, 7, b, false)
		scene.toggle_camera_drag()
		scene.toast_remaining = 0.0
		contact(scene, 4, a, true)
		contact(scene, 7, b, true)
		drag(scene, 4, a + Vector2(22, 12))
		drag(scene, 7, b + Vector2(22, 12))
		scene._process(0.0)
		assert(scene.drive_pan.length() > 0.0)
		contact(scene, 4, a, false)
		contact(scene, 7, b, false)
		await capture("camera-touch-%s.png" % ("portrait" if dimensions.y > dimensions.x else "landscape"))
		scene.camera_pan_mode = false
		scene.update_camera_tools()
	scene.clear_controls()
	scene.free()
	restore_file(SAVE, backup)
	restore_file(SAVE + ".tmp", temporary_backup)
	quit()
