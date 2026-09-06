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

func check_rock_shading(world: Node3D) -> void:
	var rounded := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD,
		Vector3.ZERO, Vector3(0,.5,.8660254), Vector3.RIGHT])
	var smooth: PackedVector3Array = world._rock_smooth_normals(rounded)
	check(smooth[0].is_equal_approx(smooth[3]), "A rounded crown must have one continuous normal across its shared edge")
	check(smooth[0].dot(Vector3.UP) > .95 and smooth[0].dot(Vector3.UP) < .999,
		"Rounded rock shading must blend both adjacent native faces")
	var ledge := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD,
		Vector3.ZERO, Vector3.UP, Vector3.RIGHT])
	var hard: PackedVector3Array = world._rock_smooth_normals(ledge)
	check(hard[0].is_equal_approx(Vector3.UP) and hard[3].is_equal_approx(Vector3.FORWARD),
		"A deliberate vertical ledge must keep its hard rim visible")

func run() -> void:
	root.size = Vector2i(1280, 720)
	for mode in [4, 5, 6]:
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
		check(metrics.tree_count > (20 if mode == 6 else 1000), "Each exploration forest needs substantial native tree coverage")
		var native_vertices := 0
		var native_points: Dictionary = {}
		for rock in core.get_expedition_rocks():
			native_vertices += rock.size()
			for vertex: Vector3 in rock:
				native_points[vertex] = int(native_points.get(vertex, 0)) + 1
		var visible_vertices := 0
		var exact_positions := true
		var unit_normals := true
		for visual in world._rock_cells:
			visible_vertices += visual.mesh.surface_get_array_len(0)
			var arrays: Array = visual.mesh.surface_get_arrays(0)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				exact_positions = exact_positions and int(native_points.get(vertex, 0)) > 0
				native_points[vertex] = int(native_points.get(vertex, 0)) - 1
			for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
				unit_normals = unit_normals and normal.is_finite() and absf(normal.length_squared() - 1.0) < .003
		check(native_vertices == visible_vertices, "Every granite rock face must exactly match native collision")
		check(exact_positions, "Normal smoothing must preserve every native rock vertex and its multiplicity")
		check(unit_normals, "Every rock lighting normal must be finite and normalized")
		check(world._weights == core.get_expedition_heightfield(mode).materials,
			"Visible material weights must remain the native weights that determine grip")
		if mode == 4:
			check_rock_shading(world)
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
		var label := "canyon" if mode == 6 else ("rockies" if mode == 4 else "russia")
		camera.position = Vector3(8, 4.3, 20)
		camera.look_at(Vector3(-15, 1.5, -28))
		await settle(7)
		root.get_texture().get_image().save_png("res://build/expedition-%s-trailhead.png" % label)
		if mode == 4:
			# A fixed grazing view of level camp dirt isolates shadow acne from
			# material/normal texture aliasing. Only the sun's shadows change.
			camera.position = Vector3(9, 6.5, 18)
			camera.look_at(Vector3(0, 0, 6))
			await settle()
			root.get_texture().get_image().save_png("res://build/expedition-shadow-on.png")
			world._sun.shadow_enabled = false
			await settle()
			root.get_texture().get_image().save_png("res://build/expedition-shadow-off.png")
			world._sun.shadow_enabled = true
		var at := Vector3(14, 0, -78) if mode == 6 else (Vector3(15, 0, -75) if mode == 4 else Vector3(-63, 0, -29))
		at.y = core.terrain_height(at.x, at.z)
		world.update_focus(at)
		camera.position = at + Vector3(9, 5.5, 12)
		camera.look_at(at + Vector3(-6, 1.2, -12))
		await settle()
		root.get_texture().get_image().save_png("res://build/expedition-%s-rock-trail.png" % label)
		# Inspect a real supporting hull at tire scale. The broader trail image
		# alone cannot reveal whether its crown and contact entry remain faceted.
		var nearest_rock := PackedVector3Array()
		var nearest_distance := INF
		for rock: PackedVector3Array in core.get_expedition_rocks():
			var rock_center := Vector3.ZERO
			for vertex: Vector3 in rock:
				rock_center += vertex
			rock_center /= float(rock.size())
			var distance := Vector2(rock_center.x-at.x,rock_center.z-at.z).length_squared()
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_rock = rock
		if not nearest_rock.is_empty():
			var rock_center := Vector3.ZERO
			var rock_top := -INF
			for vertex: Vector3 in nearest_rock:
				rock_center += vertex
				rock_top = maxf(rock_top,vertex.y)
			rock_center /= float(nearest_rock.size())
			rock_center.y = lerpf(core.terrain_height(rock_center.x,rock_center.z),rock_top,.62)
			camera.position = rock_center + Vector3(7,0,9)
			camera.position.y = maxf(core.terrain_height(camera.position.x,camera.position.z)+2.1,rock_top+1.4)
			camera.look_at(rock_center)
			await settle()
			root.get_texture().get_image().save_png("res://build/expedition-%s-contact-scale.png" % label)
		if mode == 6:
			at = Vector3(-211, core.terrain_height(-211,-232), -232)
			world.update_focus(at)
			camera.position = at + Vector3(24, 12, 29)
			camera.look_at(Vector3(-211, core.terrain_height(-211,-249)+9, -249))
			await settle()
			root.get_texture().get_image().save_png("res://build/expedition-canyon-arch.png")
		else:
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
