extends Node3D

const LEGACY_PATH = "user://offroad_setup.json"
const GARAGE_PATH = "user://offroad_garage_v3.json"
const PAINTS = ["c96c38", "c9b78e", "647263", "537781", "ede7d6", "383f47"]
const INK = Color("172126")
const PANEL = Color("18232aee")
const MUTED = Color("a6b6b8")
const PAPER = Color("f3efdf")
const ACCENT = Color("efbd71")
const ACTIONS = ["off_left", "off_right", "off_go", "off_reverse", "off_brake"]
const CAMP = Vector3(0, 1.5, 8)

var crawl_mode = false
var crawl_section = 0
var throttle_limit = 0.35
var crawl_controls: VBoxContainer
var crawl_loads: Label
var course_button: Button
var settings: Dictionary = {}
var builds: Dictionary = {}
var selected_vehicle = "pickup"
var discovered: Array[String] = []
var destination = ""
var quality = 0
var truck
var world
var trail_dust
var camera: Camera3D
var ui: Control
var garage_panel: PanelContainer
var garage_overlay: Control
var garage_footer: HBoxContainer
var drive_panel: Control
var header: PanelContainer
var mode_button: Button
var pause_button: Button
var xray_button: Button
var map_button: Button
var speed_label: Label
var drive_status: Label
var drive_damage: Label
var navigation_label: Label
var garage_status: Label
var title_label: Label
var vehicle_description: Label
var message: Label
var drive_low: Button
var drive_diff: Button
var front_diff: Button
var rear_diff: Button
var camera_toolbar: PanelContainer
var camera_drag_button: Button
var camera_follow_button: Button
var camera_hint: Label
var pause_overlay: PanelContainer
var map_overlay: PanelContainer
var map_canvas: Control
var map_status: Label
var map_rows: Dictionary = {}
var slider_nodes: Dictionary = {}
var value_labels: Dictionary = {}
var toggle_nodes: Dictionary = {}
var vehicle_buttons: Dictionary = {}
var paint_buttons: Dictionary = {}
var part_selectors: Dictionary = {}
var part_descriptions: Dictionary = {}
var touch_buttons: Dictionary = {}
var tuning_content: VBoxContainer
var tuning_button: Button
var quality_picker: OptionButton
var current_telemetry: Dictionary = {}
var landmarks: Array = []
var driving = false
var portrait = false
var xray = false
var updating_ui = false
var backgrounded = false
var help_open = false
var toast_remaining = 0.0
var tuning_delay = -1.0
var telemetry_delay = 0.0
var recovery_cooldown = 0.0
var orbit = 2.24
var orbit_distance = 9.3
var orbit_pitch = 0.49
var drive_distance = 8.2
var drive_pitch = 0.30
var drive_orbit = 0.0
var camera_follow = true
var camera_pan_mode = false
var garage_pan = Vector2.ZERO
var drive_pan = Vector2.ZERO
var camera_gestures = preload("res://scripts/two_finger_camera.gd").new()
var camera_save_delay = -1.0
var camera_target = Vector3.ZERO
var follow_direction = Vector3.BACK
var did_position_camera = false
var save_problem = ""
var has_migrated = false
var layout_frames_pending = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	setup_input()
	load_settings()
	settings = VehicleCatalog.compose(builds[selected_vehicle])
	truck = OffroadTruck.new()
	truck.name = "Truck"
	truck.process_mode = Node.PROCESS_MODE_PAUSABLE
	truck.configure(settings)
	world = OffroadWorld.new()
	world.name = "Trail"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.configure(truck.core)
	world.set_quality(quality)
	add_child(world)
	add_child(truck)
	landmarks = world.get_landmarks()
	validate_exploration()
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 52.0
	camera.near = 0.08
	camera.far = 800.0
	add_child(camera)
	trail_dust = preload("res://scripts/trail_dust.gd").new()
	add_child(trail_dust)
	apply_display_quality()
	build_ui()
	sync_controls()
	get_viewport().size_changed.connect(layout_ui)
	layout_ui()
	if not save_problem.is_empty():
		toast(save_problem)
	elif has_migrated:
		toast("Your previous pickup tune is here. Equip a part to use its matching settings.")
	else:
		toast("Choose your vehicle, fit your parts, then explore the valley.")
	save_settings()

func setup_input() -> void:
	var keys = {"off_left": [KEY_A, KEY_LEFT], "off_right": [KEY_D, KEY_RIGHT], "off_go": [KEY_W, KEY_UP], "off_reverse": [KEY_S, KEY_DOWN], "off_brake": [KEY_SPACE]}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in keys[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func box(color: Color, radius: int = 14, padding: int = 12) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.content_margin_left = padding
	result.content_margin_right = padding
	result.content_margin_top = padding
	result.content_margin_bottom = padding
	return result

func label(parent: Node, text: String, font_size: int = 17, color: Color = PAPER) -> Label:
	var result = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func button(parent: Node, text: String, callback: Callable, minimum: float = 64.0) -> Button:
	var result = Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(minimum, 46)
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func row(parent: Node, separation: int = 8) -> HBoxContainer:
	var result = HBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	parent.add_child(result)
	return result

func column(parent: Node, separation: int = 8) -> VBoxContainer:
	var result = VBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	parent.add_child(result)
	return result

func accent_button(item: Button) -> void:
	item.add_theme_stylebox_override("normal", box(ACCENT, 10))
	item.add_theme_stylebox_override("hover", box(Color("fbd49a"), 10))
	item.add_theme_stylebox_override("pressed", box(Color("bd8549"), 10))
	item.add_theme_color_override("font_color", INK)
	item.add_theme_color_override("font_hover_color", INK)
	item.add_theme_color_override("font_pressed_color", INK)

func build_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	var theme = Theme.new()
	theme.default_font_size = 16
	for kind in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", kind, box(Color("2b3c43"), 10))
		theme.set_stylebox("hover", kind, box(Color("40565c"), 10))
		theme.set_stylebox("pressed", kind, box(Color("6e7c70"), 10))
		theme.set_color("font_color", kind, PAPER)
	theme.set_stylebox("panel", "PopupMenu", box(Color("18232a"), 12, 12))
	theme.set_color("font_color", "PopupMenu", PAPER)
	theme.set_color("font_color", "CheckButton", PAPER)
	for part in ["slider", "grabber_area", "grabber_area_highlight"]:
		var rail = box(Color("33454c") if part == "slider" else ACCENT, 4, 0)
		rail.content_margin_top = 3
		rail.content_margin_bottom = 3
		theme.set_stylebox(part, "HSlider", rail)
	ui.theme = theme
	header = PanelContainer.new()
	header.add_theme_stylebox_override("panel", box(PANEL, 14, 10))
	ui.add_child(header)
	var header_row = row(header, 8)
	var brand = column(header_row, 0)
	brand.name = "Brand"
	label(brand, "BOLT YARD", 22)
	label(brand, "CRAWLWORKS  /  1.0", 10, ACCENT)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	map_button = button(header_row, "Map", toggle_map, 65)
	xray_button = button(header_row, "X-ray", toggle_xray, 72)
	button(header_row, "?", show_help, 42)
	pause_button = button(header_row, "Pause", toggle_pause, 74)
	pause_button.visible = false
	mode_button = button(header_row, "DRIVE  ›", toggle_mode, 118)
	accent_button(mode_button)
	build_garage()
	build_driving()
	build_pause()
	build_map()
	build_camera_tools()
	message = label(ui, "", 14)
	message.add_theme_stylebox_override("normal", box(Color("172126ef"), 10, 12))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.z_index = 10

func build_garage() -> void:
	garage_panel = PanelContainer.new()
	garage_panel.add_theme_stylebox_override("panel", box(PANEL, 16, 14))
	ui.add_child(garage_panel)
	var content = column(garage_panel, 8)
	var heading = row(content)
	label(heading, "GARAGE", 13, ACCENT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(heading, "3 rigs · Your builds", 12, MUTED)
	var vehicles = row(content, 6)
	for id in VehicleCatalog.VEHICLES:
		var descriptor: Dictionary = VehicleCatalog.VEHICLES[id]
		var item = button(vehicles, descriptor.name, select_vehicle.bind(id), 60)
		item.add_theme_font_size_override("font_size", 14)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vehicle_buttons[id] = item
	vehicle_description = label(content, "", 12, MUTED)
	vehicle_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 100
	content.add_child(scroll)
	var options = column(scroll, 7)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section(options, "TRAIL")
	course_button = button(options, "COPPERLINE  ·  Technical crawling", toggle_course, 0)
	accent_button(course_button)
	button(options, "Fit crawl setup to this rig", fit_crawl_setup, 0)
	section(options, "FINISH")
	var paints = row(options, 6)
	for color in PAINTS:
		var swatch = button(paints, "", select_paint.bind(color), 35)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.custom_minimum_size.y = 38
		swatch.add_theme_stylebox_override("normal", box(Color(color), 8, 4))
		swatch.add_theme_stylebox_override("hover", box(Color(color).lightened(0.2), 8, 4))
		swatch.tooltip_text = ["Rust orange", "Sand", "Forest", "Blue slate", "Ivory", "Graphite"][PAINTS.find(color)]
		paint_buttons[color] = swatch
	section(options, "EQUIPMENT")
	for slot in VehicleCatalog.SLOTS:
		var wrap = column(options, 1)
		label(wrap, VehicleCatalog.SLOT_NAMES[slot], 13, ACCENT)
		var picker = OptionButton.new()
		picker.custom_minimum_size.y = 44
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.fit_to_longest_item = false
		picker.focus_mode = Control.FOCUS_NONE
		picker.item_selected.connect(part_picked.bind(slot))
		wrap.add_child(picker)
		part_selectors[slot] = picker
		var explanation = label(wrap, "", 12, MUTED)
		explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		part_descriptions[slot] = explanation
	tuning_button = button(options, "Fine tuning  +", toggle_tuning, 100)
	tuning_content = column(options, 5)
	tuning_content.hide()
	tuning_slider(tuning_content, "tire_radius", "Tire diameter", "Larger tires add clearance and require more wheel torque.", 0.01)
	tuning_slider(tuning_content, "tire_pressure", "Relative tire pressure", "Carcass stiffness and grip multiplier, not a calibrated pressure.", 0.05)
	tuning_slider(tuning_content, "ride_height", "Suspension height", "More clearance raises the center of gravity.", 0.01)
	tuning_slider(tuning_content, "spring_rate", "Spring rate", "Softer springs flex; stiffer springs carry load.", 1000.0)
	tuning_slider(tuning_content, "damping", "Base damping", "Sets both damper directions until you adjust them individually.", 250.0)
	tuning_slider(tuning_content, "compression_damping", "Compression damping", "Resists wheel movement upward into the body. Lower values absorb ledges more freely.", 250.0)
	tuning_slider(tuning_content, "rebound_damping", "Rebound damping", "Controls how quickly a wheel extends into a hole after compression.", 250.0)
	tuning_slider(tuning_content, "compression_travel", "Compression travel", "Available upward wheel movement before the bump stop engages.", 0.01)
	tuning_slider(tuning_content, "suspension_travel", "Droop travel", "Available downward wheel extension before the rebound stop engages.", 0.01)
	tuning_slider(tuning_content, "engine_torque", "Engine torque", "Changes torque delivered through the tires.", 25.0)
	tuning_slider(tuning_content, "mass", "Vehicle mass", "Total mass, including the selected equipment.", 25.0)
	tuning_slider(tuning_content, "track_width", "Track width", "Wider stance improves stability on side slopes.", 0.05)
	tuning_slider(tuning_content, "wheelbase", "Wheelbase", "A shorter wheelbase clears crests more easily.", 0.05)
	tuning_slider(tuning_content, "body_stiffness", "Chassis stiffness", "Changes how the physical frame resists bending.", 0.05)
	tuning_toggle(tuning_content, "low_range", "Low range")
	tuning_toggle(tuning_content, "locked_diffs", "Locked differentials")
	button(tuning_content, "Use installed parts' tuning", clear_tuning, 100)
	section(options, "DISPLAY")
	quality_picker = OptionButton.new()
	quality_picker.custom_minimum_size.y = 44
	quality_picker.focus_mode = Control.FOCUS_NONE
	for quality_name in ["Performance", "Balanced", "High"]:
		quality_picker.add_item(quality_name)
	quality_picker.item_selected.connect(change_quality)
	options.add_child(quality_picker)
	var quality_note = label(options, "Performance uses a lighter 3D resolution with sharp controls. Balanced and High add detail. Rotate your phone at any time.", 12, MUTED)
	quality_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage_footer = row(content, 7)
	button(garage_footer, "Save build", save_with_toast, 90).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(garage_footer, "Repair & camp", recover, 110).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage_overlay = Control.new()
	garage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(garage_overlay)
	title_label = label(garage_overlay, "", 20)
	title_label.add_theme_stylebox_override("normal", box(PANEL, 10, 10))
	var camera_tools = row(garage_overlay, 6)
	camera_tools.name = "CameraTools"
	button(camera_tools, "Impact test", impact_test, 112)
	garage_status = label(garage_overlay, "", 12, MUTED)
	garage_status.add_theme_stylebox_override("normal", box(PANEL, 10, 10))
	garage_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func section(parent: Node, text: String) -> void:
	var item = label(parent, text, 12, ACCENT)
	item.custom_minimum_size.y = 28
	item.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func tuning_slider(parent: Node, key: String, title: String, explanation: String, step: float) -> void:
	var wrap = column(parent, 0)
	var heading = row(wrap, 2)
	label(heading, title, 14).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value = label(heading, format_value(key), 13, ACCENT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_labels[key] = value
	var slider = HSlider.new()
	slider.min_value = VehicleCatalog.LIMITS[key][0]
	slider.max_value = VehicleCatalog.LIMITS[key][1]
	slider.step = step
	slider.value = settings[key]
	slider.custom_minimum_size.y = 39
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(change_value.bind(key))
	wrap.add_child(slider)
	slider_nodes[key] = slider
	var consequence = label(wrap, explanation, 12, MUTED)
	consequence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func tuning_toggle(parent: Node, key: String, title: String) -> void:
	var item = CheckButton.new()
	item.text = title
	item.custom_minimum_size.y = 46
	item.focus_mode = Control.FOCUS_NONE
	item.toggled.connect(change_toggle.bind(key))
	parent.add_child(item)
	toggle_nodes[key] = item

func build_driving() -> void:
	drive_panel = Control.new()
	drive_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drive_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(drive_panel)
	drive_panel.hide()
	var dashboard = PanelContainer.new()
	dashboard.name = "Dashboard"
	dashboard.add_theme_stylebox_override("panel", box(PANEL, 14, 12))
	drive_panel.add_child(dashboard)
	var readouts = column(dashboard, 2)
	speed_label = label(readouts, "00  km/h", 30)
	drive_status = label(readouts, "4 wheels in contact", 12, MUTED)
	drive_damage = label(readouts, "CHASSIS  100%", 12, ACCENT)
	var navigation = PanelContainer.new()
	navigation.name = "Navigation"
	navigation.add_theme_stylebox_override("panel", box(PANEL, 12, 12))
	drive_panel.add_child(navigation)
	navigation_label = label(navigation, "", 13)
	navigation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var equipment = row(drive_panel, 7)
	equipment.name = "Equipment"
	drive_low = button(equipment, "LOW", toggle_drive_low, 85)
	drive_diff = button(equipment, "LOCKED", toggle_drive_diff, 99)
	button(equipment, "Camp", recover, 76)
	crawl_controls = column(drive_panel, 4)
	crawl_controls.name = "CrawlControls"
	crawl_controls.visible = false
	var throttle_label = label(crawl_controls, "THROTTLE LIMIT  ·  35%", 12, ACCENT)
	var pedal = HSlider.new()
	pedal.min_value = 0.10
	pedal.max_value = 1.0
	pedal.step = 0.05
	pedal.value = throttle_limit
	pedal.custom_minimum_size = Vector2(230, 44)
	pedal.value_changed.connect(func(value):
		throttle_limit = value
		throttle_label.text = "THROTTLE LIMIT  ·  %d%%" % roundi(value * 100))
	crawl_controls.add_child(pedal)
	var axles = row(crawl_controls, 6)
	front_diff = button(axles, "FRONT: LOCK", toggle_axle_diff.bind("front_locked"), 114)
	rear_diff = button(axles, "REAR: LOCK", toggle_axle_diff.bind("rear_locked"), 114)
	front_diff.add_theme_font_size_override("font_size", 13)
	rear_diff.add_theme_font_size_override("font_size", 13)
	crawl_loads = label(crawl_controls, "", 12)
	make_touch_button("Left", "‹", "off_left", Vector2(112, 104))
	make_touch_button("Right", "›", "off_right", Vector2(112, 104))
	make_touch_button("Reverse", "REV", "off_reverse", Vector2(102, 94))
	make_touch_button("Brake", "BRAKE", "off_brake", Vector2(116, 74))
	make_touch_button("Go", "GO", "off_go", Vector2(128, 120))

func make_touch_button(node_name: String, text: String, action: String, dimensions: Vector2) -> void:
	var touch_root = Node2D.new()
	touch_root.name = node_name
	drive_panel.add_child(touch_root)
	var panel = Panel.new()
	panel.size = dimensions
	panel.position = -dimensions / 2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", box(ACCENT if action == "off_go" else Color("20333de5"), 22))
	touch_root.add_child(panel)
	var caption = label(panel, text, 48 if action in ["off_left", "off_right"] else 21, INK if action == "off_go" else PAPER)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var touch = TouchScreenButton.new()
	var shape = RectangleShape2D.new()
	shape.size = dimensions
	touch.shape = shape
	touch.action = action
	touch.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	touch_root.add_child(touch)
	touch_buttons[action] = {"root": touch_root, "panel": panel, "touch": touch, "down": false}

func build_camera_tools() -> void:
	camera_toolbar = PanelContainer.new()
	camera_toolbar.name = "CameraToolbar"
	camera_toolbar.add_theme_stylebox_override("panel", box(PANEL, 12, 8))
	ui.add_child(camera_toolbar)
	var content = column(camera_toolbar, 3)
	var controls = row(content, 6)
	camera_drag_button = button(controls, "Drag: Orbit", toggle_camera_drag, 112)
	camera_follow_button = button(controls, "Follow: on", toggle_camera_follow, 112)
	camera_follow_button.tooltip_text = "Follow turns behind the rig. Off keeps your viewing angle while traveling with it."
	button(controls, "Reset view", reset_camera, 100)
	camera_hint = label(content, "2 fingers · drag to orbit / tilt · pinch to zoom", 11, MUTED)
	update_camera_tools()

func update_camera_tools() -> void:
	if not is_instance_valid(camera_toolbar):
		return
	camera_drag_button.text = "Drag: Pan" if camera_pan_mode else "Drag: Orbit"
	camera_follow_button.visible = driving
	camera_follow_button.text = "Follow: on" if camera_follow else "Follow: off"
	camera_hint.text = "2 fingers · drag to %s · pinch zoom · twist orbit" % ("pan" if camera_pan_mode else "orbit / tilt")
	camera_toolbar.reset_size()

func toggle_camera_drag() -> void:
	camera_gestures.cancel()
	camera_pan_mode = not camera_pan_mode
	update_camera_tools()
	camera_save_delay = 0.6
	toast("Two fingers on the scenery: drag to pan. Pinch zooms; twist orbits." if camera_pan_mode else "Two fingers on the scenery: drag sideways to orbit, up/down to tilt. Pinch zooms.")

func toggle_camera_follow() -> void:
	camera_gestures.cancel()
	if not driving:
		return
	if camera_follow:
		drive_orbit = atan2(follow_direction.x, follow_direction.z)
	camera_follow = not camera_follow
	if camera_follow:
		drive_orbit = 0.0
		drive_pan = Vector2.ZERO
	update_camera_tools()
	camera_save_delay = 0.6
	toast("Camera follows the rig's heading." if camera_follow else "Viewing angle held. The camera still travels with your rig.")

func reset_camera() -> void:
	camera_gestures.cancel()
	if driving:
		drive_distance = 8.2
		drive_pitch = 0.30
		drive_orbit = 0.0
		drive_pan = Vector2.ZERO
		camera_follow = true
	else:
		orbit = 2.24
		orbit_distance = 9.3
		orbit_pitch = 0.49
		garage_pan = Vector2.ZERO
	update_camera_tools()
	camera_save_delay = 0.6
	toast("Camera centered. Follow is on." if driving else "Garage camera centered.")

func camera_touch_blocked(point: Vector2) -> bool:
	# _input runs before GUI dispatch. Test actual controls on finger-down and
	# keep that ownership until lift so steering/pedal/slider drags stay theirs.
	if not is_instance_valid(ui) or backgrounded or help_open or get_tree().paused:
		return true
	for panel in [header, garage_panel, camera_toolbar]:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(point):
			return true
	if not driving:
		return garage_overlay.get_node("CameraTools").get_global_rect().has_point(point)
	for name in ["Dashboard", "Navigation", "Equipment", "CrawlControls"]:
		var control: Control = drive_panel.get_node(name)
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	for action in touch_buttons:
		if touch_buttons[action].panel.get_global_rect().has_point(point):
			return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled or not event.pressed:
			camera_gestures.touch_up(event.index)
		else:
			camera_gestures.touch_down(event.index, event.position, camera_touch_blocked(event.position))
	elif event is InputEventScreenDrag:
		camera_gestures.touch_move(event.index, event.position)

func apply_camera_gesture(gesture: Dictionary) -> void:
	if gesture.is_empty():
		return
	var drag: Vector2 = gesture.drag
	var yaw_delta = -float(gesture.twist) - (drag.x * TAU if not camera_pan_mode else 0.0)
	var distance = drive_distance if driving else orbit_distance
	# Panning moves the scene with your fingers in the camera's horizontal / up
	# plane. Bounds keep Reset discoverable even after an accidental long drag.
	if camera_pan_mode:
		var movement = Vector2(-drag.x, drag.y) * distance * 1.6
		if driving:
			drive_pan = (drive_pan + movement).limit_length(5.0)
		else:
			garage_pan = (garage_pan + movement).limit_length(4.0)
	if driving:
		drive_distance = clampf(drive_distance / float(gesture.zoom), 3.0, 20.0)
		if not camera_pan_mode:
			drive_pitch = clampf(drive_pitch + drag.y * PI, 0.10, 1.28)
		if absf(yaw_delta) > 0.0001:
			if camera_follow:
				drive_orbit = atan2(follow_direction.x, follow_direction.z)
				camera_follow = false
			drive_orbit = wrapf(drive_orbit + yaw_delta, -PI, PI)
	else:
		orbit_distance = clampf(orbit_distance / float(gesture.zoom), 3.2, 20.0)
		if not camera_pan_mode:
			orbit_pitch = clampf(orbit_pitch + drag.y * PI, 0.10, 1.28)
		orbit = wrapf(orbit + yaw_delta, -PI, PI)
	update_camera_tools()
	camera_save_delay = 0.8

func build_pause() -> void:
	pause_overlay = PanelContainer.new()
	pause_overlay.z_index = 20
	pause_overlay.add_theme_stylebox_override("panel", box(Color("111c23fa"), 18, 24))
	ui.add_child(pause_overlay)
	var content = column(pause_overlay, 14)
	label(content, "Trail paused", 26)
	label(content, "Your vehicle will be right here.", 14, MUTED)
	accent_button(button(content, "Keep exploring", toggle_pause, 270))
	button(content, "Return to garage", pause_to_garage, 270)
	pause_overlay.hide()

func build_map() -> void:
	map_overlay = PanelContainer.new()
	map_overlay.z_index = 21
	map_overlay.add_theme_stylebox_override("panel", box(Color("111c23fb"), 18, 18))
	ui.add_child(map_overlay)
	var content = column(map_overlay, 9)
	var heading = row(content)
	label(heading, "VALLEY MAP", 18).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading, "Close", toggle_map, 70)
	map_status = label(content, "", 12, ACCENT)
	map_canvas = ExplorationMap.new()
	map_canvas.custom_minimum_size = Vector2(180, 180)
	map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_canvas.configure(truck.core, landmarks)
	map_canvas.destination_selected.connect(select_destination)
	content.add_child(map_canvas)
	var info = label(content, "Tap a marker or destination. Follow the compass; discover each place by driving there.", 12, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var destinations = GridContainer.new()
	destinations.name = "Destinations"
	destinations.columns = 2
	destinations.add_theme_constant_override("h_separation", 7)
	destinations.add_theme_constant_override("v_separation", 7)
	content.add_child(destinations)
	for landmark in landmarks:
		var item = button(destinations, landmark.name, select_destination.bind(str(landmark.id)), 100)
		item.add_theme_font_size_override("font_size", 13)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item.tooltip_text = str(landmark.get("description", ""))
		map_rows[str(landmark.id)] = item
	map_overlay.hide()

func layout_ui() -> void:
	if not is_instance_valid(ui):
		return
	clear_controls()
	# Wrapped labels need their new width before their minimum height is valid.
	# Reapply the requested bounds after container/text layout settles, rather
	# than retaining a panel size clamped against the previous orientation.
	layout_frames_pending = 4
	place_ui()
	did_position_camera = false

func place_ui() -> void:
	var extent = get_viewport().get_visible_rect().size
	portrait = extent.y > extent.x
	var margin = 16.0 if portrait else 20.0
	header.position = Vector2(margin, 16)
	header.size = Vector2(extent.x - margin * 2, 66)
	# Keep the header within the smallest supported portrait viewport.
	var brand = header.get_child(0).get_node("Brand")
	brand.visible = not driving or not portrait
	mode_button.custom_minimum_size.x = 108 if portrait else 118
	xray_button.custom_minimum_size.x = 65
	if portrait:
		var sheet_y = maxf(420, extent.y * 0.53)
		garage_panel.position = Vector2(margin, sheet_y)
		garage_panel.size = Vector2(extent.x - margin * 2, extent.y - sheet_y - 16)
		garage_overlay.position = Vector2(margin, 96)
		garage_overlay.size = Vector2(extent.x - margin * 2, sheet_y - 106)
		garage_overlay.get_node("CameraTools").position = Vector2(0, sheet_y - 220)
		garage_status.position = Vector2(0, sheet_y - 166)
		garage_status.size = Vector2(extent.x - margin * 2, 48)
		message.position = Vector2(285, 390) if driving else Vector2(margin, 151)
		message.size = Vector2(extent.x - margin - 285, 78) if driving else Vector2(extent.x - margin * 2, 54)
		drive_panel.get_node("Dashboard").position = Vector2(margin, 96)
		drive_panel.get_node("Navigation").position = Vector2(margin, 204)
		drive_panel.get_node("Navigation").size = Vector2(extent.x - margin * 2, 65)
		drive_panel.get_node("Equipment").position = Vector2(extent.x - 290, 112)
	else:
		garage_panel.position = Vector2(margin, 98)
		garage_panel.size = Vector2(348, maxf(300, extent.y - 114))
		garage_overlay.position = Vector2(392, 104)
		garage_overlay.size = Vector2(maxf(300, extent.x - 412), extent.y - 125)
		garage_overlay.get_node("CameraTools").position = Vector2(0, extent.y - 268)
		garage_status.position = Vector2(0, extent.y - 212)
		garage_status.size = Vector2(maxf(300, extent.x - 412), 48)
		message.position = Vector2(392, extent.y - 64) if not driving else Vector2(285, 278)
		message.size = Vector2(maxf(240, extent.x - 414), 44) if not driving else Vector2(maxf(280, extent.x - 590), 58)
		drive_panel.get_node("Dashboard").position = Vector2(margin, 98)
		drive_panel.get_node("Navigation").position = Vector2(280, 98)
		drive_panel.get_node("Navigation").size = Vector2(maxf(240, extent.x - 590), 68)
		drive_panel.get_node("Equipment").position = Vector2(extent.x - 290, 98)
	crawl_controls.position = Vector2(20, maxf(390 if portrait else 230, drive_panel.get_node("Dashboard").position.y + drive_panel.get_node("Dashboard").size.y + 16))
	camera_toolbar.position = Vector2(margin, 286) if driving and portrait else (Vector2(extent.x - camera_toolbar.size.x - margin, 185) if driving else Vector2(extent.x - camera_toolbar.size.x - margin, 151))
	if not driving and portrait:
		camera_toolbar.position = Vector2(margin, 216)
	var bottom = extent.y - (90 if portrait else 80)
	touch_buttons.off_left.root.position = Vector2(margin + 56, bottom)
	touch_buttons.off_right.root.position = Vector2(margin + 180, bottom)
	touch_buttons.off_go.root.position = Vector2(extent.x - margin - 64, bottom - 8)
	touch_buttons.off_reverse.root.position = Vector2(extent.x - margin - 189, bottom + 3)
	touch_buttons.off_brake.root.position = Vector2(extent.x - margin - 64, bottom - 121)
	pause_overlay.size = Vector2(minf(380, extent.x - 40), 276)
	pause_overlay.position = (extent - pause_overlay.size) / 2
	map_overlay.size = Vector2(minf(720, extent.x - 36), minf(820, extent.y - 40))
	map_overlay.position = (extent - map_overlay.size) / 2

func format_value(key: String) -> String:
	var value = float(settings.get(key, 0.0))
	match key:
		"tire_radius": return "%.1f in" % (value * 2.0 / 0.0254)
		"tire_pressure": return "%.2f×" % value
		"ride_height": return "%d cm" % roundi(value * 100)
		"spring_rate": return "%.0f kN/m" % (value / 1000.0)
		"damping", "compression_damping", "rebound_damping": return "%.2f kNs/m" % (value / 1000.0)
		"compression_travel", "suspension_travel": return "%d cm" % roundi(value * 100.0)
		"engine_torque": return "%d Nm" % roundi(value)
		"mass": return "%d kg" % roundi(value)
		"track_width", "wheelbase": return "%.2f m" % value
		"body_stiffness": return "%.2f×" % value
	return str(value)

func active_build() -> Dictionary:
	return builds[selected_vehicle]

func change_value(value: float, key: String) -> void:
	if updating_ui:
		return
	builds[selected_vehicle].tuning[key] = value
	settings = VehicleCatalog.compose(active_build())
	value_labels[key].text = format_value(key)
	tuning_delay = 0.28

func change_toggle(value: bool, key: String) -> void:
	if updating_ui:
		return
	if key in ["front_locked", "rear_locked"]:
		# Materialize both current choices before removing a legacy combined
		# override, otherwise changing one formerly-open axle could lock the other.
		builds[selected_vehicle].tuning.front_locked = settings.front_locked
		builds[selected_vehicle].tuning.rear_locked = settings.rear_locked
		builds[selected_vehicle].tuning.erase("locked_diffs")
	builds[selected_vehicle].tuning[key] = value
	if key == "locked_diffs":
		builds[selected_vehicle].tuning.front_locked = value
		builds[selected_vehicle].tuning.rear_locked = value
	settings = VehicleCatalog.compose(active_build())
	truck.set_axle_drivetrain(settings.low_range, settings.front_locked, settings.rear_locked)
	update_drive_toggles()
	save_settings()

func select_vehicle(id: String) -> void:
	if not VehicleCatalog.VEHICLES.has(id) or driving:
		return
	selected_vehicle = id
	settings = VehicleCatalog.compose(active_build())
	sync_controls()
	apply_tuning()
	toast("%s ready. Each vehicle keeps its own parts and tune." % VehicleCatalog.VEHICLES[id].name)

func select_part(slot: String, id: String) -> void:
	if driving or not VehicleCatalog.SLOTS.has(slot):
		return
	builds[selected_vehicle] = VehicleCatalog.equip_part(active_build(), slot, id)
	settings = VehicleCatalog.compose(active_build())
	sync_controls()
	apply_tuning()
	toast("Equipment fitted. Matching tune updated; your other settings are kept.")

func part_picked(index: int, slot: String) -> void:
	if updating_ui:
		return
	select_part(slot, str(part_selectors[slot].get_item_metadata(index)))

func select_paint(color: String) -> void:
	if not color in PAINTS:
		return
	builds[selected_vehicle].paint = color
	settings.paint = color
	truck.body_color = Color(color)
	update_paint_buttons()
	save_settings()

func toggle_tuning() -> void:
	tuning_content.visible = not tuning_content.visible
	tuning_button.text = "Fine tuning  −" if tuning_content.visible else "Fine tuning  +"

func clear_tuning() -> void:
	builds[selected_vehicle].tuning = {}
	settings = VehicleCatalog.compose(active_build())
	sync_controls()
	apply_tuning()
	toast("Restored the settings from your installed equipment.")

func change_quality(index: int) -> void:
	quality = clampi(index, 0, 2)
	world.set_quality(quality)
	apply_display_quality()
	save_settings()
	toast("Graphics: %s. Use Performance if exploration starts to slow down." % ["Performance", "Balanced", "High"][quality])

func apply_display_quality() -> void:
	var viewport = get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = [0.75, 0.85, 1.0][quality]
	viewport.msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else Viewport.MSAA_2X

func update_paint_buttons() -> void:
	for color in paint_buttons:
		var background = box(Color(color), 8, 4)
		if color == settings.paint:
			background.set_border_width_all(3)
			background.border_color = PAPER
		paint_buttons[color].add_theme_stylebox_override("normal", background)

func update_drive_toggles() -> void:
	drive_low.text = "LOW" if settings.low_range else "HIGH"
	drive_diff.text = "MIXED" if settings.front_locked != settings.rear_locked else ("LOCKED" if settings.locked_diffs else "OPEN")
	drive_diff.visible = not crawl_mode
	front_diff.text = "FRONT: %s" % ("LOCK" if settings.front_locked else "OPEN")
	rear_diff.text = "REAR: %s" % ("LOCK" if settings.rear_locked else "OPEN")
	for item in [drive_low, drive_diff, front_diff, rear_diff]:
		var enabled = settings.low_range if item == drive_low else (settings.front_locked if item == front_diff else (settings.rear_locked if item == rear_diff else settings.locked_diffs))
		item.add_theme_stylebox_override("normal", box(Color("56634f") if enabled else Color("2b3c43"), 10))

func sync_controls() -> void:
	updating_ui = true
	for key in slider_nodes:
		slider_nodes[key].value = settings[key]
		value_labels[key].text = format_value(key)
	for key in toggle_nodes:
		toggle_nodes[key].button_pressed = settings[key]
	for id in vehicle_buttons:
		vehicle_buttons[id].add_theme_stylebox_override("normal", box(Color("58634f") if id == selected_vehicle else Color("2b3c43"), 9, 8))
	vehicle_description.text = str(VehicleCatalog.VEHICLES[selected_vehicle].description)
	title_label.text = str(VehicleCatalog.VEHICLES[selected_vehicle].name) + "  /  BASE CAMP"
	for slot in VehicleCatalog.SLOTS:
		var picker: OptionButton = part_selectors[slot]
		picker.clear()
		var available: Array = VehicleCatalog.compatible_parts(selected_vehicle, slot)
		for index in available.size():
			var part: Dictionary = available[index]
			picker.add_item(str(part.name))
			picker.set_item_metadata(index, str(part.id))
			if str(part.id) == str(active_build().parts[slot]):
				picker.select(index)
				part_descriptions[slot].text = str(part.description)
	quality_picker.select(quality)
	updating_ui = false
	update_paint_buttons()
	update_drive_toggles()

func apply_tuning() -> void:
	tuning_delay = -1.0
	clear_controls()
	settings = VehicleCatalog.compose(active_build())
	truck.configure(settings)
	world.configure(truck.core)
	if crawl_mode:
		truck.reset(recovery_point())
	truck.body_color = Color(settings.paint)
	truck.wireframe = xray
	did_position_camera = false
	save_settings()

func toggle_drive_low() -> void:
	change_toggle(not settings.low_range, "low_range")
	sync_controls()
	toast("Low range engaged." if settings.low_range else "High range engaged.")

func toggle_drive_diff() -> void:
	change_toggle(not settings.locked_diffs, "locked_diffs")
	sync_controls()
	toast("Differentials locked." if settings.locked_diffs else "Differentials open.")

func toggle_axle_diff(key: String) -> void:
	change_toggle(not bool(settings[key]), key)
	sync_controls()
	toast("%s differential %s." % ["Front" if key == "front_locked" else "Rear", "locked" if settings[key] else "open"])

func toggle_xray() -> void:
	xray = not xray
	truck.wireframe = xray
	xray_button.text = "X-ray ✓" if xray else "X-ray"
	xray_button.add_theme_stylebox_override("normal", box(Color("56634f") if xray else Color("2b3c43"), 10))
	toast("Structure view: frame, suspension and wheel guides." if xray else "Body view restored.")

func toggle_mode() -> void:
	if help_open or backgrounded or map_overlay.visible:
		return
	if tuning_delay >= 0:
		apply_tuning()
	clear_controls()
	driving = not driving
	garage_panel.visible = not driving
	garage_overlay.visible = not driving
	drive_panel.visible = driving
	pause_button.visible = driving
	mode_button.text = "GARAGE" if driving else "DRIVE  ›"
	update_camera_tools()
	if not driving:
		truck.reset(recovery_point())
		pause_overlay.hide()
		get_tree().paused = false
		pause_button.text = "Pause"
	did_position_camera = false
	layout_ui()
	save_settings()
	toast("Hold GO; use the throttle slider for precise torque. Camp returns to the last clear section." if crawl_mode and driving else ("Choose a destination on the map. Hold GO and a steering arrow together." if driving else "Fit equipment or fine-tune your build."))

func recover() -> void:
	clear_controls()
	truck.reset(recovery_point())
	recovery_cooldown = 1.0
	did_position_camera = false
	toast("Repaired at the last cleared section." if crawl_mode else "Vehicle repaired at base camp. Your discoveries are saved.")

func impact_test() -> void:
	if driving:
		return
	if tuning_delay >= 0:
		apply_tuning()
	if not xray:
		toggle_xray()
	truck.core.apply_impact(Vector3(16000.0, 0.0, 4000.0))
	toast("Side-impact test. Use Repair & camp when finished.")

func orbit_by(amount: float) -> void:
	orbit = wrapf(orbit + amount, -PI, PI)
	camera_save_delay = 0.8

func zoom_by(amount: float) -> void:
	orbit_distance = clampf(orbit_distance + amount, 3.2, 20.0)
	camera_save_delay = 0.8

func clear_controls() -> void:
	camera_gestures.cancel()
	for action in ACTIONS:
		Input.action_release(action)
	if is_instance_valid(truck):
		truck.throttle = 0.0
		truck.steering = 0.0
		truck.brake = true

func toggle_pause() -> void:
	if help_open or backgrounded or map_overlay.visible:
		return
	clear_controls()
	pause_overlay.visible = not pause_overlay.visible
	get_tree().paused = pause_overlay.visible
	pause_button.text = "Resume" if pause_overlay.visible else "Pause"
	if pause_overlay.visible:
		save_settings()

func pause_to_garage() -> void:
	pause_overlay.hide()
	get_tree().paused = false
	pause_button.text = "Pause"
	if driving:
		toggle_mode()

func toggle_map() -> void:
	if help_open or backgrounded or crawl_mode:
		return
	clear_controls()
	map_overlay.visible = not map_overlay.visible
	get_tree().paused = map_overlay.visible or pause_overlay.visible
	if map_overlay.visible:
		update_map()
		save_settings()

func select_destination(id: String) -> void:
	for landmark in landmarks:
		if str(landmark.id) == id:
			destination = id
			update_map()
			save_settings()
			return

func validate_exploration() -> void:
	var ids: Array[String] = []
	for landmark in landmarks:
		ids.append(str(landmark.id))
	var validated: Array[String] = []
	for id in discovered:
		if id in ids and not id in validated:
			validated.append(id)
	discovered = validated
	if not destination in ids:
		destination = ids[0] if not ids.is_empty() else ""

func update_map() -> void:
	if crawl_mode:
		return
	map_status.text = "%d / %d places discovered" % [discovered.size(), landmarks.size()]
	var position: Vector3 = current_telemetry.get("position", CAMP)
	map_canvas.update_state(position, discovered, destination)
	for landmark in landmarks:
		var id = str(landmark.id)
		var item: Button = map_rows[id]
		item.text = ("✓  " if id in discovered else "○  ") + str(landmark.name)
		item.add_theme_stylebox_override("normal", box(Color("58634f") if id == destination else Color("2b3c43"), 10))

func check_discoveries(position: Vector3) -> void:
	if crawl_mode:
		return
	if not driving:
		return
	for landmark in landmarks:
		var id = str(landmark.id)
		if id in discovered:
			continue
		var point: Vector3 = landmark.position
		var planar = Vector2(position.x - point.x, position.z - point.z)
		if planar.length() <= float(landmark.get("radius", 18.0)) and absf(position.y - point.y) < 15.0:
			discovered.append(id)
			save_settings()
			toast("Discovered %s  ·  %d / %d places" % [landmark.name, discovered.size(), landmarks.size()])

func show_help() -> void:
	if help_open:
		return
	clear_controls()
	help_open = true
	get_tree().paused = true
	var dialog = AcceptDialog.new()
	dialog.title = "Bolt Yard · Field guide"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.dialog_text = "BUILD YOUR RIG\nPickup, Scout and Buggy each keep a separate build.\nEquipment changes compatible parts and their matching settings.\nFine tuning overrides those settings. Reset tuning restores installed parts.\n\nEXPLORE\nSelect a destination on the map, then follow the compass.\nPlaces are discovered when you actually drive close to them.\nCamp repairs the vehicle and returns you to the workshop.\nHold GO plus a steering arrow. REV reverses; BRAKE slows the wheels.\nLow range and locked differentials help with slow climbs.\nOn Copperline, FRONT / REAR toggle each axle lock independently.\nKeyboard: WASD / arrows, Space brake, R camp, M map, Tab garage.\n\nCAMERA · TWO FINGERS ON THE SCENERY\nPinch to zoom. Twist to orbit. Drag: Orbit turns sideways and tilts up/down.\nTap Drag: Pan to move the view sideways or up/down with two fingers.\nOrbit turns Follow off; Follow: on returns behind the rig. Reset view centers it.\nButtons and pedals keep their touches. Lift fingers before changing modes.\n\nDISPLAY & SAVES\nBoth portrait and landscape layouts work; rotate at any time.\nPerformance, Balanced and High adjust scenery and shadows.\nAll builds and discoveries save on this device. The old setup is retained.\n\nPHYSICS\nThe frame and cabin deform; tires use round contacts and visual squash. Parts change the simulated build.\nRelative tire pressure is a stiffness/grip multiplier, not calibrated bar.\nTire, suspension and drivetrain models remain simplified."
	ui.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.tree_exiting.connect(func():
		help_open = false
		get_tree().paused = backgrounded or pause_overlay.visible or map_overlay.visible
	)
	var extent = get_viewport().get_visible_rect().size
	dialog.popup_centered(Vector2i(mini(740, int(extent.x) - 48), mini(790, int(extent.y) - 48)))

func load_settings() -> void:
	for id in VehicleCatalog.VEHICLES:
		builds[id] = VehicleCatalog.default_build(id)
	if FileAccess.file_exists(GARAGE_PATH):
		var file = FileAccess.open(GARAGE_PATH, FileAccess.READ)
		if file == null:
			save_problem = "Saved garage could not be opened. Default vehicles loaded."
			return
		var parsed = JSON.parse_string(file.get_as_text())
		if not parsed is Dictionary or int(parsed.get("version", 0)) != 3:
			save_problem = "Saved garage was unreadable. Default vehicles loaded."
			return
		var raw_builds = parsed.get("builds", {})
		if raw_builds is Dictionary:
			for id in builds:
				builds[id] = VehicleCatalog.validate_build(raw_builds.get(id, {}), id)
		var active = parsed.get("selected_vehicle", "pickup")
		if active is String and VehicleCatalog.VEHICLES.has(active):
			selected_vehicle = active
		var raw_progress = parsed.get("discovered", [])
		if raw_progress is Array:
			for id in raw_progress:
				if id is String and not id in discovered:
					discovered.append(id)
		if parsed.get("destination") is String:
			destination = parsed.destination
		var raw_quality = parsed.get("quality", 0)
		if raw_quality is float or raw_quality is int:
			quality = clampi(int(raw_quality), 0, 2)
		load_camera_preferences(parsed.get("camera", {}))
		return
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	var old_file = FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if old_file == null:
		return
	var legacy = JSON.parse_string(old_file.get_as_text())
	if not legacy is Dictionary:
		return
	var raw = legacy.get("settings", legacy)
	if raw is Dictionary:
		var migrated: Dictionary = VehicleCatalog.default_build("pickup")
		migrated.tuning = raw.duplicate(true)
		migrated.paint = raw.get("paint", migrated.paint)
		builds.pickup = VehicleCatalog.validate_build(migrated, "pickup")
		has_migrated = true

func camera_number(raw: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value = raw.get(key, fallback)
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), minimum, maximum)
	return fallback

func load_camera_preferences(raw) -> void:
	if not raw is Dictionary:
		return
	orbit = camera_number(raw, "orbit", 2.24, -PI, PI)
	orbit_distance = camera_number(raw, "garage_distance", 9.3, 3.2, 20.0)
	orbit_pitch = camera_number(raw, "garage_pitch", 0.49, 0.10, 1.28)
	drive_distance = camera_number(raw, "drive_distance", 8.2, 3.0, 20.0)
	drive_pitch = camera_number(raw, "drive_pitch", 0.30, 0.10, 1.28)
	drive_orbit = camera_number(raw, "drive_orbit", 0.0, -PI, PI)
	if raw.get("pan_mode") is bool:
		camera_pan_mode = raw.pan_mode
	if raw.get("follow") is bool:
		camera_follow = raw.follow
	garage_pan = Vector2(camera_number(raw, "garage_pan_x", 0.0, -4.0, 4.0), camera_number(raw, "garage_pan_y", 0.0, -4.0, 4.0)).limit_length(4.0)
	drive_pan = Vector2(camera_number(raw, "drive_pan_x", 0.0, -5.0, 5.0), camera_number(raw, "drive_pan_y", 0.0, -5.0, 5.0)).limit_length(5.0)

func camera_preferences() -> Dictionary:
	return {"orbit": orbit, "garage_distance": orbit_distance, "garage_pitch": orbit_pitch, "drive_distance": drive_distance, "drive_pitch": drive_pitch, "drive_orbit": drive_orbit, "pan_mode": camera_pan_mode, "follow": camera_follow, "garage_pan_x": garage_pan.x, "garage_pan_y": garage_pan.y, "drive_pan_x": drive_pan.x, "drive_pan_y": drive_pan.y}

func save_settings() -> bool:
	if builds.is_empty():
		return false
	var temporary = GARAGE_PATH + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 3, "selected_vehicle": selected_vehicle, "builds": builds, "discovered": discovered, "destination": destination, "quality": quality, "camera": camera_preferences()}, "\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(temporary, GARAGE_PATH) == OK

func save_with_toast() -> void:
	toast("All vehicle builds and discoveries saved." if save_settings() else "Could not save. Please try again.")

func toast(text: String) -> void:
	if not is_instance_valid(message):
		return
	message.text = text
	message.show()
	toast_remaining = 5.2

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(truck) or get_tree().paused:
		return
	truck.throttle = Input.get_axis("off_reverse", "off_go") * (throttle_limit if crawl_mode else 1.0) if driving else 0.0
	truck.steering = Input.get_axis("off_left", "off_right") if driving else 0.0
	truck.brake = Input.is_action_pressed("off_brake") if driving else true

func _process(delta: float) -> void:
	if not is_instance_valid(truck) or not is_instance_valid(ui):
		return
	if layout_frames_pending > 0:
		place_ui()
		layout_frames_pending -= 1
	toast_remaining -= delta
	if toast_remaining <= 0:
		message.hide()
	if get_tree().paused:
		return
	apply_camera_gesture(camera_gestures.sample(get_viewport().get_visible_rect().size))
	if camera_save_delay >= 0.0:
		camera_save_delay -= delta
		if camera_save_delay < 0.0:
			save_settings()
	recovery_cooldown = maxf(0.0, recovery_cooldown - delta)
	if tuning_delay >= 0:
		tuning_delay -= delta
		if tuning_delay < 0:
			apply_tuning()
	current_telemetry = truck.get_telemetry()
	update_camera(delta)
	trail_dust.update_trail(delta, driving and not xray, truck.core, truck._nodes, current_telemetry, camera, float(settings.get("tire_radius", 0.46)))
	telemetry_delay -= delta
	var position: Vector3 = current_telemetry.get("position", CAMP)
	if telemetry_delay <= 0:
		telemetry_delay = 0.12
		update_telemetry()
		world.update_focus(position)
		if not crawl_mode:
			check_discoveries(position)
	for action in touch_buttons:
		var pressed = Input.is_action_pressed(action)
		var item: Dictionary = touch_buttons[action]
		if pressed != item.down:
			item.down = pressed
			item.panel.modulate = Color("ffe0a5") if pressed else Color.WHITE
	if recovery_cooldown <= 0.0:
		if position.y < -50.0 or (driving and (absf(position.x) > 365.0 or absf(position.z) > 365.0)):
			recover()
			toast("Valley edge reached. Recovered at base camp with discoveries saved.")

func update_camera(delta: float) -> void:
	var position: Vector3 = current_telemetry.get("position", CAMP)
	var target = position + Vector3.UP * 0.3
	var desired: Vector3
	if driving:
		var speed: float = absf(float(current_telemetry.get("speed", 0.0)))
		var forward: Vector3 = current_telemetry.get("forward", Vector3.FORWARD)
		forward.y = 0.0
		if forward.length_squared() > 0.01:
			# Angular interpolation stays defined during a 180-degree reversal.
			var heading = lerp_angle(atan2(follow_direction.x, follow_direction.z), atan2(-forward.x, -forward.z), 1.0 - exp(-3.2 * delta))
			follow_direction = Vector3(sin(heading), 0.0, cos(heading))
		var yaw = atan2(follow_direction.x, follow_direction.z) if camera_follow else drive_orbit
		var direction = Vector3(sin(yaw), 0.0, cos(yaw))
		var distance = drive_distance * (1.10 if portrait else 1.0)
		var pitch = drive_pitch + (0.07 if portrait else 0.0)
		var pan = Vector3(cos(yaw), 0.0, -sin(yaw)) * drive_pan.x + Vector3.UP * drive_pan.y
		target += pan
		desired = target + direction * distance * cos(pitch) + Vector3.UP * distance * sin(pitch)
		if camera_follow:
			# Preserve the useful trail look-ahead without changing manual zoom.
			target -= follow_direction * minf(3.0 + speed * 0.07, distance * 0.48)
		target.y = maxf(target.y, float(truck.core.terrain_height(target.x, target.z)) + 0.35)
		camera.fov = lerpf(camera.fov, 60.0, 1.0 - exp(-2.0 * delta))
	else:
		camera.fov = lerpf(camera.fov, 52.0, 1.0 - exp(-4.0 * delta))
		var preview_distance = orbit_distance * (1.14 if portrait else 1.0)
		var offset = Vector3(sin(orbit) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit) * cos(orbit_pitch)) * preview_distance * 1.13
		desired = position + offset
		var camera_right = Vector3(cos(orbit), 0.0, -sin(orbit))
		if portrait:
			target -= Vector3.UP * minf(3.0, preview_distance * 0.28)
		else:
			target -= camera_right * 1.9
			desired -= camera_right * 1.9
		var pan = camera_right * garage_pan.x + Vector3.UP * garage_pan.y
		target += pan
		desired += pan
	# Terrain collision is applied to the desired camera and the smoothed
	# position, so slow interpolation cannot carry the eye through a slope.
	desired.y = maxf(desired.y, float(truck.core.terrain_height(desired.x, desired.z)) + 0.65)
	var lift = 0.0
	var sight_anchor: Vector3 = position + Vector3.UP * 0.6
	for sample in range(1, 9):
		var fraction = float(sample) / 8.0
		var point = sight_anchor.lerp(desired, fraction)
		var clearance = float(truck.core.terrain_height(point.x, point.z)) + 0.25 - point.y
		lift = maxf(lift, clearance / fraction)
	desired.y += lift
	if crawl_mode and truck.core.has_method("camera_safe_position"):
		desired = truck.core.camera_safe_position(sight_anchor, desired, 0.22)
	if not did_position_camera:
		camera_target = target
		camera.position = desired
		did_position_camera = true
	else:
		camera_target = camera_target.lerp(target, 1.0 - exp(-7.0 * delta))
		camera.position = camera.position.lerp(desired, 1.0 - exp(-7.0 * delta))
	camera.position.y = maxf(camera.position.y, float(truck.core.terrain_height(camera.position.x, camera.position.z)) + 0.4)
	if crawl_mode and truck.core.has_method("camera_safe_position"):
		camera.position = truck.core.camera_safe_position(sight_anchor, camera.position, 0.22)
	if camera.position.distance_squared_to(camera_target) > 0.01:
		camera.look_at(camera_target, Vector3.UP)

func update_telemetry() -> void:
	var speed = absf(float(current_telemetry.get("speed", 0.0))) * 3.6
	var damage = clampf(float(current_telemetry.get("damage", 0.0)), 0.0, 1.0)
	var broken = int(current_telemetry.get("broken_beams", 0))
	var grounded = clampi(int(current_telemetry.get("wheels_grounded", 0)), 0, 4)
	speed_label.text = "%02d  km/h" % roundi(speed)
	speed_label.text = "%.1f  km/h" % speed if crawl_mode else speed_label.text
	drive_status.text = "%d wheels · %s · %d fps" % [grounded, "LOW" if settings.low_range else "HIGH", Engine.get_frames_per_second()]
	drive_damage.text = "CHASSIS %d%% · %d broken" % [roundi((1.0 - damage) * 100.0), broken]
	drive_damage.add_theme_color_override("font_color", Color("f09375") if damage > 0.25 or broken > 0 else ACCENT)
	garage_status.text = "%d%% chassis · %d broken beams · %d fps\n%d / %d places discovered" % [roundi((1.0 - damage) * 100.0), broken, Engine.get_frames_per_second(), discovered.size(), landmarks.size()]
	if crawl_mode:
		var loads = current_telemetry.get("wheel_normal_loads", current_telemetry.get("wheel_loads", PackedFloat32Array([0, 0, 0, 0])))
		var squash = current_telemetry.get("wheel_compression", PackedFloat32Array([0, 0, 0, 0]))
		var flex = current_telemetry.get("axle_articulation", PackedFloat32Array([0, 0]))
		crawl_loads.text = "TIRE LOAD  kN\nFL %.1f   FR %.1f\nRL %.1f   RR %.1f\nSquash mm  %.0f · %.0f / %.0f · %.0f\nAxle flex  F %.0f° · R %.0f°" % [loads[0] / 1000.0, loads[1] / 1000.0, loads[2] / 1000.0, loads[3] / 1000.0, squash[0] * 1000.0, squash[1] * 1000.0, squash[2] * 1000.0, squash[3] * 1000.0, rad_to_deg(flex[0]), rad_to_deg(flex[1])]
		var z: float = current_telemetry.get("position", CAMP).z
		# Advance recovery only after clearing a section, never by proximity.
		var exits = [-9.0, -22.0, -40.0, -52.0, -76.0]
		if crawl_section < 5 and z < exits[crawl_section] and absf(current_telemetry.position.x) < 8:
			crawl_section += 1
			toast("Section cleared. Recovery point advanced." if crawl_section < 5 else "Copperline complete. Try a different tire pressure or line.")
		navigation_label.text = "COPPERLINE  ·  %d / 5 clear\n%s" % [crawl_section, landmarks[mini(crawl_section, 4)].description]
		return
	var position: Vector3 = current_telemetry.get("position", CAMP)
	var forward: Vector3 = current_telemetry.get("forward", Vector3.FORWARD)
	var heading = fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)
	var compass = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][roundi(heading / 45.0) % 8]
	navigation_label.text = "%s  %03d°  ·  %d / %d discovered\nChoose your next destination on the map." % [compass, roundi(heading) % 360, discovered.size(), landmarks.size()]
	for landmark in landmarks:
		if str(landmark.id) != destination:
			continue
		var point: Vector3 = landmark.position
		var difference = Vector2(point.x - position.x, point.z - position.z)
		var distance = difference.length()
		var bearing = fposmod(rad_to_deg(atan2(difference.x, -difference.y)), 360.0)
		var relative = wrapf(bearing - heading, -180.0, 180.0)
		var direction = "AHEAD" if absf(relative) < 25 else ("RIGHT" if relative > 0 else "LEFT")
		if absf(relative) > 145:
			direction = "BEHIND"
		if distance < float(landmark.get("radius", 18)):
			direction = "HERE"
		navigation_label.text = "%s  %03d°  ·  %d / %d discovered\n%s  ·  %d m  ·  %s" % [compass, roundi(heading) % 360, discovered.size(), landmarks.size(), landmark.name, roundi(distance), direction]
		break

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or help_open:
		return
	match event.physical_keycode:
		KEY_TAB:
			if not get_tree().paused:
				toggle_mode()
		KEY_R:
			if not get_tree().paused:
				recover()
		KEY_M:
			toggle_map()
		KEY_ESCAPE:
			if map_overlay.visible:
				toggle_map()
			elif driving:
				toggle_pause()
			else:
				show_help()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		backgrounded = true
		clear_controls()
		if is_instance_valid(ui):
			save_settings()
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		backgrounded = false
		clear_controls()
		if is_instance_valid(pause_overlay) and is_instance_valid(map_overlay):
			get_tree().paused = help_open or pause_overlay.visible or map_overlay.visible
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not help_open and is_instance_valid(ui):
			if map_overlay.visible:
				toggle_map()
			elif driving:
				toggle_pause()
			else:
				show_help()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()
		get_tree().quit()

func recovery_point() -> Vector3:
	if not crawl_mode:
		return CAMP
	return Vector3(0, 1.5, [8.0, -11.0, -24.0, -41.5, -55.0, -80.0][crawl_section])

func toggle_course() -> void:
	if driving:
		return
	clear_controls()
	crawl_mode = not crawl_mode
	crawl_section = 0
	var previous = world
	world = preload("res://scripts/crawl_world.gd").new() if crawl_mode else OffroadWorld.new()
	# Retain one sky and lighting set while replacing scenery; changing courses
	# must not accumulate environment/reflection allocations on a phone.
	world._environment = previous._environment
	world._sun = previous._sun
	world._reflection = previous._reflection
	for light in [previous._environment, previous._sun, previous.get_node("OpenSkyFill"), previous._reflection]:
		if is_instance_valid(light):
			light.get_parent().remove_child(light)
			world.add_child(light)
	remove_child(previous)
	previous.queue_free()
	world.name = "Trail"
	world.configure(truck.core)
	world.set_quality(quality)
	add_child(world)
	landmarks = world.get_landmarks()
	map_button.disabled = crawl_mode
	crawl_controls.visible = crawl_mode
	update_drive_toggles()
	course_button.text = "JUNIPER VALLEY  ·  Exploration" if crawl_mode else "COPPERLINE  ·  Technical crawling"
	truck.reset(CAMP)
	did_position_camera = false
	toast("Copperline ready. Fit the crawl setup, then DRIVE. Use LOW range." if crawl_mode else "Juniper Valley ready.")

func fit_crawl_setup() -> void:
	if driving:
		return
	var ids = {"tires": "rock", "wheels": "beadlock", "suspension": "lift", "gearing": "crawler"}
	for slot in ids:
		builds[selected_vehicle] = VehicleCatalog.equip_part(builds[selected_vehicle], slot, ids[slot])
	settings = VehicleCatalog.compose(active_build())
	sync_controls()
	apply_tuning()
	toast("Billygoat tires, Almost Level lift and Low Expectations gears fitted.")
