class_name TestYard
extends Node3D

func _ready() -> void:
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("9ab7c2")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dae7e6")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -32, 0)
	sun.light_color = Color("fff1d3")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55
	add_child(sun)
	solid_box(Vector3(100, 1, 120), Vector3(0, -0.5, -25), Color("718d82"))
	# Workshop launch pad and lane markings.
	YardShapes.box(self, Vector3(12, 0.025, 14), Vector3(0, 0.015, 8), Color("374d55"))
	for x in range(-5, 6):
		YardShapes.box(self, Vector3(0.025, 0.012, 12), Vector3(x, 0.035, 8), Color("536b70"))
	for z in range(2, 15):
		YardShapes.box(self, Vector3(10, 0.012, 0.025), Vector3(0, 0.035, z), Color("536b70"))
	for z in range(-65, 0, 4):
		YardShapes.box(self, Vector3(0.14, 0.025, 1.7), Vector3(-4.5, 0.02, z), Color("e3cf9a"))
		YardShapes.box(self, Vector3(0.14, 0.025, 1.7), Vector3(4.5, 0.02, z), Color("e3cf9a"))
	ramp(Vector3(0, 0, -10), 7, 8, 1.8)
	ramp(Vector3(15, 0, -20), 8, 10, 3.0)
	# Speed bumps in the left-hand lane.
	for i in range(5):
		solid_box(Vector3(5, 0.12 + i * 0.04, 0.5), Vector3(-14, 0.07 + i * 0.02, -10 - i * 3), Color("b6b092"))
	for i in range(7):
		var cone_at = Vector3(-3.3 if i % 2 == 0 else 3.3, 0.36, -29 - i * 5)
		var cone = YardShapes.cylinder(self, 0.35, 0.72, cone_at, Color("e2a04f"))
		cone.mesh.top_radius = 0.07
	for x in [-20, 20]:
		for z in [-4, -38, -64]:
			solid_box(Vector3(1.3, 1.3, 1.3), Vector3(x, 0.65, z), Color("c4b594"))
	# Solid perimeter: constructions stay inside the test ground.
	solid_box(Vector3(1, 3, 120), Vector3(-49, 1, -25), Color("526d68"))
	solid_box(Vector3(1, 3, 120), Vector3(49, 1, -25), Color("526d68"))
	solid_box(Vector3(100, 3, 1), Vector3(0, 1, -84), Color("526d68"))
	solid_box(Vector3(100, 3, 1), Vector3(0, 1, 34), Color("526d68"))

func solid_box(size: Vector3, at: Vector3, color: Color) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = at
	add_child(body)
	YardShapes.box(body, size, Vector3.ZERO, color)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func ramp(at: Vector3, width: float, length: float, height: float) -> void:
	var body = StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 2
	add_child(body)
	var points = PackedVector3Array([
		Vector3(-width / 2, 0, length / 2), Vector3(width / 2, 0, length / 2),
		Vector3(-width / 2, height, -length / 2), Vector3(width / 2, height, -length / 2),
		Vector3(-width / 2, 0, -length / 2), Vector3(width / 2, 0, -length / 2)
	])
	var shape = ConvexPolygonShape3D.new()
	shape.points = points
	var collision = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Double-sided low-poly wedge; collision and mesh share the same vertices.
	for index in [0, 1, 2, 1, 3, 2, 0, 2, 4, 1, 5, 3, 2, 3, 4, 3, 5, 4, 0, 4, 1, 1, 4, 5]:
		surface.add_vertex(points[index])
	surface.generate_normals()
	var instance = MeshInstance3D.new()
	instance.mesh = surface.commit()
	var mat = YardShapes.material(Color("c1af87")).duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	body.add_child(instance)

