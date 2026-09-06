extends OffroadWorld

## Copperline is a compact desert wash carved through one fractured rock bed.
## Every climbable silhouette comes from native convex collision triangles.
## Shrubs and <= 18 mm embedded gravel are non-supporting surface dressing.
const SECTIONS = [
	["slab", "01  FIRST FOOTING", -3.0, "Ease onto the slab. Keep all four tires loaded."],
	["steps", "02  THE STAIRCASE", -17.0, "Square approach or diagonal line: place a tire, then feed torque."],
	["garden", "03  CROOKED TEETH", -33.0, "Staggered rocks. Straddle a gap or pick the clear outside line."],
	["shelf", "04  SIDE EFFECTS", -47.0, "An off-camber shelf. Watch the uphill tire loads."],
	["summit", "05  LAST WORD", -63.0, "A long final slab with an optional ledge on the left."]
]
var _rock_material: ShaderMaterial
var _rock_bounds: Array[AABB] = []
var _crawl_props: Node3D
var _floor_shade_cache: Dictionary = {}
var _lighting_restore: Dictionary = {}
var _crawl_fill: DirectionalLight3D

func configure(solver: RefCounted) -> void:
	_core = solver
	_core.set_terrain(3)
	if not is_instance_valid(_crawl_props):
		_crawl_props = preload("res://scripts/crawl_props.gd").new()
		_crawl_props.name = "LooseObjects"
		add_child(_crawl_props)
	_crawl_props.configure(_core)

func get_landmarks() -> Array:
	var result: Array = []
	for section in SECTIONS:
		result.append({"id": section[0], "name": section[1], "position": Vector3(0, 0, section[2]), "radius": 4.0, "description": section[3]})
	return result

func _make_lighting() -> void:
	super._make_lighting()
	var settings: Environment = _environment.environment
	_crawl_fill = get_node_or_null("OpenSkyFill") as DirectionalLight3D
	_lighting_restore = {
		"rotation": _sun.rotation_degrees, "sun_color": _sun.light_color,
		"sun_energy": _sun.light_energy, "bias": _sun.shadow_bias,
		"normal_bias": _sun.shadow_normal_bias,
		"ambient_color": settings.ambient_light_color,
		"ambient_energy": settings.ambient_light_energy,
		"fog_density": settings.fog_density, "fog_color": settings.fog_light_color,
		"fog_energy": settings.fog_light_energy, "fog_sky": settings.fog_sky_affect,
		"fill_energy": _crawl_fill.light_energy if _crawl_fill != null else 0.14
	}
	# A higher late-afternoon key reveals contact faces without the nearly
	# horizontal black shadows of the exploration valley's sunset.
	_sun.rotation_degrees = Vector3(-39, -48, 0)
	_sun.light_color = Color("fff0d8")
	_sun.light_energy = 1.0
	_sun.shadow_bias = 0.9
	_sun.shadow_normal_bias = 1.8
	settings.ambient_light_color = Color("becad0")
	settings.ambient_light_energy = 0.27
	settings.fog_density = 0.00125
	settings.fog_light_color = Color("a6afb1")
	settings.fog_light_energy = 0.72
	settings.fog_sky_affect = 0.05
	if _crawl_fill != null:
		_crawl_fill.light_energy = 0.19

func _exit_tree() -> void:
	# Course switching reparents the one lighting set before removing this world.
	# Restore its exploration values without making another sky or reflection.
	if _lighting_restore.is_empty() or not is_instance_valid(_environment) or not is_instance_valid(_sun):
		return
	_sun.rotation_degrees = _lighting_restore.rotation
	_sun.light_color = _lighting_restore.sun_color
	_sun.light_energy = _lighting_restore.sun_energy
	_sun.shadow_bias = _lighting_restore.bias
	_sun.shadow_normal_bias = _lighting_restore.normal_bias
	var settings: Environment = _environment.environment
	settings.ambient_light_color = _lighting_restore.ambient_color
	settings.ambient_light_energy = _lighting_restore.ambient_energy
	settings.fog_density = _lighting_restore.fog_density
	settings.fog_light_color = _lighting_restore.fog_color
	settings.fog_light_energy = _lighting_restore.fog_energy
	settings.fog_sky_affect = _lighting_restore.fog_sky
	if is_instance_valid(_crawl_fill):
		_crawl_fill.light_energy = _lighting_restore.fill_energy

func set_quality(level: int) -> void:
	super.set_quality(level)
	if _rock_material != null:
		_rock_material.set_shader_parameter("detailed_surface", _quality > 0)
	# The inherited once-baked valley probe cannot describe this stone wash.
	# Sky reflections are stable, allocation-free, and already used by the rig.
	if _reflection != null:
		_reflection.visible = false

func _build_course() -> void:
	_core.set_terrain(3)
	_vegetation.clear()
	_rock_bounds.clear()
	_make_materials()
	_course = Node3D.new()
	_course.name = "Copperline"
	add_child(_course)
	var noise_texture: Texture2D = load("res://assets/world/copper_mineral_noise.png")
	_rock_material = ShaderMaterial.new()
	_rock_material.shader = load("res://shaders/copper_sandstone.gdshader")
	_rock_material.set_shader_parameter("grain", load("res://assets/world/terrain_rock_photo.png"))
	_rock_material.set_shader_parameter("mineral_noise", noise_texture)
	var rocks: Array = _core.get_crawl_rocks()
	_build_shared_rocks(rocks)
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = load("res://shaders/copper_ground.gdshader")
	_ground_material.set_shader_parameter("mineral_noise", noise_texture)
	_ground_material.set_shader_parameter("stone_grain", load("res://assets/world/terrain_rock_photo.png"))
	_build_wash_floor()
	_build_wash_plants()
	for section in SECTIONS:
		_make_marker(section[1], Vector3(-5.9, 0, section[2] + 5.0))
	_make_marker("COPPERLINE\nFRACTURE WASH / 85 m", Vector3(-5.9, 0, 9))
	_make_marker("LOOSE LINE\nOBJECTS MOVE", Vector3(6.1, 0, -7))
	_make_marker("FINISH\nTHE WASH CONTINUES", Vector3(-5.9, 0, -78))
	_build_route_markers()
	_built_core_id = _core.get_instance_id()
	set_quality(_quality)

func _build_shared_rocks(rocks: Array) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock_index := 0
	for vertices in rocks:
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for vertex in vertices:
			bounds = bounds.expand(vertex)
		_rock_bounds.append(bounds)
		var mineral_tint := 0.96 + 0.065 * sin(rock_index * 13.17)
		for i in range(0, vertices.size(), 3):
			var a: Vector3 = vertices[i]
			var b: Vector3 = vertices[i + 1]
			var c: Vector3 = vertices[i + 2]
			var normal := (b - a).cross(c - a).normalized()
			# Godot uses clockwise faces; native geometry has outward cross products.
			for vertex: Vector3 in [a, c, b]:
				surface.set_normal(normal)
				var foot_shade := smoothstep(0.02, 0.65, vertex.y)
				surface.set_color(Color(mineral_tint, mineral_tint, mineral_tint, foot_shade))
				surface.add_vertex(vertex)
		rock_index += 1
	var visual := MeshInstance3D.new()
	visual.name = "SharedCollisionSandstone"
	visual.mesh = surface.commit()
	visual.material_override = _rock_material
	_course.add_child(visual)

func _ground_shade(x: float, z: float) -> float:
	var key := Vector2(x, z)
	if _floor_shade_cache.has(key):
		return _floor_shade_cache[key]
	var shade := 1.0
	for bounds in _rock_bounds:
		# A soft baked contact apron, with rounded corners; it carries no depth.
		var center := bounds.get_center()
		var extent := bounds.size * 0.5
		if absf(x - center.x) > extent.x + 1.1 or absf(z - center.z) > extent.z + 1.1:
			continue
		var dx := maxf(absf(x - center.x) - extent.x * 0.82, 0.0)
		var dz := maxf(absf(z - center.z) - extent.z * 0.82, 0.0)
		var distance := sqrt(dx * dx + dz * dz)
		shade = minf(shade, lerpf(0.72, 1.0, smoothstep(0.12, 1.1, distance)))
	_floor_shade_cache[key] = shade
	return shade

func _floor_vertex(surface: SurfaceTool, vertex: Vector3, shade: bool) -> void:
	surface.set_normal(Vector3.UP)
	var value := _ground_shade(vertex.x, vertex.z) if shade else 1.0
	surface.set_color(Color(value, value, value))
	surface.add_vertex(vertex)

func _floor_quad(surface: SurfaceTool, x: float, z: float, width: float, depth: float, shade: bool) -> void:
	for vertex in [Vector3(x, 0, z), Vector3(x + width, 0, z), Vector3(x, 0, z + depth), Vector3(x + width, 0, z), Vector3(x + width, 0, z + depth), Vector3(x, 0, z + depth)]:
		_floor_vertex(surface, vertex, shade)

func _build_wash_floor() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Exactly flat native terrain: visual surface remains at y=0, including all
	# bypasses. A compact mesh carries contact shading with no mobile SSAO pass.
	for iz in range(94):
		for ix in range(48):
			_floor_quad(surface, -36.0 + ix * 1.5, -108.0 + iz * 1.5, 1.5, 1.5, true)
	_floor_quad(surface, -500, -500, 1000, 392, false)
	_floor_quad(surface, -500, 33, 1000, 467, false)
	_floor_quad(surface, -500, -108, 464, 141, false)
	_floor_quad(surface, 36, -108, 464, 141, false)
	# Weld the repeated triangle corners before upload; contact shade was also
	# cached once per grid vertex so startup does not pay for six copies.
	surface.index()
	var floor_visual := _instance(surface.commit(), _ground_material, Vector3.ZERO)
	_floor_shade_cache.clear()
	floor_visual.name = "WornSiltAndGravel"
	floor_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _clear_plant_position(at: Vector3, radius: float) -> bool:
	if absf(at.x) < 5.7:
		return false
	if at.x > 5.5 and at.x < 12.4 and at.z > -44.0 and at.z < -4.0:
		return false
	for bounds in _rock_bounds:
		if at.x > bounds.position.x - radius and at.x < bounds.end.x + radius and at.z > bounds.position.z - radius and at.z < bounds.end.z + radius:
			return false
	return true

func _yucca_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(17):
		var angle := blade * 2.39996
		var radial := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(-sin(angle), 0, cos(angle))
		var reach := 0.44 + 0.16 * sin(blade * 3.71)
		var h := 0.24 + 0.34 * pow(0.5 + 0.5 * sin(blade * 1.73), 2)
		var base := Vector3(0, 0.035, 0) + radial * 0.035
		var middle := radial * reach * 0.55 + Vector3.UP * h * 0.75
		var tip := radial * reach + Vector3.UP * h
		var width := 0.025 + 0.01 * sin(blade * 1.9)
		var points := [base, middle - across * width, middle + across * width, middle - across * width, tip, middle + across * width]
		for i in range(0, 6, 3):
			var normal: Vector3 = (points[i + 1] - points[i]).cross(points[i + 2] - points[i]).normalized()
			for vertex: Vector3 in [points[i], points[i + 1], points[i + 2]]:
				surface.set_normal(normal)
				surface.set_color(Color("818373").lerp(Color("b1a172"), float(blade % 4) * .19))
				surface.add_vertex(vertex)
	return surface.commit()

func _build_wash_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 507919
	var shrubs: Array[Transform3D] = []
	var grasses: Array[Transform3D] = []
	var yuccas: Array[Transform3D] = []
	var gravel: Array[Transform3D] = []
	for i in range(720):
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(5.8, 29.0), 0, rng.randf_range(-97, 23))
		if not _clear_plant_position(at, 0.28):
			continue
		# Distinct islands leave bare runoff channels between the rooted plants.
		var island := sin(at.x * .53 + at.z * .14) * sin(at.z * .31 - at.x * .18)
		if island < -0.13:
			continue
		var angle := rng.randf() * TAU
		var size := rng.randf_range(.34, .76)
		var basis_value := Basis(Vector3.UP, angle)
		if i % 5 == 0:
			yuccas.append(Transform3D(basis_value.scaled(Vector3.ONE * rng.randf_range(.75, 1.6)), at))
		elif i % 3 == 0:
			shrubs.append(Transform3D(basis_value.scaled(Vector3(size, size * .75, size)), at - Vector3.UP * .035))
		else:
			grasses.append(Transform3D(basis_value.scaled(Vector3(size, size * .65, size)), at))
		for j in range(3):
			var angle_offset := rng.randf() * TAU
			var gravel_at := at + Vector3(cos(angle_offset), 0, sin(angle_offset)) * rng.randf_range(.1, 1.2)
			var r := rng.randf_range(.045, .16)
			gravel.append(Transform3D(Basis(Vector3.UP, angle_offset).scaled(Vector3(r, .019, r * .7)), gravel_at - Vector3.UP * .001))
	# Low juniper branch fans read as silver-green desert scrub, never trees.
	var scrub_material := ShaderMaterial.new()
	scrub_material.shader = load("res://shaders/world_foliage.gdshader")
	scrub_material.set_shader_parameter("branch_texture", load("res://assets/world/juniper_branch_photo.png"))
	_cover_batches(_foliage_mesh(true), shrubs, "RootedDesertScrub", scrub_material)
	var plant_material := _mat(Color("c2bda4"), 1.0)
	plant_material.vertex_color_use_as_albedo = true
	plant_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cover_batches(_grass_mesh(), grasses, "DryBunchGrass", plant_material)
	_cover_batches(_yucca_mesh(), yuccas, "WashYucca", plant_material)
	_cover_batches(_rock_mesh(5083), gravel, "EmbeddedStoneChips", _rock_material)

func _make_marker(text: String, at: Vector3) -> void:
	var post := _box(Vector3(.085, 1.22, .085), at + Vector3(0, .60, 0), _materials.wood)
	post.name = "RootedTrailPost"
	var board_material := _mat(Color("273d3b"), .92)
	var board := _box(Vector3(1.73, .43, .065), at + Vector3(0, 1.18, .08), board_material)
	board.rotation.z = deg_to_rad(-1.5)
	_box(Vector3(.055, .43, .072), at + Vector3(-.82, 1.18, .086), _mat(Color("c79455"), .84))
	var caption := Label3D.new()
	caption.text = text
	caption.font_size = 48
	caption.pixel_size = .0030
	caption.position = at + Vector3(0, 1.18, .118)
	caption.modulate = Color("f1e6cd")
	caption.no_depth_test = false
	caption.shaded = true
	caption.outline_size = 0
	caption.visibility_range_end = 24.0
	_course.add_child(caption)
	# Small embedded foot chips anchor the post without a floating concrete base.
	var foot_material := _mat(Color("70624e"), 1.0)
	for side in [-1, 1]:
		var chip := _box(Vector3(.12, .026, .15), at + Vector3(side * .11, .011, 0), foot_material)
		chip.rotation.y = side * .37

func _build_route_markers() -> void:
	var copper := _mat(Color("ce9c61"), .88)
	var teal := _mat(Color("3b6460"), .88)
	# Sparse, planted route stakes keep the central route readable from above
	# while the unblocked outer tracks offer bypass and loose-object lines.
	for z in [5.3, -10.0, -23.8, -41.0, -54.7, -77.0]:
		for side in [-1, 1]:
			var at := Vector3(side * 3.95, .20, z)
			_box(Vector3(.042, .4, .042), at, _materials.wood)
			_box(Vector3(.065, .105, .056), at + Vector3(0, .125, 0), copper if side == -1 else teal)
