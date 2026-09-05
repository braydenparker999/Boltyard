class_name YardShapes
extends RefCounted

static var materials: Dictionary = {}

static func material(color: Color) -> StandardMaterial3D:
	if materials.has(color):
		return materials[color]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	materials[color] = mat
	return mat

static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = at
	parent.add_child(instance)
	return instance

static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = at
	parent.add_child(instance)
	return instance

static func part(parent: Node3D, kind: String, at: Vector3, turn: int = 0) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = at
	root.rotation.y = turn * PI / 2.0
	var color: Color = YardBlueprint.COLORS[kind]
	match kind:
		"frame":
			box(root, Vector3(0.66, 0.46, 0.66), Vector3.ZERO, color)
			box(root, Vector3(0.45, 0.025, 0.45), Vector3(0, 0.245, 0), Color("658793"))
		"wheel":
			var tire = cylinder(root, 0.38, 0.32, Vector3.ZERO, Color("202c34"))
			tire.rotation.z = PI / 2.0
			var hub = cylinder(root, 0.19, 0.35, Vector3.ZERO, Color("d8e3df"))
			hub.rotation.z = PI / 2.0
			box(root, Vector3(0.37, 0.045, 0.26), Vector3.ZERO, Color("ffb84d"))
		"motor":
			box(root, Vector3(0.62, 0.52, 0.58), Vector3.ZERO, color)
			for i in range(4):
				box(root, Vector3(0.55, 0.04, 0.045), Vector3(0, 0.28, -0.19 + i * 0.12), Color("283c46"))
			cylinder(root, 0.055, 0.36, Vector3(0.22, 0.36, 0.2), Color("60737a"))
		"seat":
			box(root, Vector3(0.55, 0.16, 0.6), Vector3(0, -0.17, 0), color)
			box(root, Vector3(0.55, 0.58, 0.14), Vector3(0, 0.06, 0.24), color)
			box(root, Vector3(0.12, 0.36, 0.12), Vector3(0, -0.04, -0.23), Color("334951"))
			box(root, Vector3(0.4, 0.055, 0.1), Vector3(0, 0.15, -0.23), Color("d8e3df"))
		"weight":
			box(root, Vector3(0.62, 0.55, 0.62), Vector3.ZERO, color)
			box(root, Vector3(0.1, 0.025, 0.55), Vector3(0, 0.285, 0), Color("64475b"))
	return root

