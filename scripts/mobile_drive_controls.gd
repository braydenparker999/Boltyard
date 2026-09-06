extends Control
## One owner per finger, retained until release even outside the artwork.
signal action_requested(action: String)
var steering := 0.0
var throttle := 0.0
var braking := false
var reverse := false
var control_scale := 1.0
var thumb_offset := 0.0
var sensitivity := 1.0
var owners: Dictionary = {}
var rects: Dictionary = {}
var buttons: Dictionary = {}
var bar := GridContainer.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 8)
	add_child(bar)
	for id in ["low", "front", "rear", "recover"]:
		var b := Button.new()
		b.text = {"low": "LOW", "front": "F · LOCK", "rear": "R · LOCK", "recover": "RECOVER"}[id]
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): action_requested.emit(id))
		bar.add_child(b)
		buttons[id] = b
	resized.connect(arrange)
	arrange()

func arrange() -> void:
	if not is_node_ready(): return
	var w := size.x
	var base := size.y - 34.0 - thumb_offset
	var k := control_scale
	var left_width := minf(280.0 * k, w * .43)
	rects = {
		"steer": Rect2(22, base - 142 * k, left_width, 136 * k),
		"throttle": Rect2(w - 22 - 106 * k, base - 214 * k, 106 * k, 208 * k),
		"brake": Rect2(w - 36 - 198 * k, base - 96 * k, 92 * k, 90 * k),
		"direction": Rect2(w - 36 - 198 * k, base - 170 * k, 92 * k, 62 * k)}
	bar.position = Vector2(22, base - 292 * k)
	bar.columns = 4 if size.y > size.x else 2
	bar.size = Vector2(w - 44 if bar.columns == 4 else left_width, (60 if bar.columns == 4 else 120) * k)
	for b in buttons.values(): b.custom_minimum_size.y = 54 * k
	queue_redraw()

func blocked(point: Vector2) -> bool:
	return point.y >= bar.position.y - 18

func cancel() -> void:
	owners.clear()
	steering = 0
	throttle = 0
	braking = false
	queue_redraw()

func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		var touch := InputEventScreenTouch.new()
		touch.index = -100
		touch.position = event.position
		touch.pressed = event.pressed
		return handle(touch)
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and owners.has(-100):
		var drag := InputEventScreenDrag.new()
		drag.index = -100
		drag.position = event.position
		return handle(drag)
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			if not owners.has(event.index): return false
			var id: String = owners[event.index]
			owners.erase(event.index)
			if id == "steer": steering = 0
			elif id == "throttle": throttle = 0
			elif id == "brake": braking = false
			elif not event.canceled:
				if id == "direction" and rects.direction.has_point(event.position):
					# Direction changes start with a released pedal.
					throttle = 0
					for finger in owners.keys():
						if owners[finger] == "throttle": owners[finger] = "guard"
					reverse = not reverse
				elif buttons.has(id) and buttons[id].get_global_rect().has_point(event.position):
					action_requested.emit(id)
			queue_redraw()
			return true
		var id := ""
		for key in rects:
			if rects[key].has_point(event.position): id = key; break
		for key in buttons:
			if buttons[key].get_global_rect().has_point(event.position): id = key; break
		if id.is_empty(): return false
		if id in owners.values(): id = "guard"
		owners[event.index] = id
		update_axis(id, event.position)
		return true
	if event is InputEventScreenDrag and owners.has(event.index):
		update_axis(owners[event.index], event.position)
		return true
	return false

func update_axis(id: String, point: Vector2) -> void:
	if id == "steer":
		var r: Rect2 = rects.steer
		var raw := clampf((point.x - r.get_center().x) / (r.size.x * .42), -1, 1)
		steering = signf(raw) * clampf((absf(raw) - .06) / .94 * sensitivity, 0, 1)
	elif id == "throttle":
		var r: Rect2 = rects.throttle
		var raw := clampf((r.end.y - 26 - point.y) / (r.size.y - 54), 0, 1)
		throttle = raw * raw
	elif id == "brake": braking = true
	queue_redraw()

func _draw() -> void:
	if rects.is_empty(): return
	var accent := Color("e7bf7d")
	for id in rects:
		var r: Rect2 = rects[id]
		var style := StyleBoxFlat.new()
		style.bg_color = Color("142127df")
		style.border_color = Color("597071a0")
		style.set_border_width_all(1)
		style.set_corner_radius_all(18)
		draw_style_box(style, r)
	var s: Rect2 = rects.steer
	draw_line(Vector2(s.position.x + 25, s.get_center().y), Vector2(s.end.x - 25, s.get_center().y), Color("819190"), 3, true)
	draw_line(s.get_center() - Vector2(0, 14), s.get_center() + Vector2(0, 14), Color("819190"), 2)
	draw_circle(s.get_center() + Vector2(steering * s.size.x * .36, 0), 24 * control_scale, accent)
	caption(s, "STEER", 15, 28)
	var p: Rect2 = rects.throttle
	var fill := Rect2(p.position + Vector2(12, 40), p.size - Vector2(24, 65))
	fill.position.y += fill.size.y * (1 - throttle)
	fill.size.y *= throttle
	draw_rect(fill, Color("e7bf7d88"))
	caption(p, "%d%%" % roundi(throttle * 100), 20, 30)
	caption(p, "GAS", 15, p.size.y - 12)
	caption(rects.brake, "BRAKE", 16, rects.brake.size.y * .58, accent if braking else Color.WHITE)
	caption(rects.direction, "REV" if reverse else "FWD", 18, rects.direction.size.y * .62, accent)

func caption(r: Rect2, text: String, font_size: int, y: float, color := Color("d9e2dd")) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, r.position + Vector2((r.size.x - width) / 2, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
