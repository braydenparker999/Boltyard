extends Node3D
## Optional appearance. The owner-provided model is bundled in personal APKs;
## public source builds retain the procedural pickup if the asset is absent.
const MODEL_PATH := "res://assets/ranger/ranger.glb"
const PAINT_SHADER = preload("res://shaders/ranger_paint.gdshader")
var model: Node3D
var paint: ShaderMaterial
var triangles := 0

func configure(settings: Dictionary) -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	model = load(MODEL_PATH).instantiate() as Node3D
	add_child(model)
	paint = ShaderMaterial.new()
	paint.shader = PAINT_SHADER
	for key in ["base", "normal", "orm", "palette", "opacity"]:
		paint.set_shader_parameter(key + "_texture", load("res://assets/ranger/body_" + key + ".png"))
	var radius := float(settings.get("tire_radius", .46))
	var ride := float(settings.get("ride_height", .35))
	var travel := float(settings.get("compression_travel", 0.0))
	if travel <= 0.0:
		travel = minf(float(settings.get("suspension_travel", .22)) * 1.273, ride * .72)
	# The original opening sits at 0.95 m. Fit its top above the tire at full
	# jounce; the body stays rigid while axles move underneath it.
	model.position.y = radius - ride + travel + .07 - .95
	model.scale.z = float(settings.get("wheelbase", 2.75)) / 2.7390745
	_prepare_meshes(model, settings)
	return true

func _prepare_meshes(node: Node, settings: Dictionary) -> void:
	if node is MeshInstance3D:
		node.layers = 2
		var parts: Dictionary = settings.get("parts", {})
		var bumper := str(parts.get("front_bumper", "stock"))
		if node.name in ["front_stock", "front_tube", "front_bumper"]:
			node.visible = str(node.name) == {"stock": "front_stock", "tube": "front_tube", "armor": "front_bumper"}.get(bumper, "front_stock")
		if node.name == "roofrack":
			node.visible = str(parts.get("roof", "none")) != "none"
		for i in range(node.mesh.get_surface_count()):
			var material: Material = node.mesh.surface_get_material(i)
			if material != null and material.resource_name == "nix_83_ranger_body":
				node.set_surface_override_material(i, paint)
			var arrays: Array = node.mesh.surface_get_arrays(i)
			if node.visible:
				triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size() / 3
	for child in node.get_children():
		_prepare_meshes(child, settings)

func update_pose(nodes: PackedVector3Array, basis: Basis, color: Color, shown: bool) -> void:
	var underside := (nodes[0] + nodes[1] + nodes[2] + nodes[3]) * .25
	global_transform = Transform3D(basis, underside)
	paint.set_shader_parameter("paint_color", color)
	visible = shown
