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

var settings: Dictionary = {}
var builds: Dictionary = {}
var selected_vehicle = "pickup"
var discovered: Array[String] = []
var destination = ""
var quality = 0
var truck
var world
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
var orbit = 0.72
var orbit_distance = 9.3
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
	label(brand, "VALLEY EXPEDITION  /  0.3", 10, ACCENT)
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
	tuning_slider(tuning_content, "damping", "Damping", "Controls how quickly the suspension settles.", 250.0)
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
	var quality_note = label(options, "Performance keeps a lighter view for longer exploration. Rotate your phone at any time.", 12, MUTED)
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
	button(camera_tools, "‹", orbit_by.bind(-0.35), 45)
	button(camera_tools, "›", orbit_by.bind(0.35), 45)
	button(camera_tools, "+", zoom_by.bind(-0.8), 42)
	button(camera_tools, "−", zoom_by.bind(0.8), 42)
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
		message.position = Vector2(margin, 286 if driving else 151)
		message.size = Vector2(extent.x - margin * 2, 54)
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
		message.position = Vector2(392, extent.y - 64) if not driving else Vector2(285, 188)
		message.size = Vector2(maxf(240, extent.x - 414), 44) if not driving else Vector2(maxf(280, extent.x - 590), 58)
		drive_panel.get_node("Dashboard").position = Vector2(margin, 98)
		drive_panel.get_node("Navigation").position = Vector2(280, 98)
		drive_panel.get_node("Navigation").size = Vector2(maxf(240, extent.x - 590), 68)
		drive_panel.get_node("Equipment").position = Vector2(extent.x - 290, 98)
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
		"damping": return "%.2f kNs/m" % (value / 1000.0)
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
	builds[selected_vehicle].tuning[key] = value
	settings = VehicleCatalog.compose(active_build())
	truck.set_drivetrain(settings.low_range, settings.locked_diffs)
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
	save_settings()
	toast("Graphics: %s. Use Performance if exploration starts to slow down." % ["Performance", "Balanced", "High"][quality])

func update_paint_buttons() -> void:
	for color in paint_buttons:
		var background = box(Color(color), 8, 4)
		if color == settings.paint:
			background.set_border_width_all(3)
			background.border_color = PAPER
		paint_buttons[color].add_theme_stylebox_override("normal", background)

func update_drive_toggles() -> void:
	drive_low.text = "LOW" if settings.low_range else "HIGH"
	drive_diff.text = "LOCKED" if settings.locked_diffs else "OPEN"
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

func toggle_xray() -> void:
	xray = not xray
	truck.wireframe = xray
	xray_button.text = "X-ray ✓" if xray else "X-ray"
	xray_button.add_theme_stylebox_override("normal", box(Color("56634f") if xray else Color("2b3c43"), 10))
	toast("Structure view: the physical beams and tire nodes." if xray else "Body view restored.")

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
	if not driving:
		truck.reset(CAMP)
		pause_overlay.hide()
		get_tree().paused = false
		pause_button.text = "Pause"
	did_position_camera = false
	layout_ui()
	save_settings()
	toast("Choose a destination on the map. Hold GO and a steering arrow together." if driving else "At base camp. Fit equipment or fine-tune your build.")

func recover() -> void:
	clear_controls()
	truck.reset(CAMP)
	recovery_cooldown = 1.0
	did_position_camera = false
	toast("Vehicle repaired at base camp. Your discoveries are saved.")

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
	orbit += amount

func zoom_by(amount: float) -> void:
	orbit_distance = clampf(orbit_distance + amount, 6.8, 13.0)

func clear_controls() -> void:
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
	if help_open or backgrounded:
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
	map_status.text = "%d / %d places discovered" % [discovered.size(), landmarks.size()]
	var position: Vector3 = current_telemetry.get("position", CAMP)
	map_canvas.update_state(position, discovered, destination)
	for landmark in landmarks:
		var id = str(landmark.id)
		var item: Button = map_rows[id]
		item.text = ("✓  " if id in discovered else "○  ") + str(landmark.name)
		item.add_theme_stylebox_override("normal", box(Color("58634f") if id == destination else Color("2b3c43"), 10))

func check_discoveries(position: Vector3) -> void:
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
	dialog.dialog_text = "BUILD YOUR RIG\nPickup, Scout and Buggy each keep a separate build.\nEquipment changes compatible parts and their matching settings.\nFine tuning overrides those settings. Reset tuning restores installed parts.\n\nEXPLORE\nSelect a destination on the map, then follow the compass.\nPlaces are discovered when you actually drive close to them.\nCamp repairs the vehicle and returns you to the workshop.\nHold GO plus a steering arrow. REV reverses; BRAKE slows the wheels.\nLow range and locked differentials help with slow climbs.\nKeyboard: WASD / arrows, Space brake, R camp, M map, Tab garage.\n\nDISPLAY & SAVES\nBoth portrait and landscape layouts work; rotate at any time.\nPerformance, Balanced and High adjust scenery and shadows.\nAll builds and discoveries save on this device. The old setup is retained.\n\nPHYSICS\nThe frame and tires are deformable. Parts change the simulated build.\nRelative tire pressure is a stiffness/grip multiplier, not calibrated bar.\nTire, suspension and drivetrain models remain simplified."
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

func save_settings() -> bool:
	if builds.is_empty():
		return false
	var temporary = GARAGE_PATH + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 3, "selected_vehicle": selected_vehicle, "builds": builds, "discovered": discovered, "destination": destination, "quality": quality}, "\t"))
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
	truck.throttle = Input.get_axis("off_reverse", "off_go") if driving else 0.0
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
	recovery_cooldown = maxf(0.0, recovery_cooldown - delta)
	if tuning_delay >= 0:
		tuning_delay -= delta
		if tuning_delay < 0:
			apply_tuning()
	current_telemetry = truck.get_telemetry()
	update_camera(delta)
	telemetry_delay -= delta
	var position: Vector3 = current_telemetry.get("position", CAMP)
	if telemetry_delay <= 0:
		telemetry_delay = 0.12
		update_telemetry()
		world.update_focus(position)
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
		var forward: Vector3 = current_telemetry.get("forward", Vector3.FORWARD)
		forward.y = 0.0
		if forward.length_squared() > 0.01:
			follow_direction = follow_direction.lerp(-forward.normalized(), 1.0 - exp(-1.8 * delta)).normalized()
		desired = target + follow_direction * (9.5 if portrait else 8.8) + Vector3.UP * (5.1 if portrait else 4.4)
		# A little look-ahead keeps the trail visible in the narrower portrait view.
		target -= follow_direction * (2.0 if portrait else 0.7)
	else:
		var preview_distance = orbit_distance * (1.14 if portrait else 1.0)
		var offset = Vector3(sin(orbit) * preview_distance, preview_distance * 0.53, cos(orbit) * preview_distance)
		desired = position + offset
		if portrait:
			target -= Vector3.UP * 3.0
		else:
			var camera_right = Vector3(cos(orbit), 0.0, -sin(orbit))
			target -= camera_right * 1.9
			desired -= camera_right * 1.9
	# Follow terrain when the camera crosses a hill instead of disappearing below it.
	desired.y = maxf(desired.y, float(truck.core.terrain_height(desired.x, desired.z)) + 1.2)
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
	var grounded = clampi(int(current_telemetry.get("wheels_grounded", 0)), 0, 4)
	speed_label.text = "%02d  km/h" % roundi(speed)
	drive_status.text = "%d wheels grounded · %s" % [grounded, "LOW" if settings.low_range else "HIGH"]
	drive_damage.text = "CHASSIS %d%% · %d broken" % [roundi((1.0 - damage) * 100.0), broken]
	drive_damage.add_theme_color_override("font_color", Color("f09375") if damage > 0.25 or broken > 0 else ACCENT)
	garage_status.text = "%d%% chassis · %d broken beams · %d fps\n%d / %d places discovered" % [roundi((1.0 - damage) * 100.0), broken, Engine.get_frames_per_second(), discovered.size(), landmarks.size()]
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
