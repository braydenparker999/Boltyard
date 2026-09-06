extends SceneTree

const Gesture = preload("res://scripts/two_finger_camera.gd")
const VIEWPORT = Vector2(1280, 720)
const CENTER = Vector2(400, 300)
var checks = 0
var failures = 0

# One contact emits drag for Garage/Free; Follow/Trail ignore it in the scene.
# Exactly two only pinch. GUI and guarded-control contacts remain excluded.
# Contact-count changes rebase; three contacts suspend. Crossing and collapse
# cannot jump the camera. Jitter accumulates through a viewport-scaled dead zone.

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func near(actual: float, expected: float) -> bool:
	return is_finite(actual) and absf(actual - expected) < 0.0001

func expect_empty(command: Dictionary, description: String) -> void:
	check(command.is_empty(), description)

func expect_motion(command: Dictionary, drag: Vector2, zoom: float, description: String) -> void:
	if not command.has("drag") or not command.has("zoom") or not command.has("twist"):
		check(false, description + " (missing command metrics)")
		return
	var actual_drag: Vector2 = command.drag
	var matches = near(actual_drag.x, drag.x) and near(actual_drag.y, drag.y)
	matches = matches and near(command.zoom, zoom) and near(command.twist, 0.0)
	check(matches, description + " (received %s)" % str(command))

func single(position: Vector2 = CENTER):
	var gesture = Gesture.new()
	gesture.touch_down(11, position)
	return gesture

func pair(first: Vector2 = Vector2(300, 300), second: Vector2 = Vector2(500, 300)):
	var gesture = single(first)
	gesture.touch_down(27, second)
	return gesture

func rotate_pair(gesture, angle: float, radius: float = 100.0) -> void:
	var offset = Vector2.RIGHT.rotated(angle) * radius
	gesture.touch_move(11, CENTER - offset)
	gesture.touch_move(27, CENTER + offset)

func test_single_drag() -> void:
	var gesture = single()
	expect_empty(gesture.sample(VIEWPORT), "one-finger touchdown starts without camera movement")
	gesture.touch_move(11, CENTER + Vector2(36, -18))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.05, -0.025), 1.0, "one finger provides horizontal orbit and vertical tilt input")
	expect_empty(gesture.sample(VIEWPORT), "a drag is consumed exactly once")
	gesture.touch_move(11, CENTER + Vector2(18, 18))
	expect_motion(gesture.sample(VIEWPORT), Vector2(-0.025, 0.05), 1.0, "drag direction can reverse from the last emitted position")
	gesture.touch_up(11)
	gesture.touch_move(11, Vector2.ZERO)
	expect_empty(gesture.sample(VIEWPORT), "released fingers cannot move the camera")

func test_pinch_only() -> void:
	var gesture = pair()
	expect_empty(gesture.sample(VIEWPORT), "joining a second finger starts pinch without initial movement")
	gesture.touch_move(11, Vector2(280, 300))
	gesture.touch_move(27, Vector2(520, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.2, "symmetric expansion zooms without dragging or twisting")
	expect_empty(gesture.sample(VIEWPORT), "a pinch is consumed exactly once")
	gesture.touch_move(11, Vector2(304, 300))
	gesture.touch_move(27, Vector2(496, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 0.8, "pinch ratio uses the previous emitted span")
	gesture = pair()
	gesture.touch_move(11, Vector2(336, 282))
	gesture.touch_move(27, Vector2(536, 282))
	expect_empty(gesture.sample(VIEWPORT), "two-finger translation never drags or pans the camera")
	gesture = pair()
	rotate_pair(gesture, deg_to_rad(30))
	expect_empty(gesture.sample(VIEWPORT), "two-finger rotation never orbits or tilts the camera")
	gesture = pair()
	var offset = Vector2.RIGHT.rotated(deg_to_rad(-20)) * 125.0
	gesture.touch_move(11, CENTER + Vector2(18, 36) - offset)
	gesture.touch_move(27, CENTER + Vector2(18, 36) + offset)
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.25, "combined translation and rotation preserve only the pinch component")
	gesture = pair()
	gesture.touch_move(27, Vector2(540, 300))
	gesture.touch_move(11, Vector2(260, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.4, "sequential finger events batch into one symmetric pinch")

func test_dead_zone_and_rotation() -> void:
	var gesture = single()
	for displacement in [0.4, 0.9, 1.4]:
		gesture.touch_move(11, CENTER + Vector2(displacement, 0))
		expect_empty(gesture.sample(VIEWPORT), "single-finger jitter of %.1f pixels remains silent" % displacement)
	gesture.touch_move(11, CENTER + Vector2(4, 0))
	expect_motion(gesture.sample(VIEWPORT), Vector2(4.0 / 720.0, 0), 1.0, "small single-finger movements accumulate into a deliberate drag")
	gesture = pair()
	gesture.touch_move(11, Vector2(299.5, 300))
	gesture.touch_move(27, Vector2(500.5, 300))
	expect_empty(gesture.sample(VIEWPORT), "a one-pixel span change remains inside the pinch dead zone")
	gesture.touch_move(11, Vector2(298, 300))
	gesture.touch_move(27, Vector2(502, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.02, "small pinch changes accumulate against the original span")
	gesture = pair()
	for degrees in [45, 90, 135, 179, -179]:
		rotate_pair(gesture, deg_to_rad(degrees))
		expect_empty(gesture.sample(VIEWPORT), "rotation through %d degrees remains silent" % degrees)
	rotate_pair(gesture, deg_to_rad(-170), 125.0)
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.25, "pinch responds after cumulative rotation and angle wrap")

func test_crossed_and_collapsed_contacts() -> void:
	var gesture = pair()
	gesture.touch_move(11, Vector2(550, 300))
	gesture.touch_move(27, Vector2(250, 300))
	expect_empty(gesture.sample(VIEWPORT), "contacts crossing between samples cannot create a zoom jump")
	gesture.touch_move(11, Vector2(565, 312))
	gesture.touch_move(27, Vector2(235, 312))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.1, "pinch resumes from rebased geometry after contacts cross")
	gesture = pair()
	gesture.touch_move(11, Vector2(390, 300))
	gesture.touch_move(27, Vector2(410, 300))
	expect_empty(gesture.sample(VIEWPORT), "nearly touching fingers cannot create an extreme zoom")
	gesture.touch_move(11, Vector2(400, 310))
	gesture.touch_move(27, Vector2(400, 310))
	expect_empty(gesture.sample(VIEWPORT), "coincident fingers remain neutral without division by zero")
	gesture.touch_move(11, Vector2(300, 310))
	gesture.touch_move(27, Vector2(500, 310))
	expect_empty(gesture.sample(VIEWPORT), "separating collapsed fingers establishes a fresh baseline")
	gesture.touch_move(11, Vector2(280, 310))
	gesture.touch_move(27, Vector2(520, 310))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.2, "pinch resumes normally after collapsed contacts separate")

func test_contact_handoff() -> void:
	var gesture = single(Vector2(300, 300))
	gesture.touch_move(11, Vector2(320, 300))
	gesture.touch_down(27, Vector2(520, 300))
	expect_empty(gesture.sample(VIEWPORT), "adding the second finger discards pending single-finger drag")
	gesture.touch_move(11, Vector2(310, 300))
	gesture.touch_move(27, Vector2(530, 300))
	gesture.touch_up(27)
	expect_empty(gesture.sample(VIEWPORT), "lifting the second finger discards pending pinch and rebases drag")
	gesture.touch_move(11, Vector2(328, 264))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, -0.05), 1.0, "the remaining finger can immediately orbit and tilt from its current position")
	gesture.touch_down(42, Vector2(528, 264))
	expect_empty(gesture.sample(VIEWPORT), "a replacement second finger joins without a jump")
	gesture.touch_move(11, Vector2(318, 264))
	gesture.touch_move(42, Vector2(538, 264))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.1, "a replacement pair zooms only from its new span")
	gesture.touch_up(11)
	gesture.touch_move(42, Vector2(520, 282))
	expect_motion(gesture.sample(VIEWPORT), Vector2(-0.025, 0.025), 1.0, "lifting the lower contact ID also hands drag to the remaining finger")
	gesture.touch_up(999)
	gesture.touch_move(999, Vector2(-1000, -1000))
	expect_empty(gesture.sample(VIEWPORT), "unknown contact events cannot create camera fingers")

func test_gui_and_third_finger() -> void:
	var gesture = Gesture.new()
	gesture.touch_down(11, Vector2(300, 300), true)
	gesture.touch_move(11, Vector2(280, 300))
	expect_empty(gesture.sample(VIEWPORT), "a GUI-owned finger stays excluded when dragged away from its control")
	gesture.touch_down(27, Vector2(500, 300))
	gesture.touch_move(27, Vector2(518, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, 0), 1.0, "one camera finger works while a drive-control finger remains down")
	gesture.touch_move(27, Vector2(536, 300))
	gesture.touch_up(11)
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, 0), 1.0, "lifting a GUI finger preserves pending camera drag")
	gesture.touch_down(42, Vector2(736, 300))
	gesture.touch_down(99, Vector2(50, 600), true)
	gesture.touch_move(27, Vector2(526, 300))
	gesture.touch_move(42, Vector2(746, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.1, "two camera fingers can pinch while a GUI-owned third finger is down")
	gesture = pair()
	gesture.touch_move(11, Vector2(280, 300))
	gesture.touch_move(27, Vector2(520, 300))
	gesture.touch_down(42, Vector2(700, 300))
	expect_empty(gesture.sample(VIEWPORT), "a third camera finger suspends and discards pending pinch")
	gesture.touch_move(11, Vector2(250, 330))
	gesture.touch_move(27, Vector2(550, 330))
	gesture.touch_move(42, Vector2(720, 350))
	expect_empty(gesture.sample(VIEWPORT), "three camera fingers remain neutral while moving")
	gesture.touch_up(42)
	expect_empty(gesture.sample(VIEWPORT), "returning from three fingers to two starts without a jump")
	gesture.touch_move(11, Vector2(235, 330))
	gesture.touch_move(27, Vector2(565, 330))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.1, "the restored pair zooms from its current positions")

func test_multiple_control_ownership() -> void:
	var gesture = Gesture.new()
	gesture.touch_down(91, Vector2(60, 648), true)
	gesture.touch_down(92, Vector2(1210, 640), true)
	gesture.touch_down(93, Vector2(60, 592), true)
	gesture.touch_move(91, Vector2(300, 300))
	gesture.touch_move(92, Vector2(500, 300))
	gesture.touch_move(93, Vector2(400, 300))
	expect_empty(gesture.sample(VIEWPORT), "steering, GO, and a guarded near miss stay excluded after leaving their controls")
	gesture.touch_down(11, Vector2(300, 300))
	gesture.touch_move(11, Vector2(318, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, 0), 1.0, "one Free-camera finger remains independent of three held control contacts")
	gesture.touch_down(27, Vector2(518, 300))
	gesture.touch_move(11, Vector2(308, 300))
	gesture.touch_move(27, Vector2(528, 300))
	gesture.touch_up(91)
	gesture.touch_up(92)
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.1, "releasing simultaneous steering and GO preserves the independent pending pinch")
	gesture.touch_up(11)
	gesture.touch_up(27)
	gesture.touch_up(93)
	gesture.touch_down(93, CENTER)
	gesture.touch_move(93, CENTER + Vector2(18, 0))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, 0), 1.0, "a released guarded contact ID can later begin a fresh scenery gesture")

func test_cancel_and_scaling() -> void:
	var gesture = single()
	gesture.touch_move(11, CENTER + Vector2(30, 0))
	gesture.cancel()
	expect_empty(gesture.sample(VIEWPORT), "cancel clears pending camera motion")
	gesture.touch_move(11, Vector2.ZERO)
	expect_empty(gesture.sample(VIEWPORT), "cancelled contacts stay inactive until a fresh touchdown")
	gesture.touch_down(11, CENTER)
	gesture.touch_move(11, CENTER + Vector2(18, 0))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, 0), 1.0, "a reused contact ID works normally after cancellation")
	var large_viewport = VIEWPORT * 2
	gesture = single(CENTER * 2)
	gesture.touch_move(11, CENTER * 2 + Vector2(72, -36))
	expect_motion(gesture.sample(large_viewport), Vector2(0.05, -0.025), 1.0, "relative single-finger drag is invariant under viewport scaling")
	gesture = single(CENTER * 2)
	gesture.touch_move(11, CENTER * 2 + Vector2(3, 0))
	expect_empty(gesture.sample(large_viewport), "the single-finger jitter dead zone scales with viewport size")
	gesture.touch_move(11, CENTER * 2 + Vector2(8, 0))
	expect_motion(gesture.sample(large_viewport), Vector2(8.0 / 1440.0, 0), 1.0, "scaled jitter accumulates into the full normalized drag")
	gesture = pair(Vector2(600, 600), Vector2(1000, 600))
	gesture.touch_move(11, Vector2(780, 600))
	gesture.touch_move(27, Vector2(820, 600))
	expect_empty(gesture.sample(large_viewport), "safe pinch separation scales with viewport size")
	gesture = single()
	gesture.touch_move(11, CENTER + Vector2(18, 0))
	expect_empty(gesture.sample(Vector2.ZERO), "an unavailable viewport cannot produce invalid camera input")
	expect_empty(gesture.sample(VIEWPORT), "restoring the viewport does not replay discarded movement")
	gesture.touch_move(11, Vector2(INF, 0))
	expect_empty(gesture.sample(VIEWPORT), "invalid touch positions cannot corrupt the camera baseline")

func run() -> void:
	test_single_drag()
	test_pinch_only()
	test_dead_zone_and_rotation()
	test_crossed_and_collapsed_contacts()
	test_contact_handoff()
	test_gui_and_third_finger()
	test_multiple_control_ownership()
	test_cancel_and_scaling()
	print("CAMERA GESTURES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
