extends OffroadWorld

const SECTIONS = [
	["slab", "01  FIRST FOOTING", -3.0, "Ease onto the slab. Keep all four tires loaded."],
	["steps", "02  THE STAIRCASE", -17.0, "Square approach or diagonal line: place a tire, then feed torque."],
	["garden", "03  CROOKED TEETH", -33.0, "Staggered rocks. Straddle a gap or pick the clear outside line."],
	["shelf", "04  SIDE EFFECTS", -47.0, "An off-camber shelf. Watch the uphill tire loads."],
	["summit", "05  LAST WORD", -63.0, "A long final slab with an optional ledge on the left."]
]

func configure(solver: RefCounted) -> void:
	_core = solver
	_core.set_terrain(3)

func get_landmarks() -> Array:
	var result: Array = []
	for section in SECTIONS:
		result.append({"id": section[0], "name": section[1], "position": Vector3(0, 0, section[2]), "radius": 4.0, "description": section[3]})
	return result

func _build_course() -> void:
	_core.set_terrain(3)
	_make_materials()
	_course = Node3D.new()
	_course.name = "Copperline"
	add_child(_course)
	var sand := StandardMaterial3D.new()
	sand.albedo_texture = load("res://assets/world/terrain_dirt.png")
	sand.albedo_color = Color("b0a08a")
	sand.uv1_scale = Vector3(80, 80, 80)
	sand.roughness = 1.0
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(400, 400)
	var floor_visual := MeshInstance3D.new()
	floor_visual.mesh = floor_mesh
	floor_visual.material_override = sand
	_course.add_child(floor_visual)
	var rock_material := ShaderMaterial.new()
	rock_material.shader = load("res://shaders/copper_sandstone.gdshader")
	rock_material.set_shader_parameter("grain", load("res://assets/world/terrain_rock_photo.png"))
	var rocks: Array = _core.get_crawl_rocks()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertices in rocks:
		for i in range(0, vertices.size(), 3):
			var a: Vector3 = vertices[i]
			var b: Vector3 = vertices[i + 1]
			var c: Vector3 = vertices[i + 2]
			var normal := (b - a).cross(c - a).normalized()
			# Godot uses clockwise faces; native geometry uses outward cross products.
			for vertex in [a, c, b]:
				surface.set_normal(normal)
				surface.add_vertex(vertex)
	var visual := MeshInstance3D.new()
	visual.name = "SharedCollisionSandstone"
	visual.mesh = surface.commit()
	visual.material_override = rock_material
	_course.add_child(visual)
	for section in SECTIONS:
		_make_marker(section[1], Vector3(-4.6, 0, section[2] + 5.0))
	_make_marker("COPPERLINE\nTechnical crawling / 85 m", Vector3(-4.6, 0, 9))
	_make_marker("FINISH", Vector3(-4.6, 0, -78))

func _make_marker(text: String, at: Vector3) -> void:
	var post := MeshInstance3D.new()
	var wood := BoxMesh.new()
	wood.size = Vector3(0.10, 1.2, 0.10)
	post.mesh = wood
	post.material_override = _materials.wood
	post.position = at + Vector3(0, 0.6, 0)
	_course.add_child(post)
	var plaque := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(1.85, 0.42, 0.07)
	plaque.mesh = board
	plaque.material_override = _materials.camp
	plaque.position = at + Vector3(0, 1.15, 0)
	_course.add_child(plaque)
	var caption := Label3D.new()
	caption.text = text
	caption.font_size = 64
	caption.pixel_size = 0.0013
	caption.position = at + Vector3(0, 1.15, 0.041)
	caption.modulate = Color("f3dfb3")
	caption.no_depth_test = false
	caption.outline_size = 0
	_course.add_child(caption)
