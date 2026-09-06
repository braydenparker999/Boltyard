extends Node3D
class_name CrawlProps

## Renders the exact native convex meshes and their solved rigid poses.
## The solver owns gravity, contact, rotation, sleep, and reset.
var _core: RefCounted
var _visuals: Array[MeshInstance3D] = []

func configure(solver: RefCounted) -> void:
	_core = solver
	process_priority = 10
	for visual in _visuals:
		visual.queue_free()
	_visuals.clear()
	if not _core.has_method("get_dynamic_objects"):
		return
	var objects: Array = _core.get_dynamic_objects()
	for object in objects:
		var triangles: PackedVector3Array = object["triangles"]
		var kind: int = int(object.get("kind", 0))
		var mesh_builder := SurfaceTool.new()
		mesh_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		mesh_builder.set_color(Color.WHITE)
		var extents := Vector3.ZERO
		for vertex in triangles:
			extents = extents.max(vertex.abs())
		for index in range(0, triangles.size(), 3):
			var a: Vector3 = triangles[index]
			var b: Vector3 = triangles[index + 1]
			var c: Vector3 = triangles[index + 2]
			var normal := (b - a).cross(c - a).normalized()
			# Native outward CCW faces become Godot's clockwise mesh winding.
			for vertex in [a, c, b]:
				mesh_builder.set_normal(normal)
				mesh_builder.add_vertex(vertex)
		var visual := MeshInstance3D.new()
		visual.name = ["LooseSandstone", "LooseTimber", "LooseCrate"][clampi(kind, 0, 2)] + str(_visuals.size())
		visual.mesh = mesh_builder.commit()
		visual.material_override = _make_material(kind, extents)
		visual.visibility_range_end = 100.0
		visual.visibility_range_end_margin = 12.0
		add_child(visual)
		_visuals.append(visual)
	update_poses()

func _process(_delta: float) -> void:
	update_poses()

func update_poses() -> void:
	if _core == null or not _core.has_method("get_dynamic_object_poses"):
		return
	var poses: Array = _core.get_dynamic_object_poses()
	for index in mini(poses.size(), _visuals.size()):
		_visuals[index].transform = poses[index]

func _make_material(kind: int, half_size: Vector3) -> Material:
	if kind == 0:
		var stone := ShaderMaterial.new()
		stone.shader = load("res://shaders/copper_sandstone.gdshader")
		stone.set_shader_parameter("grain", load("res://assets/world/terrain_rock_photo.png"))
		stone.set_shader_parameter("mineral_noise", load("res://assets/world/copper_mineral_noise.png"))
		stone.set_shader_parameter("material_local", true)
		return stone
	var wood := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;
uniform bool crate = false;
uniform vec3 half_size = vec3(0.5);
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	vec3 p = local_position;
	float grain = sin(p.x * 8.0 + sin(p.z * 43.0) * 2.0 + sin(p.y * 32.0));
	float fiber = sin(p.y * 145.0 + p.z * 77.0 + sin(p.x * 5.0) * 1.8);
	vec3 color = mix(vec3(0.20, 0.105, 0.052), vec3(0.43, 0.275, 0.13), grain * 0.22 + 0.55);
	color += fiber * 0.022;
	if (!crate && abs(local_normal.x) > 0.85) {
		float rings = sin(length(p.yz) * 105.0);
		color = vec3(0.57, 0.39, 0.21) + rings * 0.042;
	}
	if (crate) {
		vec3 q = p / max(half_size, vec3(0.001));
		vec2 uv = abs(local_normal.y) > 0.8 ? q.xz : (abs(local_normal.x) > 0.8 ? q.zy : q.xy);
		float frame = step(0.76, max(abs(uv.x), abs(uv.y)));
		float seam = 1.0 - smoothstep(0.012, 0.025, abs(sin(uv.x * 6.2831853)));
		color = mix(color * (1.0 - seam * 0.45), vec3(0.43, 0.30, 0.17), frame * 0.65);
	}
	ALBEDO = color;
	ROUGHNESS = 0.94;
}
"""
	wood.shader = shader
	wood.set_shader_parameter("crate", kind == 2)
	wood.set_shader_parameter("half_size", half_size)
	return wood
