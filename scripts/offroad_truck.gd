class_name OffroadTruck
extends Node3D

## Persistent meshes are skinned on the GPU to the native solver's mass nodes.
## Only 100 node positions and eight tire-ring centers cross the CPU/GPU boundary
## per frame. Geometry is rebuilt only when a vehicle or its parts change.
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
const RENDER_SEGMENTS := 40
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
		core.set_terrain(2)
	throttle = 0.0
	steering = 0.0
	_refresh_visuals()

func set_drivetrain(low_range: bool, locked_diffs: bool) -> void:
	if core != null:
		core.set_drivetrain(low_range, locked_diffs)

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
	var colors: Array[Color] = [body_color, Color("202a2b"), Color("325663"),
		Color("9da9a9"), Color("fff0c8"), Color("b52725"), Color("101619"),
		Color("242b2a"), Color("d8a548")]
	var roughness: Array[float] = [0.25, 0.63, 0.12, 0.27, 0.2, 0.26, 0.92, 0.93, 0.32]
	var metallic: Array[float] = [0.50, 0.12, 0.18, 0.82, 0.12, 0.15, 0.0, 0.0, 0.64]
	_materials.clear()
	for i in range(9):
		var material := ShaderMaterial.new()
		material.shader = GLASS_SHADER if i == GLASS else BODY_SHADER
		material.set_shader_parameter("surface_color", Color(0.12, 0.23, 0.27, 0.63) if i == GLASS else colors[i])
		if i != GLASS:
			material.set_shader_parameter("material_roughness", roughness[i])
			material.set_shader_parameter("material_metallic", metallic[i])
			material.set_shader_parameter("paint_coat", 0.82 if i == PAINT else 0.0)
			material.set_shader_parameter("lamp_energy", 0.7 if i == LIGHT else 0.0)
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
		_tube(DARK, 0, Vector3(x, 0.04, 0.21), Vector3(x, 0.04, 0.78), 0.045)

func _build_closed_body(suv: bool) -> void:
	var hood_back := 0.13 if suv else 0.23
	# Separate sculpted hood, nose and lower valance.
	_beveled_box(PAINT, 0, Vector3(-0.085, 0.63, -0.13), Vector3(1.085, 1.58, hood_back), 0.065)
	_quad(PAINT, 0, Vector3(-0.035, 1.59, -0.09), Vector3(0.03, 1.85, hood_back - 0.01),
		Vector3(0.97, 1.85, hood_back - 0.01), Vector3(1.035, 1.59, -0.09))
	for x in [0.20, 0.78]:
		_tube(DARK, 0, Vector3(x, 1.686, -0.04), Vector3(x, 1.82, hood_back - 0.03), 0.006, 5)
	_build_front_face(suv)
	# Doors are separated from the greenhouse so the glass can be transparent.
	_beveled_box(PAINT, 8, Vector3(-0.12, -0.13, -0.015), Vector3(1.12, 0.39, 1.015), 0.035)
	_box(DARK, 8, Vector3(-0.125, 0.37, -0.024), Vector3(1.125, 0.405, 1.026))
	var front_top := 0.15 if suv else 0.19
	var rear_top := 0.94
	# Roof is narrower than the doors; rake and chamfers reflect the sky smoothly.
	_beveled_box(PAINT, 8, Vector3(0.005, 0.97, front_top - 0.04), Vector3(0.995, 1.055, rear_top + 0.05), 0.035)
	var fbl := Vector3(-0.09, 0.395, -0.025)
	var fbr := Vector3(1.09, 0.395, -0.025)
	var ftl := Vector3(0.045, 0.96, front_top)
	var ftr := Vector3(0.955, 0.96, front_top)
	_quad(GLASS, 8, fbl, ftl, ftr, fbr)
	for p in [[fbl, ftl], [fbr, ftr]]:
		_tube(PAINT, 8, p[0], p[1], 0.035)
	_tube(DARK, 8, fbl, fbr, 0.018)
	_tube(DARK, 8, ftl, ftr, 0.013)
	# Two wipers, never painted rectangles baked into the windshield.
	for x in [0.31, 0.72]:
		_tube(DARK, 8, Vector3(x, 0.414, -0.024), Vector3(x - 0.13, 0.54, front_top * 0.2 - 0.015), 0.006, 5)
	for side in [0, 1]:
		var low_x := -0.115 if side == 0 else 1.115
		var high_x := 0.025 if side == 0 else 0.975
		# Flush side glazing, door shuts and front/rear pillars.
		var low_front := Vector3(low_x, 0.415, 0.025)
		var high_front := Vector3(high_x, 0.957, front_top + 0.012)
		var low_rear := Vector3(low_x, 0.415, 0.985)
		var high_rear := Vector3(high_x, 0.957, rear_top)
		_quad(GLASS, 8, low_front, low_rear, high_rear, high_front)
		_tube(PAINT, 8, low_rear, high_rear, 0.045 if suv else 0.04)
		var divider := 0.49 if suv else 0.74
		_tube(DARK, 8, Vector3(low_x, 0.41, divider), Vector3(high_x, 0.98, divider), 0.023)
		for door_z in ([0.49, 0.98] if suv else [0.96]):
			_tube(DARK, 8, Vector3(low_x, -0.055, door_z), Vector3(low_x, 0.40, door_z), 0.0045, 5)
			_box(DARK, 8, Vector3(low_x - 0.013, 0.26, door_z - 0.15), Vector3(low_x + 0.013, 0.304, door_z - 0.03))
		var outside := low_x - 0.10 if side == 0 else low_x + 0.10
		_tube(DARK, 8, Vector3(low_x, 0.46, 0.03), Vector3(outside, 0.49, 0.08), 0.018)
		_beveled_box(DARK, 8, Vector3(outside - 0.045, 0.44, 0.018), Vector3(outside + 0.045, 0.57, 0.15), 0.016)
		_box(METAL, 8, Vector3(outside - 0.033, 0.456, 0.151), Vector3(outside + 0.033, 0.553, 0.157))
	# Rear glass and pillars taper to the roof.
	_quad(GLASS, 8, Vector3(-0.087, 0.42, 1.025), Vector3(1.087, 0.42, 1.025),
		Vector3(0.955, 0.95, rear_top + 0.017), Vector3(0.045, 0.95, rear_top + 0.017))
	_build_interior(suv)
	if suv:
		_build_suv_rear()
	else:
		_build_pickup_bed()
	_build_fenders()

func _build_front_face(suv: bool) -> void:
	_beveled_box(DARK, 0, Vector3(0.18, 0.84, -0.145), Vector3(0.82, 1.44, -0.131), 0.025)
	if suv:
		for x in [0.22, 0.33, 0.44, 0.55, 0.66, 0.77]:
			_beveled_box(METAL, 0, Vector3(x - 0.022, 0.89, -0.152), Vector3(x + 0.022, 1.38, -0.145), 0.007)
	else:
		for y in [0.93, 1.08, 1.24, 1.38]:
			_box(METAL, 0, Vector3(0.20, y, -0.151), Vector3(0.80, y + 0.026, -0.145))
	# Individual projector lenses inside recessed headlamp housings.
	for x in [0.03, 0.97]:
		_beveled_box(DARK, 0, Vector3(x - 0.13, 0.93, -0.15), Vector3(x + 0.13, 1.50, -0.137), 0.026)
		for dx in [-0.053, 0.053]:
			_front_disc(LIGHT, Vector3(x + dx, 1.23, -0.156), 0.060 if suv else 0.052, 12)
		_box(LIGHT, 0, Vector3(x - 0.11, 1.47, -0.157), Vector3(x + 0.11, 1.51, -0.151))
		_box(AMBER, 0, Vector3(x - 0.11, 0.90, -0.154), Vector3(x + 0.11, 0.98, -0.147))
	_beveled_box(METAL, 0, Vector3(0.47, 1.05, -0.157), Vector3(0.53, 1.31, -0.151), 0.008)

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
	_box(DARK, 0, Vector3(-0.07, 0.50, 0.63), Vector3(1.07, 0.72, 1.14))
	for side in [-0.075, 0.975]:
		_beveled_box(PAINT, 0, Vector3(side, 0.58, 0.63), Vector3(side + 0.10, 1.81, 1.15), 0.035)
		_beveled_box(DARK, 0, Vector3(side - 0.012, 1.77, 0.63), Vector3(side + 0.112, 1.85, 1.153), 0.016)
	_beveled_box(PAINT, 0, Vector3(0.02, 0.65, 1.095), Vector3(0.98, 1.80, 1.15), 0.025)
	_box(DARK, 0, Vector3(0.44, 1.48, 1.153), Vector3(0.56, 1.60, 1.16))
	for x in [0.10, 0.26, 0.42, 0.58, 0.74, 0.90]:
		_box(TREAD, 0, Vector3(x, 0.72, 0.65), Vector3(x + 0.025, 0.755, 1.07))
	for x in [-0.04, 0.97]:
		_beveled_box(RED, 0, Vector3(x, 0.9, 1.154), Vector3(x + 0.07, 1.66, 1.166), 0.01)
		_box(LIGHT, 0, Vector3(x, 1.1, 1.168), Vector3(x + 0.07, 1.21, 1.171))

func _build_suv_rear() -> void:
	_beveled_box(PAINT, 0, Vector3(-0.085, 0.55, 0.80), Vector3(1.085, 1.36, 1.14), 0.045)
	for x in [-0.075, 1.01]:
		_beveled_box(RED, 0, Vector3(x, 0.87, 1.144), Vector3(x + 0.065, 1.40, 1.157), 0.012)
	_box(DARK, 8, Vector3(0.40, 0.27, 1.035), Vector3(0.60, 0.31, 1.047))
	# Tailgate spare is body-mounted, separate from the four simulated tires.
	_body_spare(8, Vector3(0.52, 0.30, 1.13), 0.32, false)

func _build_fenders() -> void:
	var dim := _dimensions(0)
	for side in [0, 1]:
		var x := -0.11 if side == 0 else 1.11
		var outer_x := x + (-0.115 if side == 0 else 0.115)
		for axle in [0.0, 1.0]:
			var hub_id: int = _hubs[(0 if axle < 0.5 else 2) + side]
			var hub_y := (_rest[hub_id].y - _rest[0].y) / dim.y
			var r := float(_settings.get("tire_radius", 0.46)) + 0.11
			# Actual circular flare with an open wheel aperture, not a square block.
			for j in range(12):
				var a := -0.08 + float(j) / 12.0 * (PI + 0.16)
				var b := -0.08 + float(j + 1) / 12.0 * (PI + 0.16)
				var p := Vector3(x, hub_y + sin(a) * r / dim.y, axle + cos(a) * r / dim.z)
				var q := Vector3(x, hub_y + sin(b) * r / dim.y, axle + cos(b) * r / dim.z)
				var po := Vector3(outer_x, p.y + 0.10, p.z)
				var qo := Vector3(outer_x, q.y + 0.10, q.z)
				_quad(DARK, 0, p, q, qo, po)
				_quad(DARK, 0, po, qo, qo + Vector3(0, 0.13, 0), po + Vector3(0, 0.13, 0))

func _build_buggy() -> void:
	# Low, open two-seat tube chassis with a tapered nose and exposed rear engine.
	_quad(PAINT, 0, Vector3(0.16, 0.76, -0.11), Vector3(0.28, 1.64, 0.28),
		Vector3(0.72, 1.64, 0.28), Vector3(0.84, 0.76, -0.11))
	for side in [0.15, 0.85]:
		var inner := 0.28 if side < 0.5 else 0.72
		_quad(PAINT, 0, Vector3(side, 0.2, -0.09), Vector3(side, 0.76, -0.11),
			Vector3(inner, 1.64, 0.28), Vector3(inner, 0.35, 0.38))
		_tube(DARK, 0, Vector3(side, 0.15, -0.08), Vector3(side, 0.23, 1.06), 0.038)
	for x in [0.24, 0.76]:
		_front_disc(LIGHT, Vector3(x, 0.83, -0.126), 0.085, 12)
	_box(DARK, 0, Vector3(0.38, 0.45, -0.135), Vector3(0.62, 0.96, -0.121))
	# A-pillars lean rearward, rear cage flares to protect the engine bay.
	for x in [0.02, 0.98]:
		var roof_x := 0.10 if x < 0.5 else 0.90
		_tube(PAINT, 8, Vector3(x, 0.03, -0.12), Vector3(roof_x, 1.08, 0.18), 0.042)
		_tube(PAINT, 8, Vector3(roof_x, 1.08, 0.18), Vector3(roof_x, 1.08, 0.93), 0.042)
		_tube(PAINT, 8, Vector3(roof_x, 1.08, 0.93), Vector3(x, 0.02, 1.24), 0.042)
		_tube(PAINT, 8, Vector3(x, 0.05, 0.0), Vector3(x, 0.05, 1.20), 0.042)
		_tube(PAINT, 8, Vector3(x, 0.08, 0.0), Vector3(x, 0.63, 0.83), 0.032)
		_tube(PAINT, 8, Vector3(x, 0.08, 1.14), Vector3(x, 0.60, 0.28), 0.032)
		_quad(PAINT, 8, Vector3(x, 0.06, 0.18), Vector3(x, 0.40, 0.43),
			Vector3(x, 0.47, 0.86), Vector3(x, 0.08, 1.10))
	for z in [0.18, 0.93]:
		_tube(PAINT, 8, Vector3(0.10, 1.08, z), Vector3(0.90, 1.08, z), 0.038)
	_tube(PAINT, 8, Vector3(0.10, 1.08, 0.18), Vector3(0.90, 1.08, 0.93), 0.031)
	_tube(PAINT, 8, Vector3(0.90, 1.08, 0.18), Vector3(0.10, 1.08, 0.93), 0.031)
	_tube(DARK, 8, Vector3(0.02, 0.52, 0.03), Vector3(0.98, 0.52, 0.03), 0.033)
	_build_interior(false)
	for x in [0.22, 0.78]:
		_tube(AMBER, 8, Vector3(x - 0.08, 0.56, 0.61), Vector3(x + 0.08, 0.17, 0.62), 0.017, 5)
		_tube(AMBER, 8, Vector3(x + 0.08, 0.56, 0.61), Vector3(x - 0.08, 0.17, 0.62), 0.017, 5)
	_beveled_box(METAL, 0, Vector3(0.32, 0.08, 0.79), Vector3(0.68, 1.42, 1.12), 0.035)
	for z in [0.81, 0.86, 0.91, 0.96, 1.01, 1.06]:
		_box(DARK, 0, Vector3(0.29, 0.4, z), Vector3(0.71, 1.12, z + 0.018))
	_tube(METAL, 0, Vector3(0.31, 0.36, 0.84), Vector3(0.13, 0.58, 1.20), 0.038)
	for x in [0.22, 0.78]:
		_box(RED, 0, Vector3(x - 0.07, 0.62, 1.145), Vector3(x + 0.07, 0.88, 1.16))

func _build_bumpers() -> void:
	var bumper := str(_parts.get("front_bumper", "stock"))
	var buggy := _vehicle_type == 2
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
	if roof == "cage_spare":
		_body_spare(8, Vector3(0.50, 0.73, 1.15), 0.38, true)
		return
	var z_front := 0.24
	var z_rear := 0.86
	for x in [0.05, 0.95]:
		_tube(DARK, 8, Vector3(x, 1.08, z_front), Vector3(x, 1.08, z_rear), 0.023)
		_tube(DARK, 8, Vector3(x, 1.19, z_front), Vector3(x, 1.19, z_rear), 0.023)
		for z in [z_front, z_rear]:
			_tube(DARK, 8, Vector3(x, 1.015, z), Vector3(x, 1.20, z), 0.02)
	for z in [z_front, z_front + 0.20, z_front + 0.40, z_rear]:
		_tube(DARK, 8, Vector3(0.05, 1.08, z), Vector3(0.95, 1.08, z), 0.02)
	if roof == "expedition_rack":
		_beveled_box(TREAD, 8, Vector3(0.08, 1.10, 0.32), Vector3(0.58, 1.38, 0.70), 0.045)
		_box(DARK, 8, Vector3(0.08, 1.33, 0.32), Vector3(0.58, 1.365, 0.70))
		for x in [0.14, 0.49]:
			_box(METAL, 8, Vector3(x, 1.23, 0.314), Vector3(x + 0.04, 1.33, 0.326))
		_beveled_box(RED, 8, Vector3(0.69, 1.10, 0.36), Vector3(0.88, 1.38, 0.68), 0.03)
		_tube(DARK, 8, Vector3(0.75, 1.39, 0.46), Vector3(0.83, 1.39, 0.56), 0.012)
	# Small LED bar shared by slim and expedition equipment.
	_box(DARK, 8, Vector3(0.19, 1.11, z_front - 0.034), Vector3(0.81, 1.20, z_front))
	for i in range(8):
		var x := 0.215 + float(i) * 0.073
		_box(LIGHT, 8, Vector3(x, 1.13, z_front - 0.041), Vector3(x + 0.045, 1.178, z_front - 0.035))

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
		Vector2(-0.025, 0.85), Vector2(0.0, 0.96), Vector2(0.14, 1.0),
		Vector2(0.86, 1.0), Vector2(1.0, 0.96), Vector2(1.025, 0.85),
		Vector2(1.01, 0.66), Vector2(0.92, 0.51)]
	for hub in _hubs:
		_wheel_profile(RUBBER, hub, profile)
		var tread_count := 28 if tire == "mud" else (32 if tire == "rock" else 40)
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
			_wheel_profile(rim_material, hub, rim_profile)
			var spokes := 6 if wheel == "alloy" else (8 if wheel == "beadlock" else 10)
			var spoke_width := 0.033 if wheel == "alloy" else 0.057
			for j in range(spokes):
				var t := float(j) / spokes
				_wheel_quad(METAL if wheel == "alloy" else DARK, hub,
					Vector3(t - spoke_width * 0.6, side, 0.13), Vector3(t + spoke_width * 0.6, side, 0.13),
					Vector3(t + spoke_width, side, 0.46), Vector3(t - spoke_width, side, 0.46), Vector3(0, sign_x, 0))
			var cap_profile: Array[Vector2] = [Vector2(side, 0.145), Vector2(side + sign_x * 0.08, 0.13),
				Vector2(side + sign_x * 0.09, 0.015)]
			_wheel_profile(METAL, hub, cap_profile, 16)
			if wheel == "beadlock":
				for j in range(16):
					var t := float(j) / 16.0
					_wheel_quad(METAL, hub, Vector3(t - 0.007, side + sign_x * 0.052, 0.47),
						Vector3(t + 0.007, side + sign_x * 0.052, 0.47), Vector3(t + 0.007, side + sign_x * 0.052, 0.515),
						Vector3(t - 0.007, side + sign_x * 0.052, 0.515), Vector3(0, sign_x, 0))
			# Molded sidewall ridges are subtle real geometry around the carcass.
			for j in range(20):
				var t := float(j) / 20.0
				_wheel_quad(TREAD, hub, Vector3(t, side, 0.78), Vector3(t + 0.012, side, 0.79),
					Vector3(t + 0.012, side, 0.91), Vector3(t, side, 0.90), Vector3(0, sign_x, 0), Color(0.58, 0.61, 0.60))

func _link_cylinder(material_id: int, binding: int, start: float, end: float, radius: float) -> void:
	for j in range(10):
		var a := float(j) * TAU / 10.0
		var b := float(j + 1) * TAU / 10.0
		var normal := Vector3(0, cos((a + b) * 0.5), sin((a + b) * 0.5))
		_wheel_quad(material_id, binding, Vector3(start, cos(a) * radius, sin(a) * radius),
			Vector3(start, cos(b) * radius, sin(b) * radius), Vector3(end, cos(b) * radius, sin(b) * radius),
			Vector3(end, cos(a) * radius, sin(a) * radius), normal)

func _build_suspension() -> void:
	for w in range(4):
		# Shock bodies, pistons and lower links bind to their actual frame and hub
		# endpoints; compression changes visible length as the tire moves.
		_link_cylinder(AMBER, 100 + w, 0.08, 0.66, 0.032)
		_link_cylinder(METAL, 100 + w, 0.40, 0.97, 0.017)
		_link_cylinder(DARK, 104 + w, 0.02, 0.98, 0.024)
		for j in range(40):
			var t := float(j) / 40.0
			var u := float(j + 1) / 40.0
			var a := Vector3(0.18 + t * 0.60, cos(t * TAU * 5.0) * 0.052, sin(t * TAU * 5.0) * 0.052)
			var b := Vector3(0.18 + u * 0.60, cos(u * TAU * 5.0) * 0.052, sin(u * TAU * 5.0) * 0.052)
			for edge in range(4):
				var angle := float(edge) * TAU / 4.0
				var next := float(edge + 1) * TAU / 4.0
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
	_ring_centers.resize(8)
	for w in range(4):
		for side in range(2):
			var ring_center := Vector3.ZERO
			for j in range(RING_SEGMENTS):
				ring_center += _nodes[_hubs[w] + 1 + side * RING_SEGMENTS + j]
			_ring_centers[w * 2 + side] = ring_center / float(RING_SEGMENTS)
	for material in _materials:
		material.set_shader_parameter("node_positions", _nodes)
		material.set_shader_parameter("ring_centers", _ring_centers)
		material.set_shader_parameter("rig_center", center)
		material.set_shader_parameter("tire_padding", _tire_padding)
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
