extends Control
## Single inexpensive canvas instrument; all telemetry stays crisp at low 3D scale.
var speed = 0.0
var grounded = 4
var damage = 0.0
var displayed_speed = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var next = lerpf(displayed_speed, speed, 1.0 - exp(-10.0 * delta))
	if absf(next - displayed_speed) > 0.02:
		displayed_speed = next
		queue_redraw()

func _draw() -> void:
	var center = size * 0.5
	var radius = minf(size.x, size.y) * 0.5 - 3.0
	# The lower bezel is cut flat to frame the traction lamps and range readout.
	var bezel = PackedVector2Array()
	for index in range(9):
		var angle = PI * 0.15 + float(index) / 8.0 * PI * 1.70
		bezel.append(center + Vector2(sin(angle), cos(angle)) * radius)
	draw_colored_polygon(bezel, Color("0b171ee0"))
	bezel.append(bezel[0])
	draw_polyline(bezel, Color("b7cbc440"), 1.0, true)
	var start = PI * 0.78
	var finish = PI * 2.22
	var reading = lerpf(start, finish, clampf(displayed_speed / 65.0, 0.006, 1.0))
	draw_arc(center, radius - 7.0, start, finish, 48, Color("59706a"), 2.0, true)
	draw_arc(center, radius - 7.0, start, reading, 48, Color("e5c893"), 3.0, true)
	for index in range(13):
		var angle = lerpf(start, finish, float(index) / 12.0)
		var direction = Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius - 14.0), center + direction * (radius - (20.0 if index % 3 == 0 else 17.0)), Color("c9d2cba5"), 1.0, true)
	var needle = center + Vector2(cos(reading), sin(reading)) * (radius - 7.0)
	draw_circle(needle, 2.7, Color("f5dfb4"))
	for wheel in range(4):
		var lamp = Rect2(center.x - 21.0 + wheel * 11.0, 89.0, 8.0, 3.0)
		draw_rect(lamp, Color("acd4b2") if wheel < grounded else Color("425653"))
	var health_width = 74.0
	draw_line(Vector2(center.x - health_width * 0.5, 117), Vector2(center.x + health_width * 0.5, 117), Color("40504d"), 2.0)
	draw_line(Vector2(center.x - health_width * 0.5, 117), Vector2(center.x - health_width * 0.5 + health_width * (1.0 - damage), 117), Color("d9bd82") if damage < 0.25 else Color("ed9276"), 2.0)
