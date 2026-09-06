extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(960, 540)
	var scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.toggle_course()
	scene.fit_crawl_setup()
	scene.change_quality(1)
	scene.toggle_mode()
	scene.toast_remaining = 0
	for i in range(30):
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/crawl-landscape.png")
	root.size = Vector2i(720, 1280)
	scene.layout_ui()
	for i in range(12):
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/crawl-portrait.png")
	# A close contact view after actual throttle input, no posed wheel offsets.
	root.size = Vector2i(960, 540)
	scene.layout_ui()
	scene.throttle_limit = 0.25
	Input.action_press("off_go")
	for i in range(125):
		await process_frame
		await RenderingServer.frame_post_draw
	Input.action_release("off_go")
	Input.action_press("off_brake")
	for i in range(30):
		await process_frame
		await RenderingServer.frame_post_draw
	scene.set_process(false)
	scene.ui.hide()
	var pos: Vector3 = scene.truck.get_telemetry().position
	scene.camera.position = pos + Vector3(4.0, 1.8, -4.0)
	scene.camera.look_at(pos + Vector3(0, -0.25, -0.65))
	for i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/crawl-contact.png")
	Input.action_release("off_brake")
	scene.queue_free()
	await process_frame
	await process_frame
	print("CRAWL VIEWS: landscape, portrait and loaded tire close-up saved")
	quit()
