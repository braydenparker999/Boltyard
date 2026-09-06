class_name VehicleCatalog
extends RefCounted

# A saved build stores part IDs and only deliberate fine-tuning overrides.
# Physical settings are rebuilt from the vehicle and installed parts each time.
const SLOTS = ["tires", "wheels", "suspension", "gearing", "front_bumper", "roof"]
const SLOT_NAMES = {
	"tires": "Tires", "wheels": "Wheels", "suspension": "Suspension",
	"gearing": "Final drive", "front_bumper": "Front bumper", "roof": "Roof equipment"
}
const DEFAULTS = {
	"tire_radius": 0.46, "tire_pressure": 1.0, "ride_height": 0.35,
	"spring_rate": 30000.0, "damping": 3000.0, "engine_torque": 450.0,
	"mass": 1200.0, "track_width": 1.9, "wheelbase": 2.7,
	"body_stiffness": 1.0, "low_range": true, "locked_diffs": true,
	"tire_grip": 1.0, "tire_width_scale": 1.0, "suspension_travel": 0.22,
	"final_drive": 1.0, "front_accessory_mass": 0.0, "roof_accessory_mass": 0.0
}
const LIMITS = {
	"tire_radius": [0.32, 0.65], "tire_pressure": [0.5, 2.0],
	"ride_height": [0.15, 0.65], "spring_rate": [15000.0, 65000.0],
	"damping": [1000.0, 7000.0], "engine_torque": [150.0, 900.0],
	"mass": [900.0, 2000.0], "track_width": [1.6, 2.3],
	"wheelbase": [2.3, 3.3], "body_stiffness": [0.5, 2.0],
	"tire_grip": [0.7, 1.4], "tire_width_scale": [0.75, 1.4],
	"suspension_travel": [0.12, 0.4], "final_drive": [0.8, 1.5],
	"front_accessory_mass": [0.0, 100.0], "roof_accessory_mass": [0.0, 100.0]
}
# These are the ten editable setup values. Part-only coefficients stay derived.
const TUNING_KEYS = [
	"tire_radius", "tire_pressure", "ride_height", "spring_rate", "damping",
	"engine_torque", "mass", "track_width", "wheelbase", "body_stiffness"
]
const VEHICLES = {
	"pickup": {
		"name": "Bison Pickup", "description": "A long-wheelbase workhorse with an open bed and a balanced trail setup.",
		"vehicle_type": 0, "paint": "c96c38",
		"base": {"mass": 1200.0, "wheelbase": 2.9, "track_width": 1.9},
		"defaults": {"tires": "all_terrain", "wheels": "steel", "suspension": "stock", "gearing": "trail", "front_bumper": "stock", "roof": "none"}
	},
	"scout": {
		"name": "Scout SUV", "description": "A compact enclosed trail rig with a shorter wheelbase for tight routes.",
		"vehicle_type": 1, "paint": "647263",
		"base": {"mass": 1080.0, "wheelbase": 2.45, "track_width": 1.76, "tire_radius": 0.42, "engine_torque": 360.0, "spring_rate": 28000.0, "damping": 2900.0, "ride_height": 0.32},
		"defaults": {"tires": "all_terrain", "wheels": "steel", "suspension": "stock", "gearing": "trail", "front_bumper": "stock", "roof": "none"}
	},
	"buggy": {
		"name": "Nomad Buggy", "description": "A light open-cage machine with a wide stance and longer stock suspension travel.",
		"vehicle_type": 2, "paint": "537781",
		"base": {"mass": 950.0, "wheelbase": 2.8, "track_width": 2.04, "tire_radius": 0.47, "engine_torque": 520.0, "spring_rate": 27000.0, "damping": 3200.0, "ride_height": 0.4, "suspension_travel": 0.28, "body_stiffness": 1.2, "low_range": false},
		"defaults": {"tires": "all_terrain", "wheels": "steel", "suspension": "stock", "gearing": "trail", "front_bumper": "stock", "roof": "none"}
	}
}
# Effects are applied in slot order. Multiplication precedes addition and set.
# All parts listed for a vehicle attach to its own geometry; no cross-fit fallbacks.
const PARTS = {
	"tires": [
		{"id": "all_terrain", "name": "All-terrain", "description": "Balanced tread, stock diameter and carcass stiffness.", "vehicles": ["pickup", "scout", "buggy"], "effects": {}, "visual": "all_terrain"},
		{"id": "mud", "name": "Mud terrain", "description": "10% larger diameter, 15% wider tire and 18% more grip; softer carcass.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"multiply": {"tire_radius": 1.1, "tire_width_scale": 1.15}, "set": {"tire_pressure": 0.85, "tire_grip": 1.18}}, "visual": "mud"},
		{"id": "rock", "name": "Billygoat · Granite LT", "description": "15% larger diameter, 10% wider tire and 30% more grip; soft crawling carcass.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"multiply": {"tire_radius": 1.15, "tire_width_scale": 1.1}, "set": {"tire_pressure": 0.65, "tire_grip": 1.3}}, "visual": "rock"}
	],
	"wheels": [
		{"id": "steel", "name": "Steel utility", "description": "Stock wheel width, track and vehicle mass.", "vehicles": ["pickup", "scout", "buggy"], "effects": {}, "visual": "steel"},
		{"id": "beadlock", "name": "Deadbolt · Ring Leader", "description": "Wider stance (+8 cm), 12% wider tires and +18 kg wheel-set mass.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"multiply": {"tire_width_scale": 1.12}, "add": {"track_width": 0.08, "mass": 18.0}}, "visual": "beadlock"},
		{"id": "alloy", "name": "Rally alloy", "description": "Lighter wheel set (-24 kg), +4 cm track and 2% wider tires.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"multiply": {"tire_width_scale": 1.02}, "add": {"track_width": 0.04, "mass": -24.0}}, "visual": "alloy"}
	],
	"suspension": [
		{"id": "stock", "name": "Factory trail", "description": "The vehicle's standard height, spring rate, damping and travel.", "vehicles": ["pickup", "scout", "buggy"], "effects": {}, "visual": "stock"},
		{"id": "lift", "name": "Almost Level · Flex Kit", "description": "+10 cm ride height, +8 cm travel, 15% softer springs and 12% more damping.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"multiply": {"spring_rate": 0.85, "damping": 1.12}, "add": {"ride_height": 0.1, "suspension_travel": 0.08}}, "visual": "lift"},
		{"id": "long_travel", "name": "Desert long travel", "description": "+6 cm ride height, +12 cm travel, 35% stiffer springs and 45% more damping.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"multiply": {"spring_rate": 1.35, "damping": 1.45}, "add": {"ride_height": 0.06, "suspension_travel": 0.12}}, "visual": "long_travel"}
	],
	"gearing": [
		{"id": "trail", "name": "Trail ratio", "description": "Stock final drive; keeps the vehicle's standard range and differential setup.", "vehicles": ["pickup", "scout", "buggy"], "effects": {}, "visual": "trail"},
		{"id": "crawler", "name": "Low Expectations · 4-Low", "description": "1.35x final reduction gives more wheel torque and a lower speed ceiling; low range and locks engaged.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"set": {"final_drive": 1.35, "low_range": true, "locked_diffs": true}}, "visual": "crawler"},
		{"id": "rally", "name": "Rally ratio", "description": "0.82x final reduction favors speed over wheel torque; high range with differential coupling unlocked.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"set": {"final_drive": 0.82, "low_range": false, "locked_diffs": false}}, "visual": "rally"}
	],
	"front_bumper": [
		{"id": "stock", "name": "Factory bumper", "description": "Standard front geometry with no accessory ballast.", "vehicles": ["pickup", "scout", "buggy"], "effects": {}, "visual": "stock"},
		{"id": "tube", "name": "Trail tube", "description": "A tubular guard adds 28 kg at the front attachment nodes.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"set": {"front_accessory_mass": 28.0}}, "visual": "tube"},
		{"id": "armor", "name": "Steel expedition", "description": "A heavy steel bumper adds 75 kg at the nose. The modeled winch is decorative.", "vehicles": ["pickup", "scout"], "effects": {"set": {"front_accessory_mass": 75.0}}, "visual": "armor"},
		{"id": "cage_brace", "name": "Cage nose brace", "description": "Nomad-only cage bracing adds 18 kg at the front attachment nodes.", "vehicles": ["buggy"], "effects": {"set": {"front_accessory_mass": 18.0}}, "visual": "cage_brace"}
	],
	"roof": [
		{"id": "none", "name": "Clear roof", "description": "No roof equipment or raised accessory mass.", "vehicles": ["pickup", "scout", "buggy"], "effects": {}, "visual": "none"},
		{"id": "slim_rack", "name": "Slim trail rack", "description": "A rack fitted to this vehicle's roof or cage adds 18 kg above the chassis.", "vehicles": ["pickup", "scout", "buggy"], "effects": {"set": {"roof_accessory_mass": 18.0}}, "visual": "slim_rack"},
		{"id": "expedition_rack", "name": "Expedition cargo", "description": "Pickup/SUV rack with cargo adds 65 kg high on the body, affecting weight transfer.", "vehicles": ["pickup", "scout"], "effects": {"set": {"roof_accessory_mass": 65.0}}, "visual": "expedition_rack"},
		{"id": "cage_spare", "name": "Cage spare carrier", "description": "A Nomad-only spare carrier adds 30 kg at the upper cage nodes.", "vehicles": ["buggy"], "effects": {"set": {"roof_accessory_mass": 30.0}}, "visual": "cage_spare"}
	]
}

static func default_build(vehicle_id: String = "pickup") -> Dictionary:
	var selected = vehicle_id if VEHICLES.has(vehicle_id) else "pickup"
	return {"vehicle": selected, "paint": VEHICLES[selected].paint, "parts": VEHICLES[selected].defaults.duplicate(true), "tuning": {}}

static func compatible_parts(vehicle_id: String, slot: String) -> Array:
	var result: Array = []
	if not VEHICLES.has(vehicle_id) or not PARTS.has(slot):
		return result
	for part in PARTS[slot]:
		if vehicle_id in part.vehicles:
			result.append(part.duplicate(true))
	return result

static func part_info(vehicle_id: String, slot: String, part_id: String) -> Dictionary:
	for part in compatible_parts(vehicle_id, slot):
		if part.id == part_id:
			return part
	return {}

static func validate_build(raw: Variant, vehicle_id: String = "") -> Dictionary:
	var data: Dictionary = raw if raw is Dictionary else {}
	var selected = vehicle_id
	if selected.is_empty():
		selected = str(data.get("vehicle", "pickup"))
	var result = default_build(selected)
	# Explicit vehicle_id owns this garage bay, even if imported data says otherwise.
	var paint: Variant = data.get("paint", "")
	if paint is String and paint.length() == 6:
		var valid_color = true
		for character in paint.to_lower():
			if not character in "0123456789abcdef":
				valid_color = false
		if valid_color:
			result.paint = paint.to_lower()
	var raw_parts: Variant = data.get("parts", {})
	if raw_parts is Dictionary:
		for slot in SLOTS:
			var candidate: Variant = raw_parts.get(slot, "")
			if candidate is String and not part_info(result.vehicle, slot, candidate).is_empty():
				result.parts[slot] = candidate
	var raw_tuning: Variant = data.get("tuning", {})
	if raw_tuning is Dictionary:
		for key in TUNING_KEYS:
			var value: Variant = raw_tuning.get(key)
			if (value is float or value is int) and is_finite(float(value)):
				result.tuning[key] = clampf(float(value), LIMITS[key][0], LIMITS[key][1])
		for key in ["low_range", "locked_diffs"]:
			if raw_tuning.get(key) is bool:
				result.tuning[key] = raw_tuning[key]
	return result

static func compose(raw_build: Dictionary) -> Dictionary:
	var build = validate_build(raw_build)
	var result = DEFAULTS.duplicate(true)
	result.merge(VEHICLES[build.vehicle].base, true)
	var visuals: Dictionary = {}
	for slot in SLOTS:
		var part = part_info(build.vehicle, slot, build.parts[slot])
		var effects: Dictionary = part.effects
		for key in effects.get("multiply", {}):
			result[key] = float(result[key]) * float(effects["multiply"][key])
		for key in effects.get("add", {}):
			result[key] = float(result[key]) + float(effects["add"][key])
		for key in effects.get("set", {}):
			result[key] = effects["set"][key]
		visuals[slot] = part.visual
	# Core mass is total curb mass: attachment fields locate those kilograms,
	# rather than adding them a second time inside the solver.
	result.mass += result.front_accessory_mass + result.roof_accessory_mass
	result.merge(build.tuning, true)
	for key in LIMITS:
		result[key] = clampf(float(result[key]), LIMITS[key][0], LIMITS[key][1])
	result.vehicle_id = build.vehicle
	result.vehicle_type = VEHICLES[build.vehicle].vehicle_type
	result.vehicle_name = VEHICLES[build.vehicle].name
	result.paint = build.paint
	result.parts = build.parts.duplicate(true)
	result.visual = visuals
	return result

static func equip_part(raw_build: Dictionary, slot: String, part_id: String) -> Dictionary:
	var build = validate_build(raw_build)
	var next = part_info(build.vehicle, slot, part_id)
	if next.is_empty() or build.parts[slot] == part_id:
		return build
	# Changing parts also removes overrides from the outgoing part, including when
	# returning to stock. Unrelated custom engine, geometry and paint choices survive.
	var previous = part_info(build.vehicle, slot, build.parts[slot])
	for part in [previous, next]:
		for operation in ["multiply", "add", "set"]:
			for key in part.effects.get(operation, {}):
				build.tuning.erase(key)
				if key in ["front_accessory_mass", "roof_accessory_mass"]:
					build.tuning.erase("mass")
	build.parts[slot] = part_id
	return build
