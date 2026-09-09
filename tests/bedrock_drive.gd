extends SceneTree
func _initialize() -> void:
	var core: RefCounted = ClassDB.instantiate("SoftBodyRig")
	var config := VehicleCatalog.compose(VehicleCatalog.default_build("buggy"))
	config.engine_torque=650.0
	config.low_range=true
	core.configure(config)
	core.set_terrain(6)
	var results: Array = []
	for location in [Vector2(8,-34),Vector2(8,-61),Vector2(5,-80)]:
		core.reset(Vector3(location.x,core.terrain_height(location.x,location.y)+1.4,location.y))
		for i in range(360): core.step(1.0/120.0,0,0,true)
		var start: Dictionary = core.get_stats()
		var begin := Time.get_ticks_usec()
		var min_up := 1.0
		var peak_articulation := 0.0
		for i in range(960):
			core.step(1.0/120.0,.22,0,false)
			if i%30==0:
				var state: Dictionary = core.get_stats()
				min_up=minf(min_up,state.up.y)
				for a in state.axle_articulation: peak_articulation=maxf(peak_articulation,absf(a))
		var cpu_ms := (Time.get_ticks_usec()-begin)/960.0/1000.0
		for i in range(300): core.step(1.0/120.0,0,0,true)
		var end: Dictionary = core.get_stats()
		var travel: float = start.position.distance_to(end.position)
		results.append({"start":str(start.position),"end":str(end.position),"travel_m":travel,"min_up":min_up,"articulation":peak_articulation,"cpu_step_ms":cpu_ms,"clamps":end.safety_clamps,"rejections":end.rejected_states,"damage":end.damage,"stop_speed":end.speed})
		if not end.position.is_finite() or end.safety_clamps!=0 or end.rejected_states!=0 or min_up<.6 or travel<2 or end.speed>.12:
			print("BEDROCK DRIVE FAIL: ",JSON.stringify(results))
			quit(1)
			return
	print("BEDROCK DRIVE: ",JSON.stringify(results))
	quit()
