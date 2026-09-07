extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(720,1560)
	var game = load("res://offroad_main.tscn").instantiate()
	root.add_child(game)
	game.select_map("utah")
	game.toggle_mode()
	for i in 45: await process_frame
	await RenderingServer.frame_post_draw
	assert(game.selected_map == "utah" and game.driving)
	assert(absf(game.truck.get_telemetry().position.x + 561.1)<10)
	root.get_texture().get_image().save_png("res://build/utah-portrait.png")
	print("UTAH PORTRAIT PASS")
	game.queue_free()
	await process_frame
	quit()
