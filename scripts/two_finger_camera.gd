extends RefCounted
## Raw-touch geometry, independent of scene state and Android gesture recognizers.
## One eligible finger drags; two eligible fingers only pinch to zoom.
## Call sample once per frame so sequential finger events form one transform.

const MIN_SPAN = 32.0
const MOTION_SLOP = 2.0
var _fingers: Dictionary = {}
var _contacts: Array = []
var _drag_position = Vector2.ZERO
var _span = Vector2.ZERO
var _pinch_length = 0.0

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
	_contacts = _fingers.keys() if _fingers.size() <= 2 else []
	_contacts.sort()
	if _contacts.size() == 1:
		_drag_position = _fingers[_contacts[0]]
	elif _contacts.size() == 2:
		_span = _fingers[_contacts[1]] - _fingers[_contacts[0]]
		_pinch_length = _span.length()

func sample(viewport_size: Vector2) -> Dictionary:
	if not viewport_size.is_finite() or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		_rebase()
		return {}
	if _contacts.is_empty():
		return {}
	var short_axis = maxf(1.0, minf(viewport_size.x, viewport_size.y))
	var scale = short_axis / 720.0
	if _contacts.size() == 1:
		var position: Vector2 = _fingers[_contacts[0]]
		var movement = position - _drag_position
		if movement.length() < MOTION_SLOP * scale:
			return {}
		_drag_position = position
		return {"drag": movement / short_axis, "zoom": 1.0, "twist": 0.0}
	var span: Vector2 = _fingers[_contacts[1]] - _fingers[_contacts[0]]
	var length = span.length()
	var old_length = _pinch_length
	var angular_step = _span.angle_to(span)
	# Follow direction every frame, even when pinch is below its dead zone. Pure
	# rotation must neither move the camera nor poison a later legitimate pinch.
	_span = span
	# Collapsed or crossed contacts establish a fresh baseline; the next stable
	# span change resumes zoom without a discontinuity.
	if length < MIN_SPAN * scale or old_length < MIN_SPAN * scale or absf(angular_step) > PI * 0.5:
		_pinch_length = length
		return {}
	if absf(length - old_length) < MOTION_SLOP * scale:
		return {}
	_pinch_length = length
	return {"drag": Vector2.ZERO, "zoom": length / old_length, "twist": 0.0}
