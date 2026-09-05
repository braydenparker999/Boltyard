extends Node3D

const SETUP_PATH = "user://offroad_setup.json"
const DEFAULTS = {
	"tire_radius": 0.46, "tire_pressure": 1.0, "ride_height": 0.35,
	"spring_rate": 30000.0, "damping": 3000.0, "engine_torque": 450.0,
	"mass": 1200.0, "track_width": 1.9, "wheelbase": 2.7,
	"body_stiffness": 1.0, "low_range": true, "locked_diffs": true,
	"paint": "c96c38", "preset": "Trail"
}
const LIMITS = {
	"tire_radius": [0.32, 0.65], "tire_pressure": [0.5, 2.0],
	"ride_height": [0.15, 0.65], "spring_rate": [15000.0, 65000.0],
	"damping": [1000.0, 7000.0], "engine_torque": [150.0, 900.0],
	"mass": [900.0, 2000.0], "track_width": [1.6, 2.3],
	"wheelbase": [2.3, 3.3], "body_stiffness": [0.5, 2.0]
}
const PRESETS = {
	"Trail": {},
	"Crawler": {"tire_radius": 0.58, "tire_pressure": 0.65, "ride_height": 0.47, "spring_rate": 24000.0, "damping": 3900.0, "engine_torque": 540.0, "track_width": 2.1, "wheelbase": 2.65, "mass": 1320.0, "body_stiffness": 0.9},
	"Desert": {"tire_radius": 0.48, "tire_pressure": 1.2, "ride_height": 0.4, "spring_rate": 43000.0, "damping": 4400.0, "engine_torque": 680.0, "track_width": 2.15, "wheelbase": 3.05, "mass": 1180.0, "low_range": false, "locked_diffs": false, "body_stiffness": 1.3}
}
const PAINTS = ["c96c38", "c9b78e", "647263", "537781", "ede7d6", "383f47"]
const INK = Color("172126")
const PANEL = Color("18232aed")
const MUTED = Color("a6b6b8")
const PAPER = Color("f3efdf")
const ACCENT = Color("efbd71")
const ACTIONS = ["off_left", "off_right", "off_go", "off_reverse", "off_brake"]

var settings = DEFAULTS.duplicate(true)
var truck
var world
var camera: Camera3D
var ui: Control
var garage_panel: PanelContainer
var garage_overlay: Control
var drive_panel: Control
var header: PanelContainer
var mode_button: Button
var pause_button: Button
var xray_button: Button
var speed_label: Label
var drive_status: Label
var drive_damage: Label
var garage_status: Label
var title_label: Label
var message: Label
var drive_low: Button
var drive_diff: Button
var pause_overlay: PanelContainer
var slider_nodes: Dictionary = {}
var value_labels: Dictionary = {}
var toggle_nodes: Dictionary = {}
var preset_buttons: Dictionary = {}
var paint_buttons: Dictionary = {}
var touch_buttons: Dictionary = {}
var current_telemetry: Dictionary = {}
var driving = false
var xray = false
var updating_ui = false
var backgrounded = false
var help_open = false
var toast_remaining = 0.0
var tuning_delay = -1.0
var telemetry_delay = 0.0
var recovery_cooldown = 0.0
var orbit = 0.72
var orbit_distance = 8.4
var camera_target = Vector3.ZERO
var follow_direction = Vector3.BACK
var did_position_camera = false
var save_problem = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	setup_input()
	load_settings()
	truck = OffroadTruck.new()
	truck.name = "Truck"
	truck.process_mode = Node.PROCESS_MODE_PAUSABLE
	truck.configure(settings)
	world = OffroadWorld.new()
	world.name = "Trail"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.configure(truck.core)
	add_child(world)
	add_child(truck)
	truck.body_color = Color(settings.paint)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 49.0
	camera.near = 0.08
	camera.far = 450.0
	add_child(camera)
	build_ui()
	sync_controls()
	get_viewport().size_changed.connect(layout_ui)
	layout_ui()
	toast(save_problem if not save_problem.is_empty() else "Your rig, your line. Tune the setup, then head out.")

func setup_input() -> void:
	var keys = {"off_left": [KEY_A, KEY_LEFT], "off_right": [KEY_D, KEY_RIGHT], "off_go": [KEY_W, KEY_UP], "off_reverse": [KEY_S, KEY_DOWN], "off_brake": [KEY_SPACE]}
	for action in keys:
		if not InputMap.has_action(action):
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
	theme.set_stylebox("normal", "Button", box(Color("2b3c43"), 10))
	theme.set_stylebox("hover", "Button", box(Color("40565c"), 10))
	theme.set_stylebox("pressed", "Button", box(Color("6e7c70"), 10))
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_color", "CheckButton", PAPER)
	var rail_colors = {"slider": Color("33454c"), "grabber_area": ACCENT, "grabber_area_highlight": Color("ffdbac")}
	for part in rail_colors:
		var rail = box(rail_colors[part], 4, 0)
		rail.content_margin_top = 3
		rail.content_margin_bottom = 3
		theme.set_stylebox(part, "HSlider", rail)
	ui.theme = theme
	header = PanelContainer.new()
	header.add_theme_stylebox_override("panel", box(PANEL, 14, 12))
	ui.add_child(header)
	var header_row = row(header, 15)
	var brand = column(header_row, 0)
	brand.custom_minimum_size.x = 185
	label(brand, "BOLT  /  OFFROAD", 24, PAPER)
	label(brand, "FIELD WORKSHOP     0.2", 11, ACCENT)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	xray_button = button(header_row, "X-RAY  OFF", toggle_xray, 118)
	button(header_row, "Guide", show_help, 70)
	pause_button = button(header_row, "Pause", toggle_pause, 72)
	pause_button.visible = false
	mode_button = button(header_row, "DRIVE  >", toggle_mode, 142)
	accent_button(mode_button)
	build_garage()
	build_driving()
	build_pause()
	message = label(ui, "", 15, PAPER)
	message.add_theme_stylebox_override("normal", box(Color("172126ef"), 10, 12))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE

func build_garage() -> void:
	garage_panel = PanelContainer.new()
	garage_panel.add_theme_stylebox_override("panel", box(PANEL, 16, 16))
	ui.add_child(garage_panel)
	var content = column(garage_panel, 11)
	var heading = row(content)
	var title = label(heading, "YOUR SETUP", 20, PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(heading, "4 × 4", 15, ACCENT)
	var presets = row(content, 6)
	for name in PRESETS:
		var item = button(presets, name, select_preset.bind(name), 88)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset_buttons[name] = item
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 130
	content.add_child(scroll)
	var settings_column = column(scroll, 5)
	settings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section(settings_column, "01   PAINT & STANCE")
	var paints = row(settings_column, 5)
	for color in PAINTS:
		var swatch = button(paints, "", select_paint.bind(color), 40)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.custom_minimum_size.y = 42
		swatch.add_theme_stylebox_override("normal", box(Color(color), 8, 4))
		swatch.add_theme_stylebox_override("hover", box(Color(color).lightened(0.2), 8, 4))
		swatch.tooltip_text = ["Rust orange", "Sand", "Forest", "Blue slate", "Ivory", "Graphite"][PAINTS.find(color)]
		paint_buttons[color] = swatch
	tuning_slider(settings_column, "track_width", "Track width", "Wider stance resists rolling on side slopes.", 0.05)
	tuning_slider(settings_column, "wheelbase", "Wheelbase", "Longer stays steady; shorter crests ridges.", 0.05)
	tuning_slider(settings_column, "mass", "Vehicle mass", "More weight asks more of tires and springs.", 25.0)
	section(settings_column, "02   TIRES")
	tuning_slider(settings_column, "tire_radius", "Tire size", "Larger tires clear rocks but need more torque.", 0.01)
	tuning_slider(settings_column, "tire_pressure", "Relative tire pressure", "Lower settings soften the tire carcass.", 0.05)
	section(settings_column, "03   SUSPENSION")
	tuning_slider(settings_column, "ride_height", "Suspension height", "More clearance raises the center of gravity.", 0.01)
	tuning_slider(settings_column, "spring_rate", "Spring rate", "Softer springs flex; stiffer springs carry load.", 1000.0)
	tuning_slider(settings_column, "damping", "Damping", "Controls how quickly the suspension settles.", 250.0)
	section(settings_column, "04   POWER & TRACTION")
	tuning_slider(settings_column, "engine_torque", "Engine torque", "Extra torque helps climbs and spins loose tires.", 25.0)
	tuning_toggle(settings_column, "low_range", "Low range", "Reduced speed and stronger crawling torque.")
	tuning_toggle(settings_column, "locked_diffs", "Locked differentials", "Keeps drive across uneven wheel contact.")
	section(settings_column, "05   STRUCTURE")
	tuning_slider(settings_column, "body_stiffness", "Chassis stiffness", "Changes how the node-and-beam chassis flexes.", 0.05)
	label(settings_column, "Tuning is saved on this device.", 12, MUTED)
	var tools = row(content, 7)
	button(tools, "Save setup", save_with_toast, 127).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(tools, "Repair & reset", recover, 140).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage_overlay = Control.new()
	garage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(garage_overlay)
	var title_backdrop = Panel.new()
	title_backdrop.position = Vector2(-12, -8)
	title_backdrop.size = Vector2(400, 108)
	title_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_backdrop.add_theme_stylebox_override("panel", box(PANEL, 14))
	garage_overlay.add_child(title_backdrop)
	label(garage_overlay, "THE PROVING GROUND", 12, ACCENT).position = Vector2(0, 0)
	title_label = label(garage_overlay, "Find your next line.", 34, PAPER)
	title_label.position = Vector2(0, 22)
	var subtitle = label(garage_overlay, "Tune your 4×4. Watch it flex. Take it outside.", 15, Color("d5dddd"))
	subtitle.position = Vector2(1, 68)
	var tools_row = row(garage_overlay, 7)
	tools_row.name = "CameraTools"
	button(tools_row, "Orbit <", orbit_by.bind(-0.35), 86)
	button(tools_row, ">", orbit_by.bind(0.35), 46)
	button(tools_row, "+", zoom_by.bind(-0.8), 46)
	button(tools_row, "−", zoom_by.bind(0.8), 46)
	button(tools_row, "Impact test", impact_test, 115)
	garage_status = label(garage_overlay, "", 14, MUTED)
	garage_status.name = "Telemetry"
	garage_status.add_theme_stylebox_override("normal", box(PANEL, 12, 14))
	garage_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func section(parent: Node, text: String) -> void:
	var item = label(parent, text, 12, ACCENT)
	item.custom_minimum_size.y = 36
	item.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func tuning_slider(parent: Node, key: String, title: String, explanation: String, step: float) -> void:
	var wrap = column(parent, 0)
	var heading = row(wrap, 2)
	var caption = label(heading, title, 15)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value = label(heading, format_value(key), 14, ACCENT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_labels[key] = value
	var slider = HSlider.new()
	slider.min_value = LIMITS[key][0]
	slider.max_value = LIMITS[key][1]
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
	consequence.custom_minimum_size.y = 31
	consequence.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func tuning_toggle(parent: Node, key: String, title: String, explanation: String) -> void:
	var wrap = column(parent, 0)
	var item = CheckButton.new()
	item.text = title
	item.custom_minimum_size.y = 46
	item.focus_mode = Control.FOCUS_NONE
	item.toggled.connect(change_toggle.bind(key))
	wrap.add_child(item)
	toggle_nodes[key] = item
	var description = label(wrap, explanation, 12, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 32

func build_driving() -> void:
	drive_panel = Control.new()
	drive_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drive_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(drive_panel)
	drive_panel.hide()
	var dashboard = PanelContainer.new()
	dashboard.name = "Dashboard"
	dashboard.position = Vector2(22, 106)
	dashboard.add_theme_stylebox_override("panel", box(PANEL, 14, 16))
	drive_panel.add_child(dashboard)
	var readouts = column(dashboard, 3)
	label(readouts, "PROVING GROUND   /   LIVE", 11, ACCENT)
	speed_label = label(readouts, "00  km/h", 34, PAPER)
	drive_status = label(readouts, "4 wheels in contact", 13, MUTED)
	drive_damage = label(readouts, "CHASSIS  100%", 13, ACCENT)
	var equipment = row(drive_panel, 8)
	equipment.name = "Equipment"
	drive_low = button(equipment, "LOW  ON", toggle_drive_low, 110)
	drive_diff = button(equipment, "DIFFS  LOCKED", toggle_drive_diff, 157)
	button(equipment, "Recover", recover, 100)
	make_touch_button("Left", "‹", "off_left", Vector2(118, 100))
	make_touch_button("Right", "›", "off_right", Vector2(118, 100))
	make_touch_button("Reverse", "REV", "off_reverse", Vector2(102, 100))
	make_touch_button("Brake", "BRAKE", "off_brake", Vector2(125, 70))
	make_touch_button("Go", "GO", "off_go", Vector2(140, 120))

func make_touch_button(node_name: String, text: String, action: String, dimensions: Vector2) -> void:
	var root = Node2D.new()
	root.name = node_name
	drive_panel.add_child(root)
	var panel = Panel.new()
	panel.size = dimensions
	panel.position = -dimensions / 2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", box(ACCENT if action == "off_go" else Color("20333ddd"), 22))
	root.add_child(panel)
	var caption = label(panel, text, 48 if action in ["off_left", "off_right"] else 22, INK if action == "off_go" else PAPER)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var touch = TouchScreenButton.new()
	var shape = RectangleShape2D.new()
	shape.size = dimensions
	touch.shape = shape
	touch.action = action
	touch.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	root.add_child(touch)
	touch_buttons[action] = {"root": root, "panel": panel, "touch": touch, "down": false}

func build_pause() -> void:
	pause_overlay = PanelContainer.new()
	pause_overlay.z_index = 20
	pause_overlay.add_theme_stylebox_override("panel", box(Color("111c23f5"), 18, 24))
	ui.add_child(pause_overlay)
	var content = column(pause_overlay, 16)
	label(content, "TAKE A BREATHER", 12, ACCENT)
	label(content, "Trail paused.", 30, PAPER)
	label(content, "Your rig will be right here.", 16, MUTED)
	accent_button(button(content, "Keep driving", toggle_pause, 270))
	button(content, "Return to garage", pause_to_garage, 270)
	pause_overlay.hide()

func layout_ui() -> void:
	if not is_instance_valid(ui):
		return
	var extent = get_viewport().get_visible_rect().size
	header.position = Vector2(22, 17)
	header.size = Vector2(extent.x - 44, 72)
	garage_panel.position = Vector2(22, 106)
	garage_panel.size = Vector2(328, maxf(260, extent.y - 127))
	garage_overlay.position = Vector2(378, 120)
	garage_overlay.size = Vector2(maxf(280, extent.x - 403), extent.y - 140)
	garage_overlay.get_node("CameraTools").position = Vector2(0, extent.y - 306)
	garage_status.position = Vector2(0, extent.y - 246)
	garage_status.size = Vector2(maxf(280, extent.x - 401), 60)
	message.position = Vector2(378, extent.y - 51) if not driving else Vector2(310, 176)
	message.size = Vector2(maxf(240, extent.x - 401), 42) if not driving else Vector2(maxf(240, extent.x - 635), 64)
	drive_panel.get_node("Equipment").position = Vector2(extent.x - 429, 106)
	touch_buttons.off_left.root.position = Vector2(88, extent.y - 86)
	touch_buttons.off_right.root.position = Vector2(222, extent.y - 86)
	touch_buttons.off_reverse.root.position = Vector2(extent.x - 256, extent.y - 86)
	touch_buttons.off_go.root.position = Vector2(extent.x - 105, extent.y - 96)
	touch_buttons.off_brake.root.position = Vector2(extent.x - 105, extent.y - 213)
	pause_overlay.size = Vector2(370, 310)
	pause_overlay.position = (extent - pause_overlay.size) / 2

func format_value(key: String) -> String:
	var value = float(settings[key])
	match key:
		"tire_radius": return "%.1f in" % (value * 2.0 / 0.0254)
		"tire_pressure": return "%.2f×" % value
		"ride_height": return "%d cm" % roundi(value * 100)
		"spring_rate": return "%.0f kN/m" % (value / 1000.0)
		"damping": return "%.2f kNs/m" % (value / 1000.0)
		"engine_torque": return "%d Nm" % roundi(value)
		"mass": return "%d kg" % roundi(value)
		"track_width", "wheelbase": return "%.2f m" % value
		"body_stiffness": return "%.2f×" % value
	return str(value)

func change_value(value: float, key: String) -> void:
	if updating_ui:
		return
	settings[key] = value
	settings.preset = "Custom"
	value_labels[key].text = format_value(key)
	tuning_delay = 0.28
	update_preset_buttons()

func change_toggle(value: bool, key: String) -> void:
	if updating_ui:
		return
	settings[key] = value
	settings.preset = "Custom"
	truck.set_drivetrain(settings.low_range, settings.locked_diffs)
	update_preset_buttons()
	update_drive_toggles()
	save_settings()

func select_preset(name: String) -> void:
	var paint: String = settings.paint
	settings = DEFAULTS.duplicate(true)
	settings.merge(PRESETS[name], true)
	settings.paint = paint
	settings.preset = name
	sync_controls()
	apply_tuning()
	toast({"Trail": "Trail setup: balanced suspension, low range and locked differentials.", "Crawler": "Crawler setup: tall tires, soft springs and a wider stance.", "Desert": "Desert setup: longer wheelbase, firmer suspension and high range."}[name])

func select_paint(color: String) -> void:
	settings.paint = color
	truck.body_color = Color(color)
	update_paint_buttons()
	save_settings()

func update_paint_buttons() -> void:
	for color in paint_buttons:
		var item: Button = paint_buttons[color]
		var background = box(Color(color), 8, 4)
		if color == settings.paint:
			background.set_border_width_all(3)
			background.border_color = PAPER
		item.add_theme_stylebox_override("normal", background)

func update_preset_buttons() -> void:
	for name in preset_buttons:
		preset_buttons[name].add_theme_stylebox_override("normal", box(Color("5b6657") if name == settings.preset else Color("2b3c43"), 9, 8))

func update_drive_toggles() -> void:
	drive_low.text = "LOW  ON" if settings.low_range else "HIGH RANGE"
	drive_diff.text = "DIFFS  LOCKED" if settings.locked_diffs else "DIFFS  OPEN"
	for item in [drive_low, drive_diff]:
		var enabled = settings.low_range if item == drive_low else settings.locked_diffs
		item.add_theme_stylebox_override("normal", box(Color("56634f") if enabled else Color("2b3c43"), 10))

func sync_controls() -> void:
	updating_ui = true
	for key in slider_nodes:
		slider_nodes[key].value = settings[key]
		value_labels[key].text = format_value(key)
	for key in toggle_nodes:
		toggle_nodes[key].button_pressed = settings[key]
	updating_ui = false
	update_preset_buttons()
	update_paint_buttons()
	update_drive_toggles()

func apply_tuning() -> void:
	tuning_delay = -1.0
	clear_controls()
	truck.configure(settings)
	world.configure(truck.core)
	truck.body_color = Color(settings.paint)
	truck.wireframe = xray
	did_position_camera = false
	save_settings()

func toggle_drive_low() -> void:
	change_toggle(not settings.low_range, "low_range")
	sync_controls()
	toast("Low range engaged: stronger crawling torque." if settings.low_range else "High range engaged: more speed, less wheel torque.")

func toggle_drive_diff() -> void:
	change_toggle(not settings.locked_diffs, "locked_diffs")
	sync_controls()
	toast("Differentials locked." if settings.locked_diffs else "Differentials open.")

func toggle_xray() -> void:
	xray = not xray
	truck.wireframe = xray
	xray_button.text = "X-RAY  ON" if xray else "X-RAY  OFF"
	xray_button.add_theme_stylebox_override("normal", box(Color("56634f") if xray else Color("2b3c43"), 10))
	toast("Structure view: watch the chassis beams deform under load." if xray else "Body panels restored.")

func toggle_mode() -> void:
	if help_open or backgrounded:
		return
	if tuning_delay >= 0:
		apply_tuning()
	clear_controls()
	driving = not driving
	garage_panel.visible = not driving
	garage_overlay.visible = not driving
	drive_panel.visible = driving
	pause_button.visible = driving
	mode_button.text = "<  GARAGE" if driving else "DRIVE  >"
	if not driving:
		truck.reset()
		pause_overlay.hide()
		get_tree().paused = false
	did_position_camera = false
	layout_ui()
	save_settings()
	toast("Hold GO and a steering arrow together. Take the rocks slowly." if driving else "Back at the workshop. Tune your setup or inspect the structure.")

func recover() -> void:
	clear_controls()
	truck.reset()
	recovery_cooldown = 1.0
	did_position_camera = false
	toast("Vehicle repaired and returned to the starting area.")

func impact_test() -> void:
	if tuning_delay >= 0:
		apply_tuning()
	if not xray:
		toggle_xray()
	truck.core.apply_impact(Vector3(16000.0, 0.0, 4000.0))
	toast("Side-impact test. Watch the beam structure, then Repair & reset.")

func orbit_by(amount: float) -> void:
	orbit += amount

func zoom_by(amount: float) -> void:
	orbit_distance = clampf(orbit_distance + amount, 5.5, 13.0)

func clear_controls() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	if is_instance_valid(truck):
		truck.throttle = 0.0
		truck.steering = 0.0
		truck.brake = true

func toggle_pause() -> void:
	if help_open or backgrounded:
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

func show_help() -> void:
	if help_open:
		return
	clear_controls()
	help_open = true
	get_tree().paused = true
	var dialog = AcceptDialog.new()
	dialog.title = "Bolt Offroad · Field guide"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.dialog_text = "GARAGE\nChoose Trail, Crawler or Desert, then tune your own setup.\nTires, suspension, mass, wheelbase and track change the physical rig.\nChanges return the vehicle to the starting area. Paint is cosmetic.\nX-RAY reveals the node-and-beam chassis. Impact test strikes it from the side.\nRepair & reset repairs damage and returns the vehicle to the start.\n\nON THE TRAIL\nHold GO plus a steering arrow. REV reverses; BRAKE slows the wheels.\nUse low range and locked differentials for slow, uneven climbs.\nHigh range is faster. Slow down before ledges and side slopes.\nKeyboard: WASD / arrows, Space brake, R recover, Tab garage, Esc pause.\n\nSAVING\nYour setup saves automatically on this device. Save setup saves it immediately.\nThe old block-building blueprint is kept separately. Uninstalling removes local saves.\n\nSIMULATION PROTOTYPE\nA deformable node-and-beam chassis with simplified tire and drivetrain models.\nRelative tire pressure approximates carcass stiffness and grip; it is not calibrated to bar.\nThis is an experimental off-road simulation, not BeamNG-level vehicle fidelity.\nNo multiplayer, dynamic mud, detailed engine simulation or licensed vehicles."
	ui.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.tree_exiting.connect(func():
		help_open = false
		get_tree().paused = backgrounded or pause_overlay.visible
	)
	dialog.popup_centered(Vector2i(820, 600))

func load_settings() -> void:
	if not FileAccess.file_exists(SETUP_PATH):
		return
	var file = FileAccess.open(SETUP_PATH, FileAccess.READ)
	if file == null:
		save_problem = "Saved setup could not be opened. Loaded the Trail setup."
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		save_problem = "Saved setup was unreadable. Loaded the Trail setup."
		return
	var payload = parsed.get("settings", parsed)
	if not payload is Dictionary:
		save_problem = "Saved setup was unreadable. Loaded the Trail setup."
		return
	var data: Dictionary = payload
	for key in LIMITS:
		var value = data.get(key, DEFAULTS[key])
		if (value is float or value is int) and is_finite(float(value)):
			settings[key] = clampf(float(value), LIMITS[key][0], LIMITS[key][1])
	for key in ["low_range", "locked_diffs"]:
		if data.get(key) is bool:
			settings[key] = data[key]
	if data.get("paint", "") in PAINTS:
		settings.paint = data.paint
	if data.get("preset", "") in ["Trail", "Crawler", "Desert", "Custom"]:
		settings.preset = data.preset

func save_settings() -> bool:
	var temporary = SETUP_PATH + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "settings": settings}, "\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(temporary, SETUP_PATH) == OK

func save_with_toast() -> void:
	toast("Setup saved on this device." if save_settings() else "Could not save the setup. Please try again.")

func toast(text: String) -> void:
	if not is_instance_valid(message):
		return
	message.text = text
	message.show()
	toast_remaining = 5.2

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(truck) or get_tree().paused:
		return
	truck.throttle = Input.get_axis("off_reverse", "off_go") if driving else 0.0
	truck.steering = Input.get_axis("off_left", "off_right") if driving else 0.0
	truck.brake = Input.is_action_pressed("off_brake") if driving else true

func _process(delta: float) -> void:
	if not is_instance_valid(truck) or not is_instance_valid(ui):
		return
	toast_remaining -= delta
	if toast_remaining <= 0:
		message.hide()
	if get_tree().paused:
		return
	recovery_cooldown = maxf(0.0, recovery_cooldown - delta)
	if tuning_delay >= 0:
		tuning_delay -= delta
		if tuning_delay < 0:
			apply_tuning()
	current_telemetry = truck.get_telemetry()
	update_camera(delta)
	telemetry_delay -= delta
	if telemetry_delay <= 0:
		telemetry_delay = 0.12
		update_telemetry()
	for action in touch_buttons:
		var pressed = Input.is_action_pressed(action)
		var item: Dictionary = touch_buttons[action]
		if pressed != item.down:
			item.down = pressed
			item.panel.modulate = Color("ffe0a5") if pressed else Color.WHITE
	var position: Vector3 = current_telemetry.get("position", Vector3.ZERO)
	if recovery_cooldown <= 0.0:
		if position.y < -30.0:
			recover()
			toast("Fall recovery: vehicle repaired and returned to the starting area.")
		elif driving and (absf(position.x) > 72.0 or position.z < -105.0 or position.z > 55.0):
			recover()
			toast("Trail boundary reached. Vehicle recovered and repaired at the start.")

func update_camera(delta: float) -> void:
	var position: Vector3 = current_telemetry.get("position", Vector3.ZERO)
	var target = position + Vector3.UP * 0.3
	var desired: Vector3
	if driving:
		var forward: Vector3 = current_telemetry.get("forward", Vector3.FORWARD)
		forward.y = 0.0
		if forward.length_squared() > 0.01:
			follow_direction = follow_direction.lerp(-forward.normalized(), 1.0 - exp(-1.8 * delta)).normalized()
		desired = target + follow_direction * 8.8 + Vector3.UP * 4.4
	else:
		var offset = Vector3(sin(orbit) * orbit_distance, orbit_distance * 0.5, cos(orbit) * orbit_distance)
		var camera_right = Vector3(cos(orbit), 0.0, -sin(orbit))
		# Move the focal point left so the rig occupies the space beside the garage.
		target -= camera_right * 1.3
		desired = target + offset
	if not did_position_camera:
		camera_target = target
		camera.position = desired
		did_position_camera = true
	else:
		camera_target = camera_target.lerp(target, 1.0 - exp(-5.0 * delta))
		camera.position = camera.position.lerp(desired, 1.0 - exp(-4.0 * delta))
	if camera.position.distance_squared_to(camera_target) > 0.01:
		camera.look_at(camera_target, Vector3.UP)

func update_telemetry() -> void:
	var speed = absf(float(current_telemetry.get("speed", 0.0))) * 3.6
	var damage = clampf(float(current_telemetry.get("damage", 0.0)), 0.0, 1.0)
	var broken = int(current_telemetry.get("broken_beams", 0))
	var grounded_wheels = clampi(int(current_telemetry.get("wheels_grounded", 0)), 0, 4)
	var nodes = int(current_telemetry.get("nodes", 0))
	var beams = int(current_telemetry.get("beams", 0))
	var sim_ms = float(current_telemetry.get("sim_ms", 0.0))
	speed_label.text = "%02d  km/h" % roundi(speed)
	drive_status.text = "%d wheels in contact  ·  %s" % [grounded_wheels, "LOW" if settings.low_range else "HIGH"]
	drive_damage.text = "CHASSIS  %d%%  ·  %d broken beams" % [roundi((1.0 - damage) * 100.0), broken]
	drive_damage.add_theme_color_override("font_color", Color("f09375") if damage > 0.25 or broken > 0 else ACCENT)
	garage_status.text = "LIVE STRUCTURE   %d nodes  /  %d beams\n%d%% chassis health  ·  %d broken  ·  %.1f ms physics  ·  %d fps" % [nodes, beams, roundi((1.0 - damage) * 100.0), broken, sim_ms, Engine.get_frames_per_second()]

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
		KEY_ESCAPE:
			if driving:
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
		if is_instance_valid(pause_overlay):
			get_tree().paused = help_open or pause_overlay.visible
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not help_open and is_instance_valid(ui):
			if driving:
				toggle_pause()
			else:
				show_help()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()
		get_tree().quit()
