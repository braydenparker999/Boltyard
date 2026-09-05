class_name YardBlueprint
extends RefCounted

const GRID = 0.7
const LIMIT = 96
const KINDS = ["frame", "wheel", "motor", "seat", "weight"]
const MASS = {"frame": 12.0, "wheel": 9.0, "motor": 38.0, "seat": 16.0, "weight": 65.0}
const COLORS = {
	"frame": Color("8babb7"), "wheel": Color("33434c"),
	"motor": Color("ffb84d"), "seat": Color("57ccb5"), "weight": Color("be889b")
}
const SYMBOLS = {"frame": "+", "wheel": "O", "motor": "M", "seat": "S", "weight": "W"}
const DIRECTIONS = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
var parts: Dictionary = {}

static func in_bounds(cell: Vector3i) -> bool:
	return absi(cell.x) <= 3 and absi(cell.z) <= 4 and cell.y >= 0 and cell.y <= 2

func put(cell: Vector3i, kind: String, turn: int = 0) -> String:
	if not in_bounds(cell) or kind not in KINDS:
		return "Choose a cell inside the build area."
	if parts.size() >= LIMIT and not parts.has(cell):
		return "Prototype limit: 96 parts."
	if kind == "wheel" and cell.y != 0:
		return "Wheels belong on the chassis layer."
	parts[cell] = {"kind": kind, "turn": posmod(turn, 4)}
	return ""

func count_kind(kind: String) -> int:
	var count = 0
	for item in parts.values():
		if item.kind == kind:
			count += 1
	return count

func total_mass() -> float:
	var result = 0.0
	for item in parts.values():
		result += MASS[item.kind]
	return result

func weighted_center() -> Vector3:
	var result = Vector3.ZERO
	for cell in parts:
		result += Vector3(cell) * GRID * MASS[parts[cell].kind]
	return result / maxf(total_mass(), 1.0)

func drive_error() -> String:
	if count_kind("seat") != 1:
		return "Add exactly one driver seat."
	if count_kind("motor") < 1:
		return "Add a motor to power the wheels."
	if count_kind("wheel") < 3:
		return "Add at least three wheels; four is a good start."
	var solid: Dictionary = {}
	for cell in parts:
		if parts[cell].kind != "wheel":
			solid[cell] = true
	if solid.is_empty():
		return "Build a connected chassis first."
	var reached: Dictionary = {}
	var todo: Array = [solid.keys()[0]]
	while not todo.is_empty():
		var cell: Vector3i = todo.pop_back()
		if reached.has(cell):
			continue
		reached[cell] = true
		for direction in DIRECTIONS:
			var neighbor: Vector3i = cell + direction
			if solid.has(neighbor) and not reached.has(neighbor):
				todo.append(neighbor)
	if reached.size() != solid.size():
		return "Connect every solid part face to face. Wheels cannot bridge a gap."
	var left_wheels = 0
	var right_wheels = 0
	for cell in parts:
		if parts[cell].kind != "wheel":
			continue
		if cell.x == 0 or cell.y != 0:
			return "Mount wheels on the left and right sides of the chassis."
		var inside = cell + Vector3i(-signi(cell.x), 0, 0)
		if not solid.has(inside):
			return "Each wheel needs a solid part immediately toward the center."
		if solid.has(cell + Vector3i(signi(cell.x), 0, 0)):
			return "Keep the outside of each wheel clear."
		if cell.x < 0:
			left_wheels += 1
		else:
			right_wheels += 1
	if left_wheels == 0 or right_wheels == 0:
		return "Put wheels on both sides."
	return ""

func to_data() -> Dictionary:
	var rows: Array = []
	for cell in parts:
		rows.append({"x": cell.x, "y": cell.y, "z": cell.z, "kind": parts[cell].kind, "turn": parts[cell].turn})
	return {"version": 1, "parts": rows}

# Validate into a separate dictionary so a damaged file never replaces a good build.
func from_data(data: Variant) -> String:
	if not data is Dictionary or data.get("version") != 1 or not data.get("parts") is Array:
		return "This is not a Bolt Yard version 1 blueprint."
	if data.parts.size() > LIMIT:
		return "This blueprint exceeds the 96-part limit."
	var candidate: Dictionary = {}
	for row in data.parts:
		if not row is Dictionary:
			return "Invalid part record."
		for field in ["x", "y", "z", "turn"]:
			var value: Variant = row.get(field)
			if not (value is int or value is float):
				return "Invalid part coordinates."
			if not is_finite(float(value)) or float(value) != floor(float(value)) or absf(float(value)) > 100.0:
				return "Invalid part coordinates."
		if row.get("kind") not in KINDS:
			return "Unknown part type."
		var cell = Vector3i(int(row.x), int(row.y), int(row.z))
		if not in_bounds(cell) or candidate.has(cell) or int(row.turn) < 0 or int(row.turn) > 3:
			return "Overlapping or out-of-range parts."
		if row.kind == "wheel" and cell.y != 0:
			return "Wheel is above the chassis layer."
		candidate[cell] = {"kind": row.kind, "turn": int(row.turn)}
	parts = candidate
	return ""

func save_file(path: String) -> Error:
	var temp = path + ".tmp"
	var file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_data(), "\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(temp, path)

func load_file(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "No saved blueprint in this slot."
	if file.get_length() > 65536:
		return "Blueprint file is too large."
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return "The saved blueprint is damaged. Your current build is unchanged."
	return from_data(parser.data)

