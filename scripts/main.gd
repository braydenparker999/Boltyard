extends Node3D

const SAVE = "user://blueprint.json"
const AUTOSAVE = "user://autosave.json"
var blueprint = YardBlueprint.new()
var history: Array = []
var preview: Node3D
var car: YardVehicle
var camera: Camera3D
var ui: Control
var build_panel: PanelContainer
var drive_panel: Control
var grid: BuildGrid
var part_buttons: Dictionary = {}
var layer_buttons: Array = []
var mode_button: Button
var info: Label
var message: Label
var speed_label: Label
var selected = "frame"
var turn = 0
var driving = false
var orbit = 0.62
var distance = 10.0
var toast_time = 0.0
var status_error = ""
var camera_target = Vector3(0, 1.1, 8)
var last_position = Vector3.ZERO
var traveled = 0.0
var air_time = 0.0
var best_jump = 0.0
var performance_timer = 0.0
var low_quality = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	setup_input()
	add_child(TestYard.new())
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 52
	camera.far = 180
	add_child(camera)
	var error = ""
	if FileAccess.file_exists(AUTOSAVE):
		error = blueprint.load_file(AUTOSAVE)
	else:
		error = blueprint.load_file("res://data/starter.json")
	if error != "":
		blueprint.load_file("res://data/starter.json")
	build_ui()
	rebuild_preview()
	if error != "":
		toast("Could not restore autosave; loaded the starter. " + error)
	else:
		toast("Tap DRIVE to try the starter. BUILD returns to your blueprint.")
	get_viewport().size_changed.connect(layout_ui)
	layout_ui()

func setup_input() -> void:
	var keys = {"yard_left": [KEY_A, KEY_LEFT], "yard_right": [KEY_D, KEY_RIGHT], "yard_go": [KEY_W, KEY_UP], "yard_reverse": [KEY_S, KEY_DOWN], "yard_brake": [KEY_SPACE]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func style(color: Color, radius: int = 12) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 9
	result.content_margin_bottom = 9
	return result

func label(parent: Node, text: String, font_size: int = 18, color: Color = Color("e4ece8")) -> Label:
	var item = Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func button(parent: Node, text: String, callback: Callable, width: float = 70) -> Button:
	var item = Button.new()
	item.text = text
	item.custom_minimum_size = Vector2(width, 46)
	item.focus_mode = Control.FOCUS_NONE
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

func row(parent: Node) -> HBoxContainer:
	var item = HBoxContainer.new()
	item.add_theme_constant_override("separation", 7)
	parent.add_child(item)
	return item

func build_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	var theme = Theme.new()
	theme.default_font_size = 17
	theme.set_stylebox("normal", "Button", style(Color("29404b")))
	theme.set_stylebox("hover", "Button", style(Color("3b5760")))
	theme.set_stylebox("pressed", "Button", style(Color("597b7f")))
	theme.set_stylebox("disabled", "Button", style(Color("24333c")))
	theme.set_color("font_color", "Button", Color("eff3ec"))
	theme.set_color("font_disabled_color", "Button", Color("72868d"))
	ui.theme = theme
	var header = PanelContainer.new()
	header.name = "Header"
	header.add_theme_stylebox_override("panel", style(Color("152832")))
	ui.add_child(header)
	header.position = Vector2(24, 16)
	var header_row = row(header)
	var title = label(header_row, "BOLT YARD", 26, Color("ffbd5b"))
	title.custom_minimum_size.x = 185
	var subtitle = label(header_row, "MACHINE WORKSHOP  /  0.1", 13, Color("9bb5bd"))
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(header_row, "Help", show_help, 66)
	button(header_row, "Quality", toggle_quality, 83)
	mode_button = button(header_row, "DRIVE  >", toggle_mode, 136)
	mode_button.add_theme_stylebox_override("normal", style(Color("d99636")))
	mode_button.add_theme_color_override("font_color", Color("152832"))
	build_panel = PanelContainer.new()
	build_panel.position = Vector2(24, 97)
	build_panel.add_theme_stylebox_override("panel", style(Color("152832")))
	ui.add_child(build_panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	build_panel.add_child(column)
	label(column, "01  /  BUILD YOUR MACHINE", 17, Color("ffbd5b"))
	var layers = row(column)
	for index in range(3):
		layer_buttons.append(button(layers, ["Chassis", "Upper", "Top"][index], set_layer.bind(index), 87))
	label(column, "FRONT  ^       Tap a cell to place a part", 12, Color("9bb5bd"))
	grid = BuildGrid.new()
	grid.blueprint = blueprint
	grid.cell_pressed.connect(edit_cell)
	column.add_child(grid)
	var palette = row(column)
	for kind in YardBlueprint.KINDS:
		var item = button(palette, YardBlueprint.SYMBOLS[kind], select_part.bind(kind), 47)
		item.tooltip_text = kind.capitalize()
		part_buttons[kind] = item
	var edits = row(column)
	part_buttons["erase"] = button(edits, "Erase", select_part.bind("erase"), 80)
	button(edits, "Rotate", rotate_part, 87)
	button(edits, "Undo", undo, 80)
	var saves = row(column)
	button(saves, "Save", save_build, 80)
	button(saves, "Load", load_build, 87)
	button(saves, "Starter", starter, 80)
	info = label(ui, "", 18)
	info.position = Vector2(350, 106)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size = Vector2(580, 110)
	message = label(ui, "", 17, Color("fff0ca"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.position = Vector2(350, 575)
	message.size = Vector2(680, 80)
	var camera_tools = row(ui)
	camera_tools.name = "CameraTools"
	button(camera_tools, "Orbit <", orbit_by.bind(-0.35), 80)
	button(camera_tools, ">", orbit_by.bind(0.35), 46)
	button(camera_tools, "Zoom +", zoom_by.bind(-1.3), 86)
	button(camera_tools, "-", zoom_by.bind(1.3), 46)
	drive_panel = Control.new()
	drive_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drive_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(drive_panel)
	drive_panel.hide()
	speed_label = label(drive_panel, "0 km/h", 30, Color("ffbd5b"))
	speed_label.position = Vector2(30, 105)
	var recovery = button(drive_panel, "Recover vehicle", recover, 165)
	recovery.name = "Recover"
	make_touch_button("Left", "<", "yard_left", Vector2(90, 596), Vector2(112, 102))
	make_touch_button("Right", ">", "yard_right", Vector2(220, 596), Vector2(112, 102))
	make_touch_button("Reverse", "REV", "yard_reverse", Vector2(970, 596), Vector2(102, 102))
	make_touch_button("Brake", "BRAKE", "yard_brake", Vector2(1100, 466), Vector2(120, 80))
	make_touch_button("Go", "GO", "yard_go", Vector2(1110, 596), Vector2(150, 102))
	set_layer(0)
	select_part("frame")

func make_touch_button(node_name: String, text: String, action: String, at: Vector2, dimensions: Vector2) -> void:
	var root = Node2D.new()
	root.name = node_name
	root.position = at
	drive_panel.add_child(root)
	var panel = Panel.new()
	panel.position = -dimensions / 2
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style(Color("c98e38") if action == "yard_go" else Color("203946"), 22))
	root.add_child(panel)
	var caption = label(panel, text, 25)
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

func layout_ui() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	ui.get_node("Header").size.x = viewport_size.x - 48
	ui.get_node("CameraTools").position = Vector2(viewport_size.x - 315, viewport_size.y - 67)
	message.size.x = maxf(200, viewport_size.x - 390)
	message.position.y = viewport_size.y - 146
	info.size.x = maxf(200, viewport_size.x - 390)
	drive_panel.get_node("Recover").position = Vector2(viewport_size.x - 194, 104)
	for node_name in ["Left", "Right", "Reverse", "Go"]:
		drive_panel.get_node(node_name).position.y = viewport_size.y - 105
	drive_panel.get_node("Go").position.x = viewport_size.x - 110
	drive_panel.get_node("Reverse").position.x = viewport_size.x - 255
	drive_panel.get_node("Brake").position = Vector2(viewport_size.x - 110, viewport_size.y - 235)

func select_part(kind: String) -> void:
	selected = kind
	for key in part_buttons:
		part_buttons[key].add_theme_stylebox_override("normal", style(Color("516f77") if key == kind else Color("29404b")))
	update_info()

func set_layer(value: int) -> void:
	grid.layer = value
	grid.queue_redraw()
	for index in range(layer_buttons.size()):
		layer_buttons[index].add_theme_stylebox_override("normal", style(Color("516f77") if index == value else Color("29404b")))

func rotate_part() -> void:
	turn = (turn + 1) % 4
	toast("New solid parts rotated %d degrees. Wheels always face sideways." % (turn * 90))
	update_info()

func checkpoint() -> void:
	history.append(blueprint.to_data())
	if history.size() > 40:
		history.pop_front()

func edit_cell(cell: Vector3i) -> void:
	if driving:
		return
	if selected == "erase" and not blueprint.parts.has(cell):
		return
	checkpoint()
	if selected == "erase":
		blueprint.parts.erase(cell)
	else:
		var error = blueprint.put(cell, selected, 0 if selected == "wheel" else turn)
		if error != "":
			history.pop_back()
			toast(error)
			return
	rebuild_preview()
	autosave()

func undo() -> void:
	if history.is_empty():
		toast("Nothing to undo yet.")
		return
	blueprint.from_data(history.pop_back())
	rebuild_preview()
	autosave()

func rebuild_preview() -> void:
	if is_instance_valid(preview):
		preview.free()
	preview = Node3D.new()
	add_child(preview)
	preview.position = Vector3(0, 1, 8)
	for cell in blueprint.parts:
		var item: Dictionary = blueprint.parts[cell]
		var at = Vector3(cell) * YardBlueprint.GRID
		if item.kind == "wheel":
			at.y -= 0.1
		YardShapes.part(preview, item.kind, at, item.turn)
	grid.queue_redraw()
	status_error = blueprint.drive_error()
	update_info()

func update_info() -> void:
	if info == null:
		return
	info.text = "%d / 96 PARTS   |   %d kg\n%s  /  %d degrees\n%s" % [blueprint.parts.size(), roundi(blueprint.total_mass()), selected.capitalize(), turn * 90, "Ready to drive. Front wheels steer; all wheels are powered." if status_error == "" else status_error]

func autosave() -> void:
	if blueprint.save_file(AUTOSAVE) != OK:
		toast("Autosave failed. Keep the app open and try Save.")

func save_build() -> void:
	if blueprint.save_file(SAVE) == OK:
		toast("Blueprint saved on this device. Save replaces this one manual slot.")
	else:
		toast("Could not save the blueprint.")

func load_build() -> void:
	checkpoint()
	var error = blueprint.load_file(SAVE)
	if error != "":
		history.pop_back()
		toast(error)
		return
	rebuild_preview()
	autosave()
	toast("Saved blueprint loaded. Undo restores your previous build.")

func starter() -> void:
	checkpoint()
	var error = blueprint.load_file("res://data/starter.json")
	if error != "":
		history.pop_back()
		toast(error)
		return
	rebuild_preview()
	autosave()
	toast("Starter restored. Undo brings back your previous build.")

func toggle_mode() -> void:
	if not driving:
		var error = blueprint.drive_error()
		if error != "":
			toast(error)
			return
		autosave()
		car = YardVehicle.new()
		car.configure(blueprint)
		car.transform = car.spawn_transform
		add_child(car)
		last_position = car.position
		traveled = 0.0
		air_time = 0.0
		preview.hide()
	else:
		if is_instance_valid(car):
			car.free()
		preview.show()
		camera_target = Vector3(0, 1.1, 8)
	driving = not driving
	build_panel.visible = not driving
	info.visible = not driving
	drive_panel.visible = driving
	ui.get_node("CameraTools").visible = not driving
	mode_button.text = "<  BUILD" if driving else "DRIVE  >"
	clear_controls()
	toast("Hold GO and steer with < >. BRAKE stops; REV reverses. Recover resets a flipped car." if driving else "Back in the workshop. Your blueprint is unchanged.")

func clear_controls() -> void:
	for action in ["yard_left", "yard_right", "yard_go", "yard_reverse", "yard_brake"]:
		Input.action_release(action)
	if is_instance_valid(car):
		car.throttle = 0
		car.steer_input = 0
		car.braking = true

func recover() -> void:
	if is_instance_valid(car):
		car.request_reset()
		last_position = car.spawn_transform.origin
		air_time = 0.0
		clear_controls()
		toast("Vehicle returned to the launch pad.")

func orbit_by(amount: float) -> void:
	orbit += amount

func zoom_by(amount: float) -> void:
	distance = clampf(distance + amount, 6.0, 17.0)

func toggle_quality() -> void:
	low_quality = not low_quality
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		node.shadow_enabled = not low_quality
	get_viewport().scaling_3d_scale = 0.75 if low_quality else 1.0
	toast("Low graphics: shadows off." if low_quality else "Standard graphics: shadows on.")

func show_help() -> void:
	var help = AcceptDialog.new()
	help.title = "Bolt Yard — quick start"
	help.dialog_text = "BUILD\nTap a part, then a grid cell. FRONT is toward the top.\n+ Frame   O Wheel   M Motor   S Seat   W Weight\nChassis / Upper / Top select height. Erase removes a part.\nWheels mount directly beside solid chassis blocks on layer 0.\nUse exactly one seat, at least one motor, and three or more wheels.\nAll solid blocks must touch. Front wheels steer automatically.\nRotate changes new solid parts; the vehicle always drives toward FRONT.\n\nDRIVE\nHold GO + a direction together. REV reverses; BRAKE stops.\nTry the small ramp ahead, bumps to the left, big ramp to the right.\nRecover returns your vehicle to the pad. BUILD returns to editing.\nKeyboard: WASD or arrows, Space brake, R recover, Tab build/drive.\n\nSAVES\nEdits autosave locally. Save / Load use one separate manual slot.\nUndo also reverses Load and Starter. Uninstalling removes local saves.\n\nPrototype: compound chassis and raycast tires, no separate bearings."
	ui.add_child(help)
	help.confirmed.connect(help.queue_free)
	help.canceled.connect(help.queue_free)
	clear_controls()
	get_tree().paused = true
	help.process_mode = Node.PROCESS_MODE_ALWAYS
	help.tree_exiting.connect(func(): get_tree().paused = false)
	help.popup_centered(Vector2i(750, 580))

func toast(text: String) -> void:
	message.text = text
	toast_time = 8.0

func _physics_process(_delta: float) -> void:
	if driving and is_instance_valid(car):
		car.throttle = Input.get_axis("yard_reverse", "yard_go")
		car.steer_input = Input.get_axis("yard_right", "yard_left")
		car.braking = Input.is_action_pressed("yard_brake")
		if car.position.y < -10:
			recover()

func _process(delta: float) -> void:
	toast_time -= delta
	if toast_time <= 0:
		message.text = ""
	var desired: Vector3
	if driving and is_instance_valid(car):
		var target = car.global_position + Vector3.UP * 0.8
		camera_target = camera_target.lerp(target, 1.0 - exp(-6.0 * delta))
		var behind = car.global_basis.z
		behind.y = 0
		if behind.length_squared() < 0.01:
			behind = Vector3.BACK
		desired = camera_target + behind.normalized() * 9.0 + Vector3.UP * 5.0
		var step_distance = car.position.distance_to(last_position)
		if step_distance < 5.0:
			traveled += step_distance
		last_position = car.position
		if car.grounded_wheels == 0:
			air_time += delta
		else:
			best_jump = maxf(best_jump, air_time)
			air_time = 0.0
		performance_timer -= delta
		if performance_timer <= 0:
			performance_timer = 0.15
			speed_label.text = "%02d km/h\n%d m  |  %d wheels grounded\nBest airtime %.1f s  |  %d fps" % [roundi(car.linear_velocity.length() * 3.6), roundi(traveled), car.grounded_wheels, best_jump, Engine.get_frames_per_second()]
	else:
		# Aim left of the model so it sits right of the blueprint panel.
		camera_target = Vector3(-1.1, 1.2, 8)
		desired = camera_target + Vector3(sin(orbit) * distance, distance * 0.72, cos(orbit) * distance)
	camera.position = camera.position.lerp(desired, 1.0 - exp(-5.0 * delta))
	if camera.position.distance_squared_to(camera_target) > 0.01:
		camera.look_at(camera_target)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			toggle_mode()
		elif event.physical_keycode == KEY_R and driving:
			recover()
		elif event.physical_keycode == KEY_ESCAPE:
			show_help()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		clear_controls()
		if is_instance_valid(ui):
			autosave()
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		# A help dialog owns its pause until it closes.
		if is_instance_valid(ui) and ui.find_children("*", "AcceptDialog", false, false).is_empty():
			get_tree().paused = false
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if driving:
			toggle_mode()
		else:
			show_help()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()
		get_tree().quit()

