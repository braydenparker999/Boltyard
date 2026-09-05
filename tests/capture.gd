extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var output_dir = ProjectSettings.globalize_path("res://").path_join("build")
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.starter()
	for index in range(90):
		await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png(output_dir.path_join("workshop.png"))
	if error != OK:
		push_error("Could not capture workshop")
		quit(1)
		return
	scene.toggle_mode()
	for index in range(90):
		await process_frame
	await RenderingServer.frame_post_draw
	error = root.get_texture().get_image().save_png(output_dir.path_join("driving.png"))
	if error != OK:
		push_error("Could not capture driving view")
		quit(1)
		return
	scene.free()
	print("CAPTURE: workshop and driving views saved")
	quit(0)
