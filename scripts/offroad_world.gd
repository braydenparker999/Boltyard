class_name OffroadWorld
extends Node3D

## The visible course is sampled from the same analytic surface used by the
## native contacts. Close grid spacing preserves tire-width ruts and ledges.
var _core: RefCounted
var _terrain: MeshInstance3D
var _decor: Node3D
var _built_core_id: int = 0
var _terrain_material: StandardMaterial3D

func configure(solver: RefCounted) -> void:
	_core = solver
	if _core == null:
		return
	_core.set_terrain(1)
	if is_inside_tree() and _built_core_id != _core.get_instance_id():
		_build_course()

func _ready() -> void:
	_make_lighting()
	if _core != null:
		_build_course()

func _make_lighting() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "MountainDaylight"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("648a9c")
	sky_material.sky_horizon_color = Color("c8d5cd")
	sky_material.ground_bottom_color = Color("657766")
	sky_material.ground_horizon_color = Color("c8d5cd")
	sky_material.sky_curve = 0.2
	sky_material.sun_angle_max = 8.0
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d1dfe0")
	settings.ambient_light_energy = 0.3
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	sun.rotation_degrees = Vector3(-48, -34, 0)
	sun.light_color = Color("ffefd3")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Compatibility shadow maps need enough receiver offset for broad, shallow
	# terrain; the previous tiny bias produced repeating self-shadow stripes.
	sun.shadow_bias = 0.2
	sun.shadow_normal_bias = 2.0
	add_child(sun)

func _axis(segments: Array) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for segment in segments:
		var start: float = segment[0]
		var end: float = segment[1]
		var count := maxi(1, ceili((end - start) / float(segment[2])))
		for i in range(count):
			values.append(lerpf(start, end, float(i) / float(count)))
	values.append(float(segments[-1][1]))
	return values

func _build_course() -> void:
	if _core == null:
		return
	if _terrain != null:
		remove_child(_terrain)
		_terrain.queue_free()
	if _decor != null:
		remove_child(_decor)
		_decor.queue_free()
	_core.set_terrain(1)
	var x_values := _axis([[-80.0, -30.0, 5.0], [-30.0, -12.0, 2.0], [-12.0, -4.0, 0.75], [-4.0, 4.0, 0.25], [4.0, 12.0, 0.75], [12.0, 30.0, 2.0], [30.0, 80.0, 5.0]])
	var z_values := _axis([[-115.0, -55.0, 2.0], [-55.0, 5.0, 0.3], [5.0, 65.0, 2.0]])
	var nx := x_values.size()
	var nz := z_values.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(nx * nz)
	normals.resize(nx * nz)
	colors.resize(nx * nz)
	for iz in range(nz):
		var z: float = z_values[iz]
		for ix in range(nx):
			var x: float = x_values[ix]
			var index: int = iz * nx + ix
			var height: float = _core.terrain_height(x, z)
			var normal: Vector3 = _core.terrain_normal(x, z)
			vertices[index] = Vector3(x, height, z)
			normals[index] = normal
			colors[index] = _ground_color(x, z, height, normal)
	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var cursor := 0
	for iz in range(nz - 1):
		for ix in range(nx - 1):
			var a: int = iz * nx + ix
			var b: int = a + 1
			var c: int = a + nx
			var d: int = c + 1
			# Clockwise when seen from above, Godot's front-face convention.
			indices[cursor] = a
			indices[cursor + 1] = b
			indices[cursor + 2] = c
			indices[cursor + 3] = b
			indices[cursor + 4] = d
			indices[cursor + 5] = c
			cursor += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_terrain_material = StandardMaterial3D.new()
	_terrain_material.vertex_color_use_as_albedo = true
	_terrain_material.albedo_color = Color.WHITE
	_terrain_material.roughness = 0.96
	_terrain = MeshInstance3D.new()
	_terrain.name = "NativeContactHeightfield"
	_terrain.mesh = mesh
	_terrain.material_override = _terrain_material
	add_child(_terrain)
	_decor = Node3D.new()
	_decor.name = "CourseMarkers"
	add_child(_decor)
	_build_markers()
	_built_core_id = _core.get_instance_id()

func _ground_color(x: float, z: float, height: float, normal: Vector3) -> Color:
	var noise := sin(x * 0.67 + z * 0.23) * cos(z * 0.39 - x * 0.42)
	var fine := sin(x * 3.6 + z * 2.1) * 0.018
	var grass := Color("76866b").lerp(Color("8b9678"), noise * 0.5 + 0.5)
	var dirt := Color("ac9874").lerp(Color("bda987"), noise * 0.28 + 0.5)
	var route := 1.0 - smoothstep(2.7, 6.7, absf(x + sin(z * 0.06) * 0.4))
	var color := grass.lerp(dirt, route)
	var rock := clampf((1.0 - normal.y) * 2.6, 0.0, 0.75)
	color = color.lerp(Color("8b8b79"), rock)
	# Muted wheel paths make the true narrow ruts easy to read from the camera.
	if z < -2.0 and z > -35.0:
		var track := exp(-pow((absf(x) - 0.83) / 0.27, 2.0)) * 0.22
		color = color.lerp(Color("766f56"), track)
	# The launch pad is color only; its height remains the exact native surface.
	if absf(x) < 6.0 and z >= 1.0 and z < 15.0:
		color = Color("697270")
		var line_x := absf(fposmod(x + 0.04, 2.0) - 0.04)
		var line_z := absf(fposmod(z + 0.04, 2.0) - 0.04)
		if line_x < 0.055 or line_z < 0.055:
			color = Color("818985")
	return color.lightened(fine + minf(height * 0.003, 0.03))

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	visual.material_override = _mat(color)
	_decor.add_child(visual)
	return visual

func _label(text: String, at: Vector3, size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_modulate = Color("20302c")
	label.outline_size = 5
	label.no_depth_test = false
	_decor.add_child(label)
	return label

func _marker(x: float, z: float, stage: String) -> void:
	var y: float = _core.terrain_height(x, z)
	_box(Vector3(0.08, 1.25, 0.08), Vector3(x, y + 0.625, z), Color("e4d8b9"))
	_box(Vector3(0.32, 0.20, 0.07), Vector3(x, y + 1.1, z + 0.01), Color("dda85f"))
	if not stage.is_empty():
		var label := _label(stage, Vector3(x, y + 1.58, z), 40, 0.008, Color("fff0d0"))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _build_markers() -> void:
	# Signs and course stakes sit on the shoulder, clear of native tire contacts.
	_marker(-4.5, -5.0, "01 / ARTICULATION")
	_marker(4.5, -5.0, "")
	_marker(-4.5, -18.0, "02 / ROCK RIPPLE")
	_marker(4.5, -18.0, "")
	_marker(-4.5, -32.0, "03 / THE LEDGE")
	_marker(4.5, -32.0, "")
	_marker(-4.5, -47.0, "RIDGE LOOP")
	_marker(4.5, -47.0, "")
	for z in range(-58, -2, 8):
		for side in [-1.0, 1.0]:
			var x: float = side * 5.1
			var y: float = _core.terrain_height(x, float(z))
			_box(Vector3(0.07, 0.55, 0.07), Vector3(x, y + 0.275, z), Color("c6c4a9"))
	# Workshop identity stays understated so it does not fight the garage UI.
	_box(Vector3(4.6, 1.55, 0.1), Vector3(-7.5, 1.7, 4.0), Color("2d4949"))
	_box(Vector3(0.10, 2.45, 0.1), Vector3(-9.1, 1.225, 4.0), Color("a4a89a"))
	_box(Vector3(0.10, 2.45, 0.1), Vector3(-5.9, 1.225, 4.0), Color("a4a89a"))
	_label("BOLT YARD", Vector3(-7.5, 1.94, 4.062), 64, 0.009, Color("f4e2b9"))
	_label("RIDGE PROVING GROUND", Vector3(-7.5, 1.43, 4.063), 32, 0.007, Color("b6ccc4"))
	# A painted start line is flush to the flat launch ground.
	for ix in range(10):
		for iz in range(2):
			var color := Color("b9c1b2") if (ix + iz) % 2 == 0 else Color("566361")
			_box(Vector3(0.6, 0.008, 0.45), Vector3(-2.7 + float(ix) * 0.6, 0.005, 0.7 + float(iz) * 0.45), color)

