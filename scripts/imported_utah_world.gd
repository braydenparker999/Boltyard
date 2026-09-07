class_name ImportedUtahWorld
extends OffroadWorld

const DATA := "res://data/utah/"
static var terrain_loaded := false
var manifest: Dictionary = {}

func configure(solver: RefCounted) -> void:
	_core = solver
	manifest = JSON.parse_string(FileAccess.get_file_as_string(DATA + "manifest.json"))
	if not terrain_loaded:
		var h := FileAccess.get_file_as_bytes(DATA + "height.bin").to_float32_array()
		var layers := FileAccess.get_file_as_bytes(DATA + "surface.bin")
		terrain_loaded = _core.load_imported_terrain(h, layers)
		assert(terrain_loaded, "Utah terrain data missing or invalid")
	_core.set_terrain(7)
	if is_inside_tree() and _course == null:
		_build_course()

func _make_lighting() -> void:
	super._make_lighting()
	_environment.environment.fog_density = 0.00030
	_environment.environment.fog_light_color = Color("b1aca1")
	_environment.environment.ambient_light_energy = 0.27
	_sun.rotation_degrees = Vector3(-38, -42, 0)

func _build_course() -> void:
	if _course != null:
		return
	_course = Node3D.new()
	_course.name = "UtahTerrain"
	add_child(_course)
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = load("res://shaders/utah_ground.gdshader")
	for name in ["ground_color", "rock_mask"]:
		_ground_material.set_shader_parameter(name, load("res://assets/utah/" + name + ".png"))
	for name in ["rock", "dirt"]:
		_ground_material.set_shader_parameter(name + "_detail", load("res://assets/utah/" + name + ".jpg"))
	for z in 8:
		for x in 8:
			var visual := MeshInstance3D.new()
			visual.name = "Terrain_%d_%d" % [x, z]
			visual.material_override = _ground_material
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_course.add_child(visual)
			var far_mesh := _make_mesh(x, z, 8)
			visual.mesh = far_mesh
			_chunks.append({"x": x, "z": z, "visual": visual, "far": far_mesh, "step": 8})
	update_focus(get_spawn_position())

func _make_mesh(x: int, z: int, step: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _core.get_imported_chunk(x, z, step))
	return mesh

func get_spawn_position() -> Vector3:
	var p: Array = manifest.spawn
	return Vector3(p[0], _core.terrain_height(p[0], p[1]) + 1.5, p[1])

func get_landmarks() -> Array:
	var result: Array = []
	for l in manifest.get("landmarks", []):
		result.append({"id": l.id, "name": l.name, "position": Vector3(l.x, _core.terrain_height(l.x, l.z), l.z), "radius": 20.0, "description": l.description})
	return result

func get_map_routes() -> Array:
	var result: Array = []
	for route in manifest.get("routes", []):
		var points := PackedVector3Array()
		for p in route:
			points.append(Vector3(p[0], 0, p[1]))
		result.append(points)
	return result

func update_focus(at: Vector3) -> void:
	if Vector2(at.x - _last_focus.x, at.z - _last_focus.z).length_squared() < 144.0:
		return
	_last_focus = at
	for chunk in _chunks:
		var center := Vector2(chunk.x * 256.0 - 896.0, chunk.z * 256.0 - 896.0)
		var delta := (Vector2(at.x, at.z) - center).abs() - Vector2(128, 128)
		var distance := Vector2(maxf(delta.x, 0), maxf(delta.y, 0)).length()
		var step := 1 if distance < 96.0 else (4 if distance < 360.0 else 8)
		if step != chunk.step:
			# Only retain fine geometry near the truck. Far meshes are small and shared.
			chunk.visual.mesh = chunk.far if step == 8 else _make_mesh(chunk.x, chunk.z, step)
			chunk.step = step

func get_metrics() -> Dictionary:
	var triangles := 0
	for chunk in _chunks:
		triangles += chunk.visual.mesh.surface_get_array_index_len(0) / 3
	return {"chunks": _chunks.size(), "triangles": triangles, "extent": 1024.0}
