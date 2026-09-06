extends RefCounted
## Raw-touch geometry, independent of scene state and Android gesture recognizers.
## Call sample once per frame so sequential finger events form one transform.

const MIN_SPAN = 32.0
const MOTION_SLOP = 2.0
var _fingers: Dictionary = {}
var _pair: Array = []
var _center = Vector2.ZERO
var _span = Vector2.ZERO

func touch_down(index: int, position: Vector2, blocked: bool = false) -> void:
	if blocked or not position.is_finite():
		touch_up(index)
		return
	_fingers[index] = position
	_rebase()

func touch_move(index: int, position: Vector2) -> void:
	if _fingers.has(index) and position.is_finite():
		_fingers[index] = position

func touch_up(index: int) -> void:
	if _fingers.erase(index):
		_rebase()

func cancel() -> void:
	_fingers.clear()
	_rebase()

func _rebase() -> void:
	_pair = _fingers.keys() if _fingers.size() == 2 else []
	_pair.sort()
	if _pair.size() == 2:
		_center = (_fingers[_pair[0]] + _fingers[_pair[1]]) * 0.5
		_span = _fingers[_pair[1]] - _fingers[_pair[0]]

func sample(viewport_size: Vector2) -> Dictionary:
	if _pair.size() != 2:
		return {}
	var short_axis = maxf(1.0, minf(viewport_size.x, viewport_size.y))
	var scale = short_axis / 720.0
	var center: Vector2 = (_fingers[_pair[0]] + _fingers[_pair[1]]) * 0.5
	var span: Vector2 = _fingers[_pair[1]] - _fingers[_pair[0]]
	var length = span.length()
	var old_length = _span.length()
	var twist = _span.angle_to(span)
	# Coincident/crossing contacts cannot establish a reliable rotation or scale.
	# Rebase after these and finger-count changes; never clamp a huge camera jump.
	if length < MIN_SPAN * scale or old_length < MIN_SPAN * scale or absf(twist) > PI * 0.5:
		_center = center
		_span = span
		return {}
	var movement = center - _center
	if movement.length() < MOTION_SLOP * scale and absf(length - old_length) < MOTION_SLOP * scale and absf(twist) * old_length * 0.5 < MOTION_SLOP * scale:
		return {}
	_center = center
	_span = span
	return {"drag": movement / short_axis, "zoom": length / old_length, "twist": twist}
