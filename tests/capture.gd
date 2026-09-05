extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.starter()
	for index in range(90):
		await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png("res://build/workshop.png")
	if error != OK:
		push_error("Could not capture workshop")
		quit(1)
		return
	scene.toggle_mode()
	for index in range(90):
		await process_frame
	await RenderingServer.frame_post_draw
	error = root.get_texture().get_image().save_png("res://build/driving.png")
	if error != OK:
		push_error("Could not capture driving view")
		quit(1)
		return
	scene.free()
	print("CAPTURE: workshop and driving views saved")
	quit(0)
