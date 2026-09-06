class_name OffroadWorld
extends Node3D

## Juniper Valley: textured highland trails, rock strata and rooted juniper stands.
## Native cache vertices and the near mesh share the same 2 m contact triangles.
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
var _materials: Dictionary = {}
var _heights := PackedFloat32Array()
var _surfaces := PackedFloat32Array()
var _normals := PackedVector3Array()
var _vegetation: Array[GeometryInstance3D] = []

func configure(solver: RefCounted) -> void:
	_core = solver
	if _core == null:
		return
	_core.set_terrain(2)
	if is_inside_tree() and _course == null:
		_build_course()
	elif _course != null:
		# Selecting another rig changes the solver, not this immutable valley.
		# Keep already-uploaded terrain, trees and reflection data alive.
		_built_core_id = _core.get_instance_id()

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
	if _ground_material != null:
		_ground_material.set_shader_parameter("detailed_surface", _quality > 0)
	for cover in _vegetation:
		cover.visibility_range_end = [82.0, 125.0, 165.0][_quality]
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
	if is_instance_valid(_environment):
		return
	_environment = WorldEnvironment.new()
	_environment.name = "JuniperDaylight"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/world/highland_sky_panorama.png")
	sky_material.energy_multiplier = 0.85
	sky.sky_material = sky_material
	settings.sky = sky
	# Panorama warm azimuth (u≈0.69) aligns with the western key light.
	settings.sky_rotation = Vector3(0, deg_to_rad(-110.0), 0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4d1d1")
	settings.ambient_light_energy = 0.17
	settings.ambient_light_sky_contribution = 0.0
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 1.0
	settings.fog_enabled = true
	settings.fog_light_color = Color("778d96")
	settings.fog_light_energy = 0.60
	settings.fog_density = 0.00038
	settings.fog_sky_affect = 0.08
	_environment.environment = settings
	add_child(_environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "ValleySun"
	_sun.rotation_degrees = Vector3(-25, -42, 0)
	_sun.light_color = Color("ffe3bc")
	_sun.light_energy = 0.75
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 58.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# GLES directional shadows need enough bias to avoid broad moire bands on
	# the almost-flat trail and vehicle sheet metal at a grazing sun angle.
	_sun.shadow_bias = 0.9
	_sun.shadow_normal_bias = 2.4
	add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.name = "OpenSkyFill"
	fill.rotation_degrees = Vector3(-62, 142, 0)
	fill.light_color = Color("bacbda")
	fill.light_energy = 0.14
	fill.shadow_enabled = false
	add_child(fill)

func _make_materials() -> void:
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = load("res://shaders/world_ground.gdshader")
	for kind in ["grass", "dirt", "rock"]:
		_ground_material.set_shader_parameter(kind + "_albedo", load("res://assets/world/terrain_" + kind + ".png"))
		_ground_material.set_shader_parameter(kind + "_normal", load("res://assets/world/terrain_" + kind + "_normal.png"))
	_ground_material.set_shader_parameter("rock_albedo", load("res://assets/world/terrain_rock_photo.png"))
	_materials.wood = _mat(Color("4e3b2b"), 0.98)
	var foliage := ShaderMaterial.new()
	foliage.shader = load("res://shaders/world_foliage.gdshader")
	foliage.set_shader_parameter("branch_texture", load("res://assets/world/juniper_branch_photo.png"))
	_materials.pine = foliage
	var rock := ShaderMaterial.new()
	rock.shader = load("res://shaders/world_rock.gdshader")
	rock.set_shader_parameter("rock_albedo", load("res://assets/world/terrain_rock_photo.png"))
	rock.set_shader_parameter("rock_normal", load("res://assets/world/terrain_rock_normal.png"))
	_materials.rock = rock
	_materials.sign = _mat(Color("6f5539"), 0.9)
	_materials.metal = _mat(Color("4c514c"), 0.62, 0.45)
	_materials.camp = _mat(Color("26352d"), 0.92)
	_materials.grass = _mat(Color("686a3c"), 1.0)
	_materials.grass.vertex_color_use_as_albedo = true
	_materials.grass.cull_mode = BaseMaterial3D.CULL_DISABLED

func _build_course() -> void:
	if _course != null:
		remove_child(_course)
		_course.queue_free()
	_core.set_terrain(2)
	_chunks.clear()
	_vegetation.clear()
	_make_materials()
	_cache_terrain()
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
	if is_instance_valid(_reflection):
		return
	_reflection = ReflectionProbe.new()
	_reflection.name = "CampReflectionCapture"
	_reflection.position = Vector3(0, 5, 8)
	_reflection.size = Vector3(50, 24, 50)
	_reflection.max_distance = 100.0
	_reflection.intensity = 0.4
	_reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	_reflection.cull_mask = 1
	_reflection.enable_shadows = false
	_reflection.box_projection = false
	_reflection.visible = _quality > 0
	_course.add_child(_reflection)
	_built_core_id = _core.get_instance_id()
	_last_focus = Vector3(10000, 0, 10000)
	update_focus(Vector3(0, 0, 8))
	set_quality(_quality)

func _cache_terrain() -> void:
	# A single packed native transfer avoids half a million GDExtension crossings.
	if _core.has_method("get_terrain_samples"):
		var samples: Dictionary = _core.get_terrain_samples()
		_heights = samples.heights
		_surfaces = samples.surfaces
	else:
		_heights.resize(385 * 385)
		_surfaces.resize(385 * 385)
		for iz in range(385):
			for ix in range(385):
				var i := iz * 385 + ix
				_heights[i] = _core.terrain_height(-384.0 + ix * 2.0, -384.0 + iz * 2.0)
				_surfaces[i] = _core.terrain_surface(-384.0 + ix * 2.0, -384.0 + iz * 2.0)
	_normals.resize(385 * 385)
	for iz in range(385):
		for ix in range(385):
			var left: float = _heights[iz * 385 + maxi(0, ix - 1)]
			var right: float = _heights[iz * 385 + mini(384, ix + 1)]
			var north: float = _heights[maxi(0, iz - 1) * 385 + ix]
			var south: float = _heights[mini(384, iz + 1) * 385 + ix]
			_normals[iz * 385 + ix] = Vector3(left - right, 4.0, north - south).normalized()

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
			var sample_index := int((z + 384.0) * 0.5) * 385 + int((x + 384.0) * 0.5)
			var h: float = _heights[sample_index]
			var normal: Vector3 = _normals[sample_index]
			var surface: float = _surfaces[sample_index]
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
	# COLOR carries blend weights, never unconverted sRGB surface colors.
	var trail := smoothstep(0.86, 0.985, surface)
	var stone := smoothstep(0.07, 0.48, 1.0 - normal.y)
	stone = maxf(stone, smoothstep(42.0, 90.0, h) * 0.48)
	var quarry := 1.0 - smoothstep(0.72, 1.18, Vector2((x + 178.0) / 48.0, (z - 12.0) / 56.0).length())
	stone = maxf(stone, quarry * 0.58)
	var shore := (1.0 - smoothstep(2.1, 5.2, h)) * (1.0 - smoothstep(52.0, 72.0, Vector2(x, z).distance_to(LAKE_CENTER)))
	return Color(trail, stone, shore, 1.0)

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

func _branch_card(surface: SurfaceTool, origin: Vector3, across: Vector3, out: Vector3, shade: float) -> void:
	var normal := across.cross(out).normalized()
	var points := [origin - across, origin + across, origin - across + out, origin + across + out]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
	for i in [0, 1, 2, 1, 3, 2]:
		surface.set_normal(normal)
		surface.set_uv(uvs[i])
		surface.set_color(Color(shade, shade, shade, 1.0))
		surface.add_vertex(points[i])

func _foliage_mesh(simple := false) -> ArrayMesh:
	# Angled, crossed branch fans carry a botanical needle cutout. Native
	# alpha scissoring keeps the detailed silhouette in the opaque draw pass.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in range(4):
		var height := 0.29 + float(layer) * 0.155
		var spread := 1.05 - float(layer) * 0.17
		for branch in range(5):
			var angle := float(branch) * TAU / 5.0 + layer * 1.72
			var radial := Vector3(cos(angle), 0, sin(angle))
			var tangent := Vector3(-sin(angle), 0, cos(angle))
			var reach := spread * (0.86 + 0.14 * sin(branch * 5.7 + layer))
			var origin := Vector3(0, height, 0)
			var out := radial * reach + Vector3.UP * (0.12 + float(layer) * 0.015)
			var shade := 0.81 + float(layer) * 0.045 + float(branch % 2) * 0.045
			_branch_card(surface, origin, tangent * spread * 0.43 + Vector3.UP * 0.07, out, shade)
			if not simple:
				_branch_card(surface, origin, tangent * spread * 0.15 + Vector3.UP * 0.155, out, shade * 0.95)
	for i in range(3):
		var angle := float(i) * PI / 3.0
		_branch_card(surface, Vector3(0, 0.70, 0), Vector3(cos(angle), 0, sin(angle)) * 0.22, Vector3.UP * 0.34, 1.0)
	return surface.commit()

func _branch_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in range(4):
		for branch in range(4):
			var angle := float(branch) * TAU / 4.0 + layer * 1.72
			var spread := 0.65 - float(layer) * 0.11
			var start := Vector3(0, 0.24 + layer * 0.14, 0)
			var end := Vector3(cos(angle) * spread, 0.39 + layer * 0.135, sin(angle) * spread)
			var direction := (end - start).normalized()
			var across := direction.cross(Vector3.UP).normalized()
			var up := direction.cross(across).normalized()
			for side in range(5):
				var a := float(side) * TAU / 5.0
				var b := float(side + 1) * TAU / 5.0
				var na := across * cos(a) + up * sin(a)
				var nb := across * cos(b) + up * sin(b)
				for vertex in [start + na * 0.048, end + na * 0.01, start + nb * 0.048, start + nb * 0.048, end + na * 0.01, end + nb * 0.01]:
					surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

func _rock_mesh(seed_value: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var radial := PackedFloat32Array()
	for i in range(11):
		radial.append(rng.randf_range(0.91, 1.0))
	var profiles := [1.0, 1.0, 0.94, 0.98, 0.88, 0.65]
	var levels := [-0.42, 0.08, 0.32, 0.38, 0.77, 0.97]
	var ring_vertices: Array[Vector3] = []
	for ring in range(6):
		for side in range(11):
			var angle := float(side) * TAU / 11.0
			# Fractured planes and a sheared shelf form broad rock faces; the
			# buried foot anchors each outcrop naturally into sloping ground.
			var block_shape := minf(1.0, 0.9 / maxf(absf(cos(angle)), absf(sin(angle))))
			var radius: float = profiles[ring] * radial[side] * block_shape
			ring_vertices.append(Vector3(cos(angle) * radius + float(ring) * 0.019, levels[ring] + 0.05 * sin(angle * 3.0 + ring), sin(angle) * radius))
	for ring in range(5):
		for side in range(11):
			var a := ring * 11 + side
			var b := ring * 11 + (side + 1) % 11
			for index in [a, b, a + 11, b, b + 11, a + 11]:
				surface.set_color(Color(0.80 + 0.035 * ring, 0.80 + 0.035 * ring, 0.80 + 0.035 * ring))
				surface.add_vertex(ring_vertices[index])
	for side in range(11):
		surface.set_color(Color(1, 1, 1))
		surface.add_vertex(ring_vertices[55 + side])
		surface.add_vertex(ring_vertices[55 + (side + 1) % 11])
		surface.add_vertex(Vector3(0.12, 0.98, 0))
	surface.generate_normals()
	return surface.commit()

func _coarse_height(x: float, z: float) -> float:
	# The far mesh's exact 8 m triangles, including the same diagonal split.
	var x0 := floorf((x + EXTENT) / 8.0) * 8.0 - EXTENT
	var z0 := floorf((z + EXTENT) / 8.0) * 8.0 - EXTENT
	var tx := (x - x0) / 8.0
	var tz := (z - z0) / 8.0
	var a: float = _core.terrain_height(x0, z0)
	var b: float = _core.terrain_height(x0 + 8.0, z0)
	var c: float = _core.terrain_height(x0, z0 + 8.0)
	var d: float = _core.terrain_height(x0 + 8.0, z0 + 8.0)
	if tx + tz <= 1.0:
		return a + tx * (b - a) + tz * (c - a)
	return d + (1.0 - tx) * (c - d) + (1.0 - tz) * (b - d)

func _bake_rocks(mesh: ArrayMesh, transforms: Array[Transform3D], title: String) -> void:
	if transforms.is_empty():
		return
	var arrays := mesh.surface_get_arrays(0)
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var source_indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		source_indices = arrays[Mesh.ARRAY_INDEX]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for transform in transforms:
		var world_vertices := PackedVector3Array()
		world_vertices.resize(source.size())
		var lowest: float = transform.origin.y
		var apron := transform.basis.x.length() + 4.0
		for sample_index in range(8):
			var angle := sample_index * TAU / 8.0
			var x := transform.origin.x + cos(angle) * apron
			var z := transform.origin.z + sin(angle) * apron
			lowest = minf(lowest, minf(_core.terrain_height(x, z), _coarse_height(x, z)))
		for i in range(source.size()):
			var at: Vector3 = transform * source[i]
			world_vertices[i] = at
			if source[i].y < 0.0:
				lowest = minf(lowest, minf(_core.terrain_height(at.x, at.z), _coarse_height(at.x, at.z)))
		# A single broad plane below every near/far ground corner anchors the
		# entire foot. It cannot form narrow dangling tips on a quarry ledge.
		var triangle_vertices := source.size() if source_indices.is_empty() else source_indices.size()
		for vertex_index in range(triangle_vertices):
			var i: int = vertex_index if source_indices.is_empty() else source_indices[vertex_index]
			var at: Vector3 = world_vertices[i]
			if source[i].y < 0.0:
				at.y = minf(at.y, lowest - 0.55)
			surface.set_color(colors[i] if not colors.is_empty() else Color.WHITE)
			surface.add_vertex(at)

	surface.generate_normals()
	var visual := _instance(surface.commit(), _materials.rock, Vector3.ZERO)
	visual.name = title

func _build_obstacles() -> void:
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var rocks: Array = [[], [], []]
	var posts: Array[Transform3D] = []
	var obstacles: Array = _core.get_obstacles()
	var index := 0
	for obstacle in obstacles:
		var x: float = obstacle.x
		var z: float = obstacle.z
		var radius: float = obstacle.radius
		var h: float = obstacle.height
		var at := Vector3(x, _core.terrain_height(x, z), z)
		var turn := Basis(Vector3.UP, x * 0.31 + z * 0.23)
		if int(obstacle.type) == 0:
			trunks.append(Transform3D(turn.scaled(Vector3(radius, h * 0.81, radius)), at + Vector3.UP * h * 0.395))
			var spread := h * (0.25 + 0.10 * (sin(x * 0.37 + z * 0.29) * 0.5 + 0.5))
			crowns.append(Transform3D(turn.scaled(Vector3(spread, h, spread)), at))
		elif int(obstacle.type) == 1:
			rocks[index % 3].append(Transform3D(turn.scaled(Vector3(radius, h, radius)), at))
			index += 1
		else:
			posts.append(Transform3D(Basis.IDENTITY.scaled(Vector3(radius, h, radius)), at + Vector3.UP * h * 0.5))
	var trunk := _cylinder(1.0, 1.0, 9)
	trunk.top_radius = 0.48
	_multimesh(trunk, _materials.wood, trunks, "RootedJuniperTrunks")
	_multimesh(_branch_mesh(), _materials.wood, crowns, "JuniperBranches")
	_multimesh(_foliage_mesh(), _materials.pine, crowns, "IrregularJuniperCrowns")
	for variant in range(3):
		var transforms: Array[Transform3D] = []
		transforms.assign(rocks[variant])
		_bake_rocks(_rock_mesh(912 + variant * 971), transforms, "WeatheredOutcrops%d" % variant)
	_multimesh(_cylinder(1.0, 1.0, 8), _materials.sign, posts, "TrailPosts")

func _grass_mesh(reeds := false) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(9 if not reeds else 7):
		var angle := float(blade) * 2.39996
		var base := Vector3(cos(angle) * 0.24, -0.025, sin(angle) * 0.24)
		var lean := Vector3(sin(angle * 1.7), 0, cos(angle * 1.7)) * 0.23
		var side := Vector3(cos(angle), 0, sin(angle)) * (0.021 if reeds else 0.05)
		var h := 0.50 + 0.43 * sin(blade * 5.1) * sin(blade * 5.1)
		var tint := Color("a29562") if reeds else Color("a4a070")
		for vertex in [base - side, base + side, base + lean + Vector3.UP * h]:
			surface.set_normal(Vector3.UP)
			surface.set_color(tint)
			surface.add_vertex(vertex)
	return surface.commit()

func _build_outskirts() -> void:
	var crowns: Array[Transform3D] = []
	var trunks: Array[Transform3D] = []
	var cover: Array[Transform3D] = []
	var reeds: Array[Transform3D] = []
	var shrubs: Array[Transform3D] = []
	var scree: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 792117
	for i in range(260):
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(255.0, 377.0)
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		var y: float = _core.terrain_height(x, z)
		if _core.terrain_normal(x, z).y < 0.77:
			continue
		var h := rng.randf_range(6.0, 13.0)
		crowns.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(h * 0.28, h, h * 0.28)), Vector3(x, y, z)))
		trunks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(h * 0.025, h * 0.70, h * 0.025)), Vector3(x, y + h * 0.34, z)))
	# Fine grass stays inside camera-local batches; empty road shoulders read clearly.
	for i in range(4300):
		var x := rng.randf_range(-244.0, 244.0)
		var z := rng.randf_range(-220.0, 240.0)
		var s: float = _core.terrain_surface(x, z)
		if s > 0.89 or s < 0.7 or Vector2(x, z - 8).length() < 24.0:
			continue
		if _core.terrain_normal(x, z).y < 0.88:
			continue
		var y: float = _core.terrain_height(x, z)
		var h := rng.randf_range(0.25, 0.66)
		cover.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h, h, h)), Vector3(x, y, z)))
		# Low sage grows in islands around the open grass, with broad exposed
		# earth between them. These flexible plants stay below the wheel hubs.
		if sin(x * 0.052 + sin(z * 0.038) * 1.7) * cos(z * 0.064) > 0.28 and i % 3 == 0:
			var shrub_h := rng.randf_range(0.35, 0.72)
			shrubs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(shrub_h * 0.9, shrub_h, shrub_h * 0.9)), Vector3(x, y, z)))
	for i in range(420):
		var angle := rng.randf() * TAU
		var shore := 1.0 + 0.115 * sin(angle * 3.0 + 0.7) + 0.065 * cos(angle * 5.0 - 0.2) + 0.025 * sin(angle * 9.0)
		var radius := rng.randf_range(0.87, 1.02) * shore
		var x := LAKE_CENTER.x + cos(angle) * 49.0 * radius
		var z := LAKE_CENTER.y + sin(angle) * 42.0 * radius
		var y: float = _core.terrain_height(x, z)
		if y < LAKE_LEVEL - 0.45 or y > LAKE_LEVEL + 0.8:
			continue
		var h := rng.randf_range(0.7, 1.5)
		reeds.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(h * 0.6, h, h * 0.6)), Vector3(x, y, z)))
	for obstacle in _core.get_obstacles():
		if int(obstacle.type) != 1:
			continue
		for i in range(7):
			var angle := rng.randf() * TAU
			var spread: float = float(obstacle.radius) * rng.randf_range(1.2, 2.7)
			var x: float = float(obstacle.x) + cos(angle) * spread
			var z: float = float(obstacle.z) + sin(angle) * spread
			if _core.terrain_surface(x, z) > 0.96:
				continue
			var y: float = _core.terrain_height(x, z)
			var r := rng.randf_range(0.09, 0.27)
			# These tiny, embedded fragments are cosmetic surface aggregate.
			scree.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(r, r * 0.35, r)), Vector3(x, y - 0.015, z)))
	_multimesh(_foliage_mesh(true), _materials.pine, crowns, "HighlandForest")
	_multimesh(_cylinder(1.0, 1.0, 6), _materials.wood, trunks, "HighlandTrunks")
	_cover_batches(_grass_mesh(), cover, "SageGrass")
	_cover_batches(_grass_mesh(true), reeds, "LakesideReeds")
	var shrub_mesh := SurfaceTool.new()
	shrub_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var angle := i * PI / 5.0
		_branch_card(shrub_mesh, Vector3.ZERO, Vector3(cos(angle), 0, sin(angle)) * 0.65, Vector3.UP * (0.72 + 0.15 * sin(i * 5.1)), 0.94)
	_cover_batches(shrub_mesh.commit(), shrubs, "LowSageIslands", _materials.pine)
	_cover_batches(_rock_mesh(4831), scree, "EmbeddedScree", _materials.rock)

func _cover_batches(mesh: Mesh, transforms: Array[Transform3D], title: String, material: Material = null) -> void:
	var batches: Dictionary = {}
	for transform in transforms:
		var key := Vector2i(floori(transform.origin.x / 32.0), floori(transform.origin.z / 32.0))
		if not batches.has(key):
			batches[key] = []
		batches[key].append(transform)
	for key in batches:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = batches[key].size()
		for i in range(multi.instance_count):
			multi.set_instance_transform(i, batches[key][i])
		var visual := MultiMeshInstance3D.new()
		visual.name = title
		visual.multimesh = multi
		visual.material_override = _materials.grass if material == null else material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 125.0
		_course.add_child(visual)
		_vegetation.append(visual)

func _water_triangle(surface: SurfaceTool, points: Array[Vector3]) -> void:
	# Clip water to the exact solid terrain triangles. No floating ellipse edge.
	var clipped: Array[Vector3] = []
	for i in range(3):
		var a := points[i]
		var b := points[(i + 1) % 3]
		if a.y <= LAKE_LEVEL:
			clipped.append(a)
		if (a.y <= LAKE_LEVEL) != (b.y <= LAKE_LEVEL):
			clipped.append(a.lerp(b, (LAKE_LEVEL - a.y) / (b.y - a.y)))
	if clipped.size() < 3:
		return
	for i in range(1, clipped.size() - 1):
		for point in [clipped[0], clipped[i], clipped[i + 1]]:
			surface.set_normal(Vector3.UP)
			surface.set_color(Color(clampf((LAKE_LEVEL - point.y) / 4.0, 0.0, 1.0), 0, 0))
			surface.add_vertex(Vector3(point.x, LAKE_LEVEL + 0.022, point.z))

func _build_lake() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(52):
		for ix in range(62):
			var x := 34.0 + ix * 2.0
			var z := 28.0 + iz * 2.0
			var a := Vector3(x, _core.terrain_height(x, z), z)
			var b := Vector3(x + 2, _core.terrain_height(x + 2, z), z)
			var c := Vector3(x, _core.terrain_height(x, z + 2), z + 2)
			var d := Vector3(x + 2, _core.terrain_height(x + 2, z + 2), z + 2)
			_water_triangle(surface, [a, b, c])
			_water_triangle(surface, [b, d, c])
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/world_water.gdshader")
	material.set_shader_parameter("ripple_normal", load("res://assets/world/terrain_dirt_normal.png"))
	_instance(surface.commit(), material, Vector3.ZERO)

func _label(text_value: String, at: Vector3, size := 36, pixel_size := 0.014) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = at
	label.font_size = size
	label.pixel_size = pixel_size
	label.modulate = Color("e5d9ba")
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = true
	label.visibility_range_end = 38.0
	_course.add_child(label)
	return label

func _build_camp() -> void:
	var stripe := _mat(Color("a99a76"), 0.94)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.08, 0.014, 6.8), Vector3(side * 2.4, 0.014, 8.0), stripe)
	_box(Vector3(4.85, 0.014, 0.08), Vector3(0, 0.014, 11.4), stripe)
	_box(Vector3(3.1, 0.96, 0.15), Vector3(-7.0, 2.00, 8.22), _materials.camp)
	_box(Vector3(3.25, 0.08, 0.21), Vector3(-7.0, 2.52, 8.22), _materials.wood)
	_label("BOLT YARD", Vector3(-7.0, 2.15, 8.305), 48, 0.007)
	_label("JUNIPER VALLEY", Vector3(-7.0, 1.86, 8.305), 27, 0.007)
	var back_title := _label("BOLT YARD", Vector3(-7.0, 2.15, 8.135), 48, 0.007)
	back_title.rotation.y = PI
	var back_subtitle := _label("JUNIPER VALLEY", Vector3(-7.0, 1.86, 8.135), 27, 0.007)
	back_subtitle.rotation.y = PI
	# A simple trailhead noticeboard and stone edging give the garage a location.
	_box(Vector3(1.35, 0.95, 0.12), Vector3(-8.5, 1.58, 8.0), _materials.wood)
	_box(Vector3(1.14, 0.76, 0.015), Vector3(-8.5, 1.60, 8.075), _mat(Color("baac87"), 0.95))
	_label("VALLEY LOOP\n6 DESTINATIONS", Vector3(-8.5, 1.59, 8.093), 22, 0.005)

func _build_wayfinding() -> void:
	const POSTS := [Vector2(-87,-112), Vector2(-183,12), Vector2(-96,180), Vector2(161,95), Vector2(160,-165)]
	var index := 0
	for landmark in get_landmarks():
		if landmark.id == "camp":
			continue
		var post: Vector2 = POSTS[index]
		var at := Vector3(post.x, _core.terrain_height(post.x, post.y) + 2.05, post.y + 0.22)
		var board := _box(Vector3(2.35, 0.51, 0.14), at, _materials.camp)
		board.name = "TrailBoard_" + landmark.id
		_label("%02d  %s" % [index + 1, landmark.name], at + Vector3(0, 0, 0.08), 28, 0.005)
		index += 1
