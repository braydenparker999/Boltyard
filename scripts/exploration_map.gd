class_name ExplorationMap
extends Control

signal destination_selected(id: String)

var extent = 320.0
const GRID = 56
var landmarks: Array = []
var heights: PackedFloat32Array = []
var vehicle_position = Vector3.ZERO
var discovered: Array[String] = []
var destination = ""
var trails: Dictionary = {}
## Difficulty per route index, so a six-route network reads as a network and
## not as one undifferentiated tangle of identical lines.
var route_grades: Dictionary = {}
const ROUTE_COLORS := [Color("d9bd8299"), Color("cfa96b99"), Color("d2865e99")]
var height_min = 0.0
var height_max = 60.0

func configure(core, locations: Array) -> void:
	landmarks = locations.duplicate(true)
	heights.clear()
	trails.clear()
	route_grades.clear()
	if core.has_method("get_expedition_route_info"):
		var info: Array = core.get_expedition_route_info()
		for index in range(info.size()):
			route_grades[index] = int(info[index].get("difficulty", 0))
	if core.has_method("get_expedition_trails"):
		for point in core.get_expedition_trails():
			var route = int(point.route)
			if not trails.has(route):
				trails[route] = PackedVector3Array()
			trails[route].append(point.position)
	# Sample the same height function used for tire contact, once for the atlas.
	for z in GRID:
		for x in GRID:
			var px = lerpf(-extent, extent, (float(x) + 0.5) / GRID)
			var pz = lerpf(-extent, extent, (float(z) + 0.5) / GRID)
			heights.append(float(core.terrain_height(px, pz)))
	mouse_filter = Control.MOUSE_FILTER_STOP
	height_min = heights[0] if not heights.is_empty() else 0.0
	height_max = height_min + 1.0
	for height in heights:
		height_min = minf(height_min, height)
		height_max = maxf(height_max, height)
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	queue_redraw()

func update_state(position: Vector3, visited: Array[String], selected: String) -> void:
	vehicle_position = position
	discovered = visited.duplicate()
	destination = selected
	queue_redraw()

func map_rect() -> Rect2:
	var side = maxf(40.0, minf(size.x - 16.0, size.y - 12.0))
	return Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)

func project(point: Vector3) -> Vector2:
	var area = map_rect()
	return area.position + Vector2((point.x + extent) / (extent * 2.0), (point.z + extent) / (extent * 2.0)) * area.size

func _draw() -> void:
	var area = map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("132329"))
	if heights.size() == GRID * GRID:
		var cell = area.size / GRID
		for z in GRID:
			for x in GRID:
				var height = heights[z * GRID + x]
				var tone = clampf((height - height_min) / maxf(1.0, height_max - height_min), 0.0, 1.0)
				var color = Color("304b48").lerp(Color("9a9478"), tone)
				draw_rect(Rect2(area.position + Vector2(x, z) * cell, cell + Vector2.ONE), color)
	for route in trails:
		var line = PackedVector2Array()
		for point in trails[route]:
			line.append(project(point))
		if line.size() > 1:
			var grade: int = clampi(int(route_grades.get(route, 0)), 0, ROUTE_COLORS.size() - 1)
			draw_polyline(line, ROUTE_COLORS[grade], 2.0 if grade < 2 else 2.6, true)
	for i in range(1, 4):
		var amount = area.size.x * i / 4.0
		draw_line(area.position + Vector2(amount, 0), area.position + Vector2(amount, area.size.y), Color("bed3cb23"))
		draw_line(area.position + Vector2(0, amount), area.position + Vector2(area.size.x, amount), Color("bed3cb23"))
	draw_rect(area, Color("99b6ac"), false, 1.0)
	var font = ThemeDB.fallback_font
	draw_string(font, area.position + Vector2(8, 19), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f3efdf"))
	draw_string(font, area.end + Vector2(-76, -9), "%d × %d m" % [int(extent * 2), int(extent * 2)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f3efdf"))
	for index in landmarks.size():
		var landmark: Dictionary = landmarks[index]
		var point = project(landmark.position)
		var selected = str(landmark.id) == destination
		if selected:
			draw_arc(point, 13, 0, TAU, 24, Color("efbd71"), 2, true)
		draw_circle(point, 9, Color("efbd71") if str(landmark.id) in discovered else Color("21373b"))
		draw_arc(point, 9, 0, TAU, 20, Color("efbd71"), 1, true)
		draw_string(font, point + Vector2(-3.5, 4), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("132329") if str(landmark.id) in discovered else Color("f3efdf"))
	var player = project(vehicle_position)
	draw_circle(player, 5, Color("edf5f4"))
	draw_arc(player, 7.5, 0, TAU, 20, Color("14252d"), 2, true)

func _gui_input(event: InputEvent) -> void:
	var position: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
	elif event is InputEventScreenTouch and event.pressed:
		position = event.position
	else:
		return
	var closest = ""
	var distance = 24.0
	for landmark in landmarks:
		var delta = project(landmark.position).distance_to(position)
		if delta < distance:
			distance = delta
			closest = str(landmark.id)
	if not closest.is_empty():
		destination_selected.emit(closest)
		accept_event()
