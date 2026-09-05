class_name YardVehicle
extends RigidBody3D

# One compound chassis body; each tire has an independent suspension ray.
# This prototype does not simulate bearings, tire sidewalls, or detached parts.
const RADIUS = 0.38
const REST = 0.44
const TRAVEL = 0.22
var wheels: Array = []
var throttle = 0.0
var steer_input = 0.0
var braking = false
var steer_angle = 0.0
var grounded_wheels = 0
var motors = 0
var reset_pending = false
var spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 8))

func configure(blueprint: YardBlueprint) -> void:
	mass = maxf(blueprint.total_mass(), 1.0)
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = blueprint.weighted_center()
	linear_damp = 0.05
	angular_damp = 0.5
	continuous_cd = true
	can_sleep = false
	collision_layer = 2
	collision_mask = 1
	motors = blueprint.count_kind("motor")
	var physics_mat = PhysicsMaterial.new()
	physics_mat.friction = 0.6
	physics_material_override = physics_mat
	for cell in blueprint.parts:
		var item: Dictionary = blueprint.parts[cell]
		var local = Vector3(cell) * YardBlueprint.GRID
		if item.kind == "wheel":
			var pivot = Node3D.new()
			add_child(pivot)
			pivot.position = local
			var visual = YardShapes.part(pivot, "wheel", Vector3.ZERO)
			wheels.append({"mount": local + Vector3.UP * 0.2, "pivot": pivot, "visual": visual, "steering": cell.z < 0})
		else:
			YardShapes.part(self, item.kind, local, item.turn)
			var collision = CollisionShape3D.new()
			var shape = BoxShape3D.new()
			shape.size = Vector3(0.66, 0.46 if item.kind == "frame" else 0.62, 0.66)
			collision.shape = shape
			collision.position = local
			add_child(collision)

func request_reset() -> void:
	reset_pending = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if reset_pending:
		state.transform = spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		reset_pending = false
		steer_angle = 0.0
		return
	if wheels.is_empty():
		return
	steer_angle = move_toward(steer_angle, steer_input * 0.48, state.step * 2.4)
	var transform_now = state.transform
	var up = transform_now.basis.y
	var wheel_mass = mass / wheels.size()
	var stiffness = wheel_mass * 9.81 / 0.14
	var damping = 1.35 * sqrt(stiffness * wheel_mass)
	grounded_wheels = 0
	for wheel in wheels:
		var mount: Vector3 = wheel.mount
		var origin = transform_now * mount
		var query = PhysicsRayQueryParameters3D.create(origin, origin - up * (REST + TRAVEL + RADIUS), 1, [get_rid()])
		var hit = state.get_space_state().intersect_ray(query)
		var extension = REST + TRAVEL
		var steer = steer_angle if wheel.steering else 0.0
		wheel.pivot.rotation.y = steer
		if not hit.is_empty() and hit.normal.dot(up) > 0.3:
			grounded_wheels += 1
			extension = clampf(origin.distance_to(hit.position) - RADIUS, 0.0, REST + TRAVEL)
			var contact: Vector3 = hit.position
			var offset = contact - transform_now.origin
			var com_offset = contact - (transform_now * center_of_mass)
			var velocity = state.linear_velocity + state.angular_velocity.cross(com_offset)
			var spring = maxf(0.0, (REST - extension) * stiffness - velocity.dot(up) * damping)
			spring = minf(spring, wheel_mass * 9.81 * 5.0)
			state.apply_force(up * spring, offset)
			var forward = (-transform_now.basis.z).rotated(up, steer)
			forward = forward.slide(hit.normal).normalized()
			var side: Vector3 = forward.cross(hit.normal).normalized()
			var speed = velocity.dot(forward)
			var sideways = velocity.dot(side)
			var grip = spring * 1.1
			var lateral = clampf(-sideways * wheel_mass * 7.0, -grip, grip)
			var drive = throttle * minf(motors * 1800.0, 5000.0) / wheels.size()
			# Taper acceleration at speed; no force while the wheels are airborne.
			if speed * throttle > 0:
				drive *= clampf(1.0 - absf(speed) / 22.0, 0.0, 1.0)
			var longitudinal = drive - speed * wheel_mass * 0.12
			if braking:
				longitudinal = -speed * wheel_mass * 12.0
			var tire_force = forward * longitudinal + side * lateral
			if tire_force.length() > grip:
				tire_force = tire_force.normalized() * grip
			state.apply_force(tire_force, offset)
			wheel.visual.rotation.x -= speed * state.step / RADIUS
		wheel.pivot.position = mount - Vector3.UP * extension

