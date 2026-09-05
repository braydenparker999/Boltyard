class_name OffroadWorld
extends Node3D

## Juniper Valley. The near mesh and C++ contacts share the same 2 m triangles.
## Distant meshes, vegetation and reflection captures are built once.
const EXTENT := 384.0
const CHUNK_SIZE := 64.0
const CHUNKS := 12
const LAKE_CENTER := Vector2(96.0, 81.0)
const LAKE_LEVEL := 1.9
const LANDMARK_DATA := [
	["camp", "BASE CAMP", 0.0, 8.0, "Your garage and the start of the valley loop."],
	["grove", "JUNIPER GROVE", -90.0, -105.0, "A shaded trail winding between old junipers."],
	["quarry", "REDSTONE QUARRY", -178.0, 12.0, "Terraced stone and tight, rocky turns."],
	["overlook", "EAGLE OVERLOOK", -92.0, 176.0, "A long climb to the western panorama."],
	["lake", "MIRROR LAKE", 157.0, 92.0, "Follow the shoreline below the eastern ridge."],
	["ridge", "SIGNAL RIDGE", 155.0, -162.0, "The exposed summit at the far end of the loop."]
]
var _core: RefCounted
var _built_core_id := 0
var _course: Node3D
var _chunks: Array[Dictionary] = []
var _last_focus := Vector3(10000, 0, 10000)
var _quality := 1
var _sun: DirectionalLight3D
var _environment: WorldEnvironment
var _reflection: ReflectionProbe
var _ground_material: ShaderMaterial
var _grain: NoiseTexture2D
var _materials: Dictionary = {}

func configure(solver: RefCounted) -> void:
	_core = solver
	if _core == null:
		return
	_core.set_terrain(2)
	if is_inside_tree() and _built_core_id != _core.get_instance_id():
		_build_course()

func _ready() -> void:
	_make_lighting()
	if _core != null:
		_build_course()
	set_quality(_quality)

func set_quality(level: int) -> void:
	_quality = clampi(level, 0, 2)
	if _sun != null:
		_sun.directional_shadow_max_distance = [38.0, 58.0, 85.0][_quality]
		_sun.shadow_enabled = true
	if _reflection != null:
		_reflection.visible = _quality > 0
	_last_focus = Vector3(10000, 0, 10000)

func get_landmarks() -> Array:
	var result: Array = []
	for record in LANDMARK_DATA:
		var x: float = record[2]
		var z: float = record[3]
		var y: float = _core.terrain_height(x, z) if _core != null else 0.0
		result.append({"id": record[0], "name": record[1], "position": Vector3(x, y, z), "radius": 17.0, "description": record[4]})
	return result

func update_focus(at: Vector3) -> void:
	if at.distance_squared_to(_last_focus) < 144.0:
		return
	_last_focus = at
	var near_distance: float = [112.0, 144.0, 190.0][_quality]
	for chunk in _chunks:
		var center: Vector3 = chunk.center
		var distance := Vector2(center.x - at.x, center.z - at.z).length()
		var visual: MeshInstance3D = chunk.visual
		var close: bool = distance < near_distance
		visual.mesh = chunk.near_mesh if close else chunk.far_mesh
		visual.visible = distance < 650.0

func _make_lighting() -> void:
	_environment = WorldEnvironment.new()
	_environment.name = "JuniperDaylight"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5b83a2")
	sky_material.sky_horizon_color = Color("d7d9cc")
	sky_material.ground_bottom_color = Color("65716a")
	sky_material.ground_horizon_color = Color("d7d9cc")
	sky_material.sky_curve = 0.16
	sky_material.sun_angle_max = 2.0
	sky_material.sun_curve = 0.055
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.35
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 0.95
	settings.fog_enabled = true
	settings.fog_light_color = Color("bbc9c3")
	settings.fog_light_energy = 0.55
	settings.fog_density = 0.00135
	settings.fog_sky_affect = 0.15
	_environment.environment = settings
	add_child(_environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "ValleySun"
	_sun.rotation_degrees = Vector3(-38, -36, 0)
	_sun.light_color = Color("fff3dd")
	_sun.light_energy = 0.72
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 58.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.shadow_bias = 0.7
	_sun.shadow_normal_bias = 2.4
	add_child(_sun)

func _make_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1837
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	_grain = NoiseTexture2D.new()
	_grain.width = 256
	_grain.height = 256
	_grain.seamless = true
	_grain.noise = noise
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = load("res://shaders/world_ground.gdshader")
	_ground_material.set_shader_parameter("grain", _grain)
	_materials.wood = _mat(Color("514637"), 0.96)
	_materials.pine = _mat(Color("344c3d"), 0.95)
	_materials.pine_light = _mat(Color("4e6348"), 0.94)
	_materials.rock = _mat(Color("8e8171"), 0.94)
	_materials.sign = _mat(Color("deab67"), 0.64)
	_materials.metal = _mat(Color("52615e"), 0.5, 0.55)
	_materials.camp = _mat(Color("324943"), 0.85)

func _build_course() -> void:
	if _course != null:
		remove_child(_course)
		_course.queue_free()
	_core.set_terrain(2)
	_chunks.clear()
	_make_materials()
	_course = Node3D.new()
	_course.name = "JuniperValley"
	add_child(_course)
	for iz in range(CHUNKS):
		for ix in range(CHUNKS):
			var x := -EXTENT + float(ix) * CHUNK_SIZE
			var z := -EXTENT + float(iz) * CHUNK_SIZE
			var near_mesh := _terrain_chunk(x, z, 2)
			var far_mesh := _terrain_chunk(x, z, 8)
			var visual := MeshInstance3D.new()
			visual.name = "Terrain_%d_%d" % [ix, iz]
			visual.mesh = far_mesh
			visual.material_override = _ground_material
			_course.add_child(visual)
			_chunks.append({"center": Vector3(x + 32.0, 0, z + 32.0), "visual": visual, "near_mesh": near_mesh, "far_mesh": far_mesh})
	_build_obstacles()
	_build_outskirts()
	_build_lake()
	_build_camp()
	_build_wayfinding()
	_reflection = ReflectionProbe.new()
	_reflection.name = "CampReflectionCapture"
	_reflection.position = Vector3(0, 5, 8)
	_reflection.size = Vector3(50, 24, 50)
	_reflection.max_distance = 100.0
	_reflection.intensity = 0.7
	_reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	_reflection.cull_mask = 1
	_reflection.enable_shadows = false
	_reflection.box_projection = false
	_reflection.visible = _quality > 0
	_course.add_child(_reflection)
	_built_core_id = _core.get_instance_id()
	_last_focus = Vector3(10000, 0, 10000)
	update_focus(Vector3(0, 0, 8))

func _terrain_chunk(x0: float, z0: float, step: int) -> ArrayMesh:
	var side: int = int(CHUNK_SIZE) / step + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	colors.resize(side * side)
	uvs.resize(side * side)
	for iz in range(side):
		for ix in range(side):
			var x := x0 + float(ix * step)
			var z := z0 + float(iz * step)
			var index := iz * side + ix
			var h: float = _core.terrain_height(x, z)
			var normal: Vector3 = _core.terrain_normal(x, z)
			var surface: float = _core.terrain_surface(x, z)
			vertices[index] = Vector3(x, h, z)
			normals[index] = normal
			colors[index] = _ground_color(x, z, h, normal, surface)
			uvs[index] = Vector2(x, z) * 0.15
	var indices := PackedInt32Array()
	for iz in range(side - 1):
		for ix in range(side - 1):
			var a := iz * side + ix
			indices.append_array(PackedInt32Array([a, a + 1, a + side, a + 1, a + side + 1, a + side]))
	# Skirts hide cracks between 2 m and 8 m LOD boundaries. They never rise above the shared surface.
	var edges: Array = []
	var north: Array[int] = []
	var south: Array[int] = []
	var east: Array[int] = []
	var west: Array[int] = []
	for i in range(side):
		north.append(i)
		south.append((side - 1) * side + i)
		west.append(i * side)
		east.append(i * side + side - 1)
	edges = [north, east, south, west]
	for edge in edges:
		for i in range(edge.size() - 1):
			var a: int = edge[i]
			var b: int = edge[i + 1]
			var c := vertices.size()
			vertices.append(vertices[a] - Vector3.UP * 7.0)
			vertices.append(vertices[b] - Vector3.UP * 7.0)
			normals.append(normals[a])
			normals.append(normals[b])
			colors.append(colors[a])
			colors.append(colors[b])
			uvs.append(uvs[a])
			uvs.append(uvs[b])
			indices.append_array(PackedInt32Array([a, b, c, b, c + 1, c, b, a, c, c + 1, b, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _ground_color(x: float, z: float, h: float, normal: Vector3, surface: float) -> Color:
	var grass := Color("647052").lerp(Color("78805b"), (sin(x * 0.051) * cos(z * 0.043) + 1.0) * 0.5)
	var rock := Color("999083")
	var color := grass.lerp(rock, smoothstep(0.12, 0.45, 1.0 - normal.y))
	color = color.lerp(Color("9e967d"), smoothstep(48.0, 95.0, h) * 0.68)
	if surface > 0.96:
		color = Color("a29578")
	elif surface > 0.89:
		color = Color("a0937b")
	elif surface < 0.7:
		color = Color("777664")
	if Vector2(x, z - 8.0).length() < 15.0:
		color = Color("777d72")
	return color

func _mat(color: Color, roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _instance(mesh: Mesh, material: Material, at: Vector3, scale_value := Vector3.ONE) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	visual.scale = scale_value
	_course.add_child(visual)
	return visual

func _box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, material, at)

func _multimesh(mesh: Mesh, material: Material, transforms: Array[Transform3D], label_text: String) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var visual := MultiMeshInstance3D.new()
	visual.name = label_text
	visual.multimesh = multi
	visual.material_override = material
	_course.add_child(visual)

func _cylinder(radius: float, height: float, sides := 10) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh

func _pine_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in range(4):
		var bottom := 0.28 + layer * 0.15
		var top := bottom + 0.30
		var radius := 1.0 - float(layer) * 0.20
		for i in range(9):
			var angle := float(i) * TAU / 9.0 + layer * 0.7
			var next := float(i + 1) * TAU / 9.0 + layer * 0.7
			var a := Vector3(cos(angle) * radius, bottom, sin(angle) * radius)
			var b := Vector3(cos(next) * radius, bottom, sin(next) * radius)
			var peak := Vector3(0, top, 0)
			surface.add_vertex(a)
			surface.add_vertex(b)
			surface.add_vertex(peak)
	surface.generate_normals()
	return surface.commit()

func _build_obstacles() -> void:
	var trunk_transforms: Array[Transform3D] = []
	var crown_transforms: Array[Transform3D] = []
	var rock_transforms: Array[Transform3D] = []
	var post_transforms: Array[Transform3D] = []
	var obstacles: Array = _core.get_obstacles()
	for obstacle in obstacles:
		var x: float = obstacle.x
		var z: float = obstacle.z
		var radius: float = obstacle.radius
		var h: float = obstacle.height
		var y: float = _core.terrain_height(x, z)
		var at := Vector3(x, y, z)
		if int(obstacle.type) == 0:
			trunk_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(radius, h, radius)), at + Vector3.UP * h * 0.5))
			crown_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(h * 0.21, h, h * 0.21)), at))
		elif int(obstacle.type) == 1:
			rock_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(radius, h, radius)), at + Vector3.UP * h * 0.5))
		else:
			post_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(radius, h, radius)), at + Vector3.UP * h * 0.5))
	_multimesh(_cylinder(1.0, 1.0, 8), _materials.wood, trunk_transforms, "SolidJuniperTrunks")
	_multimesh(_pine_mesh(), _materials.pine, crown_transforms, "JuniperCanopies")
	_multimesh(_cylinder(1.0, 1.0, 9), _materials.rock, rock_transforms, "SolidQuarryBoulders")
	_multimesh(_cylinder(1.0, 1.0, 8), _materials.sign, post_transforms, "LandmarkPosts")

func _build_outskirts() -> void:
	# Far tree silhouettes grow on the enclosing mountain slopes, beyond the loop.
	# Small ground cover is deliberately non-solid, like grass and twigs.
	var crowns: Array[Transform3D] = []
	var cover: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 792117
	for i in range(240):
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(300.0, 376.0)
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		var y: float = _core.terrain_height(x, z)
		var h := rng.randf_range(8.0, 15.0)
		crowns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(h * 0.22, h, h * 0.22)), Vector3(x, y, z)))
	for i in range(440):
		var x := rng.randf_range(-240.0, 240.0)
		var z := rng.randf_range(-240.0, 240.0)
		var s: float = _core.terrain_surface(x, z)
		if s > 0.9 or s < 0.7 or Vector2(x, z - 8).length() < 20.0:
			continue
		var y: float = _core.terrain_height(x, z)
		var h := rng.randf_range(0.22, 0.58)
		cover.append(Transform3D(Basis.IDENTITY.scaled(Vector3(h, h, h)), Vector3(x, y, z)))
	_multimesh(_pine_mesh(), _materials.pine_light, crowns, "DistantForestSilhouettes")
	var bush := SphereMesh.new()
	bush.radius = 1.0
	bush.height = 1.1
	bush.radial_segments = 7
	bush.rings = 3
	_multimesh(bush, _materials.pine_light, cover, "LowGroundCover")

func _build_lake() -> void:
	# Horizontal lake polygon stays inside the shared shallow basin. Opaque PBR
	# avoids screen-copy/depth-texture costs and supports sky reflections on GLES3.
	var vertices := PackedVector3Array([Vector3(LAKE_CENTER.x, LAKE_LEVEL, LAKE_CENTER.y)])
	var normals := PackedVector3Array([Vector3.UP])
	var indices := PackedInt32Array()
	for i in range(65):
		var angle := float(i) / 64.0 * TAU
		vertices.append(Vector3(LAKE_CENTER.x + cos(angle) * 40.0, LAKE_LEVEL, LAKE_CENTER.y + sin(angle) * 34.0))
		normals.append(Vector3.UP)
	for i in range(64):
		indices.append_array(PackedInt32Array([0, i + 1, i + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/world_water.gdshader")
	_instance(mesh, material, Vector3.ZERO)

func _label(text_value: String, at: Vector3, size := 36, pixel_size := 0.014) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = at
	label.font_size = size
	label.pixel_size = pixel_size
	label.modulate = Color("f4e7cb")
	label.outline_modulate = Color("24372e")
	label.outline_size = 5
	label.visibility_range_end = 70.0
	_course.add_child(label)
	return label

func _build_camp() -> void:
	# Ground markings and an open fabric shade keep spawn clear of solid scenery.
	var stripe := _mat(Color("c8baa0"), 0.94)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.1, 0.009, 7.0), Vector3(side * 2.4, 0.008, 8.0), stripe)
	_box(Vector3(4.9, 0.009, 0.1), Vector3(0, 0.008, 11.5), stripe)
	# Lightweight wayfinding board is attached to the native camp post.
	_box(Vector3(3.4, 0.90, 0.12), Vector3(-7.0, 2.05, 8.0), _materials.camp)
	_label("BOLT YARD", Vector3(-7.0, 2.20, 8.08), 52, 0.008)
	_label("JUNIPER VALLEY", Vector3(-7.0, 1.91, 8.08), 28, 0.009)
	var ground_label := _label("VALLEY LOOP  /  1.8 KM", Vector3(0, 0.025, -4.0), 36, 0.012)
	ground_label.rotation_degrees.x = -90

func _build_wayfinding() -> void:
	var index := 0
	for landmark in get_landmarks():
		if landmark.id == "camp":
			continue
		index += 1
		var at: Vector3 = landmark.position
		var label := _label("%02d  /  %s" % [index, landmark.name], at + Vector3(0, 4.4, 0), 40, 0.016)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
