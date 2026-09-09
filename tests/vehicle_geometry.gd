extends SceneTree

# Run with: godot --headless --path . --script tests/vehicle_geometry.gd
# This suite inspects the uploaded mesh as well as the CPU mirror of its skin.
# GPU deformation is separately covered by rendered vehicle captures.
const Catalog = preload("res://scripts/vehicle_catalog.gd")
const Truck = preload("res://scripts/offroad_truck.gd")
const STEP = 1.0 / 120.0
const SEAM_TOLERANCE = 0.00001
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func fully_fitted(vehicle_id: String) -> Dictionary:
	var build = Catalog.default_build(vehicle_id)
	var equipment = {
		"tires": "rock", "wheels": "beadlock", "suspension": "long_travel", "gearing": "crawler",
		"front_bumper": "cage_brace" if vehicle_id == "buggy" else "armor",
		"roof": "cage_spare" if vehicle_id == "buggy" else "expedition_rack"
	}
	for slot in equipment:
		build = Catalog.equip_part(build, slot, equipment[slot])
	check(build.parts == equipment, "%s accepts the complete equipment fixture" % vehicle_id)
	return build

func inspect_uploaded_mesh(mesh: ArrayMesh) -> Dictionary:
	var result = {"triangles": 0, "bad_arrays": 0, "nonfinite": 0, "bad_normals": 0}
	for surface in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bindings: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or vertices.is_empty() or vertices.size() % 3 != 0:
			result.bad_arrays += 1
		if vertices.size() != normals.size() or vertices.size() != bindings.size() or vertices.size() != colors.size():
			result.bad_arrays += 1
		result.triangles += vertices.size() / 3
		for point in vertices:
			if not point.is_finite():
				result.nonfinite += 1
		for normal in normals:
			if not normal.is_finite():
				result.nonfinite += 1
			elif normal.length_squared() < 0.5 or normal.length_squared() > 1.5:
				result.bad_normals += 1
		for binding in bindings:
			if not binding.is_finite():
				result.nonfinite += 1
		for color in colors:
			if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):
				result.nonfinite += 1
	return result

func rest_samples(truck: Node3D) -> PackedVector3Array:
	var samples = PackedVector3Array()
	# Include points outside the frame and cab cubes: trim, bumpers and roof
	# equipment must extrapolate safely as well as the panels inside each cube.
	for base in [0, 8]:
		for x in [-0.15, 0.5, 1.15]:
			for y in [-0.1, 0.5, 1.4]:
				for z in [-0.2, 0.5, 1.25]:
					samples.append(truck.call("debug_rest_point", base, Vector3(x, y, z)))
	return samples

func rest_identity_error(truck: Node3D, samples: PackedVector3Array) -> float:
	var error = 0.0
	for point in samples:
		var deformed: Vector3 = truck.call("debug_deform_point", point)
		if not point.is_finite() or not deformed.is_finite():
			return INF
		error = maxf(error, point.distance_to(deformed))
	return error

func inspect_rendered_triangles(truck: Node3D, mesh: ArrayMesh) -> Dictionary:
	var result = {"degenerate": 0, "examples": []}
	for surface in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bindings: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for index in range(0, vertices.size(), 3):
			var a: Vector3 = truck.call("_debug_vertex", roundi(bindings[index].x), vertices[index], bindings[index].y)
			var b: Vector3 = truck.call("_debug_vertex", roundi(bindings[index + 1].x), vertices[index + 1], bindings[index + 1].y)
			var c: Vector3 = truck.call("_debug_vertex", roundi(bindings[index + 2].x), vertices[index + 2], bindings[index + 2].y)
			if a.is_finite() and b.is_finite() and c.is_finite() and (b - a).cross(c - a).length_squared() < 0.000000000000001:
				result.degenerate += 1
				if result.examples.size() < 6:
					result.examples.append({"surface": surface, "triangle": index / 3, "binding": bindings[index].x, "source": [vertices[index], vertices[index + 1], vertices[index + 2]], "rendered": [a, b, c]})
	return result

func live_samples_are_valid(truck: Node3D, samples: PackedVector3Array) -> bool:
	var stats: Dictionary = truck.core.get_stats()
	var center: Vector3 = stats.position
	if not center.is_finite():
		return false
	for point in samples:
		var deformed: Vector3 = truck.call("debug_deform_point", point)
		if not deformed.is_finite() or deformed.distance_to(center) > 15.0:
			return false
	return true

func validate_live(truck: Node3D, samples: PackedVector3Array, label: String) -> void:
	truck.call("_refresh_visuals")
	var validation: Dictionary = truck.call("get_visual_validation")
	check(int(validation.get("live_nonfinite_vertices", -1)) == 0, "%s has finite deformed body, wheel and suspension vertices" % label)
	var seam_gap = float(validation.get("max_seam_gap", INF))
	check(is_finite(seam_gap) and seam_gap <= SEAM_TOLERANCE, "%s keeps shared panel boundaries together" % label)
	check(live_samples_are_valid(truck, samples), "%s keeps frame, cab and accessory skin samples finite and bounded" % label)

func advance(truck: Node3D, count: int, throttle: float, steering: float, brake: bool) -> void:
	for frame in range(count):
		truck.core.step(STEP, throttle, steering, brake)
	truck.call("_refresh_visuals")

func exercise(build: Dictionary, fitted: bool) -> void:
	var label = "%s %s" % [build.vehicle, "fully fitted" if fitted else "stock"]
	var truck = Truck.new()
	var settings := Catalog.compose(build)
	settings.procedural_body = true
	truck.configure(settings)
	root.add_child(truck)
	# Advance the native solver explicitly so this suite is deterministic and
	# independent of rendering cadence or a machine's headless frame rate.
	truck.set_physics_process(false)
	truck.set_process(false)
	truck.core.set_terrain(0)
	var body = truck.get_node_or_null("ParticleSkinnedVehicle") as MeshInstance3D
	check(body != null and body.mesh is ArrayMesh, "%s uploads an ArrayMesh" % label)
	if body == null or not body.mesh is ArrayMesh:
		truck.free()
		return
	var mesh = body.mesh as ArrayMesh
	var original_mesh_rid = mesh.get_rid()
	var uploaded = inspect_uploaded_mesh(mesh)
	check(uploaded.bad_arrays == 0 and mesh.get_surface_count() > 0, "%s has complete triangle, normal, binding and color arrays" % label)
	check(uploaded.nonfinite == 0 and uploaded.bad_normals == 0, "%s uploads finite attributes and usable normals" % label)
	var validation: Dictionary = truck.call("get_visual_validation")
	# Fixed-body coilovers, captive springs and mount hardware share the existing
	# nine surfaces; bounded geometry budget includes their added detail.
	var triangle_limit = 22000 if fitted else 21000
	check(uploaded.triangles > 1000 and uploaded.triangles < triangle_limit, "%s uses %d triangles, below %d" % [label, uploaded.triangles, triangle_limit])
	check(int(validation.get("triangles", -1)) == uploaded.triangles, "%s triangle telemetry matches the uploaded mesh" % label)
	check(int(validation.get("nonfinite_vertices", -1)) == 0 and int(validation.get("degenerate_triangles", -1)) == 0, "%s has finite rest geometry with no degenerate triangles" % label)
	var rendered = inspect_rendered_triangles(truck, mesh)
	check(rendered.degenerate == 0, "%s has no degenerate triangles after rest-pose skinning (%d found)" % [label, rendered.degenerate])
	if rendered.degenerate > 0:
		print("DEGENERATE DETAILS %s: %s" % [label, str(rendered.examples)])
	var clearance = float(validation.get("min_wheel_clearance", -INF))
	check(is_finite(clearance) and clearance > 0.0, "%s leaves positive clearance around the rendered tires" % label)
	var samples = rest_samples(truck)
	var original_rest_origin: Vector3 = truck.core.get_rest_nodes()[0]
	check(rest_identity_error(truck, samples) < 0.0001, "%s preserves the authored shape in the native rest pose" % label)
	validate_live(truck, samples, label + " rest")
	var original_center: Vector3 = truck.core.get_stats().position
	advance(truck, 360, 0.0, 0.0, true)
	check(truck.core.get_stats().contacts > 0 and original_center.distance_to(truck.core.get_stats().position) > 0.05, "%s exercises a settled pose with tire contact" % label)
	validate_live(truck, samples, label + " settled")
	advance(truck, 180, 0.65, 0.8, false)
	validate_live(truck, samples, label + " steering right")
	advance(truck, 120, 0.4, -0.8, false)
	validate_live(truck, samples, label + " steering left")
	# A deterministic pose edit proves that the skin actually responds to a
	# changed structural node, then the impulse tests evolving crash poses.
	var roof_point: Vector3 = truck.call("debug_rest_point", 8, Vector3(0, 1, 0))
	var roof_before: Vector3 = truck.call("debug_deform_point", roof_point)
	truck.core.displace_node(12, Vector3(0.30, -0.16, 0.13))
	truck.call("_refresh_visuals")
	var roof_after: Vector3 = truck.call("debug_deform_point", roof_point)
	check(roof_after.is_finite() and roof_before.distance_to(roof_after) > 0.01, "%s visibly follows a rigid body pose edit" % label)
	validate_live(truck, samples, label + " pose edit")
	truck.core.apply_impact(Vector3(16000, 0, 4000))
	for phase in range(3):
		advance(truck, 40, 0.0, 0.5, false)
		validate_live(truck, samples, "%s impact %d" % [label, phase + 1])
	check(body.mesh.get_rid() == original_mesh_rid, "%s reuses its uploaded mesh while settling, steering and deforming" % label)
	# Repair at a distant checkpoint must move the bind pose as well as the
	# particles. An obsolete rest origin can otherwise distort the whole skin.
	truck.reset(Vector3(84, 4, -63))
	var repaired_nodes: PackedVector3Array = truck.core.get_rest_nodes()
	var repaired_frame: Vector3 = truck.call("debug_rest_point", 0, Vector3.ZERO)
	var repaired_roof: Vector3 = truck.call("debug_rest_point", 8, Vector3(0, 1, 0))
	check(repaired_frame.distance_to(repaired_nodes[0]) < 0.0001 and repaired_roof.distance_to(repaired_nodes[12]) < 0.0001, "%s repair updates frame and cab bind origins at a distant checkpoint" % label)
	var repaired_samples = rest_samples(truck)
	var translation = repaired_nodes[0] - original_rest_origin
	var translation_error = 0.0
	for index in range(samples.size()):
		translation_error = maxf(translation_error, (repaired_samples[index] - samples[index]).distance_to(translation))
	check(translation_error < 0.0001 and rest_identity_error(truck, repaired_samples) < 0.0001, "%s repair restores the authored shape after translating the bind pose" % label)
	validate_live(truck, repaired_samples, label + " distant repair")
	check(body.mesh.get_rid() == original_mesh_rid and truck.core.get_stats().broken_beams == 0, "%s repair resets damage and preserves its uploaded mesh" % label)
	truck.free()

func run() -> void:
	check(ClassDB.class_exists("SoftBodyRig"), "native soft-body extension is registered")
	if not ClassDB.class_exists("SoftBodyRig"):
		quit(1)
		return
	var probe = Truck.new()
	var hooks_available = probe.has_method("get_visual_validation") and probe.has_method("debug_rest_point") and probe.has_method("debug_deform_point")
	check(hooks_available, "vehicle exposes rest and live skin validation hooks")
	probe.free()
	if not hooks_available:
		quit(1)
		return
	for vehicle_id in Catalog.VEHICLES:
		exercise(Catalog.default_build(vehicle_id), false)
		exercise(fully_fitted(vehicle_id), true)
	print("VEHICLE GEOMETRY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
