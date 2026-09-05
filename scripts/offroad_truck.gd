class_name OffroadTruck
extends Node3D

## Every visible body panel and tire is skinned directly to the native solver's
## world-space particles. There is deliberately no rigid replacement vehicle.
var core: RefCounted
var throttle: float = 0.0
var steering: float = 0.0
var brake: bool = false
var wireframe: bool = false
var body_color: Color = Color("d88844")
var _body: MeshInstance3D
var _graph: MeshInstance3D
var _body_mesh := ImmediateMesh.new()
var _graph_mesh := ImmediateMesh.new()
var _materials: Array[StandardMaterial3D] = []
var _panels: Array = []
var _bind_map: Dictionary = {}
var _bind_points := PackedVector3Array()
var _bind_bases := PackedInt32Array()
var _deformed := PackedVector3Array()
var _nodes := PackedVector3Array()
var _hubs := PackedInt32Array()
var _tire_skin := PackedVector3Array()
var _tire_padding: float = 0.0552
var _stats: Dictionary = {}
var _sim_ms: float = 0.0
var _configured: bool = false

const PAINT := 0
const DARK := 1
const GLASS := 2
const METAL := 3
const LIGHT := 4
const RED := 5
const RUBBER := 6
const TREAD := 7
const AMBER := 8
const RING_SEGMENTS := 10

func configure(settings: Dictionary) -> void:
	if core == null:
		if not ClassDB.class_exists("SoftBodyRig"):
			push_error("SoftBodyRig native extension is unavailable.")
			return
		core = ClassDB.instantiate("SoftBodyRig") as RefCounted
	_tire_padding = clampf(float(settings.get("tire_radius", 0.46)), 0.32, 0.65) * 0.12
	core.configure(settings)
	core.set_terrain(1)
	if settings.has("body_color"):
		body_color = Color(settings.body_color)
	_hubs = core.get_wheel_hubs()
	_configured = true
	if is_inside_tree():
		_refresh_visuals()

func _ready() -> void:
	_build_materials()
	_body = MeshInstance3D.new()
	_body.name = "ParticleSkinnedTruck"
	_body.mesh = _body_mesh
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_body)
	_graph = MeshInstance3D.new()
	_graph.name = "BeamDiagnostic"
	_graph.mesh = _graph_mesh
	_graph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_graph)
	_build_panels()
	if not _configured:
		configure({})
	_refresh_visuals()

func reset() -> void:
	if core != null:
		core.reset(Vector3(0.0, 1.5, 8.0))
		core.set_terrain(1)
	throttle = 0.0
	steering = 0.0
	_refresh_visuals()

func set_drivetrain(low_range: bool, locked_diffs: bool) -> void:
	if core != null and core.has_method("set_drivetrain"):
		core.set_drivetrain(low_range, locked_diffs)

func get_telemetry() -> Dictionary:
	if core != null:
		_stats = core.get_stats()
	_stats["sim_ms"] = _sim_ms
	if not _stats.has("position"):
		_stats["position"] = Vector3(0, 1.5, 8)
	if not _stats.has("forward"):
		_stats["forward"] = Vector3.FORWARD
	if not _stats.has("up"):
		_stats["up"] = Vector3.UP
	return _stats

func _physics_process(delta: float) -> void:
	if not _configured or core == null:
		return
	var begin_usec := Time.get_ticks_usec()
	core.step(delta, throttle, steering, brake)
	_sim_ms = float(Time.get_ticks_usec() - begin_usec) / 1000.0

func _process(_delta: float) -> void:
	_refresh_visuals()

func _material(color: Color, roughness: float = 0.75) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result

func _build_materials() -> void:
	_materials = [
		_material(body_color, 0.38), _material(Color("202b2c")),
		_material(Color("20434b"), 0.18), _material(Color("9ea8a2"), 0.35),
		_material(Color("fff0c4"), 0.25), _material(Color("b83f2f"), 0.25),
		_material(Color("171b1c")), _material(Color("333a39")),
		_material(Color("ecc465"), 0.4)
	]
	_materials[METAL].metallic = 0.65
	_materials[LIGHT].emission_enabled = true
	_materials[LIGHT].emission = Color("f4d690")
	_materials[LIGHT].emission_energy_multiplier = 0.8
	var graph_material := _material(Color.WHITE)
	graph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	graph_material.vertex_color_use_as_albedo = true
	graph_material.no_depth_test = true
	_materials.append(graph_material)

# A panel's coordinates are trilinear weights inside the corresponding chassis
# or cab node box. Modest extrapolation gives fenders and bumpers a real outline
# while ensuring every point follows local bending and permanent deformation.
func _bind_vertex(base: int, at: Vector3) -> int:
	var key := Vector4(at.x, at.y, at.z, float(base))
	if _bind_map.has(key):
		return int(_bind_map[key])
	var index := _bind_points.size()
	_bind_map[key] = index
	_bind_points.append(at)
	_bind_bases.append(base)
	return index

func _panel(material_id: int, base: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_panels[material_id].append(PackedInt32Array([_bind_vertex(base, a), _bind_vertex(base, d), _bind_vertex(base, c), _bind_vertex(base, b)]))

func _box(material_id: int, base: int, lo: Vector3, hi: Vector3) -> void:
	var a := Vector3(lo.x, lo.y, lo.z)
	var b := Vector3(hi.x, lo.y, lo.z)
	var c := Vector3(hi.x, hi.y, lo.z)
	var d := Vector3(lo.x, hi.y, lo.z)
	var e := Vector3(lo.x, lo.y, hi.z)
	var f := Vector3(hi.x, lo.y, hi.z)
	var g := Vector3(hi.x, hi.y, hi.z)
	var h := Vector3(lo.x, hi.y, hi.z)
	_panel(material_id, base, a, b, c, d)
	_panel(material_id, base, f, e, h, g)
	_panel(material_id, base, e, a, d, h)
	_panel(material_id, base, b, f, g, c)
	_panel(material_id, base, d, c, g, h)
	_panel(material_id, base, e, f, b, a)

func _build_panels() -> void:
	_panels.clear()
	_bind_map.clear()
	_bind_points.clear()
	_bind_bases.clear()
	for unused in range(9):
		_panels.append([])
	# Ladder-frame underbody and substantial but open pickup bed.
	_box(DARK, 0, Vector3(0.09, -0.14, -0.02), Vector3(0.91, 0.35, 1.02))
	_box(PAINT, 0, Vector3(-0.08, 0.42, -0.12), Vector3(1.08, 1.88, 0.2))
	_box(PAINT, 0, Vector3(-0.08, 0.38, 0.2), Vector3(0.015, 1.02, 0.63))
	_box(PAINT, 0, Vector3(0.985, 0.38, 0.2), Vector3(1.08, 1.02, 0.63))
	_box(DARK, 0, Vector3(-0.05, 0.65, 0.62), Vector3(1.05, 0.8, 1.12))
	_box(PAINT, 0, Vector3(-0.08, 0.72, 0.62), Vector3(0.025, 1.85, 1.14))
	_box(PAINT, 0, Vector3(0.975, 0.72, 0.62), Vector3(1.08, 1.85, 1.14))
	_box(PAINT, 0, Vector3(0.02, 0.72, 1.075), Vector3(0.98, 1.85, 1.14))
	# Cab body itself uses the eight cab particles, independent of chassis twist.
	_box(PAINT, 8, Vector3(-0.09, -0.16, -0.01), Vector3(1.09, 0.96, 1.01))
	_box(PAINT, 8, Vector3(-0.12, 0.95, -0.05), Vector3(1.12, 1.035, 1.05))
	_panel(GLASS, 8, Vector3(0.04, 0.4, -0.019), Vector3(0.96, 0.4, -0.019), Vector3(0.96, 0.89, -0.019), Vector3(0.04, 0.89, -0.019))
	_panel(GLASS, 8, Vector3(0.06, 0.4, 1.019), Vector3(0.06, 0.86, 1.019), Vector3(0.94, 0.86, 1.019), Vector3(0.94, 0.4, 1.019))
	for side in [-0.098, 1.098]:
		_panel(GLASS, 8, Vector3(side, 0.36, 0.09), Vector3(side, 0.9, 0.09), Vector3(side, 0.9, 0.65), Vector3(side, 0.36, 0.65))
		_panel(GLASS, 8, Vector3(side, 0.36, 0.71), Vector3(side, 0.9, 0.71), Vector3(side, 0.9, 0.92), Vector3(side, 0.36, 0.92))
		_box(DARK, 8, Vector3(side - 0.01, 0.21, 0.52), Vector3(side + 0.01, 0.25, 0.66))
		# Mirrors and the belt line remain coupled to the cab particles.
		var outboard: float = side - 0.10 if side < 0 else side + 0.10
		_box(DARK, 8, Vector3(minf(side, outboard), 0.4, -0.02), Vector3(maxf(side, outboard), 0.53, 0.13))
	# Bumpers, grille, lights and hood louvers deform with the chassis.
	_box(DARK, 0, Vector3(-0.16, 0.1, -0.205), Vector3(1.16, 0.53, -0.115))
	_box(METAL, 0, Vector3(0.3, 0.06, -0.225), Vector3(0.7, 0.4, -0.202))
	_box(DARK, 0, Vector3(-0.16, 0.1, 1.13), Vector3(1.16, 0.53, 1.22))
	_panel(DARK, 0, Vector3(0.18, 0.65, -0.124), Vector3(0.82, 0.65, -0.124), Vector3(0.82, 1.63, -0.124), Vector3(0.18, 1.63, -0.124))
	for slot in range(6):
		var sx := 0.245 + float(slot) * 0.09
		_box(METAL, 0, Vector3(sx, 0.75, -0.132), Vector3(sx + 0.025, 1.48, -0.127))
	for sx in [-0.005, 0.85]:
		_box(LIGHT, 0, Vector3(sx, 1.0, -0.139), Vector3(sx + 0.155, 1.59, -0.123))
		_box(AMBER, 0, Vector3(sx, 0.72, -0.14), Vector3(sx + 0.155, 0.88, -0.124))
		_box(RED, 0, Vector3(sx, 0.92, 1.142), Vector3(sx + 0.155, 1.61, 1.151))
	for stripe in range(4):
		var stripe_z := -0.015 + float(stripe) * 0.04
		_panel(DARK, 0, Vector3(0.32, 1.887, stripe_z), Vector3(0.68, 1.887, stripe_z), Vector3(0.68, 1.887, stripe_z + 0.012), Vector3(0.32, 1.887, stripe_z + 0.012))
	# Rock sliders and squared wheel flares: they bend rather than floating.
	for side in [-0.13, 1.13]:
		_box(DARK, 0, Vector3(side - 0.035, 0.15, 0.2), Vector3(side + 0.035, 0.4, 0.77))
		for end_z in [-0.03, 0.96]:
			_box(DARK, 0, Vector3(side - 0.07, 0.38, end_z - 0.17), Vector3(side + 0.07, 0.7, end_z + 0.17))
	# A simple roof rack is cab-weighted as well.
	_box(DARK, 8, Vector3(0.01, 1.09, 0.11), Vector3(0.99, 1.14, 0.16))
	_box(DARK, 8, Vector3(0.01, 1.09, 0.84), Vector3(0.99, 1.14, 0.89))
	for sx in [0.02, 0.95]:
		_box(DARK, 8, Vector3(sx, 1.025, 0.12), Vector3(sx + 0.035, 1.15, 0.88))

func _skin(base: int, local: Vector3) -> Vector3:
	var front_low: Vector3 = _nodes[base].lerp(_nodes[base + 1], local.x)
	var rear_low: Vector3 = _nodes[base + 2].lerp(_nodes[base + 3], local.x)
	var front_high: Vector3 = _nodes[base + 4].lerp(_nodes[base + 5], local.x)
	var rear_high: Vector3 = _nodes[base + 6].lerp(_nodes[base + 7], local.x)
	return front_low.lerp(rear_low, local.z).lerp(front_high.lerp(rear_high, local.z), local.y)

func _triangle(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	mesh.surface_set_normal(normal)
	# Godot's clockwise front-face convention is opposite the cross-product.
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(b)

func _quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(mesh, a, b, c)
	_triangle(mesh, a, c, d)

func _refresh_visuals() -> void:
	if core == null or _body == null:
		return
	_nodes = core.get_nodes()
	if _nodes.size() < 100:
		return
	_tire_skin = _nodes.duplicate()
	for hub in _hubs:
		for side in range(2):
			var ring_start: int = hub + 1 + side * RING_SEGMENTS
			var center := Vector3.ZERO
			for j in range(RING_SEGMENTS):
				center += _nodes[ring_start + j]
			center /= float(RING_SEGMENTS)
			for j in range(RING_SEGMENTS):
				var id: int = ring_start + j
				_tire_skin[id] = _nodes[id] + (_nodes[id] - center).normalized() * _tire_padding
	_materials[PAINT].albedo_color = body_color
	_body.visible = not wireframe
	_graph.visible = wireframe
	if wireframe:
		_draw_graph()
		return
	_deformed.resize(_bind_points.size())
	for i in range(_bind_points.size()):
		_deformed[i] = _skin(_bind_bases[i], _bind_points[i])
	_body_mesh.clear_surfaces()
	for material_id in range(9):
		_body_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _materials[material_id])
		for panel in _panels[material_id]:
			_quad(_body_mesh, _deformed[panel[0]], _deformed[panel[1]], _deformed[panel[2]], _deformed[panel[3]])
		if material_id == RUBBER:
			_draw_tires()
		elif material_id == TREAD:
			_draw_treads()
		elif material_id == METAL:
			_draw_rims()
		elif material_id == AMBER:
			_draw_suspension()
		_body_mesh.surface_end()

func _draw_tires() -> void:
	for hub in _hubs:
		var center: Vector3 = _nodes[hub]
		for j in range(RING_SEGMENTS):
			var k: int = (j + 1) % RING_SEGMENTS
			var a: Vector3 = _tire_skin[hub + 1 + j]
			var b: Vector3 = _tire_skin[hub + 1 + k]
			var c: Vector3 = _tire_skin[hub + 11 + k]
			var d: Vector3 = _tire_skin[hub + 11 + j]
			_quad(_body_mesh, a, b, c, d)
			_quad(_body_mesh, a, center.lerp(a, 0.50), center.lerp(b, 0.50), b)
			_quad(_body_mesh, d, c, center.lerp(c, 0.50), center.lerp(d, 0.50))

func _draw_treads() -> void:
	for hub in _hubs:
		var center: Vector3 = _nodes[hub]
		for j in range(RING_SEGMENTS):
			var k: int = (j + 1) % RING_SEGMENTS
			var inner_a: Vector3 = _tire_skin[hub + 1 + j]
			var inner_b: Vector3 = _tire_skin[hub + 1 + k]
			var outer_a: Vector3 = _tire_skin[hub + 11 + j]
			var outer_b: Vector3 = _tire_skin[hub + 11 + k]
			var normal := ((inner_a + inner_b + outer_a + outer_b) * 0.25 - center).normalized()
			var a := inner_a.lerp(inner_b, 0.18)
			var b := inner_a.lerp(inner_b, 0.62)
			var c := outer_a.lerp(outer_b, 0.8)
			var d := outer_a.lerp(outer_b, 0.35)
			_quad(_body_mesh, a + normal * 0.025, b + normal * 0.025, c + normal * 0.025, d + normal * 0.025)

func _draw_rims() -> void:
	for hub in _hubs:
		var center: Vector3 = _nodes[hub]
		for side in range(2):
			var ring_start: int = hub + 1 + side * RING_SEGMENTS
			var face_center := Vector3.ZERO
			for j in range(RING_SEGMENTS):
				face_center += _nodes[ring_start + j]
			face_center /= float(RING_SEGMENTS)
			var cap := center.lerp(face_center, 0.72)
			for j in range(RING_SEGMENTS):
				var k: int = (j + 1) % RING_SEGMENTS
				var a := center.lerp(_nodes[ring_start + j], 0.49)
				var b := center.lerp(_nodes[ring_start + k], 0.49)
				var inner_a := cap.lerp(a, 0.64)
				var inner_b := cap.lerp(b, 0.64)
				_quad(_body_mesh, a, b, inner_b, inner_a)
				if j % 2 == 0:
					_triangle(_body_mesh, cap, inner_a, inner_b)

func _draw_suspension() -> void:
	for w in range(_hubs.size()):
		var a: Vector3 = _nodes[w + 4]
		var b: Vector3 = _nodes[_hubs[w]]
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.FORWARD).normalized() * 0.035
		if side.length_squared() < 0.00001:
			side = Vector3.RIGHT * 0.035
		var other := axis.cross(side)
		for j in range(5):
			var t := float(j) * TAU / 5.0
			var t2 := float(j + 1) * TAU / 5.0
			var p := side * cos(t) + other * sin(t)
			var q := side * cos(t2) + other * sin(t2)
			_quad(_body_mesh, a + p, b + p, b + q, a + q)

func _draw_graph() -> void:
	_graph_mesh.clear_surfaces()
	var beams: PackedInt32Array = core.get_beams()
	var kinds: PackedInt32Array = core.get_beam_kinds()
	var broken: PackedByteArray = core.get_broken()
	var strains := PackedFloat32Array()
	if core.has_method("get_strains"):
		strains = core.get_strains()
	var colors := [Color("f0c96f"), Color("65d9e8"), Color("8de89a"), Color("9bb6c5")]
	_graph_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _materials[9])
	for i in range(beams.size() >> 1):
		var color: Color = colors[clampi(kinds[i], 0, 3)]
		if i < strains.size():
			color = color.lerp(Color("ff694f"), clampf(absf(strains[i]) * 6.0, 0.0, 1.0))
		if broken[i] != 0:
			color = Color("ff3e4e")
		_graph_mesh.surface_set_color(color)
		_graph_mesh.surface_add_vertex(_nodes[beams[i * 2]])
		_graph_mesh.surface_add_vertex(_nodes[beams[i * 2 + 1]])
	_graph_mesh.surface_end()
