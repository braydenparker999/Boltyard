extends SceneTree
var failures = 0
var checks = 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + title)
	else:
		print("PASS: " + title)
func _initialize() -> void:
	call_deferred("run")
func settle() -> void:
	for i in range(8):
		await process_frame
func run() -> void:
	var save_path = "user://offroad_garage_v3.json"
	var existed = FileAccess.file_exists(save_path)
	var saved = FileAccess.get_file_as_bytes(save_path) if existed else PackedByteArray()
	var scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.select_map("legacy")
	await settle()
	var discoveries = scene.discovered.duplicate()
	var environment_id = scene.world._environment.get_instance_id()
	scene.toggle_course()
	scene.fit_crawl_setup()
	await settle()
	check(scene.truck.core.get_crawl_rocks().size() >= 15 and absf(scene.truck.core.terrain_height(20, -60)) < 0.001, "Copperline uses shared convex rocks over its own ground")
	check(scene.settings.parts.tires == "rock" and scene.settings.parts.gearing == "crawler", "crawl package composes compatible fitted parts")
	check(scene.world._environment.get_instance_id() == environment_id, "course switching retains the sky and lighting resources")
	scene.toggle_mode()
	scene.toggle_rig_controls()
	for dimensions in [Vector2i(960, 540), Vector2i(720, 1280)]:
		root.size = dimensions
		scene.layout_ui()
		await settle()
		var area: Rect2 = scene.crawl_controls.get_global_rect()
		var extent: Vector2 = scene.get_viewport().get_visible_rect().size
		check(area.position.x >= 0 and area.position.y >= 0 and area.end.x <= extent.x and area.end.y <= extent.y, "crawl throttle and loads fit " + str(dimensions))
		check(not area.intersects(scene.drive_panel.get_node("Dashboard").get_global_rect()) and not area.intersects(scene.drive_panel.get_node("Navigation").get_global_rect()), "crawl controls do not overlap navigation or dashboard")
	scene.crawl_section = 2
	Input.action_press("off_go")
	scene.recover()
	check(not Input.is_action_pressed("off_go") and absf(scene.truck.core.get_stats().position.z + 24) < 0.01, "recovery clears input and returns to the last clear section")
	scene.toggle_mode()
	scene.apply_tuning()
	check(absf(scene.truck.core.get_stats().position.z + 24) < 0.01, "garage tuning preserves the current recovery section")
	scene.toggle_course()
	await settle()
	check(scene.discovered == discoveries and scene.landmarks.size() == 6 and not scene.map_button.disabled, "valley discoveries and map survive a course round trip")
	check(scene.world._environment.get_instance_id() == environment_id, "returning to valley still uses the original sky")
	scene.queue_free()
	await settle()
	if existed:
		FileAccess.open(save_path, FileAccess.WRITE).store_buffer(saved)
	else:
		DirAccess.remove_absolute(save_path)
	print("CRAWL INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
