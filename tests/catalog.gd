extends SceneTree

const Catalog = preload("res://scripts/vehicle_catalog.gd")
const ROUNDTRIP_PATH = "user://catalog-test-roundtrip.json"
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func close_to(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.0001

func run() -> void:
	var garage: Dictionary = {}
	for vehicle_id in Catalog.VEHICLES:
		var build = Catalog.default_build(vehicle_id)
		var setup = Catalog.compose(build)
		garage[vehicle_id] = build
		check(setup.vehicle_id == vehicle_id and setup.vehicle_type == Catalog.VEHICLES[vehicle_id].vehicle_type, "%s keeps its distinct native chassis type" % vehicle_id)
		for slot in Catalog.SLOTS:
			var options = Catalog.compatible_parts(vehicle_id, slot)
			var unique: Dictionary = {}
			var valid_options = options.size() == 3
			for part in options:
				unique[part.id] = true
				var equipped = Catalog.equip_part(build, slot, part.id)
				valid_options = valid_options and equipped.parts[slot] == part.id and Catalog.compose(equipped).parts[slot] == part.id
			check(valid_options and unique.size() == 3, "%s %s offers three compatible and equipable parts" % [vehicle_id, slot])
	var pickup = Catalog.compose(garage.pickup)
	var scout = Catalog.compose(garage.scout)
	var buggy = Catalog.compose(garage.buggy)
	check(scout.wheelbase < pickup.wheelbase and buggy.mass < scout.mass and buggy.track_width > pickup.track_width, "vehicle choice changes wheelbase, weight and stance")
	check(buggy.suspension_travel > pickup.suspension_travel, "Nomad has distinct stock suspension travel")
	var custom = Catalog.equip_part(garage.pickup, "tires", "rock")
	custom = Catalog.equip_part(custom, "wheels", "beadlock")
	custom = Catalog.equip_part(custom, "suspension", "lift")
	custom = Catalog.equip_part(custom, "gearing", "crawler")
	custom = Catalog.equip_part(custom, "front_bumper", "armor")
	custom = Catalog.equip_part(custom, "roof", "expedition_rack")
	var fitted = Catalog.compose(custom)
	check(close_to(fitted.tire_radius, 0.46 * 1.15) and close_to(fitted.tire_width_scale, 1.1 * 1.12), "tire and wheel dimensions compose rather than replacing each other")
	check(close_to(fitted.tire_grip, 1.3) and close_to(fitted.tire_pressure, 0.65), "crawler tires change grip and deformable carcass stiffness")
	check(close_to(fitted.mass, 1358.0) and close_to(fitted.front_accessory_mass, 75.0) and close_to(fitted.roof_accessory_mass, 65.0), "wheel and accessory weights are included exactly once in total mass")
	check(close_to(fitted.ride_height, 0.45) and close_to(fitted.suspension_travel, 0.30) and close_to(fitted.spring_rate, 25500.0), "lift kit changes clearance, physical travel and spring stiffness")
	check(close_to(fitted.final_drive, 1.35) and fitted.low_range and fitted.locked_diffs, "crawler gearing configures actual drivetrain inputs")
	check(close_to(fitted.wheel_accessory_mass, 18.0), "beadlock mass is allocated to actual unsprung wheels")
	check(close_to(Catalog.compose(Catalog.equip_part(garage.pickup, "wheels", "alloy")).wheel_accessory_mass, -24.0), "alloy mass reduction is applied to wheel assemblies")
	var axle_build = Catalog.equip_part(garage.pickup, "gearing", "rally")
	axle_build.tuning.front_locked = true
	var axle_setup = Catalog.compose(axle_build)
	check(axle_setup.front_locked and not axle_setup.rear_locked, "one axle can lock independently of the open gearing preset")
	axle_build.tuning.locked_diffs = true
	axle_build.tuning.front_locked = false
	axle_setup = Catalog.compose(axle_build)
	check(not axle_setup.front_locked and axle_setup.rear_locked, "legacy shared switch migrates without overwriting an explicit axle choice")
	check(close_to(fitted.compression_damping, fitted.damping) and close_to(fitted.rebound_damping, fitted.damping), "existing saved damping supplies both damper directions")
	axle_build.tuning.compression_damping = 1700.0
	axle_build.tuning.rebound_damping = 5700.0
	axle_setup = Catalog.compose(axle_build)
	check(close_to(axle_setup.compression_damping, 1700.0) and close_to(axle_setup.rebound_damping, 5700.0), "compression and rebound tune independently")
	custom.tuning.engine_torque = 610.0
	custom.tuning.tire_radius = 0.6
	custom.tuning.mass = 1700.0
	custom.paint = "ede7d6"
	var tuned = Catalog.compose(custom)
	check(close_to(tuned.tire_radius, 0.6) and close_to(tuned.mass, 1700.0), "fine tuning is an absolute override of the fitted setup")
	var changed = Catalog.equip_part(custom, "tires", "all_terrain")
	var changed_setup = Catalog.compose(changed)
	check(not changed.tuning.has("tire_radius") and close_to(changed_setup.tire_radius, 0.46), "returning to stock tires clears tire size override")
	check(close_to(changed_setup.engine_torque, 610.0) and close_to(changed_setup.mass, 1700.0) and changed.paint == "ede7d6", "part swap preserves unrelated tuning and paint")
	changed = Catalog.equip_part(changed, "roof", "none")
	check(not changed.tuning.has("mass") and close_to(Catalog.compose(changed).mass, 1293.0), "removing roof equipment updates total weight despite an old mass override")
	check(garage.pickup.parts.roof == "none" and garage.pickup.tuning.is_empty(), "editing one build cannot mutate another build or catalog defaults")
	var unsupported = Catalog.equip_part(garage.buggy, "roof", "expedition_rack")
	check(unsupported.parts.roof == "none", "incompatible SUV cargo rack cannot be fitted to buggy")
	check(Catalog.compatible_parts("unknown", "roof").is_empty() and Catalog.compatible_parts("pickup", "unknown").is_empty(), "unknown vehicle or part slot returns no installation choices")
	var corrupt = {
		"vehicle": "buggy", "paint": "nothex", "parts": {"roof": "cage_spare", "front_bumper": "armor", "engine": "unrecognized"},
		"tuning": {"mass": -1, "engine_torque": 99999, "damping": NAN, "spring_rate": INF, "tire_radius": "0.6", "tire_grip": 10, "low_range": "true", "locked_diffs": false}
	}
	var sanitized = Catalog.validate_build(corrupt, "scout")
	var safe_setup = Catalog.compose(sanitized)
	check(sanitized.vehicle == "scout" and sanitized.parts.roof == "none" and sanitized.parts.front_bumper == "armor", "saved garage bay owns vehicle identity and rejects only incompatible parts")
	check(not sanitized.parts.has("engine") and not sanitized.tuning.has("tire_grip"), "unknown parts and part-only coefficient overrides are rejected")
	check(close_to(safe_setup.mass, 900.0) and close_to(safe_setup.engine_torque, 900.0), "out-of-range saved numeric tuning is clamped")
	check(close_to(safe_setup.damping, 2900.0) and close_to(safe_setup.spring_rate, 28000.0) and close_to(safe_setup.tire_radius, 0.42), "nonfinite and incorrectly typed saved tuning is discarded")
	check(safe_setup.low_range and not safe_setup.locked_diffs and safe_setup.paint == Catalog.VEHICLES.scout.paint, "boolean and paint validation preserves only well-formed saved choices")
	check(Catalog.validate_build(null).vehicle == "pickup" and Catalog.validate_build({"parts": [], "tuning": []}, "buggy").vehicle == "buggy", "malformed save shapes fall back to valid vehicle builds")
	check(Catalog.validate_build({"paint": "AABBCC"}).paint == "aabbcc", "valid custom paint survives normalized save validation")
	garage.pickup = custom
	garage.scout = Catalog.equip_part(garage.scout, "roof", "expedition_rack")
	garage.buggy = Catalog.equip_part(garage.buggy, "roof", "cage_spare")
	garage.buggy.tuning.engine_torque = 580.0
	var saved = FileAccess.open(ROUNDTRIP_PATH, FileAccess.WRITE)
	check(saved != null, "per-vehicle save fixture can be written")
	if saved != null:
		saved.store_string(JSON.stringify({"version": 2, "selected_vehicle": "scout", "builds": garage}))
		saved.close()
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUNDTRIP_PATH))
		check(loaded is Dictionary and loaded.get("selected_vehicle") == "scout", "saved garage selection survives file round trip")
		if loaded is Dictionary:
			for vehicle_id in garage:
				var restored = Catalog.validate_build(loaded.builds[vehicle_id], vehicle_id)
				check(restored.parts == garage[vehicle_id].parts and restored.paint == garage[vehicle_id].paint and restored.tuning == garage[vehicle_id].tuning, "%s independently restores installed parts, paint and tuning" % vehicle_id)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUNDTRIP_PATH))
	print("CATALOG: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
