extends SceneTree

var checks = 0
var failures = 0
const GARAGE = "user://offroad_garage_v3.json"
const LEGACY = "user://offroad_setup.json"
var backup: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func preserve(path: String) -> void:
	backup[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

func restore() -> void:
	for path in backup:
		if backup[path] == null:
			DirAccess.remove_absolute(path)
		else:
			var file = FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backup[path])
			file.close()
	DirAccess.remove_absolute(GARAGE + ".tmp")

func write_json(path: String, payload: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

func frame_settle(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func inside_view(control: Control, extent: Vector2) -> bool:
	var area = control.get_global_rect()
	return area.position.x >= -1 and area.position.y >= -1 and area.end.x <= extent.x + 1 and area.end.y <= extent.y + 1

func run() -> void:
	preserve(GARAGE)
	preserve(LEGACY)
	DirAccess.remove_absolute(GARAGE)
	var old_settings = VehicleCatalog.DEFAULTS.duplicate(true)
	old_settings.engine_torque = 625.0
	old_settings.tire_radius = 0.51
	old_settings.paint = "537781"
	write_json(LEGACY, {"version": 1, "settings": old_settings})
	var legacy_bytes = FileAccess.get_file_as_bytes(LEGACY)
	root.size = Vector2i(1280, 720)
	await frame_settle(2)
	var scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	await frame_settle(12)
	var initial_extent = scene.get_viewport().get_visible_rect().size
	check(inside_view(scene.garage_panel, initial_extent) and inside_view(scene.garage_footer, initial_extent), "initial garage and persistent save/repair footer fit after container layout settles")
	if initial_extent.x > initial_extent.y:
		check(scene.garage_panel.size.x <= 350.0 and scene.garage_panel.get_global_rect().end.x < scene.title_label.global_position.x, "initial landscape garage keeps its requested sidebar width without covering the vehicle title")
	check(scene.has_migrated, "v0.2 setup is migrated into the new garage")
	check(scene.settings.engine_torque == 625.0 and is_equal_approx(scene.settings.tire_radius, 0.51) and scene.settings.paint == "537781", "migration retains the previous physical tune and paint")
	check(FileAccess.get_file_as_bytes(LEGACY) == legacy_bytes, "migration leaves the original setup file intact")
	check(scene.builds.scout.tuning.is_empty() and scene.builds.buggy.tuning.is_empty(), "legacy pickup tune does not overwrite the other vehicles")
	check(scene.slider_nodes.size() == 10 and scene.part_selectors.size() == 6, "garage exposes ten tuning controls and six equipment slots")

	scene.select_vehicle("scout")
	scene.select_part("tires", "rock")
	scene.select_paint("ede7d6")
	scene.change_value(575.0, "engine_torque")
	scene.select_part("suspension", "lift")
	check(scene.settings.vehicle_id == "scout" and scene.settings.tire_grip == 1.3, "vehicle and part selections reach the composed simulation settings")
	check(scene.settings.engine_torque == 575.0, "equipment changes keep unrelated manual tuning")
	scene.select_vehicle("buggy")
	scene.select_part("roof", "cage_spare")
	scene.select_paint("c9b78e")
	check(scene.settings.roof_accessory_mass == 30.0, "vehicle-specific spare adds physical accessory mass")
	scene.select_vehicle("pickup")
	check(scene.settings.engine_torque == 625.0, "returning to the pickup restores its independent tune")
	scene.select_vehicle("scout")
	check(scene.settings.parts.tires == "rock" and scene.settings.paint == "ede7d6", "switching vehicles restores installed equipment and paint")
	scene.discovered.clear()
	scene.select_destination("ridge")
	check(scene.discovered.is_empty(), "choosing a destination does not award exploration progress")
	scene.toggle_map()
	check(paused and scene.map_overlay.visible, "opening the map pauses vehicle simulation")
	scene.toggle_map()
	check(not paused, "closing the map resumes the simulation")
	scene.toggle_mode()
	var ridge: Dictionary = {}
	for landmark in scene.landmarks:
		if landmark.id == "ridge":
			ridge = landmark
	check(not ridge.is_empty(), "exploration map provides the ridge destination")
	if not ridge.is_empty():
		scene.check_discoveries(ridge.position + Vector3(70, 1, 70))
		check(not scene.discovered.has("ridge"), "distant vehicles do not discover a landmark")
		scene.check_discoveries(ridge.position + Vector3.UP)
		scene.check_discoveries(ridge.position + Vector3.UP)
		check(scene.discovered.count("ridge") == 1, "physical proximity discovers each landmark only once")
	scene.change_quality(1)
	check(scene.save_settings(), "all builds and exploration progress save successfully")
	scene.free()
	await frame_settle(1)
	scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	await frame_settle()
	check(not scene.has_migrated and scene.selected_vehicle == "scout", "new garage reloads the selected vehicle without repeating migration")
	check(scene.settings.parts.tires == "rock" and scene.settings.engine_torque == 575.0, "reload restores the active vehicle's equipment and manual tune")
	check(scene.builds.buggy.parts.roof == "cage_spare" and scene.builds.buggy.paint == "c9b78e", "reload also restores an inactive vehicle's independent build")
	check(scene.discovered.has("ridge") and scene.destination == "ridge" and scene.quality == 1, "reload retains discovery, destination and graphics preference")
	check(FileAccess.get_file_as_bytes(LEGACY) == legacy_bytes, "new garage updates leave the legacy save unchanged")

	for dimensions in [Vector2i(720, 1280), Vector2i(1280, 720)]:
		root.size = dimensions
		await frame_settle()
		scene.layout_ui()
		await frame_settle(12)
		var extent = scene.get_viewport().get_visible_rect().size
		check(scene.portrait == (dimensions.y > dimensions.x), "rotation selects the %s layout" % ("portrait" if dimensions.y > dimensions.x else "landscape"))
		check(inside_view(scene.header, extent) and inside_view(scene.garage_panel, extent) and inside_view(scene.garage_footer, extent), "header and garage fit the %s viewport" % str(dimensions))
		scene.toggle_mode()
		await frame_settle(12)
		var navigation: Control = scene.drive_panel.get_node("Navigation")
		check(inside_view(navigation, extent) and navigation.size.y <= 82.0, "navigation stays compact after rotating to the %s viewport" % str(dimensions))
		var controls_inside = true
		for action in scene.touch_buttons:
			controls_inside = controls_inside and inside_view(scene.touch_buttons[action].panel, extent)
		check(controls_inside, "all five driving touch targets fit the %s viewport" % str(dimensions))
		Input.action_press("off_go")
		Input.action_press("off_right")
		scene.layout_ui()
		check(not Input.is_action_pressed("off_go") and not Input.is_action_pressed("off_right") and scene.truck.throttle == 0.0, "rotation clears throttle and steering inputs")
		scene.toggle_mode()
		await frame_settle()
		check(not scene.driving and scene.truck.core.get_stats().position.distance_to(Vector3(0, 1.5, 8)) < 1.0, "garage return repairs and resets the vehicle at base camp")
	scene.free()
	restore()
	print("EXPLORER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
