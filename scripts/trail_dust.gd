extends Node3D

# A bounded pool of camera-facing puffs. Emit at planted rear tires only;
# visual dust never adds forces, terrain edits or collision objects.
const CAPACITY = 24
const LIFE = 1.15
var cloud := MultiMeshInstance3D.new()
var instances := MultiMesh.new()
var points := PackedVector3Array()
var velocities := PackedVector3Array()
var ages := PackedFloat32Array()
var phases := PackedFloat32Array()
var cursor = 0
var emission_time = 0.0
var random := RandomNumberGenerator.new()

func _ready() -> void:
	random.seed = 20407
	points.resize(CAPACITY)
	velocities.resize(CAPACITY)
	ages.resize(CAPACITY)
	ages.fill(LIFE)
	phases.resize(CAPACITY)
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.instance_count = CAPACITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	instances.mesh = quad
	cloud.multimesh = instances
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud.custom_aabb = AABB(Vector3(-390, -60, -390), Vector3(780, 280, 780))
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/trail_dust.gdshader")
	cloud.material_override = material
	add_child(cloud)
	for i in range(CAPACITY):
		instances.set_instance_custom_data(i, Color(0, 0, 0, 0))
	cloud.hide()

func update_trail(delta: float, enabled: bool, core: RefCounted, nodes: PackedVector3Array, stats: Dictionary, camera: Camera3D, tire_radius: float) -> void:
	if not enabled:
		ages.fill(LIFE)
		emission_time = 0.0
		cloud.hide()
		return
	var dt = minf(delta, 0.1)
	var speed = absf(float(stats.get("speed", 0.0)))
	emission_time += dt
	if speed > 3.5 and int(stats.get("wheels_grounded", 0)) > 0 and emission_time > 0.10 and nodes.size() == 100:
		emission_time = 0.0
		for hub in [58, 79]:
			var point: Vector3 = nodes[hub]
			var ground = float(core.terrain_height(point.x, point.z))
			# Low-grip water/mud never produces dry dust. Reject airborne hubs.
			if point.y - ground > tire_radius + 0.10 or float(core.terrain_surface(point.x, point.z)) < 0.70:
				continue
			points[cursor] = Vector3(point.x, ground + 0.16, point.z)
			velocities[cursor] = -Vector3(stats.forward) * minf(speed * 0.10, 1.8) + Vector3(random.randf_range(-0.20, 0.20), 0.55, 0.10)
			ages[cursor] = 0.0
			phases[cursor] = random.randf_range(-PI, PI)
			cursor = (cursor + 1) % CAPACITY
	var active = 0
	for i in range(CAPACITY):
		ages[i] += dt
		if ages[i] >= LIFE:
			instances.set_instance_custom_data(i, Color(0, 0, 0, 0))
			continue
		active += 1
		points[i] += velocities[i] * dt
		var age = ages[i] / LIFE
		var size = 0.30 + age * 1.45
		var basis = camera.global_basis.rotated(camera.global_basis.z, phases[i]).scaled(Vector3.ONE * size)
		instances.set_instance_transform(i, Transform3D(basis, points[i]))
		instances.set_instance_custom_data(i, Color(age, float(i) / CAPACITY, 0, sin(age * PI) * 0.22))
	cloud.visible = active > 0
