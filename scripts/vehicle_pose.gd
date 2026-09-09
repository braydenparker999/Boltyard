extends RefCounted
## One render timeline for the rigid body, rolling tires and mechanical mounts.
## Physics remains authoritative; interpolation never feeds back into the solver.

static func body_transform(nodes: PackedVector3Array) -> Transform3D:
	var x := (nodes[1] - nodes[0]).normalized()
	var z := (nodes[2] - nodes[0]).normalized()
	var y := z.cross(x).normalized()
	z = x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), nodes[0])

static func capture(core: RefCounted) -> Dictionary:
	var nodes: PackedVector3Array = core.get_nodes()
	return {"nodes": nodes, "wheels": core.get_wheel_visuals(), "body": body_transform(nodes)}

static func wheel_basis(axis: Vector3, up: Vector3, phase: float) -> Basis:
	axis = axis.normalized()
	up = (up - axis * up.dot(axis)).normalized()
	var tangent := axis.cross(up).normalized()
	return Basis(axis, up * cos(phase) + tangent * sin(phase), tangent * cos(phase) - up * sin(phase))

static func interpolate(previous: Dictionary, current: Dictionary, alpha: float) -> Dictionary:
	alpha = clampf(alpha, 0.0, 1.0)
	var a: PackedVector3Array = previous.nodes
	var b: PackedVector3Array = current.nodes
	var before: Transform3D = previous.body
	var after: Transform3D = current.body
	var body := Transform3D(Basis(before.basis.get_rotation_quaternion().slerp(after.basis.get_rotation_quaternion(), alpha)), before.origin.lerp(after.origin, alpha))
	var nodes := b.duplicate()
	var inverse := after.affine_inverse()
	for i in range(16):
		nodes[i] = body * (inverse * b[i])
	var wa: Dictionary = previous.wheels
	var wb: Dictionary = current.wheels
	var wheels := wb.duplicate(true)
	for key in ["axes", "normals", "points", "link_starts", "link_ends", "axle_ups"]:
		var values: PackedVector3Array = wb[key].duplicate()
		for i in range(values.size()):
			values[i] = wa[key][i].lerp(wb[key][i], alpha)
			if key in ["axes", "normals", "axle_ups"] and values[i].length_squared() > 0.000001:
				values[i] = values[i].normalized()
		wheels[key] = values
	wheels.up = body.basis.y
	for w in range(4):
		var hub := 16 + w * 21
		nodes[hub] = a[hub].lerp(b[hub], alpha)
		wheels.phases[w] = lerp_angle(wa.phases[w], wb.phases[w], alpha)
		wheels.compression[w] = lerpf(wa.compression[w], wb.compression[w], alpha)
		var from_basis := wheel_basis(wa.axes[w], wa.up, wa.phases[w])
		var to_basis := wheel_basis(wb.axes[w], wb.up, wb.phases[w])
		var basis := wheel_basis(wheels.axes[w], wheels.up, wheels.phases[w])
		for j in range(1, 21):
			# Interpolate tire deflection in its rotating local frame. Blending
			# rotating world vertices directly would shrink the tire at speed.
			var local_a := from_basis.transposed() * (a[hub + j] - a[hub])
			var local_b := to_basis.transposed() * (b[hub + j] - b[hub])
			nodes[hub + j] = nodes[hub] + basis * local_a.lerp(local_b, alpha)
	# Contact slots can reorder when crossing a triangle edge. Match nearby
	# surfaces, never blend unrelated slot normals into an invented plane.
	for w in range(4):
		var used: Array[int] = []
		for j in range(6):
			var slot := w * 6 + j
			var plane: Color = wb.patch_planes[slot]
			var patch: Color = wb.patch_centers[slot]
			if patch.a <= 0.0:
				continue
			var nearest := -1
			var distance := 0.25
			for k in range(6):
				var old_slot := w * 6 + k
				var old_patch: Color = wa.patch_centers[old_slot]
				var old_plane: Color = wa.patch_planes[old_slot]
				var separation := Vector3(patch.r - old_patch.r, patch.g - old_patch.g, patch.b - old_patch.b).length_squared()
				if k not in used and old_patch.a > 0.0 and Vector3(plane.r, plane.g, plane.b).dot(Vector3(old_plane.r, old_plane.g, old_plane.b)) > 0.98 and separation < distance:
					nearest = k
					distance = separation
			if nearest >= 0:
				used.append(nearest)
				var blended: Color = wa.patch_planes[w * 6 + nearest].lerp(plane, alpha)
				var length := Vector3(blended.r, blended.g, blended.b).length()
				wheels.patch_planes[slot] = blended / length
				wheels.patch_centers[slot] = wa.patch_centers[w * 6 + nearest].lerp(patch, alpha)
	return {"nodes": nodes, "wheels": wheels, "body": body}
