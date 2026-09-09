extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var backups := {}
	for path in ["user://offroad_garage_v3.json","user://offroad_garage_v3.json.tmp","user://offroad_setup.json"]:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		DirAccess.remove_absolute(path)
	root.size=Vector2i(720,1560)
	var scene=load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.builds.buggy=VehicleCatalog.default_build("buggy")
	scene.select_vehicle("buggy")
	scene.fit_crawl_setup()
	scene.change_quality(0)
	scene.start_bedrock_narrows()
	for i in range(65): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/bedrock-portrait-controls.png")
	# Actual analog inputs drive the rig; no animated vehicle poses.
	scene.throttle_limit=.24
	Input.action_press("off_go")
	for i in range(90): await process_frame
	Input.action_release("off_go")
	scene.clear_controls()
	print("BEDROCK PORTRAIT: ",scene.truck.get_telemetry().position)
	scene.queue_free()
	await process_frame
	for path in backups:
		if backups[path]==null:DirAccess.remove_absolute(path)
		else:
			var file=FileAccess.open(path,FileAccess.WRITE)
			file.store_buffer(backups[path])
	quit()
