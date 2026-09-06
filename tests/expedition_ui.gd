extends SceneTree
## Integration coverage for region switching, independent progress and compact UI.
const SAVE = "user://offroad_garage_v3.json"
const LEGACY = "user://offroad_setup.json"
var backups: Dictionary = {}
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, detail: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + detail)
	else:
		failures += 1
		push_error("FAIL: " + detail)

func settle(count: int = 8) -> void:
	for index in range(count):
		await process_frame

func preserve() -> void:
	for path in [SAVE, SAVE + ".tmp", LEGACY]:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

func restore() -> void:
	for path in backups:
		if backups[path] == null:
			DirAccess.remove_absolute(path)
		else:
			var file = FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backups[path])
			file.close()

func open_scene():
	var scene = load("res://offroad_main.tscn").instantiate()
	root.add_child(scene)
	scene.truck.set_physics_process(false)
	await settle()
	return scene

func run() -> void:
	preserve()
	var builds: Dictionary = {}
	for id in VehicleCatalog.VEHICLES:
		builds[id] = VehicleCatalog.default_build(id)
	builds.buggy.paint = "ede7d6"
	builds.buggy.tuning.engine_torque = 650.0
	var file = FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 3, "selected_vehicle": "buggy", "builds": builds, "discovered": ["camp", "ridge"], "destination": "ridge", "quality": 0}))
	file.close()
	root.size = Vector2i(1280, 720)
	var scene = await open_scene()
	check(scene.selected_map == "rockies" and scene.world.map_mode == 4 and scene.truck.core.get_terrain_mode() == 4, "an existing garage starts the new mountain expedition")
	check(scene.exploration_progress.legacy.discovered == ["camp", "ridge"] and scene.exploration_progress.legacy.destination == "ridge", "the old valley discoveries remain preserved separately")
	check(scene.builds == builds and scene.selected_vehicle == "buggy", "expedition migration preserves all vehicle builds and the active rig")
	check(scene.map_buttons.size() == 2 and scene.map_buttons.has("rockies") and scene.map_buttons.has("russia"), "the primary destination chooser exposes the two requested regions")
	check(scene.garage_pages.trails.visible and not scene.garage_pages.rig.visible and not scene.garage_pages.tune.visible, "the garage opens on region selection without equipment or tuning clutter")
	scene.show_garage_tab("rig")
	check(scene.garage_pages.rig.visible and not scene.garage_pages.trails.visible and scene.part_selectors.size() == 6, "equipment remains reachable in its own garage tab")
	scene.show_garage_tab("tune")
	check(scene.garage_pages.tune.visible and not scene.tuning_content.visible, "advanced suspension settings stay collapsed until requested")
	scene.toggle_tuning()
	check(scene.tuning_content.visible and scene.slider_nodes.has("rebound_damping"), "the complete suspension tune remains available")
	scene.show_garage_tab("trails")
	var mountain_id = str(scene.landmarks[1].id)
	scene.discovered.clear()
	scene.discovered.append(mountain_id)
	scene.select_destination(mountain_id)
	scene.select_map("russia")
	await settle()
	check(scene.selected_map == "russia" and scene.world.map_mode == 5 and scene.truck.core.get_terrain_mode() == 5, "choosing Russia changes both scenery and the authoritative native terrain mode")
	check(not mountain_id in scene.discovered and scene.map_rows.has(str(scene.landmarks[1].id)), "Russia has its own discoveries and the atlas refreshes destination controls")
	check(scene.map_canvas.extent == 320.0 and not scene.map_canvas.trails.is_empty(), "the map displays the actual 640 m region and its native trail network")
	var russian_id = str(scene.landmarks[1].id)
	scene.discovered.clear()
	scene.discovered.append(russian_id)
	scene.select_destination(russian_id)
	scene.select_map("rockies")
	await settle()
	check(mountain_id in scene.discovered and scene.destination == mountain_id and not russian_id in scene.discovered, "returning to the mountains restores only its matching progress")
	check(scene.builds == builds, "changing regions does not replace vehicle builds or paint")
	for dimensions in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		root.size = dimensions
		scene.layout_ui()
		await settle(10)
		var bounds = scene.get_viewport().get_visible_rect()
		check(bounds.encloses(scene.header.get_global_rect()) and bounds.encloses(scene.garage_panel.get_global_rect()), "garage panels fit " + str(dimensions))
		scene.toggle_mode()
		await settle(8)
		check(not scene.crawl_controls.visible and not scene.drive_panel.get_node("Equipment").visible, "driving starts with clear scenery and the rig drawer closed")
		scene.toggle_rig_controls()
		await settle(8)
		check(scene.crawl_controls.visible and bounds.encloses(scene.drive_panel.get_node("RigBackdrop").get_global_rect()), "the rig drawer opens within " + str(dimensions))
		check(scene.front_diff.is_visible_in_tree() and scene.rear_diff.is_visible_in_tree(), "both axle lockers remain available while exploring")
		scene.toggle_mode()
		await settle(8)
		check(not scene.crawl_controls.visible, "returning to the garage closes the driving drawer")
	scene.select_map("russia")
	check(scene.save_settings(), "region selection and separate exploration state save successfully")
	scene.free()
	await settle(2)
	scene = await open_scene()
	check(scene.selected_map == "russia" and russian_id in scene.discovered and scene.destination == russian_id, "relaunch restores the chosen Russian map and its progress")
	check(mountain_id in scene.exploration_progress.rockies.discovered and scene.exploration_progress.legacy.discovered == ["camp", "ridge"], "relaunch also retains the inactive mountain and legacy discoveries")
	check(scene.builds == builds, "all saved rigs survive the region roundtrip")
	scene.clear_controls()
	scene.free()
	paused = false
	await settle(2)
	restore()
	print("EXPEDITION UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
