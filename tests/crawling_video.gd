extends SceneTree
var scene
var trace: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
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
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if good else 1)
