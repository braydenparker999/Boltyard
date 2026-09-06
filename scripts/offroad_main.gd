extends Node3D

const LEGACY_PATH = "user://offroad_setup.json"
const GARAGE_PATH = "user://offroad_garage_v3.json"
const PAINTS = ["c96c38", "c9b78e", "647263", "537781", "ede7d6", "383f47"]
const INK = Color("111a1d")
const PANEL = Color("142127ec")
const MUTED = Color("a1b4b3")
const PAPER = Color("edf1e9")
const ACCENT = Color("d9bd82")
const ACTIONS = ["off_left", "off_right", "off_go", "off_reverse", "off_brake"]
const CAMP = Vector3(0, 1.5, 8)

const EXPEDITIONS = {
	"rockies": {"name": "SILVERPINE RANGE", "region": "ROCKY MOUNTAINS", "mode": 4, "color": "829b88", "description": "Granite shelves, pine forest and high mountain passes. Find your line through the landscape."},
	"russia": {"name": "KARELIAN TAIGA", "region": "RUSSIA", "mode": 5, "color": "a2af82", "description": "Wet forest tracks, glacial stone and quiet lakes. Crawl through birch and spruce country."}
}
var selected_map = "rockies"
var exploration_progress: Dictionary = {}
var map_buttons: Dictionary = {}
var garage_tabs: Dictionary = {}
var garage_pages: Dictionary = {}
var garage_tab = "trails"
var map_title: Label
var rig_button: Button
var speed_dial: Control
var expedition_label: Label
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
	world = create_world(selected_map)
	world.name = "Trail"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.configure(truck.core)
	world.set_quality(quality)
	add_child(world)
	add_child(truck)
	landmarks = world.get_landmarks()
	restore_exploration_progress()
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
		toast("Drag one finger to look around. Pinch to zoom. Choose a region and explore.")
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
	label(brand, "BOLT YARD", 20)
	expedition_label = label(brand, "EXPEDITIONS", 10, ACCENT)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	map_button = button(header_row, "Map", toggle_map, 65)
	rig_button = button(header_row, "Rig", toggle_rig_controls, 56)
	rig_button.hide()
	xray_button = button(header_row, "Structure", toggle_xray, 78)
	xray_button.hide()
	pause_button = button(header_row, "Pause", toggle_pause, 74)
	pause_button.visible = false
	mode_button = button(header_row, "EXPLORE  ›", toggle_mode, 118)
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
	label(heading, "YOUR EXPEDITION", 12, ACCENT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(heading, "3 rigs / saved builds", 11, MUTED)
	var vehicles = row(content, 6)
	for id in VehicleCatalog.VEHICLES:
		var descriptor: Dictionary = VehicleCatalog.VEHICLES[id]
		var item = button(vehicles, descriptor.name, select_vehicle.bind(id), 60)
		item.add_theme_font_size_override("font_size", 14)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vehicle_buttons[id] = item
	vehicle_description = label(content, "", 12, MUTED)
	vehicle_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tabs = row(content, 5)
	for tab in ["trails", "rig", "tune"]:
		var tab_button = button(tabs, {"trails": "TRAILS", "rig": "EQUIPMENT", "tune": "SETUP"}[tab], show_garage_tab.bind(tab), 60)
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.add_theme_font_size_override("font_size", 12)
		garage_tabs[tab] = tab_button
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 100
	content.add_child(scroll)
	var options = column(scroll, 7)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var trails = column(options, 9)
	garage_pages.trails = trails
	for id in EXPEDITIONS:
		var descriptor: Dictionary = EXPEDITIONS[id]
		var item = button(trails, descriptor.region + "\n" + descriptor.name, select_map.bind(id), 0)
		item.custom_minimum_size.y = 76
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.add_theme_font_size_override("font_size", 16)
		map_buttons[id] = item
	var details = label(trails, "", 13, MUTED)
	details.name = "MapDetails"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	course_button = button(trails, "Fit a crawling setup", fit_crawl_setup, 0)
	label(trails, "640 m regions / open exploration", 12, ACCENT)
	var equipment_page = column(options, 7)
	garage_pages.rig = equipment_page
	section(equipment_page, "PAINT")
	var paints = row(equipment_page, 6)
	for color in PAINTS:
		var swatch = button(paints, "", select_paint.bind(color), 35)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch.custom_minimum_size.y = 38
		swatch.add_theme_stylebox_override("normal", box(Color(color), 8, 4))
		swatch.add_theme_stylebox_override("hover", box(Color(color).lightened(0.2), 8, 4))
		swatch.tooltip_text = ["Rust orange", "Sand", "Forest", "Blue slate", "Ivory", "Graphite"][PAINTS.find(color)]
		paint_buttons[color] = swatch
	section(equipment_page, "INSTALLED EQUIPMENT")
	for slot in VehicleCatalog.SLOTS:
		var wrap = column(equipment_page, 1)
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
	var setup_page = column(options, 7)
	garage_pages.tune = setup_page
	var inspection = row(setup_page)
	button(inspection, "Structure view", toggle_xray, 128).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(inspection, "Field guide", show_help, 100).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(setup_page, "Chassis impact test", impact_test, 100)
	tuning_button = button(setup_page, "Suspension & drivetrain  +", toggle_tuning, 100)
	tuning_content = column(setup_page, 5)
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
	section(setup_page, "DISPLAY")
	quality_picker = OptionButton.new()
	quality_picker.custom_minimum_size.y = 44
	quality_picker.focus_mode = Control.FOCUS_NONE
	for quality_name in ["Performance", "Balanced", "High"]:
		quality_picker.add_item(quality_name)
	quality_picker.item_selected.connect(change_quality)
	setup_page.add_child(quality_picker)
	var quality_note = label(setup_page, "Performance uses a lighter 3D resolution with sharp controls. Balanced and High add detail. Rotate your phone at any time.", 12, MUTED)
	quality_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage_footer = row(content, 7)
	button(garage_footer, "Save build", save_with_toast, 90).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(garage_footer, "Repair rig", recover, 110).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage_overlay = Control.new()
	garage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(garage_overlay)
	title_label = label(garage_overlay, "", 20)
	title_label.add_theme_stylebox_override("normal", box(PANEL, 10, 10))
	var camera_tools = row(garage_overlay, 6)
	camera_tools.name = "CameraTools"
	button(camera_tools, "Impact test", impact_test, 112)
	camera_tools.hide()
	garage_status = label(garage_overlay, "", 12, MUTED)
	garage_status.add_theme_stylebox_override("normal", box(PANEL, 10, 10))
	garage_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage_status.hide()
	show_garage_tab(garage_tab)
	update_map_selection()

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
	var dashboard = Control.new()
	dashboard.name = "Dashboard"
	dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.custom_minimum_size = Vector2(160, 164)
	drive_panel.add_child(dashboard)
	speed_dial = preload("res://scripts/trail_dashboard.gd").new()
	speed_dial.size = Vector2(140, 140)
	speed_dial.position = Vector2(10, 0)
	dashboard.add_child(speed_dial)
	speed_label = label(dashboard, "0.0", 30)
	speed_label.position = Vector2(0, 43)
	speed_label.size = Vector2(160, 40)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var units = label(dashboard, "km/h", 11, MUTED)
	units.position = Vector2(0, 82)
	units.size.x = 160
	units.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drive_status = label(dashboard, "LOW / 4WD", 10, ACCENT)
	drive_status.position = Vector2(0, 104)
	drive_status.size.x = 160
	drive_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drive_damage = label(dashboard, "RIG 100%", 10, MUTED)
	drive_damage.position = Vector2(0, 144)
	drive_damage.size.x = 160
	drive_damage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var navigation = PanelContainer.new()
	navigation.name = "Navigation"
	navigation.add_theme_stylebox_override("panel", box(Color("142127ba"), 10, 10))
	drive_panel.add_child(navigation)
	navigation_label = label(navigation, "", 12)
	navigation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rig_backdrop = Panel.new()
	rig_backdrop.name = "RigBackdrop"
	rig_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	rig_backdrop.add_theme_stylebox_override("panel", box(Color("142127ec"), 12, 10))
	drive_panel.add_child(rig_backdrop)
	rig_backdrop.hide()
	var equipment = row(drive_panel, 6)
	equipment.name = "Equipment"
	drive_low = button(equipment, "LOW", toggle_drive_low, 76)
	drive_diff = button(equipment, "LOCKED", toggle_drive_diff, 90)
	button(equipment, "Recover", recover, 86)
	equipment.hide()
	crawl_controls = column(drive_panel, 5)
	crawl_controls.name = "CrawlControls"
	crawl_controls.hide()
	var throttle_label = label(crawl_controls, "THROTTLE LIMIT  /  35%", 12, ACCENT)
	var pedal = HSlider.new()
	pedal.min_value = 0.10
	pedal.max_value = 1.0
	pedal.step = 0.05
	pedal.value = throttle_limit
	pedal.custom_minimum_size = Vector2(254, 44)
	pedal.value_changed.connect(func(value):
		throttle_limit = value
		throttle_label.text = "THROTTLE LIMIT  /  %d%%" % roundi(value * 100))
	crawl_controls.add_child(pedal)
	var axles = row(crawl_controls, 6)
	front_diff = button(axles, "F / LOCK", toggle_axle_diff.bind("front_locked"), 124)
	rear_diff = button(axles, "R / LOCK", toggle_axle_diff.bind("rear_locked"), 124)
	front_diff.add_theme_font_size_override("font_size", 12)
	rear_diff.add_theme_font_size_override("font_size", 12)
	crawl_loads = label(crawl_controls, "", 11, MUTED)
	make_touch_button("Left", "‹", "off_left", Vector2(84, 84))
	make_touch_button("Right", "›", "off_right", Vector2(84, 84))
	make_touch_button("Reverse", "R", "off_reverse", Vector2(78, 78))
	make_touch_button("Brake", "BRAKE", "off_brake", Vector2(72, 72))
	make_touch_button("Go", "↑", "off_go", Vector2(98, 98))

func toggle_rig_controls() -> void:
	if not driving:
		return
	clear_controls()
	crawl_controls.visible = not crawl_controls.visible
	drive_panel.get_node("Equipment").visible = crawl_controls.visible
	drive_panel.get_node("RigBackdrop").visible = crawl_controls.visible
	rig_button.text = "Rig ×" if crawl_controls.visible else "Rig"
	layout_ui()

func make_touch_button(node_name: String, text: String, action: String, dimensions: Vector2) -> void:
	var touch_root = Node2D.new()
	touch_root.name = node_name
	drive_panel.add_child(touch_root)
	var panel = Panel.new()
	panel.size = dimensions
	panel.position = -dimensions / 2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", box(Color("d9bd82e8") if action == "off_go" else Color("142127bb"), 100, 0))
	touch_root.add_child(panel)
	var caption = label(panel, text, 48 if action in ["off_left", "off_right"] else (36 if action == "off_go" else (14 if action == "off_brake" else 22)), INK if action == "off_go" else PAPER)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var touch = TouchScreenButton.new()
	var shape = CircleShape2D.new()
	shape.radius = minf(dimensions.x, dimensions.y) * 0.5
	touch.shape = shape
	touch.action = action
	touch.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	touch_root.add_child(touch)
	touch_buttons[action] = {"root": touch_root, "panel": panel, "touch": touch, "down": false}

func build_camera_tools() -> void:
	camera_toolbar = PanelContainer.new()
	camera_toolbar.name = "CameraToolbar"
	camera_toolbar.add_theme_stylebox_override("panel", box(Color("142127b8"), 12, 6))
	ui.add_child(camera_toolbar)
	var content = column(camera_toolbar, 3)
	var controls = row(content, 6)
	camera_drag_button = button(controls, "Orbit", toggle_camera_drag, 76)
	camera_follow_button = button(controls, "Follow", toggle_camera_follow, 76)
	camera_follow_button.tooltip_text = "Follow turns behind the rig. Off keeps your viewing angle while traveling with it."
	button(controls, "Center", reset_camera, 76)
	camera_hint = label(content, "1 finger to look · pinch to zoom", 11, MUTED)
	update_camera_tools()

func update_camera_tools() -> void:
	if not is_instance_valid(camera_toolbar):
		return
	camera_drag_button.text = "Pan" if camera_pan_mode else "Orbit"
	camera_follow_button.visible = driving
	camera_follow_button.text = "Follow ✓" if camera_follow else "Follow"
	camera_hint.text = "1 finger %s · pinch zoom" % ("pan" if camera_pan_mode else "look")
	camera_toolbar.reset_size()

func toggle_camera_drag() -> void:
	camera_gestures.cancel()
	camera_pan_mode = not camera_pan_mode
	update_camera_tools()
	camera_save_delay = 0.6
	toast("Drag one finger to pan. Pinch to zoom." if camera_pan_mode else "Drag one finger to orbit and tilt. Pinch to zoom.")

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
		var tools: Control = garage_overlay.get_node("CameraTools")
		return tools.is_visible_in_tree() and tools.get_global_rect().has_point(point)
	for name in ["Navigation", "Equipment", "CrawlControls", "RigBackdrop"]:
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
	var yaw_delta = -drag.x * TAU if not camera_pan_mode else 0.0
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
	map_title = label(heading, "REGION MAP", 18)
	map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading, "Close", toggle_map, 70)
	map_status = label(content, "", 12, ACCENT)
	map_canvas = ExplorationMap.new()
	map_canvas.custom_minimum_size = Vector2(180, 180)
	map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_canvas.extent = 384.0 if selected_map == "legacy" else 320.0
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
	var margin = 18.0
	header.position = Vector2(margin, 14)
	header.size = Vector2(extent.x - margin * 2, 62)
	var brand = header.get_child(0).get_node("Brand")
	brand.visible = true
	mode_button.custom_minimum_size.x = 98 if portrait else 118
	if portrait:
		var sheet_y = maxf(420.0, extent.y * 0.53)
		garage_panel.position = Vector2(margin, sheet_y)
		garage_panel.size = Vector2(extent.x - margin * 2, extent.y - sheet_y - 18)
		garage_overlay.position = Vector2(margin, 92)
		garage_overlay.size = Vector2(extent.x - margin * 2, sheet_y - 100)
		camera_toolbar.position = Vector2(extent.x - camera_toolbar.size.x - margin, sheet_y - 80)
	else:
		garage_panel.position = Vector2(margin, 94)
		garage_panel.size = Vector2(350, maxf(300, extent.y - 112))
		garage_overlay.position = Vector2(392, 96)
		garage_overlay.size = Vector2(maxf(280, extent.x - 412), extent.y - 120)
		camera_toolbar.position = Vector2(extent.x - camera_toolbar.size.x - margin, extent.y - 98)
	var dashboard: Control = drive_panel.get_node("Dashboard")
	dashboard.position = Vector2(extent.x * 0.5 - 80, extent.y - 184)
	dashboard.size = Vector2(160, 164)
	var navigation: Control = drive_panel.get_node("Navigation")
	navigation.position = Vector2(margin, 90)
	navigation.size = Vector2(minf(348, extent.x - 332), 60)
	drive_panel.get_node("Equipment").position = Vector2(margin, 168)
	crawl_controls.position = Vector2(margin + 12, 226)
	drive_panel.get_node("Equipment").position.x = margin + 12
	drive_panel.get_node("RigBackdrop").position = Vector2(margin, 156)
	drive_panel.get_node("RigBackdrop").size = Vector2(280, 270)
	if driving:
		camera_toolbar.position = Vector2(extent.x - camera_toolbar.size.x - margin, 90)
	message.position = Vector2(392, 148) if not portrait and not driving else Vector2(margin, 170 if not driving else 160)
	message.size = Vector2(maxf(220, extent.x - 414), 52) if not portrait and not driving else Vector2(extent.x - margin * 2, 52)
	if driving:
		message.position = Vector2(extent.x * 0.5 - minf(230.0, extent.x * 0.3), extent.y - 248)
		message.size = Vector2(minf(460.0, extent.x * 0.6), 52)
	var bottom = extent.y - 72
	touch_buttons.off_left.root.position = Vector2(margin + 42, bottom)
	touch_buttons.off_right.root.position = Vector2(margin + 138, bottom)
	touch_buttons.off_go.root.position = Vector2(extent.x - margin - 49, bottom - 9)
	touch_buttons.off_reverse.root.position = Vector2(extent.x - margin - 148, bottom + 1)
	touch_buttons.off_brake.root.position = Vector2(extent.x - margin - 49, bottom - 111)
	pause_overlay.size = Vector2(minf(380, extent.x - 40), 276)
	pause_overlay.position = (extent - pause_overlay.size) / 2
	map_overlay.size = Vector2(minf(720, extent.x - 36), minf(860, extent.y - 40))
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
	tuning_button.text = "Suspension & drivetrain  −" if tuning_content.visible else "Suspension & drivetrain  +"

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
	drive_diff.visible = false
	front_diff.text = "F / %s" % ("LOCK" if settings.front_locked else "OPEN")
	rear_diff.text = "R / %s" % ("LOCK" if settings.rear_locked else "OPEN")
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
	title_label.text = str(VehicleCatalog.VEHICLES[selected_vehicle].name) + "  /  " + (str(EXPEDITIONS[selected_map].name) if EXPEDITIONS.has(selected_map) else "WORKSHOP")
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
	mode_button.text = "Garage" if driving else "EXPLORE  ›"
	rig_button.visible = driving
	if not driving:
		crawl_controls.hide()
		drive_panel.get_node("Equipment").hide()
		drive_panel.get_node("RigBackdrop").hide()
		rig_button.text = "Rig"
	update_camera_tools()
	if not driving:
		truck.reset(recovery_point())
		pause_overlay.hide()
		get_tree().paused = false
		pause_button.text = "Pause"
	did_position_camera = false
	layout_ui()
	save_settings()
	toast("Hold ↑ to drive. Drag one finger on the scenery to look around. Rig opens trail controls." if driving else "Choose a trail, fit equipment or adjust your setup.")

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
		destination = ids[1 if EXPEDITIONS.has(selected_map) and ids.size() > 1 else 0] if not ids.is_empty() else ""

func update_map() -> void:
	if crawl_mode:
		return
	map_title.text = str(EXPEDITIONS[selected_map].name) if EXPEDITIONS.has(selected_map) else "VALLEY MAP"
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
	dialog.dialog_text = "BUILD YOUR RIG\nPickup, Scout and Buggy each keep a separate build.\nEquipment changes compatible parts and their matching settings.\nFine tuning overrides those settings. Reset tuning restores installed parts.\n\nEXPLORE\nSelect a destination on the map, then follow the compass.\nPlaces are discovered when you actually drive close to them.\nCamp repairs the vehicle and returns you to the workshop.\nHold the up arrow plus a steering arrow. R reverses; the pause-shaped pedal brakes.\nLow range and locked differentials help with slow climbs.\nRig opens throttle and independent front / rear differential controls.\nKeyboard: WASD / arrows, Space brake, R camp, M map, Tab garage.\n\nCAMERA · ONE FINGER ON THE SCENERY\nDrag to orbit and tilt. Two fingers pinch to zoom only.\nTap Pan to move the view sideways or up/down with one finger.\nOrbit turns Follow off; Follow returns behind the rig. Center resets the view.\nButtons and pedals keep their touches. Lift fingers before changing modes.\n\nDISPLAY & SAVES\nBoth portrait and landscape layouts work; rotate at any time.\nPerformance, Balanced and High adjust scenery and shadows.\nAll builds and discoveries save on this device. The old setup is retained.\n\nPHYSICS\nThe frame and cabin deform; tires use round contacts and visual squash. Parts change the simulated build.\nRelative tire pressure is a stiffness/grip multiplier, not calibrated bar.\nTire, suspension and drivetrain models remain simplified."
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
		var map_id = parsed.get("selected_map", "rockies")
		if map_id is String and map_id in ["rockies", "russia", "legacy"]:
			selected_map = map_id
		var per_map = parsed.get("map_progress", {})
		if per_map is Dictionary:
			for id in ["rockies", "russia", "legacy"]:
				if per_map.get(id) is Dictionary:
					exploration_progress[id] = per_map[id].duplicate(true)
		var old_progress_map = selected_map if parsed.has("selected_map") else "legacy"
		if not exploration_progress.has(old_progress_map):
			exploration_progress[old_progress_map] = {"discovered": parsed.get("discovered", []), "destination": parsed.get("destination", "")}
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
	store_exploration_progress()
	var temporary = GARAGE_PATH + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 3, "selected_vehicle": selected_vehicle, "builds": builds, "discovered": discovered, "destination": destination, "quality": quality, "selected_map": selected_map if not crawl_mode else "legacy", "map_progress": exploration_progress, "camera": camera_preferences()}, "\t"))
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
	truck.throttle = Input.get_axis("off_reverse", "off_go") * (throttle_limit if settings.low_range else 1.0) if driving else 0.0
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
		if position.y < -50.0 or (driving and (absf(position.x) > (365.0 if selected_map == "legacy" else 316.0) or absf(position.z) > (365.0 if selected_map == "legacy" else 316.0))):
			recover()
			toast("Region edge reached. Recovered at camp with discoveries saved.")

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
	if truck.core.has_method("camera_safe_position"):
		desired = truck.core.camera_safe_position(sight_anchor, desired, 0.22)
	if not did_position_camera:
		camera_target = target
		camera.position = desired
		did_position_camera = true
	else:
		camera_target = camera_target.lerp(target, 1.0 - exp(-7.0 * delta))
		camera.position = camera.position.lerp(desired, 1.0 - exp(-7.0 * delta))
	camera.position.y = maxf(camera.position.y, float(truck.core.terrain_height(camera.position.x, camera.position.z)) + 0.4)
	if truck.core.has_method("camera_safe_position"):
		camera.position = truck.core.camera_safe_position(sight_anchor, camera.position, 0.22)
	if camera.position.distance_squared_to(camera_target) > 0.01:
		camera.look_at(camera_target, Vector3.UP)

func update_telemetry() -> void:
	var speed = absf(float(current_telemetry.get("speed", 0.0))) * 3.6
	var damage = clampf(float(current_telemetry.get("damage", 0.0)), 0.0, 1.0)
	var broken = int(current_telemetry.get("broken_beams", 0))
	var grounded = clampi(int(current_telemetry.get("wheels_grounded", 0)), 0, 4)
	speed_label.text = "%.1f" % speed if speed < 10.0 else "%02d" % roundi(speed)
	speed_dial.speed = speed
	speed_dial.queue_redraw()
	drive_status.text = "%s / %d CONTACT" % ["LOW" if settings.low_range else "HIGH", grounded]
	drive_damage.text = "RIG %d%%" % roundi((1.0 - damage) * 100.0)
	drive_damage.add_theme_color_override("font_color", Color("f09375") if damage > 0.25 or broken > 0 else ACCENT)
	garage_status.text = "%d%% chassis · %d broken beams · %d fps\n%d / %d places discovered" % [roundi((1.0 - damage) * 100.0), broken, Engine.get_frames_per_second(), discovered.size(), landmarks.size()]
	if crawl_controls.visible or crawl_mode:
		var loads = current_telemetry.get("wheel_normal_loads", current_telemetry.get("wheel_loads", PackedFloat32Array([0, 0, 0, 0])))
		var squash = current_telemetry.get("wheel_compression", PackedFloat32Array([0, 0, 0, 0]))
		var flex = current_telemetry.get("axle_articulation", PackedFloat32Array([0, 0]))
		crawl_loads.text = "TIRE LOAD / kN  %.1f · %.1f / %.1f · %.1f\nCOMPRESSION / mm  %.0f · %.0f / %.0f · %.0f\nAXLE FLEX  F %.0f° / R %.0f°" % [loads[0] / 1000.0, loads[1] / 1000.0, loads[2] / 1000.0, loads[3] / 1000.0, squash[0] * 1000.0, squash[1] * 1000.0, squash[2] * 1000.0, squash[3] * 1000.0, rad_to_deg(flex[0]), rad_to_deg(flex[1])]
	if crawl_mode:
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
		return Vector3(0, float(truck.core.terrain_height(0, 8)) + 1.5, 8)
	return Vector3(0, 1.5, [8.0, -11.0, -24.0, -41.5, -55.0, -80.0][crawl_section])

func create_world(id: String):
	if id == "copperline":
		return load("res://scripts/crawl_world.gd").new()
	if id == "legacy":
		return OffroadWorld.new()
	var result = load("res://scripts/expedition_world.gd").new()
	result.map_mode = int(EXPEDITIONS[id].mode)
	return result

func show_garage_tab(id: String) -> void:
	garage_tab = id
	for key in garage_pages:
		garage_pages[key].visible = key == id
	for key in garage_tabs:
		var style = box(Color("3b4e4b") if key == id else Color("202f35"), 8, 8)
		if key == id:
			style.border_width_bottom = 2
			style.border_color = ACCENT
		garage_tabs[key].add_theme_stylebox_override("normal", style)

func update_map_selection() -> void:
	for id in map_buttons:
		var style = box(Color("324641") if selected_map == id else Color("203039"), 12, 12)
		style.border_width_left = 4
		style.border_color = Color(EXPEDITIONS[id].color)
		if selected_map == id:
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
		map_buttons[id].add_theme_stylebox_override("normal", style)
	if EXPEDITIONS.has(selected_map):
		garage_pages.trails.get_node("MapDetails").text = str(EXPEDITIONS[selected_map].description)
		expedition_label.text = str(EXPEDITIONS[selected_map].region)
	else:
		garage_pages.trails.get_node("MapDetails").text = "Legacy workshop terrain"
		expedition_label.text = "WORKSHOP"

func store_exploration_progress() -> void:
	if not crawl_mode:
		exploration_progress[selected_map] = {"discovered": discovered.duplicate(), "destination": destination}

func restore_exploration_progress() -> void:
	discovered.clear()
	destination = ""
	var progress = exploration_progress.get(selected_map, {})
	if progress is Dictionary:
		var visited = progress.get("discovered", [])
		if visited is Array:
			for id in visited:
				if id is String and not id in discovered:
					discovered.append(id)
		if progress.get("destination") is String:
			destination = progress.destination
	validate_exploration()

func refresh_map_destinations() -> void:
	map_canvas.extent = 384.0 if selected_map == "legacy" else 320.0
	map_canvas.configure(truck.core, landmarks)
	map_title.text = str(EXPEDITIONS[selected_map].name) if EXPEDITIONS.has(selected_map) else "WORKSHOP MAP"
	var grid: GridContainer = map_overlay.get_child(0).get_node("Destinations")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	map_rows.clear()
	for landmark in landmarks:
		var item = button(grid, str(landmark.name), select_destination.bind(str(landmark.id)), 100)
		item.add_theme_font_size_override("font_size", 12)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item.tooltip_text = str(landmark.get("description", ""))
		map_rows[str(landmark.id)] = item
	update_map()

func select_map(id: String) -> void:
	if driving or id == selected_map or not id in ["rockies", "russia", "copperline", "legacy"]:
		return
	clear_controls()
	store_exploration_progress()
	selected_map = id
	crawl_mode = selected_map == "copperline"
	crawl_section = 0
	var previous = world
	world = create_world(selected_map)
	world._environment = previous._environment
	world._sun = previous._sun
	world._reflection = previous._reflection
	for light in [previous._environment, previous._sun, previous.get_node_or_null("OpenSkyFill"), previous._reflection]:
		if is_instance_valid(light):
			light.get_parent().remove_child(light)
			world.add_child(light)
	remove_child(previous)
	previous.queue_free()
	world.name = "Trail"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.configure(truck.core)
	world.set_quality(quality)
	add_child(world)
	landmarks = world.get_landmarks()
	restore_exploration_progress()
	map_button.disabled = crawl_mode
	crawl_controls.hide()
	drive_panel.get_node("Equipment").hide()
	drive_panel.get_node("RigBackdrop").hide()
	update_map_selection()
	refresh_map_destinations()
	sync_controls()
	truck.reset(recovery_point())
	current_telemetry = truck.get_telemetry()
	did_position_camera = false
	save_settings()
	toast((str(EXPEDITIONS[selected_map].name) + " ready. Choose your line.") if EXPEDITIONS.has(selected_map) else "Workshop terrain ready.")

func toggle_course() -> void:
	# Retained for the legacy course regression fixture. Primary navigation is
	# the two named exploration regions; no hidden boolean selects their core.
	select_map("legacy" if crawl_mode else "copperline")

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
