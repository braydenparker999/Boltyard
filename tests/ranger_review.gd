extends SceneTree
## Real solved vehicle pose exported for an offline geometry review, also usable
## as a rendered capture on a machine with a graphics driver.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://assets/ranger/ranger.glb"):
		print("RANGER REVIEW: owner-provided appearance not present in this checkout")
		quit()
		return
	var truck = load("res://scripts/offroad_truck.gd").new()
	var build := VehicleCatalog.default_build("pickup")
	for slot in ["tires", "wheels", "suspension", "front_bumper", "gearing"]:
		build = VehicleCatalog.equip_part(build, slot, {"tires": "rock", "wheels": "beadlock", "suspension": "lift", "front_bumper": "armor", "gearing": "crawler"}[slot])
	var settings := VehicleCatalog.compose(build)
	settings.wheelbase = 2.75
	settings.track_width = 2.1
	truck.configure(settings)
	root.add_child(truck)
	truck.set_process(false)
	truck.set_physics_process(false)
	truck.core.set_terrain(3)
	truck.reset(Vector3(0, 1.5, 8))
	for i in range(360): truck.core.step(1.0 / 120.0, 0, 0, true)
	truck._refresh_visuals()
	assert(truck._ranger != null)
	assert(truck._ranger.triangles > 40000 and truck._ranger.triangles < 55000)
	assert(truck.get_visual_validation().live_nonfinite_vertices == 0)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for surface in range(truck._body_mesh.get_surface_count()):
		var arrays: Array = truck._body_mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bindings: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var tint: Color = truck._body_mesh.surface_get_material(surface).get_shader_parameter("surface_color")
		for i in range(positions.size()):
			vertices.append(truck._debug_vertex(roundi(bindings[i].x), positions[i], bindings[i].y))
			colors.append(tint * arrays[Mesh.ARRAY_COLOR][i])
	FileAccess.open("res://build/3.4/mechanical-vertices.bin", FileAccess.WRITE).store_buffer(vertices.to_byte_array())
	FileAccess.open("res://build/3.4/mechanical-colors.bin", FileAccess.WRITE).store_buffer(colors.to_byte_array())
	var pose: Transform3D = truck._ranger.model.global_transform
	var report := {"settings": settings, "vertices": vertices.size(), "body_triangles": truck._ranger.triangles,
		"total_triangles": truck.get_telemetry().render_triangles, "body_matrix": [Array(PackedFloat32Array([pose.basis.x.x, pose.basis.x.y, pose.basis.x.z])), Array(PackedFloat32Array([pose.basis.y.x, pose.basis.y.y, pose.basis.y.z])), Array(PackedFloat32Array([pose.basis.z.x, pose.basis.z.y, pose.basis.z.z])), Array(PackedFloat32Array([pose.origin.x, pose.origin.y, pose.origin.z]))]}
	FileAccess.open("res://build/3.4/ranger-review.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print("RANGER REVIEW: %d body triangles, %d total; solved mechanical mesh exported" % [truck._ranger.triangles, truck.get_telemetry().render_triangles])
	truck.free()
	quit()
