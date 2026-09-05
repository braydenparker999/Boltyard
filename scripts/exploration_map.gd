class_name ExplorationMap
extends Control

signal destination_selected(id: String)

const EXTENT = 384.0
const GRID = 28
var landmarks: Array = []
var heights: PackedFloat32Array = []
var vehicle_position = Vector3.ZERO
var discovered: Array[String] = []
var destination = ""

func configure(core, locations: Array) -> void:
	landmarks = locations.duplicate(true)
	heights.clear()
	# Sample the same height function used for tire contact, once for the atlas.
	for z in GRID:
		for x in GRID:
			var px = lerpf(-EXTENT, EXTENT, (float(x) + 0.5) / GRID)
			var pz = lerpf(-EXTENT, EXTENT, (float(z) + 0.5) / GRID)
			heights.append(float(core.terrain_height(px, pz)))
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	return area.position + Vector2((point.x + EXTENT) / (EXTENT * 2.0), (point.z + EXTENT) / (EXTENT * 2.0)) * area.size

func _draw() -> void:
	var area = map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("132329"))
	if heights.size() == GRID * GRID:
		var cell = area.size / GRID
		for z in GRID:
			for x in GRID:
				var height = heights[z * GRID + x]
				var tone = clampf((height + 4.0) / 40.0, 0.0, 1.0)
				var color = Color("304b48").lerp(Color("9a9478"), tone)
				draw_rect(Rect2(area.position + Vector2(x, z) * cell, cell + Vector2.ONE), color)
	for i in range(1, 4):
		var amount = area.size.x * i / 4.0
		draw_line(area.position + Vector2(amount, 0), area.position + Vector2(amount, area.size.y), Color("bed3cb23"))
		draw_line(area.position + Vector2(0, amount), area.position + Vector2(area.size.x, amount), Color("bed3cb23"))
	draw_rect(area, Color("99b6ac"), false, 1.0)
	var font = ThemeDB.fallback_font
	draw_string(font, area.position + Vector2(8, 19), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f3efdf"))
	draw_string(font, area.end + Vector2(-76, -9), "768 × 768 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f3efdf"))
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
