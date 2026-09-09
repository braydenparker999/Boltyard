extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/ranger_paint.gdshader")
	for key in ["base", "normal", "orm", "palette", "opacity"]:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill({"normal": Color(.5, .5, 1), "orm": Color(1, .6, .1), "palette": Color(1, 0, 0)}.get(key, Color.WHITE))
		material.set_shader_parameter(key + "_texture", ImageTexture.create_from_image(image))
	mesh.material_override = material
	stage.add_child(mesh)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(2, 2, 3)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	for i in range(4):
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	print("RANGER SHADER: paint, second UV palette, normal and ORM material rendered")
	quit()
