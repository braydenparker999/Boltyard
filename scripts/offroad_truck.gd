class_name OffroadTruck
extends Node3D

## All bodywork uses one continuous rest-space deformation field. Coincident
## panel edges stay coincident as the frame and cabin bend independently.
## Twenty dynamic nodes drive the frame, cabin and hubs. Eighty derived wheel
## guides provide round, rotating tires with limited contact squash.
var core: RefCounted
var throttle: float = 0.0
var steering: float = 0.0
var brake: bool = false
var wireframe: bool = false
var body_color: Color = Color("d88844")
var _body: MeshInstance3D
var _graph: MeshInstance3D
var _body_mesh := ArrayMesh.new()
var _graph_mesh := ImmediateMesh.new()
var _materials: Array[ShaderMaterial] = []
var _graph_material: StandardMaterial3D
var _nodes := PackedVector3Array()
var _rest := PackedVector3Array()
var _hubs := PackedInt32Array()
var _ring_centers := PackedVector3Array()
var _wheel_axes := PackedVector3Array()
var _wheel_normals := PackedVector3Array()
var _wheel_points := PackedVector3Array()
var _wheel_phases := PackedFloat32Array()
var _wheel_compression := PackedFloat32Array()
var _wheel_up := Vector3.UP
var _link_starts := PackedVector3Array()
var _link_ends := PackedVector3Array()
var _axle_ups := PackedVector3Array()
var _stats: Dictionary = {}
var _settings: Dictionary = {}
var _parts: Dictionary = {}
var _sim_ms: float = 0.0
var _configured: bool = false
var _vehicle_type: int = 0
var _tire_padding: float = 0.0552
var _last_color := Color.TRANSPARENT
var _buckets: Array[MeshBucket] = []
var _graph_tick: float = 0.0
var _triangle_count: int = 0
var _body_coefficients := PackedVector3Array()
var _frame_size := Vector3.ONE
var _cab_size := Vector3.ONE
var _cab_offset := Vector3.ZERO
var _cab_scale := Vector3.ONE
var _waist: float = 0.60
var _arch_radius: float = 0.62
var _arch_center_y: float = -0.10
var _render_tire_radius: float = 0.54
var _validation: Dictionary = {}

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
const RENDER_SEGMENTS := 24
const BODY_SHADER = preload("res://shaders/vehicle_body.gdshader")
const GLASS_SHADER = preload("res://shaders/vehicle_glass.gdshader")

class MeshBucket:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var bindings := PackedVector2Array()
	var colors := PackedColorArray()

func configure(settings: Dictionary) -> void:
	if core == null:
		if not ClassDB.class_exists("SoftBodyRig"):
			push_error("SoftBodyRig native extension is unavailable.")
			return
		core = ClassDB.instantiate("SoftBodyRig") as RefCounted
	_settings = settings.duplicate(true)
	_parts = settings.get("parts", {}).duplicate(true)
	_vehicle_type = clampi(int(settings.get("vehicle_type", 0)), 0, 2)
	_tire_padding = clampf(float(settings.get("tire_radius", 0.46)), 0.32, 0.65) * 0.12
	core.configure(settings)
	core.set_terrain(2)
	var paint_value: Variant = settings.get("paint", settings.get("body_color", "d88844"))
	body_color = paint_value if paint_value is Color else Color(str(paint_value))
	_hubs = core.get_wheel_hubs()
	_nodes = core.get_nodes()
	_rest = core.get_rest_nodes() if core.has_method("get_rest_nodes") else _nodes.duplicate()
	_configured = true
	if is_inside_tree() and _body != null:
		_build_vehicle_mesh()
		_refresh_visuals()

func _ready() -> void:
	_build_materials()
	_body = MeshInstance3D.new()
	_body.name = "ParticleSkinnedVehicle"
	_body.layers = 2
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Vertex positions in the source mesh are binding coordinates. The explicit
	# bounds surround the real, shader-deformed vehicle and follow its center.
	_body.custom_aabb = AABB(Vector3(-18, -18, -18), Vector3(36, 36, 36))
	add_child(_body)
	_graph = MeshInstance3D.new()
	_graph.name = "BeamDiagnostic"
	_graph.mesh = _graph_mesh
	_graph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_graph)
	if not _configured:
		configure({})
	else:
		_build_vehicle_mesh()
	_refresh_visuals()

func reset(origin: Vector3 = Vector3(0.0, 1.5, 8.0)) -> void:
	if core != null:
		core.reset(origin)
		_rest = core.get_rest_nodes()
	throttle = 0.0
	steering = 0.0
	_refresh_visuals()

func set_drivetrain(low_range: bool, locked_diffs: bool) -> void:
	if core != null:
		core.set_drivetrain(low_range, locked_diffs)

func set_axle_drivetrain(low_range: bool, front_locked: bool, rear_locked: bool) -> void:
	if core != null:
		core.set_axle_drivetrain(low_range, front_locked, rear_locked)

func get_telemetry() -> Dictionary:
	if core != null:
		_stats = core.get_stats()
	_stats["sim_ms"] = _sim_ms
	_stats["render_triangles"] = _triangle_count
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

func _process(delta: float) -> void:
	_graph_tick += delta
	_refresh_visuals()

func _build_materials() -> void:
	var colors: Array[Color] = [body_color, Color("202728"), Color("29434b"),
		Color("b2babd"), Color("f5ebd7"), Color("92252a"), Color("202729"),
		Color("2a3232"), Color("bd9659")]
	var roughness: Array[float] = [0.34, 0.61, 0.085, 0.25, 0.17, 0.22, 0.87, 0.82, 0.32]
	var metallic: Array[float] = [0.04, 0.18, 0.0, 0.93, 0.0, 0.0, 0.0, 0.0, 0.82]
	_materials.clear()
	for i in range(9):
		var material := ShaderMaterial.new()
		material.shader = GLASS_SHADER if i == GLASS else BODY_SHADER
		material.set_shader_parameter("surface_color", Color(0.085, 0.14, 0.17, 0.70) if i == GLASS else colors[i])
		if i != GLASS:
			material.set_shader_parameter("surface_kind", i)
			material.set_shader_parameter("material_roughness", roughness[i])
			material.set_shader_parameter("material_metallic", metallic[i])
			material.set_shader_parameter("paint_coat", 0.76 if i == PAINT else 0.0)
			material.set_shader_parameter("lamp_energy", 0.24 if i == LIGHT else (0.055 if i == RED else 0.0))
		_materials.append(material)
	_graph_material = StandardMaterial3D.new()
	_graph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_graph_material.vertex_color_use_as_albedo = true
	_graph_material.no_depth_test = true

func _dimensions(base: int) -> Vector3:
	return Vector3(maxf(_rest[base].distance_to(_rest[base + 1]), 0.1),
		maxf(_rest[base].distance_to(_rest[base + 4]), 0.1),
		maxf(_rest[base].distance_to(_rest[base + 2]), 0.1))

func _vertex(material_id: int, binding: int, p: Vector3, n: Vector3, tint: Color) -> void:
	var bucket: MeshBucket = _buckets[material_id]
	if binding < 16:
		var source_size := _dimensions(binding)
		var point := (_rest[binding] + p * source_size - _rest[0]) / _frame_size
		bucket.vertices.append(point)
		bucket.normals.append((n * _frame_size / source_size).normalized())
		bucket.bindings.append(Vector2.ZERO)
	else:
		bucket.vertices.append(p)
		bucket.normals.append(n)
		bucket.bindings.append(Vector2(float(binding), 0.0))
	bucket.colors.append(tint)

func _tri(material_id: int, base: int, a: Vector3, b: Vector3, c: Vector3, tint: Color = Color.WHITE) -> void:
	var normal := (b - a).cross(c - a).normalized()
	_vertex(material_id, base, a, normal, tint)
	_vertex(material_id, base, c, normal, tint)
	_vertex(material_id, base, b, normal, tint)

func _quad(material_id: int, base: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color = Color.WHITE) -> void:
	_tri(material_id, base, a, b, c, tint)
	_tri(material_id, base, a, c, d, tint)

func _box(material_id: int, base: int, lo: Vector3, hi: Vector3, tint: Color = Color.WHITE) -> void:
	var a := Vector3(lo.x, lo.y, lo.z)
	var b := Vector3(hi.x, lo.y, lo.z)
	var c := Vector3(hi.x, hi.y, lo.z)
	var d := Vector3(lo.x, hi.y, lo.z)
	var e := Vector3(lo.x, lo.y, hi.z)
	var f := Vector3(hi.x, lo.y, hi.z)
	var g := Vector3(hi.x, hi.y, hi.z)
	var h := Vector3(lo.x, hi.y, hi.z)
	_quad(material_id, base, a, d, c, b, tint)
	_quad(material_id, base, f, g, h, e, tint)
	_quad(material_id, base, e, h, d, a, tint)
	_quad(material_id, base, b, c, g, f, tint)
	_quad(material_id, base, d, h, g, c, tint)
	_quad(material_id, base, e, a, b, f, tint)

# A chamfered rectangle extruded along Z: broad flat faces with light-catching
# bevels give hoods, bumpers and bed rails a manufactured, non-cubic silhouette.
func _beveled_box(material_id: int, base: int, lo: Vector3, hi: Vector3, bevel: float = 0.025, tint: Color = Color.WHITE) -> void:
	var dim := _dimensions(base)
	var bx := minf(bevel / dim.x, (hi.x - lo.x) * 0.24)
	var by := minf(bevel / dim.y, (hi.y - lo.y) * 0.24)
	var outline: Array[Vector2] = [Vector2(lo.x + bx, lo.y), Vector2(hi.x - bx, lo.y),
		Vector2(hi.x, lo.y + by), Vector2(hi.x, hi.y - by), Vector2(hi.x - bx, hi.y),
		Vector2(lo.x + bx, hi.y), Vector2(lo.x, hi.y - by), Vector2(lo.x, lo.y + by)]
	for i in range(8):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % 8]
		_quad(material_id, base, Vector3(a.x, a.y, lo.z), Vector3(b.x, b.y, lo.z),
			Vector3(b.x, b.y, hi.z), Vector3(a.x, a.y, hi.z), tint)
		_tri(material_id, base, Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z),
			Vector3(b.x, b.y, lo.z), Vector3(a.x, a.y, lo.z), tint)
		_tri(material_id, base, Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, hi.z),
			Vector3(a.x, a.y, hi.z), Vector3(b.x, b.y, hi.z), tint)

func _tube(material_id: int, base: int, a: Vector3, b: Vector3, radius: float = 0.025, segments: int = 8) -> void:
	var dim := _dimensions(base)
	var axis := ((b - a) * dim).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = axis.cross(Vector3.FORWARD)
	side = side.normalized()
	var other := axis.cross(side).normalized()
	for j in range(segments):
		var p := (side * cos(float(j) * TAU / segments) + other * sin(float(j) * TAU / segments)) * radius / dim
		var q := (side * cos(float(j + 1) * TAU / segments) + other * sin(float(j + 1) * TAU / segments)) * radius / dim
		_quad(material_id, base, a + p, a + q, b + q, b + p)

func _build_vehicle_mesh() -> void:
	if _rest.size() < 100:
		return
	_frame_size = _dimensions(0)
	_cab_size = _dimensions(8)
	_cab_offset = (_rest[0] - _rest[8]) / _cab_size
	_cab_scale = _frame_size / _cab_size
	var radius := float(_settings.get("tire_radius", 0.46))
	var tread := 0.080 if str(_parts.get("tires", "all_terrain")) == "mud" else (0.065 if str(_parts.get("tires", "all_terrain")) == "rock" else 0.037)
	_render_tire_radius = radius * 0.88 * (1.0 + tread) + _tire_padding
	_arch_radius = _render_tire_radius + 0.065
	var ride := float(_settings.get("ride_height", 0.35))
	var travel := float(_settings.get("suspension_travel", 0.22))
	_arch_center_y = -ride + minf(travel * 1.273, ride * 0.72)
	_waist = maxf(0.60, _arch_center_y + _arch_radius + 0.13)
	_buckets.clear()
	for unused in range(9):
		_buckets.append(MeshBucket.new())
	_build_frame()
	if _vehicle_type == 2:
		_build_buggy()
	else:
		_build_closed_body(_vehicle_type == 1)
	_build_bumpers()
	_build_roof_parts()
	_build_wheels()
	_build_suspension()
	_body_mesh = ArrayMesh.new()
	_triangle_count = 0
	for material_id in range(9):
		var bucket: MeshBucket = _buckets[material_id]
		if bucket.vertices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bucket.vertices
		arrays[Mesh.ARRAY_NORMAL] = bucket.normals
		arrays[Mesh.ARRAY_TEX_UV2] = bucket.bindings
		arrays[Mesh.ARRAY_COLOR] = bucket.colors
		_body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_body_mesh.surface_set_material(_body_mesh.get_surface_count() - 1, _materials[material_id])
		_triangle_count += bucket.vertices.size() / 3
	_body.mesh = _body_mesh
	_validation = _inspect_mesh()
	_buckets.clear()

func _build_frame() -> void:
	# Twin chassis rails, cross-members, sump guard and driveshaft.
	for x in [0.2, 0.8]:
		_beveled_box(DARK, 0, Vector3(x - 0.035, -0.13, -0.07), Vector3(x + 0.035, 0.25, 1.07), 0.02)
	for z in [0.03, 0.45, 0.93]:
		_box(DARK, 0, Vector3(0.18, -0.09, z), Vector3(0.82, 0.2, z + 0.035))
	_beveled_box(METAL, 0, Vector3(0.30, -0.16, 0.13), Vector3(0.70, -0.08, 0.42), 0.018)
	_tube(METAL, 0, Vector3(0.5, -0.10, 0.05), Vector3(0.5, -0.10, 0.93), 0.032)
	for x in [-0.10, 1.10]:
		_tube(DARK, 0, Vector3(x, 0.04, 0.26), Vector3(x, 0.04, 0.74), 0.038, 6)
		for z in [0.31, 0.66]:
			_tube(DARK, 0, Vector3(0.20 if x < 0.5 else 0.80, 0.04, z), Vector3(x, 0.04, z), 0.027, 6)

# Design coordinates use normalized frame X/Z and metres above its underside.
func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y / _frame_size.y, z)

func _solid(material_id: int, lo: Vector3, hi: Vector3, bevel: float = 0.025) -> void:
	_beveled_box(material_id, 0, _v(lo.x, lo.y, lo.z), _v(hi.x, hi.y, hi.z), bevel)

func _bar(material_id: int, a: Vector3, b: Vector3, radius: float = 0.025, segments: int = 6) -> void:
	_tube(material_id, 0, _v(a.x, a.y, a.z), _v(b.x, b.y, b.z), radius, segments)

func _panel(material_id: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_quad(material_id, 0, _v(a.x, a.y, a.z), _v(b.x, b.y, b.z), _v(c.x, c.y, c.z), _v(d.x, d.y, d.z))

func _build_closed_body(suv: bool) -> void:
	var cab_front := 0.14 if suv else 0.22
	var cab_rear := 1.12 if suv else 0.64
	var roof_front := cab_front + (0.12 if suv else 0.085)
	var roof_rear := cab_rear - 0.055
	var roof_y := maxf(_rest[12].y - _rest[0].y + 0.035, _waist + 0.43)
	# A complete continuous lower shell: aperture-shaped outer panels, inner
	# arch returns, floor, firewall and boxed rockers. No freestanding flare.
	_build_side_shell(-0.10, -0.04, -0.15, 1.16)
	_build_side_shell(1.10, 1.04, -0.15, 1.16)
	_solid(DARK, Vector3(0.06, 0.015, 0.13), Vector3(0.94, 0.09, 1.12), 0.018)
	_solid(PAINT, Vector3(-0.10, 0.07, cab_front), Vector3(1.10, _waist, cab_front + 0.035), 0.018)
	# A low, sloped bonnet is closed on every side and joins the windshield cowl.
	var hood_front_y := _waist - 0.055
	_panel(PAINT, Vector3(-0.07, hood_front_y, -0.15), Vector3(-0.04, _waist + 0.015, cab_front + 0.015),
		Vector3(1.04, _waist + 0.015, cab_front + 0.015), Vector3(1.07, hood_front_y, -0.15))
	for x in [-0.10, 1.10]:
		var inset: float = x + (0.03 if x < 0.5 else -0.03)
		_panel(PAINT, Vector3(x, _waist - 0.09, -0.15), Vector3(x, _waist - 0.09, cab_front + 0.015),
			Vector3(inset, _waist + 0.015, cab_front + 0.015), Vector3(inset, hood_front_y, -0.15))
	_solid(PAINT, Vector3(-0.10, 0.27, -0.158), Vector3(1.10, hood_front_y, -0.135), 0.024)
	_build_front_face(suv)
	# Cabin: shared exact windshield/side/rear corner positions, solid pillars,
	# window seals and a roof with thickness. Lower panels remain hollow inside.
	var fbl := Vector3(-0.07, _waist, cab_front)
	var fbr := Vector3(1.07, _waist, cab_front)
	var ftl := Vector3(0.075, roof_y, roof_front)
	var ftr := Vector3(0.925, roof_y, roof_front)
	var rbl := Vector3(-0.07, _waist, cab_rear)
	var rbr := Vector3(1.07, _waist, cab_rear)
	var rtl := Vector3(0.075, roof_y, roof_rear)
	var rtr := Vector3(0.925, roof_y, roof_rear)
	_panel(GLASS, fbl, ftl, ftr, fbr)
	_panel(GLASS, rbl, rbr, rtr, rtl)
	_panel(GLASS, fbl, rbl, rtl, ftl)
	_panel(GLASS, fbr, ftr, rtr, rbr)
	for edge in [[fbl,ftl],[fbr,ftr],[rbl,rtl],[rbr,rtr]]:
		_bar(PAINT, edge[0], edge[1], 0.043)
	for edge in [[fbl,fbr],[rbl,rbr],[fbl,rbl],[fbr,rbr],[ftl,ftr],[rtl,rtr],[ftl,rtl],[ftr,rtr]]:
		_bar(DARK, edge[0], edge[1], 0.013)
	_solid(PAINT, Vector3(0.045, roof_y - 0.012, roof_front - 0.027), Vector3(0.955, roof_y + 0.044, roof_rear + 0.027), 0.023)
	for side in [0, 1]:
		var x := -0.075 if side == 0 else 1.075
		var xt := 0.073 if side == 0 else 0.927
		var divider := 0.58 if suv else 0.57
		_bar(PAINT if suv else DARK, Vector3(x, _waist, divider), Vector3(xt, roof_y, divider), 0.035 if suv else 0.019)
		if suv:
			_bar(PAINT, Vector3(x, _waist, 0.86), Vector3(xt, roof_y, 0.86), 0.037)
		for door_z in ([0.58, 0.86] if suv else [0.60]):
			_bar(DARK, Vector3(-0.104 if side == 0 else 1.104, 0.10, door_z), Vector3(-0.104 if side == 0 else 1.104, _waist - 0.03, door_z), 0.004, 4)
			_solid(DARK, Vector3(x - 0.038, _waist - 0.12, door_z - 0.11), Vector3(x + 0.038, _waist - 0.09, door_z - 0.045), 0.008)
		# A small stamped fender badge gives the truck a manufactured detail.
		var badge_x := -0.106 if side == 0 else 1.106
		_solid(METAL, Vector3(badge_x - 0.003, _waist - 0.175, cab_front + 0.023), Vector3(badge_x + 0.003, _waist - 0.148, cab_front + 0.077), 0.004)
		var outside := -0.175 if side == 0 else 1.175
		_bar(DARK, Vector3(x, _waist + 0.07, cab_front + 0.045), Vector3(outside, _waist + 0.105, cab_front + 0.065), 0.018)
		_solid(DARK, Vector3(outside - 0.032, _waist + 0.07, cab_front + 0.035), Vector3(outside + 0.032, _waist + 0.165, cab_front + 0.105), 0.016)
		_solid(METAL, Vector3(outside - 0.024, _waist + 0.085, cab_front + 0.105), Vector3(outside + 0.024, _waist + 0.148, cab_front + 0.109), 0.006)
	# A-pillar wiper arms sit on the same windshield plane.
	for x in [0.31, 0.72]:
		_bar(DARK, Vector3(x, _waist + 0.018, cab_front - 0.004), Vector3(x - 0.12, _waist + 0.11, cab_front + 0.012), 0.005, 4)
	_build_interior(suv)
	if suv:
		_solid(PAINT, Vector3(-0.10, 0.10, 1.12), Vector3(1.10, _waist, 1.165), 0.025)
		_solid(DARK, Vector3(0.41, _waist - 0.10, 1.168), Vector3(0.60, _waist - 0.075, 1.173), 0.006)
		# Spare carrier reaches the tailgate, with a visible central mount.
		_solid(DARK, Vector3(0.43, _waist - 0.22, 1.16), Vector3(0.59, _waist + 0.08, 1.215), 0.012)
		_body_spare(0, _v(0.51, _waist + 0.03, 1.21), 0.31, false)
	else:
		_build_pickup_bed()
	for x in [-0.082, 1.012]:
		_solid(DARK, Vector3(x - 0.008, 0.24, 1.164), Vector3(x + 0.078, _waist - 0.035, 1.18), 0.012)
		_solid(RED, Vector3(x, 0.265, 1.181), Vector3(x + 0.060, _waist - 0.06, 1.186), 0.010)
		_solid(LIGHT, Vector3(x + 0.003, 0.32, 1.187), Vector3(x + 0.057, 0.352, 1.19), 0.004)

func _arch_bottom(z: float) -> float:
	var lower := 0.07
	for axle in [0.0, 1.0]:
		var dz: float = (z - axle) * _frame_size.z
		if absf(dz) < _arch_radius:
			lower = maxf(lower, _arch_center_y + sqrt(maxf(0.0, _arch_radius * _arch_radius - dz * dz)))
	return lower

func _body_shoulder(z: float) -> float:
	var hood_back := 0.14 if _vehicle_type == 1 else 0.22
	return _waist - 0.055 * (1.0 - clampf((z + 0.15) / (hood_back + 0.15), 0.0, 1.0))

func _build_side_shell(outer_x: float, inner_x: float, front: float, rear: float) -> void:
	# All aperture segments are shared by the painted panel and its attached
	# black flare. Sampling both arches avoids a solid slab through each tire.
	var stations: Array[float] = [front, rear, 0.32, 0.50, 0.68]
	for axle in [0.0, 1.0]:
		for j in range(17):
			var z: float = axle - cos(float(j) * PI / 16.0) * _arch_radius / _frame_size.z
			if z > front and z < rear:
				stations.append(z)
	stations.sort()
	var outward := -0.052 if outer_x < 0.5 else 0.052
	for j in range(stations.size() - 1):
		var a := stations[j]
		var b := stations[j + 1]
		var ya := _arch_bottom(a)
		var yb := _arch_bottom(b)
		var a0 := Vector3(outer_x, ya, a)
		var b0 := Vector3(outer_x, yb, b)
		var upper_a := _body_shoulder(a)
		var upper_b := _body_shoulder(b)
		var a1 := Vector3(outer_x, upper_a, a)
		var b1 := Vector3(outer_x, upper_b, b)
		if outer_x < 0.5:
			_panel(PAINT, a0, b0, b1, a1)
		else:
			_panel(PAINT, a0, a1, b1, b0)
		_panel(DARK, Vector3(inner_x, ya, a), Vector3(inner_x, yb, b), Vector3(inner_x, upper_b, b), Vector3(inner_x, upper_a, a))
		_panel(PAINT, a1, b1, Vector3(inner_x, upper_b, b), Vector3(inner_x, upper_a, a))
		_panel(DARK, a0, Vector3(inner_x, ya, a), Vector3(inner_x, yb, b), b0)
		if ya > 0.08 or yb > 0.08:
			var ao := Vector3(outer_x + outward, ya + 0.035, a)
			var bo := Vector3(outer_x + outward, yb + 0.035, b)
			_panel(DARK, a0, b0, bo, ao)
			_panel(DARK, ao, bo, Vector3(outer_x, yb + 0.075, b), Vector3(outer_x, ya + 0.075, a))
			var liner_x := 0.22 if outer_x < 0.5 else 0.78
			_panel(DARK, a0, Vector3(liner_x, ya, a), Vector3(liner_x, yb, b), b0)
			_panel(DARK, Vector3(liner_x, -0.12, a), Vector3(liner_x, ya, a), Vector3(liner_x, yb, b), Vector3(liner_x, -0.12, b))
	for z in [front, rear]:
		_panel(PAINT, Vector3(outer_x, _arch_bottom(z), z), Vector3(outer_x, _body_shoulder(z), z), Vector3(inner_x, _body_shoulder(z), z), Vector3(inner_x, _arch_bottom(z), z))

func _build_front_face(suv: bool) -> void:
	var top := _waist - 0.062
	var bottom := maxf(0.28, top - 0.23)
	var middle := (top + bottom) * 0.5
	_solid(DARK, Vector3(0.17, bottom, -0.174), Vector3(0.83, top, -0.160), 0.016)
	if suv:
		for x in [0.23, 0.34, 0.45, 0.56, 0.67, 0.78]:
			_solid(METAL, Vector3(x - 0.017, bottom + 0.025, -0.179), Vector3(x + 0.017, top - 0.025, -0.174), 0.006)
	else:
		for j in range(3):
			var y := bottom + 0.038 + float(j) * (top - bottom - 0.064) / 2.0
			_solid(METAL, Vector3(0.19, y, -0.179), Vector3(0.81, y + 0.012, -0.174), 0.004)
	for x in [0.035, 0.965]:
		_solid(DARK, Vector3(x - 0.122, bottom - 0.003, -0.177), Vector3(x + 0.122, top + 0.002, -0.160), 0.021)
		if suv:
			_front_disc(METAL, _v(x, middle, -0.179), 0.096, 16)
			_front_disc(LIGHT, _v(x, middle, -0.181), 0.077, 16)
		else:
			for dx in [-0.056, 0.056]:
				_solid(METAL, Vector3(x + dx - 0.043, middle - 0.061, -0.180), Vector3(x + dx + 0.043, middle + 0.061, -0.178), 0.01)
				_solid(LIGHT, Vector3(x + dx - 0.034, middle - 0.050, -0.183), Vector3(x + dx + 0.034, middle + 0.050, -0.180), 0.008)
		_solid(AMBER, Vector3(x - 0.083, bottom - 0.033, -0.179), Vector3(x + 0.083, bottom - 0.012, -0.173), 0.007)
	_solid(METAL, Vector3(0.476, middle - 0.032, -0.184), Vector3(0.524, middle + 0.032, -0.179), 0.007)

func _front_disc(material_id: int, center: Vector3, radius: float, segments: int = 12) -> void:
	var d := _dimensions(0)
	for j in range(segments):
		var a := Vector3(cos(float(j) * TAU / segments) * radius / d.x, sin(float(j) * TAU / segments) * radius / d.y, 0)
		var b := Vector3(cos(float(j + 1) * TAU / segments) * radius / d.x, sin(float(j + 1) * TAU / segments) * radius / d.y, 0)
		_tri(material_id, 0, center, center + b, center + a)

func _build_interior(suv: bool) -> void:
	# Interior remains visible through tinted glass and follows cab deformation.
	_box(DARK, 8, Vector3(-0.04, 0.04, 0.035), Vector3(1.04, 0.36, 0.18))
	_box(DARK, 8, Vector3(0.44, -0.01, 0.18), Vector3(0.56, 0.17, 0.62))
	var rows: Array = [0.39, 0.74] if suv else [0.55]
	for row in rows:
		for x in [0.22, 0.78]:
			_beveled_box(DARK, 8, Vector3(x - 0.16, -0.02, row - 0.14), Vector3(x + 0.16, 0.14, row + 0.11), 0.045)
			_beveled_box(DARK, 8, Vector3(x - 0.15, 0.12, row + 0.07), Vector3(x + 0.15, 0.62, row + 0.17), 0.035)
			_beveled_box(DARK, 8, Vector3(x - 0.085, 0.58, row + 0.08), Vector3(x + 0.085, 0.75, row + 0.16), 0.02)
	var steering_center := Vector3(0.24, 0.37, 0.23)
	for j in range(12):
		var a := steering_center + Vector3(cos(float(j) * TAU / 12) * 0.10, sin(float(j) * TAU / 12) * 0.13, 0)
		var b := steering_center + Vector3(cos(float(j + 1) * TAU / 12) * 0.10, sin(float(j + 1) * TAU / 12) * 0.13, 0)
		_tube(DARK, 8, a, b, 0.009, 5)
	_box(METAL, 8, steering_center - Vector3(0.034, 0.034, 0.018), steering_center + Vector3(0.034, 0.034, 0.018))

func _build_pickup_bed() -> void:
	_solid(DARK, Vector3(0.035, 0.135, 0.635), Vector3(0.965, 0.19, 1.125), 0.012)
	_solid(PAINT, Vector3(-0.10, 0.08, 0.62), Vector3(1.10, _waist, 0.65), 0.02)
	_solid(PAINT, Vector3(-0.10, 0.12, 1.125), Vector3(1.10, _waist, 1.166), 0.022)
	# The liner continues up the inner tailgate, including its wheel-well side.
	_panel(DARK, Vector3(-0.095, 0.12, 1.124), Vector3(-0.095, _waist - 0.015, 1.124), Vector3(1.095, _waist - 0.015, 1.124), Vector3(1.095, 0.12, 1.124))
	for side in [-0.11, 1.025]:
		_solid(DARK, Vector3(side, _waist - 0.012, 0.645), Vector3(side + 0.085, _waist + 0.018, 1.16), 0.01)
	# Wheel tubs fully enclose the bed's tire apertures; ribs are broad enough
	# to remain legible without hundreds of tiny decorative triangles.
	for side in [0.015, 0.79]:
		_solid(DARK, Vector3(side, 0.18, 0.79), Vector3(side + 0.195, minf(_waist - 0.07, _arch_center_y + _arch_radius + 0.02), 1.10), 0.035)
	for x in [0.26, 0.38, 0.50, 0.62, 0.74]:
		_solid(TREAD, Vector3(x, 0.19, 0.66), Vector3(x + 0.022, 0.207, 1.11), 0.006)
	_solid(DARK, Vector3(0.43, _waist - 0.13, 1.17), Vector3(0.57, _waist - 0.09, 1.175), 0.006)

func _build_buggy() -> void:
	# A complete tub with one coherent cage. Every brace terminates at another
	# structural tube, including the door diagonals and engine-bay stays.
	_solid(DARK, Vector3(0.09, 0.025, 0.20), Vector3(0.91, 0.12, 0.89), 0.018)
	_solid(PAINT, Vector3(0.12, 0.10, 0.25), Vector3(0.88, 0.43, 0.278), 0.018)
	_solid(DARK, Vector3(0.12, 0.12, 0.76), Vector3(0.88, 0.57, 0.79), 0.018)
	# Sculpted, capped nose with recessed grille and enclosed round lamps.
	_panel(PAINT, Vector3(0.14, 0.18, -0.13), Vector3(0.27, 0.43, 0.25), Vector3(0.73, 0.43, 0.25), Vector3(0.86, 0.18, -0.13))
	_panel(PAINT, Vector3(0.14, 0.08, -0.13), Vector3(0.86, 0.08, -0.13), Vector3(0.86, 0.18, -0.13), Vector3(0.14, 0.18, -0.13))
	_panel(DARK, Vector3(0.14, 0.08, -0.13), Vector3(0.27, 0.12, 0.26), Vector3(0.73, 0.12, 0.26), Vector3(0.86, 0.08, -0.13))
	for side in [0, 1]:
		var x := 0.14 if side == 0 else 0.86
		var upper_x := 0.27 if side == 0 else 0.73
		_panel(PAINT, Vector3(x, 0.08, -0.13), Vector3(x, 0.18, -0.13), Vector3(upper_x, 0.43, 0.25), Vector3(upper_x, 0.12, 0.26))
	_solid(DARK, Vector3(0.35, 0.12, -0.142), Vector3(0.65, 0.21, -0.13), 0.015)
	for x in [0.24, 0.76]:
		_solid(DARK, Vector3(x - 0.055, 0.11, -0.147), Vector3(x + 0.055, 0.29, -0.108), 0.024)
		_front_disc(METAL, _v(x, 0.225, -0.149), 0.077, 16)
		_front_disc(LIGHT, _v(x, 0.225, -0.151), 0.061, 16)
	var roof_y := _rest[12].y - _rest[0].y + 0.08
	for side in [0, 1]:
		var x := 0.09 if side == 0 else 0.91
		var roof_x := 0.18 if side == 0 else 0.82
		var a := Vector3(x, 0.17, 0.23)
		var at := Vector3(roof_x, roof_y, 0.39)
		var c := Vector3(x, 0.17, 0.89)
		var ct := Vector3(roof_x, roof_y, 0.71)
		var am := a.lerp(at, 0.40)
		var cm := c.lerp(ct, 0.53)
		for edge in [[a,at],[at,ct],[ct,c],[a,c],[a,cm],[c,am]]:
			_bar(PAINT, edge[0], edge[1], 0.036)
		_bar(PAINT, ct, Vector3(x, 0.17, 0.74), 0.034)
		_panel(PAINT, a, c, c.lerp(ct, 0.27), a.lerp(at, 0.27))
		for z in [0.23, 0.74, 0.89]:
			_bar(DARK, Vector3(x, 0.04, z), Vector3(x, 0.185, z), 0.036)
		_bar(DARK, Vector3(x, 0.17, 0.89), Vector3(0.24 if side == 0 else 0.76, 0.17, 1.10), 0.032)
	for z in [0.39, 0.71]:
		_bar(PAINT, Vector3(0.18, roof_y, z), Vector3(0.82, roof_y, z), 0.036)
	_bar(PAINT, Vector3(0.18, roof_y, 0.39), Vector3(0.82, roof_y, 0.71), 0.028)
	_bar(DARK, Vector3(0.125, 0.43, 0.292), Vector3(0.875, 0.43, 0.292), 0.030)
	_bar(PAINT, Vector3(0.09, 0.17, 0.89), Vector3(0.91, 0.17, 0.89), 0.034)
	_build_interior(false)
	for x in [0.25, 0.75]:
		_solid(DARK, Vector3(x - 0.12, 0.12, 0.44), Vector3(x + 0.12, 0.25, 0.59), 0.018)
		_bar(AMBER, Vector3(x - 0.065, 0.54, 0.59), Vector3(x + 0.065, 0.32, 0.57), 0.013, 4)
		_bar(AMBER, Vector3(x + 0.065, 0.54, 0.59), Vector3(x - 0.065, 0.32, 0.57), 0.013, 4)
	# Rear engine has a sump and mounts, cylinder covers and a supported exhaust.
	_solid(DARK, Vector3(0.30, 0.12, 0.80), Vector3(0.70, 0.20, 1.12), 0.022)
	_solid(METAL, Vector3(0.33, 0.19, 0.82), Vector3(0.67, 0.43, 1.09), 0.03)
	for x in [0.28, 0.60]:
		_solid(DARK, Vector3(x, 0.29, 0.84), Vector3(x + 0.12, 0.39, 1.065), 0.015)
		for z in [0.86, 0.91, 0.96, 1.01]:
			_solid(METAL, Vector3(x - 0.005, 0.39, z), Vector3(x + 0.125, 0.403, z + 0.012), 0.004)
	_bar(METAL, Vector3(0.31, 0.25, 0.87), Vector3(0.17, 0.21, 1.14), 0.033)
	_bar(DARK, Vector3(0.17, 0.21, 1.12), Vector3(0.22, 0.065, 1.10), 0.018)
	for x in [0.22, 0.78]:
		_solid(DARK, Vector3(x - 0.073, 0.12, 1.135), Vector3(x + 0.073, 0.23, 1.15), 0.015)
		_solid(RED, Vector3(x - 0.057, 0.146, 1.15), Vector3(x + 0.057, 0.211, 1.155), 0.01)

func _build_bumpers() -> void:
	var bumper := str(_parts.get("front_bumper", "stock"))
	var buggy := _vehicle_type == 2
	for x in [0.22, 0.78]:
		_box(DARK, 0, Vector3(x - 0.028, 0.10, -0.22), Vector3(x + 0.028, 0.40, 0.04))
		_box(DARK, 0, Vector3(x - 0.028, 0.10, 1.01), Vector3(x + 0.028, 0.40, 1.19))
	if bumper == "armor":
		_beveled_box(DARK, 0, Vector3(-0.16, 0.16, -0.25), Vector3(1.16, 0.76, -0.13), 0.045)
		_beveled_box(METAL, 0, Vector3(0.28, 0.05, -0.267), Vector3(0.72, 0.25, -0.19), 0.02)
		_box(DARK, 0, Vector3(0.37, 0.73, -0.24), Vector3(0.63, 1.10, -0.15))
		_tube(METAL, 0, Vector3(0.39, 0.91, -0.249), Vector3(0.61, 0.91, -0.249), 0.035)
		for x in [0.20, 0.80]:
			_tube(RED, 0, Vector3(x, 0.23, -0.265), Vector3(x, 0.53, -0.265), 0.023)
	elif bumper == "tube" or bumper == "cage_brace":
		_tube(DARK, 0, Vector3(-0.13, 0.40, -0.22), Vector3(1.13, 0.40, -0.22), 0.049)
		_tube(DARK, 0, Vector3(0.21, 0.40, -0.22), Vector3(0.29, 1.28, -0.24), 0.035)
		_tube(DARK, 0, Vector3(0.79, 0.40, -0.22), Vector3(0.71, 1.28, -0.24), 0.035)
		_tube(DARK, 0, Vector3(0.29, 1.28, -0.24), Vector3(0.71, 1.28, -0.24), 0.035)
		if bumper == "cage_brace":
			_tube(AMBER, 0, Vector3(0.13, 0.35, -0.20), Vector3(0.42, 1.28, 0.26), 0.028)
			_tube(AMBER, 0, Vector3(0.87, 0.35, -0.20), Vector3(0.58, 1.28, 0.26), 0.028)
	else:
		_beveled_box(DARK, 0, Vector3(0.07 if buggy else -0.12, 0.13, -0.205),
			Vector3(0.93 if buggy else 1.12, 0.56, -0.128), 0.035)
		_box(METAL, 0, Vector3(0.36, 0.14, -0.211), Vector3(0.64, 0.43, -0.206))
	_beveled_box(DARK, 0, Vector3(0.08 if buggy else -0.12, 0.12, 1.13),
		Vector3(0.92 if buggy else 1.12, 0.53, 1.205), 0.032)
	for x in [0.21, 0.79]:
		_box(RED, 0, Vector3(x - 0.04, 0.27, 1.207), Vector3(x + 0.04, 0.35, 1.21))

func _build_roof_parts() -> void:
	var roof := str(_parts.get("roof", "none"))
	if roof == "none":
		return
	var buggy := _vehicle_type == 2
	var roof_y := _rest[12].y - _rest[0].y + (0.08 if buggy else 0.035)
	if not buggy:
		roof_y = maxf(roof_y, _waist + 0.43)
	if roof == "cage_spare":
		for x in [0.15, 0.85]:
			_bar(DARK, Vector3(x, 0.56, 0.79), Vector3(0.50, 0.60, 0.915), 0.029)
		_bar(DARK, Vector3(0.50, 0.17, 0.89), Vector3(0.50, 0.60, 0.915), 0.032)
		_body_spare(0, _v(0.50, 0.62, 0.91), 0.36, true)
		return
	var z_front := 0.42 if buggy else (0.30 if _vehicle_type == 1 else 0.33)
	var z_rear := 0.68 if buggy else (1.015 if _vehicle_type == 1 else 0.565)
	var x_left := 0.18 if buggy else 0.13
	var x_right := 1.0 - x_left
	for x in [x_left, x_right]:
		for z in [z_front, z_rear]:
			_bar(DARK, Vector3(x, roof_y + 0.025, z), Vector3(x, roof_y + 0.17, z), 0.018)
		_bar(DARK, Vector3(x, roof_y + 0.085, z_front), Vector3(x, roof_y + 0.085, z_rear), 0.021)
		_bar(DARK, Vector3(x, roof_y + 0.17, z_front), Vector3(x, roof_y + 0.17, z_rear), 0.020)
	for j in range(4):
		var z := lerpf(z_front, z_rear, float(j) / 3.0)
		_bar(DARK, Vector3(x_left, roof_y + 0.085, z), Vector3(x_right, roof_y + 0.085, z), 0.018)
	for z in [z_front, z_rear]:
		_bar(DARK, Vector3(x_left, roof_y + 0.17, z), Vector3(x_right, roof_y + 0.17, z), 0.019)
	if roof == "expedition_rack":
		var case_front := lerpf(z_front, z_rear, 0.12)
		var case_rear := lerpf(z_front, z_rear, 0.88)
		_solid(TREAD, Vector3(0.16, roof_y + 0.10, case_front), Vector3(0.61, roof_y + 0.31, case_rear), 0.032)
		_solid(DARK, Vector3(0.153, roof_y + 0.275, case_front - 0.003), Vector3(0.617, roof_y + 0.292, case_rear + 0.003), 0.010)
		for x in [0.23, 0.53]:
			_solid(METAL, Vector3(x, roof_y + 0.20, case_front - 0.007), Vector3(x + 0.028, roof_y + 0.277, case_front - 0.003), 0.004)
		_solid(RED, Vector3(0.70, roof_y + 0.10, case_front), Vector3(0.85, roof_y + 0.36, case_rear), 0.024)
		_bar(DARK, Vector3(0.74, roof_y + 0.373, (case_front + case_rear) * 0.5), Vector3(0.81, roof_y + 0.373, (case_front + case_rear) * 0.5), 0.014)
	_solid(DARK, Vector3(0.23, roof_y + 0.09, z_front - 0.020), Vector3(0.77, roof_y + 0.16, z_front), 0.009)
	for j in range(6):
		var x := 0.25 + float(j) * 0.084
		_solid(LIGHT, Vector3(x, roof_y + 0.108, z_front - 0.024), Vector3(x + 0.055, roof_y + 0.145, z_front - 0.020), 0.004)

func _body_spare(base: int, center: Vector3, radius: float, angled: bool) -> void:
	var dim := _dimensions(base)
	var depth := 0.22
	for j in range(24):
		var a := float(j) * TAU / 24.0
		var b := float(j + 1) * TAU / 24.0
		var p := Vector3(cos(a), sin(a), 0) * radius / dim
		var q := Vector3(cos(b), sin(b), 0) * radius / dim
		var offset := Vector3(0, depth * 0.30 if angled else 0.0, depth) / dim
		_quad(RUBBER, base, center + p, center + q, center + q + offset, center + p + offset)
		_quad(RUBBER, base, center + p, center + p * 0.50, center + q * 0.50, center + q)
		_tri(DARK, base, center + offset, center + q * 0.44 + offset, center + p * 0.44 + offset)
		_quad(RUBBER, base, center + p + offset, center + q + offset, center + q * 0.53 + offset, center + p * 0.53 + offset)
		_quad(METAL, base, center + p * 0.53 + offset, center + q * 0.53 + offset, center + q * 0.34 + offset, center + p * 0.34 + offset)
		if j % 3 == 0:
			_tri(DARK, base, center + offset, center + p * 0.39 + offset, center + q * 0.39 + offset)

func _wheel_quad(material_id: int, hub: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, tint: Color = Color.WHITE) -> void:
	for p in [a, c, b, a, d, c]:
		_vertex(material_id, hub, p, normal, tint)

func _wheel_profile(material_id: int, hub: int, profile: Array[Vector2], segments: int = RENDER_SEGMENTS) -> void:
	for k in range(profile.size() - 1):
		var p: Vector2 = profile[k]
		var q: Vector2 = profile[k + 1]
		var normal := Vector3(0.0, p.y - q.y, q.x - p.x).normalized()
		for j in range(segments):
			var t := float(j) / segments
			var u := float(j + 1) / segments
			_wheel_quad(material_id, hub, Vector3(t, p.x, p.y), Vector3(u, p.x, p.y),
				Vector3(u, q.x, q.y), Vector3(t, q.x, q.y), normal)

func _tread_block(hub: int, angle: float, width: float, side_a: float, side_b: float, height: float, skew: float) -> void:
	var a := Vector3(angle, side_a, 1.0)
	var b := Vector3(angle + width, side_a, 1.0)
	var c := Vector3(angle + width + skew, side_b, 1.0)
	var d := Vector3(angle + skew, side_b, 1.0)
	var radial := Vector3(0, 0, height)
	_wheel_quad(TREAD, hub, a + radial, b + radial, c + radial, d + radial, Vector3(0, 0, 1))
	_wheel_quad(TREAD, hub, a, b, b + radial, a + radial, Vector3(0, -1, 0))
	_wheel_quad(TREAD, hub, c, d, d + radial, c + radial, Vector3(0, 1, 0))
	_wheel_quad(TREAD, hub, b, c, c + radial, b + radial, Vector3(1, 0, 0))
	_wheel_quad(TREAD, hub, d, a, a + radial, d + radial, Vector3(-1, 0, 0))

func _build_wheels() -> void:
	var tire := str(_parts.get("tires", "all_terrain"))
	var wheel := str(_parts.get("wheels", "steel"))
	var profile: Array[Vector2] = [Vector2(0.08, 0.51), Vector2(-0.01, 0.66),
		Vector2(-0.025, 0.89), Vector2(0.14, 1.0),
		Vector2(0.86, 1.0), Vector2(1.025, 0.89),
		Vector2(1.01, 0.66), Vector2(0.92, 0.51)]
	for hub in _hubs:
		var rigid_binding := 200 + int((hub - 16) / 21)
		_wheel_profile(RUBBER, hub, profile)
		var tread_count := 18 if tire == "mud" else (24 if tire == "rock" else 32)
		var height := 0.080 if tire == "mud" else (0.065 if tire == "rock" else 0.037)
		for j in range(tread_count):
			var t := float(j) / tread_count
			var width := 0.52 / tread_count
			_tread_block(hub, t, width, 0.07, 0.47, height, 0.22 / tread_count)
			_tread_block(hub, t + 0.20 / tread_count, width, 0.53, 0.93, height, -0.22 / tread_count)
		for side in [-0.018, 1.018]:
			var sign_x := -1.0 if side < 0.5 else 1.0
			var rim_material := AMBER if wheel == "beadlock" else METAL
			var rim_profile: Array[Vector2] = [Vector2(side, 0.515), Vector2(side + sign_x * 0.024, 0.545),
				Vector2(side + sign_x * 0.049, 0.53), Vector2(side + sign_x * 0.049, 0.44), Vector2(side, 0.42)]
			_wheel_profile(rim_material, rigid_binding, rim_profile, 20)
			var spokes := 6 if wheel == "alloy" else (8 if wheel == "beadlock" else 10)
			var spoke_width := 0.028 if wheel == "alloy" else 0.035
			for j in range(spokes):
				var t := float(j) / spokes
				_wheel_quad(DARK if wheel == "beadlock" else METAL, rigid_binding,
					Vector3(t - spoke_width * 0.6, side, 0.13), Vector3(t + spoke_width * 0.6, side, 0.13),
					Vector3(t + spoke_width, side, 0.46), Vector3(t - spoke_width, side, 0.46), Vector3(0, sign_x, 0))
			var cap_profile: Array[Vector2] = [Vector2(side, 0.145), Vector2(side + sign_x * 0.08, 0.13),
				Vector2(side + sign_x * 0.09, 0.015)]
			_wheel_profile(METAL, rigid_binding, cap_profile, 12)
			if wheel == "beadlock":
				for j in range(16):
					var t := float(j) / 16.0
					_wheel_quad(METAL, rigid_binding, Vector3(t - 0.007, side + sign_x * 0.052, 0.47),
						Vector3(t + 0.007, side + sign_x * 0.052, 0.47), Vector3(t + 0.007, side + sign_x * 0.052, 0.515),
						Vector3(t - 0.007, side + sign_x * 0.052, 0.515), Vector3(0, sign_x, 0))
			# Molded sidewall ridges are subtle real geometry around the carcass.
			for j in range(12):
				var t := float(j) / 12.0
				_wheel_quad(TREAD, hub, Vector3(t, side, 0.78), Vector3(t + 0.012, side, 0.79),
					Vector3(t + 0.012, side, 0.91), Vector3(t, side, 0.90), Vector3(0, sign_x, 0), Color(0.58, 0.61, 0.60))

func _link_cylinder(material_id: int, binding: int, start: float, end: float, radius: float, sides: int = 8) -> void:
	for j in range(sides):
		var a := float(j) * TAU / sides
		var b := float(j + 1) * TAU / sides
		var normal := Vector3(0, cos((a + b) * 0.5), sin((a + b) * 0.5))
		_wheel_quad(material_id, binding, Vector3(start, cos(a) * radius, sin(a) * radius),
			Vector3(start, cos(b) * radius, sin(b) * radius), Vector3(end, cos(b) * radius, sin(b) * radius),
			Vector3(end, cos(a) * radius, sin(a) * radius), normal)

func _build_suspension() -> void:
	for axle in range(2):
		_link_cylinder(DARK, 114 + axle, 0.02, 0.97, 0.042)
		_link_cylinder(METAL, 114 + axle, 0.73, 0.92, 0.052)
		_link_cylinder(DARK, 108 + axle, 0.08, 0.92, 0.065)
		_link_cylinder(METAL, 108 + axle, 0.44, 0.56, 0.13)
		_link_cylinder(DARK, 108 + axle, 0.40, 0.44, 0.10)
		_link_cylinder(DARK, 108 + axle, 0.56, 0.60, 0.10)
	for w in range(4):
		# Four-link rods and coilover eyes terminate at the same chassis and
		# carrier hardpoints used by the native constraints.
		_link_cylinder(AMBER, 100 + w, 0.07, 0.57, 0.034)
		_link_cylinder(METAL, 100 + w, 0.46, 0.96, 0.017)
		_link_cylinder(METAL, 104 + w, 0.04, 0.96, 0.027)
		_link_cylinder(DARK, 110 + w, 0.04, 0.96, 0.024)
		for binding in [100 + w, 104 + w, 110 + w]:
			_link_cylinder(DARK, binding, 0.0, 0.055, 0.045, 6)
			_link_cylinder(DARK, binding, 0.945, 1.0, 0.045, 6)
			_link_cylinder(METAL, binding, 0.007, 0.023, 0.050, 6)
			_link_cylinder(METAL, binding, 0.977, 0.993, 0.050, 6)
		for j in range(24):
			var t := float(j) / 24.0
			var u := float(j + 1) / 24.0
			var a := Vector3(0.18 + t * 0.60, cos(t * TAU * 5.0) * 0.052, sin(t * TAU * 5.0) * 0.052)
			var b := Vector3(0.18 + u * 0.60, cos(u * TAU * 5.0) * 0.052, sin(u * TAU * 5.0) * 0.052)
			for edge in range(3):
				var angle := float(edge) * TAU / 3.0
				var next := float(edge + 1) * TAU / 3.0
				var p := Vector3(cos(angle) * 0.007, sin(angle) * cos(t * TAU * 5.0) * 0.009, sin(angle) * sin(t * TAU * 5.0) * 0.009)
				var q := Vector3(cos(next) * 0.007, sin(next) * cos(t * TAU * 5.0) * 0.009, sin(next) * sin(t * TAU * 5.0) * 0.009)
				_wheel_quad(RED if str(_parts.get("suspension", "stock")) == "long_travel" else AMBER,
					100 + w, a + p, a + q, b + q, b + p, Vector3(0, cos(t * TAU * 5.0), sin(t * TAU * 5.0)))

func _refresh_visuals() -> void:
	if core == null or _body == null:
		return
	_nodes = core.get_nodes()
	if _nodes.size() < 100:
		return
	var center := Vector3.ZERO
	for j in range(8):
		center += _nodes[j]
	center /= 8.0
	_body.global_position = center
	_update_body_coefficients()
	var wheels: Dictionary = core.get_wheel_visuals()
	_wheel_axes = wheels.axes
	_wheel_normals = wheels.normals
	_wheel_points = wheels.points
	_wheel_phases = wheels.phases
	_wheel_compression = wheels.compression
	_wheel_up = wheels.up
	_link_starts = wheels.link_starts
	_link_ends = wheels.link_ends
	_axle_ups = wheels.axle_ups
	_ring_centers.resize(8)
	for w in range(4):
		for side in range(2):
			var ring_center := Vector3.ZERO
			for j in range(RING_SEGMENTS):
				ring_center += _nodes[_hubs[w] + 1 + side * RING_SEGMENTS + j]
			_ring_centers[w * 2 + side] = ring_center / float(RING_SEGMENTS)
	for material in _materials:
		material.set_shader_parameter("node_positions", _nodes)
		material.set_shader_parameter("body_coefficients", _body_coefficients)
		material.set_shader_parameter("cab_offset", _cab_offset)
		material.set_shader_parameter("cab_scale", _cab_scale)
		material.set_shader_parameter("body_height", _frame_size.y)
		material.set_shader_parameter("blend_start", 0.20)
		material.set_shader_parameter("blend_end", maxf(_rest[12].y - _rest[0].y - 0.08, 0.65))
		material.set_shader_parameter("ring_centers", _ring_centers)
		material.set_shader_parameter("rig_center", center)
		material.set_shader_parameter("tire_padding", _tire_padding)
		material.set_shader_parameter("wheel_axes", _wheel_axes)
		material.set_shader_parameter("wheel_normals", _wheel_normals)
		material.set_shader_parameter("wheel_points", _wheel_points)
		material.set_shader_parameter("wheel_phases", _wheel_phases)
		material.set_shader_parameter("wheel_compression", _wheel_compression)
		material.set_shader_parameter("wheel_up", _wheel_up)
		material.set_shader_parameter("link_starts", _link_starts)
		material.set_shader_parameter("link_ends", _link_ends)
		material.set_shader_parameter("axle_ups", _axle_ups)
		material.set_shader_parameter("tire_radius", _tire_padding / 0.12)
		material.set_shader_parameter("tire_width", _tire_padding / 0.12 * 0.58 * float(_settings.get("tire_width_scale", 1.0)))
	if body_color != _last_color:
		_materials[PAINT].set_shader_parameter("surface_color", body_color)
		_last_color = body_color
	_body.visible = not wireframe
	_graph.visible = wireframe
	if wireframe and _graph_tick > 0.045:
		_graph_tick = 0.0
		_draw_graph()

func _draw_graph() -> void:
	_graph_mesh.clear_surfaces()
	var beams: PackedInt32Array = core.get_beams()
	var kinds: PackedInt32Array = core.get_beam_kinds()
	var broken: PackedByteArray = core.get_broken()
	var strains: PackedFloat32Array = core.get_strains()
	var colors := [Color("f0c96f"), Color("65d9e8"), Color("8de89a"), Color("9bb6c5")]
	_graph_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _graph_material)
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

func _update_body_coefficients() -> void:
	_body_coefficients.resize(16)
	for base in [0, 8]:
		var a := _nodes[base]
		var x := _nodes[base + 1] - a
		var y := _nodes[base + 4] - a
		var z := _nodes[base + 2] - a
		var xy := _nodes[base + 5] - a - x - y
		var xz := _nodes[base + 3] - a - x - z
		var yz := _nodes[base + 6] - a - y - z
		_body_coefficients[base] = a
		_body_coefficients[base + 1] = x
		_body_coefficients[base + 2] = y
		_body_coefficients[base + 3] = z
		_body_coefficients[base + 4] = xy
		_body_coefficients[base + 5] = xz
		_body_coefficients[base + 6] = yz
		_body_coefficients[base + 7] = _nodes[base + 7] - a - x - y - z - xy - xz - yz

func _debug_cell(base: int, p: Vector3) -> Vector3:
	return _body_coefficients[base] + _body_coefficients[base + 1] * p.x + _body_coefficients[base + 2] * p.y + _body_coefficients[base + 3] * p.z + _body_coefficients[base + 4] * p.x * p.y + _body_coefficients[base + 5] * p.x * p.z + _body_coefficients[base + 6] * p.y * p.z + _body_coefficients[base + 7] * p.x * p.y * p.z

func debug_rest_point(base: int, p: Vector3) -> Vector3:
	return _rest[base] + p * _dimensions(base)

func debug_deform_point(rest_point: Vector3) -> Vector3:
	var p := (rest_point - _rest[0]) / _frame_size
	var end := maxf(_rest[12].y - _rest[0].y - 0.08, 0.65)
	var t: float = clampf((p.y * _frame_size.y - 0.20) / (end - 0.20), 0.0, 1.0)
	return _debug_cell(0, p).lerp(_debug_cell(8, _cab_offset + p * _cab_scale), t * t * (3.0 - 2.0 * t))

func _debug_ring(first: int, phase: float) -> Vector3:
	var f := fposmod(phase, 1.0) * 10.0
	var k := int(floor(f))
	var t: float = f - floorf(f)
	var a := _nodes[first + (k + 9) % 10]
	var b := _nodes[first + k]
	var c := _nodes[first + (k + 1) % 10]
	var d := _nodes[first + (k + 2) % 10]
	return 0.5 * ((2.0 * b) + (c - a) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)

func _debug_vertex(binding: int, p: Vector3) -> Vector3:
	if binding < 16:
		return debug_deform_point(_rest[0] + p * _frame_size)
	if binding >= 200:
		var w := binding - 200
		var axle := _wheel_axes[w]
		var up := _wheel_up
		up = (up - axle * up.dot(axle)).normalized()
		var angle := p.x * TAU + _wheel_phases[w]
		var radial := up * cos(angle) + axle.cross(up).normalized() * sin(angle)
		var radius := _tire_padding / 0.12
		return _nodes[_hubs[w]] + axle * ((p.y - 0.5) * radius * 0.58 * float(_settings.get("tire_width_scale", 1.0))) + radial * (radius * 0.88 * p.z)
	if binding >= 100:
		var w := (binding - 100) % 4
		var upper := _link_starts[8 + w]
		var lower := _link_ends[8 + w]
		if binding >= 114:
			upper = _link_starts[binding - 102]
			lower = _link_ends[binding - 102]
		elif binding >= 110:
			upper = _link_starts[binding - 106]
			lower = _link_ends[binding - 106]
		elif binding >= 104 and binding < 108:
			upper = _link_starts[binding - 104]
			lower = _link_ends[binding - 104]
		elif binding >= 108:
			var axle := binding - 108
			upper = _nodes[_hubs[axle * 2]]
			lower = _nodes[_hubs[axle * 2 + 1]]
		var axis := (lower - upper).normalized()
		var reference := Vector3.UP if absf(axis.y) < 0.90 else Vector3.BACK
		if binding in [108, 109]:
			reference = _axle_ups[binding - 108]
		var side := axis.cross(reference).normalized()
		var other := axis.cross(side).normalized()
		return upper.lerp(lower, p.x) + side * p.y + other * p.z
	var w := int((binding - 16) / 21)
	var center := _ring_centers[w * 2].lerp(_ring_centers[w * 2 + 1], p.y)
	var ring := _debug_ring(binding + 1, p.x).lerp(_debug_ring(binding + 11, p.x), p.y)
	var radial := ring - center
	var pad := _tire_padding * clampf((p.z - 0.50) * 2.0, 0.0, 1.0)
	var point := center + radial * p.z + (radial + Vector3.ONE * 0.000001).normalized() * pad
	if _wheel_compression[w] > 0.0001 and p.z > 0.55:
		var depth := (point - _wheel_points[w]).dot(_wheel_normals[w])
		point += _wheel_normals[w] * maxf(0.0, 0.002 - depth)
		var patch := clampf(1.0 - maxf(depth, 0.0) / maxf(_tire_padding * 3.0, 0.01), 0.0, 1.0)
		var sidewall := clampf(absf(p.y - 0.5) * 2.0, 0.0, 1.0) * clampf((p.z - 0.55) * 3.0, 0.0, 1.0)
		point += _wheel_axes[w] * signf(p.y - 0.5) * _wheel_compression[w] * 0.30 * patch * sidewall
	return point

func _inspect_mesh() -> Dictionary:
	var invalid := 0
	var degenerate := 0
	for surface in range(_body_mesh.get_surface_count()):
		var arrays := _body_mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for j in range(vertices.size()):
			if not vertices[j].is_finite() or not normals[j].is_finite():
				invalid += 1
		for j in range(0, vertices.size(), 3):
			if (vertices[j + 1] - vertices[j]).cross(vertices[j + 2] - vertices[j]).length_squared() < 0.000000000000001:
				degenerate += 1
	return {"triangles": _triangle_count, "nonfinite_vertices": invalid, "degenerate_triangles": degenerate,
		"min_wheel_clearance": _arch_radius - _render_tire_radius}

# Explicit diagnostic: does not run during normal frames or rebuild geometry.
func get_visual_validation() -> Dictionary:
	var report := _validation.duplicate()
	var nonfinite := 0
	for surface in range(_body_mesh.get_surface_count()):
		var arrays := _body_mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bindings: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for j in range(vertices.size()):
			if not _debug_vertex(roundi(bindings[j].x), vertices[j]).is_finite():
				nonfinite += 1
	# Re-express shared structural seam samples in each original cell's rest
	# coordinates. Both must produce the same world result despite cab damage.
	var seam_gap := 0.0
	for q in [Vector3(0.0, 0.4, 0.0), Vector3(1.0, 0.4, 0.0), Vector3(0.0, 0.4, 1.0), Vector3(1.0, 0.4, 1.0)]:
		var from_cab := debug_rest_point(8, q)
		var frame_q := (from_cab - _rest[0]) / _frame_size
		seam_gap = maxf(seam_gap, debug_deform_point(from_cab).distance_to(debug_deform_point(debug_rest_point(0, frame_q))))
	report["live_nonfinite_vertices"] = nonfinite
	report["max_seam_gap"] = seam_gap
	return report
