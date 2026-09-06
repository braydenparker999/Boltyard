extends SceneTree

const Gesture = preload("res://scripts/two_finger_camera.gd")
const VIEWPORT = Vector2(1280, 720)
const CENTER = Vector2(400, 300)
var checks = 0
var failures = 0

# Contract: touch events update contact positions; sample() emits at most one
# command for their combined geometry. The second eligible contact establishes
# the baseline immediately. Drag is centroid displacement / viewport short axis,
# zoom is the span ratio, and twist is the shortest signed angle in radians.
#
# Exactly two eligible contacts are required. GUI-blocked contacts never join
# the camera gesture. Changes to the eligible pair discard accumulated motion
# and rebase; three eligible contacts suspend motion. A separation below 32
# virtual pixels (720-pixel short axis) or a >90-degree step freezes/rebases.
# Recovery from a collapsed pair also rebases before producing more motion.
# Motion below the 2-virtual-pixel dead zone accumulates against the last emitted
# baseline. Pure pan, pinch, and twist commands contain all three metrics.

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

func expect_motion(command: Dictionary, drag: Vector2, zoom: float, twist: float, description: String) -> void:
	var complete = command.has("drag") and command.has("zoom") and command.has("twist")
	if not complete:
		check(false, description + " (missing command metrics)")
		return
	var actual_drag: Vector2 = command.drag
	var matches = near(actual_drag.x, drag.x) and near(actual_drag.y, drag.y)
	matches = matches and near(command.zoom, zoom) and near(command.twist, twist)
	check(matches, description + " (received %s)" % str(command))

func pair(first: Vector2 = Vector2(300, 300), second: Vector2 = Vector2(500, 300)):
	var gesture = Gesture.new()
	gesture.touch_down(11, first)
	gesture.touch_down(27, second)
	return gesture

func rotate_pair(gesture, angle: float, radius: float = 100.0) -> void:
	var offset = Vector2.RIGHT.rotated(angle) * radius
	gesture.touch_move(11, CENTER - offset)
	gesture.touch_move(27, CENTER + offset)

func test_basic_geometry() -> void:
	var gesture = pair()
	expect_empty(gesture.sample(VIEWPORT), "joining a second finger emits no initial camera motion")
	gesture.touch_move(11, Vector2(280, 300))
	gesture.touch_move(27, Vector2(520, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.2, 0.0, "symmetric expansion pinches without dragging or twisting")
	expect_empty(gesture.sample(VIEWPORT), "sampling twice consumes the emitted motion exactly once")
	gesture.touch_move(11, Vector2(304, 300))
	gesture.touch_move(27, Vector2(496, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 0.8, 0.0, "pinch ratio uses the previous emitted span")

	gesture = pair()
	gesture.touch_move(11, Vector2(336, 282))
	gesture.touch_move(27, Vector2(536, 282))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.05, -0.025), 1.0, 0.0, "centroid drag uses the viewport short axis for both coordinates")

	gesture = pair()
	rotate_pair(gesture, deg_to_rad(30))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.0, deg_to_rad(30), "rotation around a fixed centroid produces only signed twist")

	gesture = pair()
	var offset = Vector2.RIGHT.rotated(deg_to_rad(-20)) * 125.0
	gesture.touch_move(11, CENTER + Vector2(18, 36) - offset)
	gesture.touch_move(27, CENTER + Vector2(18, 36) + offset)
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, 0.05), 1.25, deg_to_rad(-20), "one sample preserves simultaneous translation, pinch, and twist")

func test_event_batching_and_dead_zone() -> void:
	var gesture = pair()
	# The first move temporarily changes the centroid. Only final frame geometry
	# is sampled, so the intermediate one-contact position must not leak through.
	gesture.touch_move(27, Vector2(540, 300))
	gesture.touch_move(11, Vector2(260, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.4, 0.0, "sequential finger events batch into a symmetric pinch")

	gesture = pair()
	for displacement in [0.4, 0.9, 1.4]:
		gesture.touch_move(11, Vector2(300 + displacement, 300))
		gesture.touch_move(27, Vector2(500 + displacement, 300))
		expect_empty(gesture.sample(VIEWPORT), "subthreshold pan jitter of %.1f pixels remains silent" % displacement)
	gesture.touch_move(11, Vector2(304, 300))
	gesture.touch_move(27, Vector2(504, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2(4.0 / 720.0, 0), 1.0, 0.0, "small movement accumulates until the dead zone is exceeded")

	gesture = pair()
	gesture.touch_move(11, Vector2(299.5, 300))
	gesture.touch_move(27, Vector2(500.5, 300))
	expect_empty(gesture.sample(VIEWPORT), "a one-pixel span change remains inside the pinch dead zone")
	gesture.touch_move(11, Vector2(298, 300))
	gesture.touch_move(27, Vector2(502, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.02, 0.0, "small pinch changes accumulate against the original span")

	gesture = pair()
	rotate_pair(gesture, 0.005)
	expect_empty(gesture.sample(VIEWPORT), "subpixel rotation arc remains inside the twist dead zone")
	rotate_pair(gesture, 0.05)
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.0, 0.05, "rotation accumulates until its arc exceeds the dead zone")

func test_angle_wrap_and_crossing() -> void:
	var offset = Vector2.RIGHT.rotated(deg_to_rad(179)) * 100.0
	var gesture = pair(CENTER - offset, CENTER + offset)
	rotate_pair(gesture, deg_to_rad(-179))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.0, deg_to_rad(2), "twist wraps from positive PI to negative PI by the short positive arc")
	offset = Vector2.RIGHT.rotated(deg_to_rad(-179)) * 100.0
	gesture = pair(CENTER - offset, CENTER + offset)
	rotate_pair(gesture, deg_to_rad(179))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.0, deg_to_rad(-2), "twist wraps from negative PI to positive PI by the short negative arc")

	gesture = pair()
	gesture.touch_move(11, Vector2(500, 300))
	gesture.touch_move(27, Vector2(300, 300))
	expect_empty(gesture.sample(VIEWPORT), "contacts crossing between samples cannot cause a half-turn or zoom jump")
	gesture.touch_move(11, Vector2(500, 312))
	gesture.touch_move(27, Vector2(300, 312))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0, 12.0 / 720.0), 1.0, 0.0, "motion after a crossing starts from its rebased geometry")

	gesture = pair()
	rotate_pair(gesture, deg_to_rad(120))
	expect_empty(gesture.sample(VIEWPORT), "an angular step greater than ninety degrees rebases")
	rotate_pair(gesture, deg_to_rad(125))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.0, deg_to_rad(5), "ordinary twist resumes after an angular discontinuity")

func test_collapsed_contacts() -> void:
	var gesture = pair()
	gesture.touch_move(11, Vector2(390, 300))
	gesture.touch_move(27, Vector2(410, 300))
	expect_empty(gesture.sample(VIEWPORT), "a pair below the safe separation freezes without an extreme pinch")
	gesture.touch_move(11, Vector2(400, 310))
	gesture.touch_move(27, Vector2(400, 310))
	expect_empty(gesture.sample(VIEWPORT), "coincident contacts remain neutral without division by zero")
	gesture.touch_move(11, Vector2(300, 310))
	gesture.touch_move(27, Vector2(500, 310))
	expect_empty(gesture.sample(VIEWPORT), "recovering a safe separation establishes a fresh baseline")
	gesture.touch_move(11, Vector2(280, 310))
	gesture.touch_move(27, Vector2(520, 310))
	expect_motion(gesture.sample(VIEWPORT), Vector2.ZERO, 1.2, 0.0, "pinch resumes normally after collapsed contacts separate")

func test_contact_lifecycle() -> void:
	var gesture = Gesture.new()
	gesture.touch_down(11, Vector2(50, 50))
	gesture.touch_move(11, Vector2(300, 300))
	expect_empty(gesture.sample(VIEWPORT), "one finger never moves the camera")
	gesture.touch_down(27, Vector2(500, 300))
	gesture.touch_move(11, Vector2(310, 300))
	gesture.touch_move(27, Vector2(510, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2(10.0 / 720.0, 0), 1.0, 0.0, "the second touchdown establishes a baseline before the first sample")
	gesture.touch_up(27)
	gesture.touch_move(11, Vector2(600, 300))
	expect_empty(gesture.sample(VIEWPORT), "lifting one finger immediately stops camera gestures")
	gesture.touch_down(42, Vector2(800, 300))
	expect_empty(gesture.sample(VIEWPORT), "a replacement second finger joins without a jump")
	gesture.touch_move(11, Vector2(618, 300))
	gesture.touch_move(42, Vector2(818, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2(18.0 / 720.0, 0), 1.0, 0.0, "a replacement pair emits only its new motion")

	gesture = pair()
	gesture.touch_move(11, Vector2(330, 300))
	gesture.touch_move(27, Vector2(530, 300))
	gesture.touch_up(27)
	gesture.touch_down(42, Vector2(700, 300))
	expect_empty(gesture.sample(VIEWPORT), "lifting and rejoining before sampling discards stale pair motion")
	gesture.touch_up(999)
	gesture.touch_move(999, Vector2(-1000, -1000))
	expect_empty(gesture.sample(VIEWPORT), "unknown contact events do not create eligible fingers")

func test_gui_and_third_finger() -> void:
	var gesture = Gesture.new()
	gesture.touch_down(11, Vector2(300, 300), true)
	gesture.touch_down(27, Vector2(500, 300))
	gesture.touch_move(11, Vector2(280, 300))
	gesture.touch_move(27, Vector2(520, 300))
	expect_empty(gesture.sample(VIEWPORT), "a GUI-owned finger cannot form a camera pair")
	gesture.touch_down(42, Vector2(720, 300))
	gesture.touch_move(27, Vector2(538, 300))
	gesture.touch_move(42, Vector2(738, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2(18.0 / 720.0, 0), 1.0, 0.0, "two eligible fingers work while a GUI-owned finger remains down")

	gesture = pair()
	gesture.touch_down(99, Vector2(700, 600), true)
	gesture.touch_move(99, Vector2(50, 20))
	gesture.touch_move(11, Vector2(300, 312))
	gesture.touch_move(27, Vector2(500, 312))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0, 12.0 / 720.0), 1.0, 0.0, "adding and moving a GUI finger does not suspend the active pair")
	gesture.touch_move(11, Vector2(300, 324))
	gesture.touch_move(27, Vector2(500, 324))
	gesture.touch_up(99)
	expect_motion(gesture.sample(VIEWPORT), Vector2(0, 12.0 / 720.0), 1.0, 0.0, "lifting a GUI finger preserves pending eligible-pair motion")

	gesture = pair()
	gesture.touch_move(11, Vector2(320, 300))
	gesture.touch_move(27, Vector2(520, 300))
	gesture.touch_down(42, Vector2(700, 300))
	expect_empty(gesture.sample(VIEWPORT), "a third eligible finger suspends and discards pending pair motion")
	gesture.touch_move(11, Vector2(350, 330))
	gesture.touch_move(27, Vector2(550, 330))
	gesture.touch_move(42, Vector2(720, 350))
	expect_empty(gesture.sample(VIEWPORT), "three eligible fingers remain neutral while moving")
	gesture.touch_up(42)
	expect_empty(gesture.sample(VIEWPORT), "returning from three fingers to two rebases without a jump")
	gesture.touch_move(11, Vector2(359, 330))
	gesture.touch_move(27, Vector2(559, 330))
	expect_motion(gesture.sample(VIEWPORT), Vector2(9.0 / 720.0, 0), 1.0, 0.0, "the restored pair responds from its current positions")

func test_cancel_and_viewport_scaling() -> void:
	var gesture = pair()
	gesture.touch_move(11, Vector2(320, 300))
	gesture.touch_move(27, Vector2(520, 300))
	gesture.cancel()
	expect_empty(gesture.sample(VIEWPORT), "cancel clears pending gesture motion")
	gesture.touch_move(11, Vector2(350, 300))
	gesture.touch_move(27, Vector2(550, 300))
	expect_empty(gesture.sample(VIEWPORT), "cancelled contacts stay inactive until fresh touchdown events")
	gesture.touch_down(11, Vector2(300, 300))
	gesture.touch_down(27, Vector2(500, 300))
	gesture.touch_move(11, Vector2(318, 300))
	gesture.touch_move(27, Vector2(518, 300))
	expect_motion(gesture.sample(VIEWPORT), Vector2(0.025, 0), 1.0, 0.0, "fresh contacts work after cancel with reused contact IDs")

	var large_viewport = VIEWPORT * 2
	gesture = pair(Vector2(600, 600), Vector2(1000, 600))
	gesture.touch_move(11, Vector2(672, 564))
	gesture.touch_move(27, Vector2(1072, 564))
	expect_motion(gesture.sample(large_viewport), Vector2(0.05, -0.025), 1.0, 0.0, "equivalent relative motion is invariant under viewport scaling")
	gesture = pair(Vector2(600, 600), Vector2(1000, 600))
	gesture.touch_move(11, Vector2(603, 600))
	gesture.touch_move(27, Vector2(1003, 600))
	expect_empty(gesture.sample(large_viewport), "the jitter dead zone scales with viewport size")
	gesture.touch_move(11, Vector2(608, 600))
	gesture.touch_move(27, Vector2(1008, 600))
	expect_motion(gesture.sample(large_viewport), Vector2(8.0 / 1440.0, 0), 1.0, 0.0, "scaled jitter still accumulates into the full normalized displacement")
	gesture = pair(Vector2(600, 600), Vector2(1000, 600))
	gesture.touch_move(11, Vector2(780, 600))
	gesture.touch_move(27, Vector2(820, 600))
	expect_empty(gesture.sample(large_viewport), "safe contact separation scales with viewport size")

func run() -> void:
	test_basic_geometry()
	test_event_batching_and_dead_zone()
	test_angle_wrap_and_crossing()
	test_collapsed_contacts()
	test_contact_lifecycle()
	test_gui_and_third_finger()
	test_cancel_and_viewport_scaling()
	print("CAMERA GESTURES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
