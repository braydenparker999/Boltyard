extends SceneTree

## Render the authored environment without posing or displacing contact geometry.
## Run under an actual Compatibility display, not --headless.
func _initialize() -> void:
	call_deferred("run")

func settle(frames := 5) -> void:
	for i in range(frames):
		await process_frame
		await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var core: RefCounted = ClassDB.instantiate("SoftBodyRig")
	var world = load("res://scripts/crawl_world.gd").new()
	world.configure(core)
	stage.add_child(world)
	world.set_quality(1)
	# Let the native loose objects settle under gravity before any art capture.
	for step in range(180):
		core.step(1.0 / 120.0, 0.0, 0.0, true)
	var camera := Camera3D.new()
	camera.near = .08
	camera.far = 600.0
	camera.fov = 62.0
	stage.add_child(camera)
	camera.current = true
	camera.position = Vector3(7.3, 5.6, 14.5)
	camera.look_at(Vector3(-.4, .3, -23))
	await settle(10)
	root.get_texture().get_image().save_png("res://build/copperline-1.0-environment.png")
	camera.position = Vector3(16, 18, 5)
	camera.look_at(Vector3(0, 0, -40))
	await settle()
	root.get_texture().get_image().save_png("res://build/copperline-1.0-lines.png")
	camera.position = Vector3(-.7, 1.35, 2.4)
	camera.look_at(Vector3(.4, .25, -3.3))
	await settle()
	root.get_texture().get_image().save_png("res://build/copperline-1.0-stone.png")
	camera.position = Vector3(-5.8, 1.1, 5.8)
	camera.look_at(Vector3(-8.5, .4, -4.0))
	await settle()
	root.get_texture().get_image().save_png("res://build/copperline-1.0-plants.png")
	var rock_count: int = core.get_crawl_rocks().size()
	var native_vertices := 0
	for rock in core.get_crawl_rocks():
		native_vertices += rock.size()
	var rock_visual := world.get_node("Copperline/SharedCollisionSandstone") as MeshInstance3D
	var drawn_vertices: int = rock_visual.mesh.surface_get_array_len(0)
	assert(drawn_vertices == native_vertices, "Rock rendering must contain exactly the native contact faces")
	print("COPPERLINE RENDERING: %d shared rocks, %d native/drawn vertices, %d foliage batches, draws=%d triangles=%d" % [rock_count, native_vertices, world._vegetation.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	stage.queue_free()
	await process_frame
	quit()
