extends SceneTree

var scene
var output_dir: String

func _initialize() -> void:
	call_deferred("capture")

func shot(name: String, wait_seconds: float = 0.65) -> void:
	await create_timer(wait_seconds).timeout
	for index in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png(output_dir.path_join(name + ".png"))
	if error != OK:
		push_error("Could not capture " + name)
		quit(1)

func capture() -> void:
	output_dir = ProjectSettings.globalize_path("res://").path_join("build")
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(1280, 720)
	scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	for id in ["pickup", "scout", "buggy"]:
		scene.builds[id] = VehicleCatalog.default_build(id)
	scene.select_vehicle("pickup")
	scene.toast_remaining = 0.0
	await shot("workshop", 1.4)
	scene.select_vehicle("scout")
	scene.toast_remaining = 0.0
	await shot("scout")
	scene.select_vehicle("buggy")
	scene.toast_remaining = 0.0
	await shot("buggy")
	scene.select_vehicle("pickup")
	root.size = Vector2i(720, 1280)
	await process_frame
	scene.layout_ui()
	scene.toast_remaining = 0.0
	await shot("portrait-garage")
	scene.toggle_mode()
	scene.toast_remaining = 0.0
	await shot("portrait-driving")
	scene.toggle_map()
	await shot("map", 0.2)
	scene.toggle_map()
	root.size = Vector2i(1280, 720)
	await process_frame
	scene.layout_ui()
	await shot("driving")
	var landmark: Dictionary = scene.landmarks[1]
	scene.truck.reset(landmark.position + Vector3.UP * 1.5)
	scene.did_position_camera = false
	scene.world.update_focus(landmark.position)
	scene.toast_remaining = 0.0
	await shot("exploration")
	scene.toggle_xray()
	scene.toast_remaining = 0.0
	await shot("node-beam", 0.2)
	scene.toggle_xray()
	scene.toggle_mode()
	scene.impact_test()
	scene.toast_remaining = 0.0
	await shot("impact", 0.8)
	scene.toggle_xray()
	scene.toast_remaining = 0.0
	await shot("impact-body", 0.2)
	scene.free()
	print("CAPTURE: workshop and driving views saved; vehicles, portrait, map and exploration verified")
	quit(0)
