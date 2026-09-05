class_name BuildGrid
extends Control

signal cell_pressed(cell: Vector3i)
var blueprint: YardBlueprint
var layer = 0
const CELL = 36.0

func _init() -> void:
	custom_minimum_size = Vector2(CELL * 7, CELL * 9)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	if blueprint == null:
		return
	var font = ThemeDB.fallback_font
	for z in range(-4, 5):
		for x in range(-3, 4):
			var cell = Vector3i(x, layer, z)
			var rect = Rect2(Vector2((x + 3) * CELL, (z + 4) * CELL), Vector2.ONE * (CELL - 3))
			var color = Color("263b45")
			var symbol = ""
			if blueprint.parts.has(cell):
				var kind: String = blueprint.parts[cell].kind
				color = YardBlueprint.COLORS[kind]
				symbol = YardBlueprint.SYMBOLS[kind]
			elif layer > 0 and blueprint.parts.has(cell - Vector3i.UP):
				color = Color("3c535b")
			draw_style_box(tile_style(color), rect)
			if symbol != "":
				var text_width = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
				draw_string(font, rect.position + Vector2((rect.size.x - text_width) / 2, 25), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("101d25") if symbol != "O" else Color("e4ece8"))

func tile_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	return style

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var x = int(event.position.x / CELL) - 3
		var z = int(event.position.y / CELL) - 4
		var cell = Vector3i(x, layer, z)
		if YardBlueprint.in_bounds(cell):
			cell_pressed.emit(cell)
		accept_event()
