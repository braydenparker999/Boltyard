extends Control
## Low cost canvas dial: readable against trees, sky and rock without a large HUD.
var speed = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center = size * 0.5
	var radius = minf(size.x, size.y) * 0.5 - 5.0
	draw_circle(center, radius, Color("101b21ce"))
	draw_arc(center, radius - 1.0, 0, TAU, 64, Color("bdcbc731"), 1.0, true)
	var start = PI * 0.78
	var finish = PI * 2.22
	draw_arc(center, radius - 9.0, start, finish, 48, Color("52615b"), 3.0, true)
	draw_arc(center, radius - 9.0, start, lerpf(start, finish, clampf(speed / 65.0, 0.005, 1.0)), 48, Color("d9bd82"), 3.0, true)
	for index in range(13):
		var angle = lerpf(start, finish, float(index) / 12.0)
		var direction = Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius - 15.0), center + direction * (radius - (20.0 if index % 3 == 0 else 18.0)), Color("c9d2cba5"), 1.0, true)
