extends SceneTree

## Inspect the exact native/visual terrain contract and capture both landscapes.
## Run with the Compatibility display; these are real scene renders.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle(frames := 4) -> void:
	for i in range(frames):
		await process_frame
		await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(1280, 720)
	for mode in [4, 5]:
		var stage := Node3D.new()
		root.add_child(stage)
		var core: RefCounted = ClassDB.instantiate("SoftBodyRig")
		core.configure({})
		var world = load("res://scripts/expedition_world.gd").new()
		world.map_mode = mode
		world.configure(core)
		stage.add_child(world)
		world.set_quality(1)
		world.update_focus(Vector3(0, 0, 8))
		var metrics: Dictionary = world.get_world_metrics()
		check(metrics.terrain_chunks == 100, "Each map must cover the full native 640 m square")
		check(metrics.tree_count == core.get_expedition_obstacles().size(), "Every visible tree trunk must come from native tree collision")
		check(metrics.tree_count > 1000, "Each exploration forest needs substantial native tree coverage")
		var native_vertices := 0
		for rock in core.get_expedition_rocks():
			native_vertices += rock.size()
		var visible_vertices := 0
		for visual in world._rock_cells:
			visible_vertices += visual.mesh.surface_get_array_len(0)
		check(native_vertices == visible_vertices, "Every granite rock face must exactly match native collision")
		for point in [Vector2(-18,-36), Vector2(-38,-76), Vector2(108,-87), Vector2(-215,8), Vector2(0,8)]:
			var index := int((point.y + 320) * .5) * 321 + int((point.x + 320) * .5)
			var sample_point := Vector2(-320 + float(index % 321) * 2, -320 + floorf(float(index) / 321.0) * 2)
			check(absf(world._heights[index] - core.terrain_height(sample_point.x, sample_point.y)) < .001, "Terrain grid vertices must match actual tire support height")
		var camera := Camera3D.new()
		camera.near = .12
		camera.far = 850
		camera.fov = 63
		stage.add_child(camera)
		camera.current = true
		var label := "rockies" if mode == 4 else "russia"
		camera.position = Vector3(8, 4.3, 20)
		camera.look_at(Vector3(-15, 1.5, -28))
		await settle(7)
		root.get_texture().get_image().save_png("res://build/expedition-%s-trailhead.png" % label)
		var at := Vector3(-40, 0, -71) if mode == 4 else Vector3(-51, 0, -32)
		at.y = core.terrain_height(at.x, at.z)
		world.update_focus(at)
		camera.position = at + Vector3(9, 5.5, 12)
		camera.look_at(at + Vector3(-6, 1.2, -12))
		await settle()
		root.get_texture().get_image().save_png("res://build/expedition-%s-rock-trail.png" % label)
		var water: Dictionary = core.get_expedition_water(mode)
		at = Vector3(water.x + water.rx * .80, water.height, water.z + water.rz * 1.15)
		world.update_focus(at)
		camera.position = at + Vector3(7, 8, 9)
		camera.look_at(Vector3(water.x - water.rx * .4, water.height + 1.0, water.z - water.rz * .2))
		await settle()
		root.get_texture().get_image().save_png("res://build/expedition-%s-lake.png" % label)
		print("EXPEDITION WORLD ", label, ": ", JSON.stringify(metrics), " native/drawn rock vertices=", native_vertices, ", draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), ", triangles=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		stage.queue_free()
		await process_frame
		await process_frame
	print("EXPEDITION WORLD CHECKS: ", checks, " checks / ", failures, " failures")
	quit(0 if failures == 0 else 1)
