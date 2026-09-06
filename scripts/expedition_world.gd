class_name ExpeditionWorld
extends OffroadWorld

## Two connected exploration landscapes. Native data owns every supporting
## surface and tree trunk; the renderer adds non-supporting leaves and litter.
const MAP_EXTENT := 320.0
const MAP_SIDE := 321
const MAP_CHUNKS := 10
const CELL_SIZE := 64.0
const ROCK_CREASE_COS := 0.743145 # 42 degrees: weathered crowns blend, cut ledges stay legible.
var map_mode := 4
var _weights := PackedColorArray()
var _gravel_weights := PackedFloat32Array()
var _forest_cells: Array[Dictionary] = []
var _rock_cells: Array[MeshInstance3D] = []
var _expedition_rock: ShaderMaterial
var _world_metrics: Dictionary = {}
var _tree_count := 0
var _foliage_meshes: Dictionary = {}
var _branch_meshes: Dictionary = {}

func configure(solver: RefCounted) -> void:
	_core = solver
	if _core == null:
		return
	_core.set_terrain(map_mode)
	if is_inside_tree() and _course == null:
		_build_course()
	elif _course != null:
		_built_core_id = _core.get_instance_id()

func get_landmarks() -> Array:
	if _core == null:
		return []
	var result: Array = []
	var source: Array = _core.get_expedition_landmarks(map_mode)
	for i in range(source.size()):
		var record: Dictionary = source[i]
		var at: Vector3 = record.get("position", Vector3(float(record.get("x", 0)), 0, float(record.get("z", 0))))
		at.y = _core.terrain_height(at.x, at.z)
		result.append({"id": str(record.get("id", "camp" if i == 0 else "place_%d" % i)),
			"name": str(record.get("name", "Trail")), "position": at,
			"radius": float(record.get("radius", 15.0)),
			"description": str(record.get("description", record.get("detail", "")))})
	return result

func _make_lighting() -> void:
	super._make_lighting()
	var taiga := map_mode == 5
	_sun.rotation_degrees = Vector3(-43, -39, 0) if not taiga else Vector3(-32, -58, 0)
	_sun.light_color = Color("fff5e5") if not taiga else Color("f0f1e8")
	_sun.light_energy = 1.05 if not taiga else 0.86
	# Retain OffroadWorld's GLES shadow bias (.9 / 2.4). Reducing it caused
	# self-shadow interference rings on level dirt and bands on vehicle panels.
	var settings := _environment.environment
	settings.ambient_light_color = Color("bccbd1") if not taiga else Color("c0cad0")
	settings.ambient_light_energy = .32 if not taiga else .39
	settings.tonemap_exposure = 1.0
	settings.fog_light_color = Color("a9bdc7") if not taiga else Color("a6b5b4")
	settings.fog_density = .0010 if not taiga else .0018
	settings.fog_light_energy = .84
	settings.fog_sky_affect = .06
	var fill := get_node_or_null("OpenSkyFill") as DirectionalLight3D
	if fill != null:
		fill.light_energy = .17 if not taiga else .21
		fill.light_color = Color("b8c9d1")
	# Use a neutral daylight sky for both locations. Replacing the material on
	# the retained Sky avoids accumulating environment resources on map changes.
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/world/expedition_daylight_sky.png")
	sky_material.energy_multiplier = .87 if not taiga else .78
	settings.sky.sky_material = sky_material
	if _reflection != null:
		_reflection.visible = false

func set_quality(level: int) -> void:
	super.set_quality(level)
	if _expedition_rock != null:
		_expedition_rock.set_shader_parameter("detailed_surface", _quality > 0)
	if _reflection != null:
		_reflection.visible = false
	_last_focus = Vector3(10000, 0, 10000)

func _load_surface(preferred: String, fallback: String) -> Texture2D:
	return load(preferred if ResourceLoader.exists(preferred) else fallback) as Texture2D

func _make_materials() -> void:
	var granite := _load_surface("res://assets/world/expedition_granite.png", "res://assets/world/terrain_rock_photo.png")
	var forest := _load_surface("res://assets/world/expedition_forest_floor.png", "res://assets/world/terrain_grass.png")
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = load("res://shaders/expedition_ground.gdshader")
	_ground_material.set_shader_parameter("forest_floor", forest)
	_ground_material.set_shader_parameter("granite", granite)
	_ground_material.set_shader_parameter("trail_gravel", load("res://assets/world/terrain_dirt.png"))
	_ground_material.set_shader_parameter("detail_normal", load("res://assets/world/terrain_rock_normal.png"))
	_ground_material.set_shader_parameter("soil_normal", load("res://assets/world/terrain_dirt_normal.png"))
	_ground_material.set_shader_parameter("taiga", 1.0 if map_mode == 5 else 0.0)
	_expedition_rock = ShaderMaterial.new()
	_expedition_rock.shader = load("res://shaders/expedition_granite.gdshader")
	_expedition_rock.set_shader_parameter("granite", granite)
	_expedition_rock.set_shader_parameter("forest_floor", forest)
	_expedition_rock.set_shader_parameter("detail_normal", load("res://assets/world/terrain_rock_normal.png"))
	_expedition_rock.set_shader_parameter("taiga", 1.0 if map_mode == 5 else 0.0)
	for kind in ["pine", "birch"]:
		var bark := ShaderMaterial.new()
		bark.shader = load("res://shaders/expedition_bark.gdshader")
		bark.set_shader_parameter("birch", kind == "birch")
		_materials[kind + "_bark"] = bark
		var foliage := ShaderMaterial.new()
		foliage.shader = load("res://shaders/expedition_foliage.gdshader")
		var leaf_path := "res://assets/world/expedition_birch_branch.png"
		foliage.set_shader_parameter("branch_texture", _load_surface(leaf_path if kind == "birch" else "res://assets/world/juniper_branch_photo.png", "res://assets/world/juniper_branch_photo.png"))
		foliage.set_shader_parameter("birch", kind == "birch")
		foliage.set_shader_parameter("leaf_geometry", kind == "birch" and not ResourceLoader.exists(leaf_path))
		_materials[kind] = foliage
	_materials.wood = _mat(Color("493c2c"), .97)
	_materials.sign = _mat(Color("303e34"), .94)
	_materials.fern = _mat(Color("637548"), 1.0)
	_materials.fern.vertex_color_use_as_albedo = true
	_materials.fern.cull_mode = BaseMaterial3D.CULL_DISABLED

func _cache_terrain() -> void:
	var samples: Dictionary = _core.get_expedition_heightfield(map_mode)
	_heights = samples.heights
	_surfaces = samples.surfaces
	_weights = samples.materials
	_gravel_weights = samples.get("gravel", PackedFloat32Array())
	if _gravel_weights.is_empty():
		_gravel_weights.resize(_heights.size())
	assert(_heights.size() == MAP_SIDE * MAP_SIDE, "Expedition terrain must match the native 2 m grid")
	_normals.resize(_heights.size())
	for iz in range(MAP_SIDE):
		for ix in range(MAP_SIDE):
			var left: float = _heights[iz * MAP_SIDE + maxi(0, ix - 1)]
			var right: float = _heights[iz * MAP_SIDE + mini(MAP_SIDE - 1, ix + 1)]
			var north: float = _heights[maxi(0, iz - 1) * MAP_SIDE + ix]
			var south: float = _heights[mini(MAP_SIDE - 1, iz + 1) * MAP_SIDE + ix]
			var dx := float(mini(MAP_SIDE - 1, ix + 1) - maxi(0, ix - 1)) * 2.0
			var dz := float(mini(MAP_SIDE - 1, iz + 1) - maxi(0, iz - 1)) * 2.0
			_normals[iz * MAP_SIDE + ix] = Vector3((left - right) / dx, 1.0, (north - south) / dz).normalized()

func _build_course() -> void:
	if _course != null:
		return
	_core.set_terrain(map_mode)
	_make_materials()
	_cache_terrain()
	_course = Node3D.new()
	_course.name = "SilverpineRange" if map_mode == 4 else "KareliaTaiga"
	add_child(_course)
	for iz in range(MAP_CHUNKS):
		for ix in range(MAP_CHUNKS):
			var x := -MAP_EXTENT + float(ix) * CELL_SIZE
			var z := -MAP_EXTENT + float(iz) * CELL_SIZE
			var visual := MeshInstance3D.new()
			visual.name = "Terrain_%d_%d" % [ix, iz]
			var near_mesh := _terrain_chunk(x, z, 2)
			var far_mesh := _terrain_chunk(x, z, 8)
			visual.mesh = far_mesh
			visual.material_override = _ground_material
			_course.add_child(visual)
			_chunks.append({"center": Vector3(x + 32, 0, z + 32), "visual": visual,
				"near_mesh": near_mesh, "far_mesh": far_mesh})
	_build_expedition_rocks()
	_build_forest()
	_build_expedition_lake()
	_build_trailhead()
	_built_core_id = _core.get_instance_id()
	_last_focus = Vector3(10000, 0, 10000)
	set_quality(_quality)
	update_focus(Vector3(0, 0, 8))
	_world_metrics = {"map_mode": map_mode, "terrain_chunks": _chunks.size(),
		"tree_count": _tree_count, "forest_batches": _forest_cells.size(),
		"rock_batches": _rock_cells.size(), "terrain_grid_spacing": 2.0,
		"map_width_m": MAP_EXTENT * 2.0, "rock_crease_degrees": 42.0,
		"surface_weights_from_native": true}

func get_world_metrics() -> Dictionary:
	return _world_metrics.duplicate()

func _terrain_chunk(x0: float, z0: float, step: int) -> ArrayMesh:
	var side := int(CELL_SIZE) / step + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var surface_detail := PackedVector2Array()
	var indices := PackedInt32Array()
	for iz in range(side):
		for ix in range(side):
			var x := x0 + float(ix * step)
			var z := z0 + float(iz * step)
			var sample_index := int((z + MAP_EXTENT) * .5) * MAP_SIDE + int((x + MAP_EXTENT) * .5)
			vertices.append(Vector3(x, _heights[sample_index], z))
			normals.append(_normals[sample_index])
			colors.append(_weights[sample_index])
			surface_detail.append(Vector2(_gravel_weights[sample_index], 0))
	for iz in range(side - 1):
		for ix in range(side - 1):
			var a := iz * side + ix
			indices.append_array(PackedInt32Array([a, a + 1, a + side, a + 1, a + side + 1, a + side]))
	# Skirts extend downward only. The entire driving radius uses the native 2 m
	# triangles; coarse distant cells cannot create phantom rocks near a tire.
	var edges: Array = [[], [], [], []]
	for i in range(side):
		edges[0].append(i)
		edges[1].append((side - 1) * side + i)
		edges[2].append(i * side)
		edges[3].append(i * side + side - 1)
	for edge in edges:
		for i in range(edge.size() - 1):
			var a: int = edge[i]
			var b: int = edge[i + 1]
			var c := vertices.size()
			vertices.append(vertices[a] - Vector3.UP * 8)
			vertices.append(vertices[b] - Vector3.UP * 8)
			normals.append(normals[a])
			normals.append(normals[b])
			colors.append(colors[a])
			colors.append(colors[b])
			surface_detail.append(surface_detail[a])
			surface_detail.append(surface_detail[b])
			indices.append_array(PackedInt32Array([a, b, c, b, c + 1, c, b, a, c, c + 1, b, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = surface_detail
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _rock_smooth_normals(vertices: PackedVector3Array) -> PackedVector3Array:
	# The native triangle soup is kept verbatim. Weld only the lighting normals
	# within each hull, and never across a ledge or between overlapping rocks.
	# Corner-angle weighting avoids the diagonal bands caused by a triangle's
	# area or by the number of triangles meeting at the crown.
	var adjacent: Dictionary = {}
	var face_normals := PackedVector3Array()
	for i in range(0, vertices.size(), 3):
		var normal := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).normalized()
		face_normals.append(normal)
		for corner in range(3):
			var vertex := vertices[i + corner]
			var first := (vertices[i + (corner + 1) % 3] - vertex).normalized()
			var second := (vertices[i + (corner + 2) % 3] - vertex).normalized()
			var angle := acos(clampf(first.dot(second), -1.0, 1.0))
			if not adjacent.has(vertex):
				adjacent[vertex] = []
			adjacent[vertex].append(Vector4(normal.x, normal.y, normal.z, angle))
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for i in range(vertices.size()):
		var face := face_normals[i / 3]
		var weighted := Vector3.ZERO
		for contribution: Vector4 in adjacent[vertices[i]]:
			var normal := Vector3(contribution.x, contribution.y, contribution.z)
			if face.dot(normal) >= ROCK_CREASE_COS:
				weighted += normal * contribution.w
		result[i] = weighted.normalized() if weighted.length_squared() > .00001 else face
	return result

func _native_wetness(at: Vector3) -> float:
	# Use the same two triangles as native material sampling and the ground mesh.
	var gx := clampf((at.x + MAP_EXTENT) * .5, 0, MAP_SIDE - 1)
	var gz := clampf((at.z + MAP_EXTENT) * .5, 0, MAP_SIDE - 1)
	var ix := mini(MAP_SIDE - 2, int(gx))
	var iz := mini(MAP_SIDE - 2, int(gz))
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	var i := iz * MAP_SIDE + ix
	if tx + tz <= 1.0:
		return _weights[i].a * (1.0 - tx - tz) + _weights[i + 1].a * tx + _weights[i + MAP_SIDE].a * tz
	return _weights[i + MAP_SIDE + 1].a * (tx + tz - 1.0) + _weights[i + MAP_SIDE].a * (1.0 - tx) + _weights[i + 1].a * (1.0 - tz)

func _build_expedition_rocks() -> void:
	var cells: Dictionary = {}
	var rocks: Array = _core.get_expedition_rocks(map_mode)
	var rock_index := 0
	for entry in rocks:
		var vertices: PackedVector3Array = entry if entry is PackedVector3Array else entry.triangles
		if vertices.is_empty():
			continue
		var center := Vector3.ZERO
		for p in vertices:
			center += p
		center /= float(vertices.size())
		var cell := Vector2i(floori(center.x / CELL_SIZE), floori(center.z / CELL_SIZE))
		if not cells.has(cell):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			cells[cell] = surface
		var surface: SurfaceTool = cells[cell]
		var tint := .96 + .04 * sin(float(rock_index) * 12.13)
		var smooth_normals := _rock_smooth_normals(vertices)
		for i in range(0, vertices.size(), 3):
			for corner in [0, 2, 1]:
				var vertex := vertices[i + corner]
				var floor_height: float = _core.terrain_height(vertex.x, vertex.z)
				surface.set_normal(smooth_normals[i + corner])
				surface.set_color(Color(tint, tint, tint, smoothstep(-.04, .9, vertex.y - floor_height)))
				surface.set_uv(Vector2(_native_wetness(vertex), 0))
				surface.add_vertex(vertex)
		rock_index += 1
	for key in cells:
		var surface: SurfaceTool = cells[key]
		var visual := _instance(surface.commit(), _expedition_rock, Vector3.ZERO)
		visual.name = "Bedrock_%d_%d" % [key.x, key.y]
		_rock_cells.append(visual)

func _emit_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for vertex in [a, c, b]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.add_vertex(vertex)

func _tapered_limb(surface: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float, sides: int, tint: Color) -> void:
	var direction := (b - a).normalized()
	var tangent := direction.cross(Vector3.FORWARD).normalized()
	if tangent.length_squared() < .1:
		tangent = Vector3.RIGHT
	var other := direction.cross(tangent).normalized()
	for side in range(sides):
		var theta := float(side) * TAU / float(sides)
		var next := float(side + 1) * TAU / float(sides)
		var n0 := tangent * cos(theta) + other * sin(theta)
		var n1 := tangent * cos(next) + other * sin(next)
		var points := [a + n0 * radius_a, a + n1 * radius_a, b + n0 * radius_b, b + n1 * radius_b]
		var uvs := [Vector2(float(side) / sides, a.y), Vector2(float(side + 1) / sides, a.y), Vector2(float(side) / sides, b.y), Vector2(float(side + 1) / sides, b.y)]
		for index in [0, 1, 2, 1, 3, 2]:
			surface.set_normal(n0 if index in [0, 2] else n1)
			surface.set_color(tint)
			surface.set_uv(uvs[index])
			surface.add_vertex(points[index])

func _trunk_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Below the first crown the trunk radius exactly matches its native cylinder.
	_tapered_limb(surface, Vector3(0, -.025, 0), Vector3(0, .32, 0), 1.0, .94, 9, Color.WHITE)
	_tapered_limb(surface, Vector3(0, .32, 0), Vector3(.1, .70, -.08), .94, .56, 9, Color(.95,.95,.95))
	_tapered_limb(surface, Vector3(.1, .70, -.08), Vector3(.15, 1, -.10), .56, .06, 7, Color.WHITE)
	return surface.commit()

func _conifer_branches(variant: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in range(7):
		var y := .23 + layer * .104
		var width := (.160 - layer * .019) * (1.0 + .10 * sin(variant * 3.1 + layer))
		for branch in range(6):
			var angle := branch * TAU / 6 + layer * 2.39 + variant * .93
			var end := Vector3(cos(angle) * width, y + .038, sin(angle) * width)
			_tapered_limb(surface, Vector3(0, y, 0), end, .0065 * (1.0 - layer * .1), .001, 4, Color(.92,.92,.92))
	return surface.commit()

func _conifer_crown(variant: int, simple: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers := 5 if simple else 8
	var branches := 4 if simple else 7
	for layer in range(layers):
		var t := float(layer) / float(layers)
		var y := .20 + t * .73 + .018 * sin(layer * 3.27 + variant)
		var width := (.205 * pow(1.0 - t, .78) + .018) * (1.0 + .17 * sin(variant * 2.31 + layer * 1.83))
		for branch in range(branches):
			var angle := branch * TAU / float(branches) + layer * 2.39 + variant * .93
			var radial := Vector3(cos(angle), 0, sin(angle))
			var tangent := Vector3(-sin(angle), 0, cos(angle))
			var out := radial * width * (1.0 + .14 * sin(branch * 2.71 + layer)) + Vector3.UP * (.048 + .025 * t)
			var origin := Vector3(0, y + .017 * sin(branch * 1.87 + layer), 0)
			var shade := .84 + .13 * t + .06 * sin(branch * 2.79 + variant)
			_branch_card(surface, origin, tangent * width * .53 + Vector3.UP * .026, out, shade)
			if not simple:
				_branch_card(surface, origin - radial * .012, tangent * width * .18 + Vector3.UP * width * .24, out, shade * .91)
	for plane in range(3):
		var angle := plane * PI / 3
		_branch_card(surface, Vector3(0, .83, 0), Vector3(cos(angle), 0, sin(angle)) * .037, Vector3.UP * .18, 1.0)
	return surface.commit()

func _birch_branches(simple: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for branch in range(6 if simple else 11):
		var angle := branch * 2.39996
		var y := .36 + float(branch % 5) * .092
		var reach := .16 * (1.0 - (y - .35) * .75)
		var middle := Vector3(cos(angle) * reach * .65, y + .12, sin(angle) * reach * .65)
		var end := Vector3(cos(angle) * reach, y + .26, sin(angle) * reach)
		_tapered_limb(surface, Vector3(0,y,0), middle, .007, .003, 5, Color.WHITE)
		_tapered_limb(surface, middle, end, .003, .0005, 4, Color.WHITE)
	return surface.commit()

func _birch_crown(simple: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_photo := ResourceLoader.exists("res://assets/world/expedition_birch_branch.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 91374
	for branch in range(6 if simple else 11):
		var angle := branch * 2.39996
		var y := .36 + float(branch % 5) * .092
		var reach := .16 * (1.0 - (y - .35) * .75)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var tangent := Vector3(-sin(angle), 0, cos(angle))
		if has_photo:
			_branch_card(surface, radial * reach * .35 + Vector3.UP * (y + .08), tangent * .10, radial * .075 + Vector3.UP * .23, .94)
			_branch_card(surface, radial * reach * .5 + Vector3.UP * (y + .08), tangent * .025 + Vector3.UP * .08, radial * .10 + Vector3.UP * .16, .91)
		else:
			for leaf in range(14 if simple else 34):
				var at := radial * reach * rng.randf_range(.40, 1.25) + tangent * rng.randf_range(-.085, .085) + Vector3.UP * (y + rng.randf_range(.08, .28))
				var across := tangent * rng.randf_range(.018, .035)
				var rise := Vector3.UP * rng.randf_range(.028, .047) + radial * .012
				var tint := Color(.85,.92,.71).lerp(Color(1.1,1.05,.85), rng.randf())
				_emit_triangle(surface, at - across, at - rise, at + across, tint)
				_emit_triangle(surface, at - across, at + across, at + rise, tint)
	return surface.commit()

func _make_batch(mesh: Mesh, material: Material, transforms: Array, label_text: String) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
		var tone := .91 + .14 * sin(float(i) * 12.817 + transforms[i].origin.x)
		multi.set_instance_color(i, Color(tone, tone, tone))
	var visual := MultiMeshInstance3D.new()
	visual.name = label_text
	visual.multimesh = multi
	visual.material_override = material
	_course.add_child(visual)
	return visual

func _build_forest() -> void:
	var obstacles: Array = _core.get_expedition_obstacles(map_mode)
	var cells: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 81831 + map_mode
	var plants: Dictionary = {}
	for obstacle in obstacles:
		var x := float(obstacle.x)
		var z := float(obstacle.z)
		var h := float(obstacle.height)
		var radius := float(obstacle.radius)
		var kind := "birch" if int(obstacle.type) == 3 else "pine"
		var at := Vector3(x, _core.terrain_height(x, z), z)
		var cell := Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))
		# Variants vary between cells; per-tree scale/rotation varies within them.
		# This keeps one canopy draw per species/cell instead of doubling draws.
		var variant := absi(cell.x * 17 + cell.y * 31) % 2
		var key := "%d_%d_%s_%d" % [cell.x, cell.y, kind, variant]
		if not cells.has(key):
			cells[key] = {"trunks": [], "crowns": [], "center": Vector3((cell.x + .5) * CELL_SIZE, 0, (cell.y + .5) * CELL_SIZE), "kind": kind, "variant": variant}
		var basis_value := Basis(Vector3.UP, rng.randf() * TAU)
		cells[key].trunks.append(Transform3D(basis_value.scaled(Vector3(radius, h, radius)), at))
		cells[key].crowns.append(Transform3D(basis_value.scaled(Vector3.ONE * h), at))
		_tree_count += 1
		# Rooted ferns occur in sparse islands; they are less than knee height and
		# never conceal the driving surface or add invisible supporting collision.
		if _tree_count % 2 == 0:
			for j in range(2):
				var p := at + Vector3(rng.randf_range(-2.4, 2.4), 0, rng.randf_range(-2.4, 2.4))
				p.y = _core.terrain_height(p.x, p.z)
				var sample_index := clampi(roundi((p.z + MAP_EXTENT) * .5), 0, 320) * MAP_SIDE + clampi(roundi((p.x + MAP_EXTENT) * .5), 0, 320)
				if _weights[sample_index].g > .38 or _weights[sample_index].r > .58 or _weights[sample_index].a > .8:
					continue
				if not plants.has(cell):
					plants[cell] = []
				var size := rng.randf_range(.55, 1.08)
				plants[cell].append(Transform3D(Basis(Vector3.UP, rng.randf()*TAU).scaled(Vector3(size, size, size)), p))
	var trunk_mesh := _trunk_mesh()
	for kind in ["pine", "birch"]:
		for variant in range(2):
			var key: String = kind + str(variant)
			_foliage_meshes[key] = [_conifer_crown(variant, false), _conifer_crown(variant, true)] if kind == "pine" else [_birch_crown(false), _birch_crown(true)]
			_branch_meshes[key] = _conifer_branches(variant) if kind == "pine" else _birch_branches(false)
	for key in cells:
		var cell: Dictionary = cells[key]
		var kind: String = cell.kind
		var meshes: Array = _foliage_meshes[kind + str(cell.variant)]
		var trunks := _make_batch(trunk_mesh, _materials[kind + "_bark"], cell.trunks, "Trunks_" + key)
		var branches := _make_batch(_branch_meshes[kind + str(cell.variant)], _materials[kind + "_bark"], cell.crowns, "Boughs_" + key)
		var crowns := _make_batch(meshes[1], _materials[kind], cell.crowns, "Canopy_" + key)
		_forest_cells.append({"center": cell.center, "trunks": trunks, "branches": branches, "crowns": crowns, "near_mesh": meshes[0], "far_mesh": meshes[1]})
	var fern_mesh := _fern_mesh()
	for cell in plants:
		var cover := _make_batch(fern_mesh, _materials.fern, plants[cell], "ForestFloor_%d_%d" % [cell.x, cell.y])
		cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cover.visibility_range_end = 95.0
		_vegetation.append(cover)

func _fern_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in range(7):
		var angle := frond * 2.39996
		var radial := Vector3(cos(angle), 0, sin(angle))
		var tangent := Vector3(-sin(angle), 0, cos(angle))
		var height := .38 + .10 * sin(frond * 1.27)
		for leaf in range(5):
			var t := float(leaf + 1) / 6.0
			var center := radial * t * .49 + Vector3.UP * (sin(t * PI * .82) * height)
			var half_width := .095 * sin(t * PI)
			var tip := center + radial * .13
			var tint := Color(.7,.8,.6).lerp(Color(1.1,1.,.77), t)
			_emit_triangle(surface, center, center + tangent * half_width + radial * .025, tip, tint)
			_emit_triangle(surface, center, tip, center - tangent * half_width + radial * .025, tint)
	return surface.commit()

func update_focus(at: Vector3) -> void:
	if at.distance_squared_to(_last_focus) < 144.0:
		return
	_last_focus = at
	var terrain_near: float = [106.0, 138.0, 178.0][_quality]
	for chunk in _chunks:
		var center: Vector3 = chunk.center
		var distance := Vector2(center.x - at.x, center.z - at.z).length()
		chunk.visual.mesh = chunk.near_mesh if distance < terrain_near else chunk.far_mesh
		chunk.visual.visible = distance < 750.0
	var tree_near: float = [87.0, 112.0, 148.0][_quality]
	var tree_far: float = [305.0, 385.0, 450.0][_quality]
	for cell in _forest_cells:
		var center: Vector3 = cell.center
		var distance := Vector2(center.x - at.x, center.z - at.z).length()
		cell.crowns.multimesh.mesh = cell.near_mesh if distance < tree_near else cell.far_mesh
		cell.crowns.visible = distance < tree_far
		cell.trunks.visible = distance < tree_far
		cell.branches.visible = distance < tree_near
		cell.crowns.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if distance < tree_near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_expedition_lake() -> void:
	var center := Vector2(108, -87) if map_mode == 4 else Vector2(26, -147)
	var radius := Vector2(35, 28) if map_mode == 4 else Vector2(83, 66)
	var water_height := 5.0 if map_mode == 4 else -1.6
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangle_count := 0
	for z in range(floori(center.y - radius.y - 8), ceili(center.y + radius.y + 8), 2):
		for x in range(floori(center.x - radius.x - 8), ceili(center.x + radius.x + 8), 2):
			for triangle in [[Vector2(x,z), Vector2(x+2,z), Vector2(x,z+2)], [Vector2(x+2,z), Vector2(x+2,z+2), Vector2(x,z+2)]]:
				var polygon: Array[Vector3] = []
				for p in triangle:
					polygon.append(Vector3(p.x, _core.terrain_height(p.x, p.y), p.y))
				var clipped: Array[Vector3] = []
				for i in range(3):
					var a := polygon[i]
					var b := polygon[(i + 1) % 3]
					if a.y < water_height:
						clipped.append(a)
					if (a.y < water_height) != (b.y < water_height):
						clipped.append(a.lerp(b, (water_height - a.y) / (b.y - a.y)))
				for i in range(1, clipped.size() - 1):
					for vertex in [clipped[0], clipped[i], clipped[i + 1]]:
						surface.set_normal(Vector3.UP)
						surface.set_color(Color(clampf((water_height - vertex.y) / 2.5, 0, 1), 0, 0))
						surface.add_vertex(Vector3(vertex.x, water_height + .014, vertex.z))
					triangle_count += 1
	if triangle_count == 0:
		return
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/world_water.gdshader")
	material.set_shader_parameter("ripple_normal", load("res://assets/world/terrain_dirt_normal.png"))
	material.set_shader_parameter("deep_color", Color("172d32") if map_mode == 5 else Color("233f49"))
	material.set_shader_parameter("shallow_color", Color("475548"))
	var water := _instance(surface.commit(), material, Vector3.ZERO)
	water.name = "GlacialLake"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_trailhead() -> void:
	# Wayfinding belongs to the trailhead. The routes themselves remain natural
	# connected rock and soil, without floating labels or obstacle-course gates.
	var title := "SILVERPINE RANGE" if map_mode == 4 else "KARELIA / КАРЕЛИЯ"
	var sub := "ROCKY MOUNTAINS" if map_mode == 4 else "NORTHWEST RUSSIA"
	var at := Vector3(-6.5, _core.terrain_height(-6.5, 9.8), 9.8)
	for offset in [-1.18, 1.18]:
		_box(Vector3(.13, 2.25, .13), at + Vector3(offset, 1.125, 0), _materials.wood)
	_box(Vector3(2.6, 1.06, .12), at + Vector3(0, 1.82, 0), _materials.sign)
	_box(Vector3(2.78, .13, .30), at + Vector3(0, 2.40, 0), _materials.wood)
	_label(title, at + Vector3(0, 2.00, .068), 29, .0044)
	_label(sub + "\nEXPLORE / CHOOSE YOUR LINE", at + Vector3(0, 1.63, .068), 21, .0040)
