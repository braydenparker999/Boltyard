extends RefCounted
## Rolling wall-clock presentation intervals. Includes frame cap / vsync wait;
## CPU fields are measured separately, never labelled GPU timing.
const CAPACITY := 240
var frames := PackedFloat32Array()
var physics := PackedFloat32Array()
var preparation := PackedFloat32Array()
var ticks := PackedInt32Array()
var simulated := PackedFloat32Array()
var cursor := 0
var count := 0
var previous_usec := 0
var summary_usec := 0
var summary: Dictionary = {}

func _init() -> void:
	ticks.resize(CAPACITY)
	simulated.resize(CAPACITY)
	frames.resize(CAPACITY)
	physics.resize(CAPACITY)
	preparation.resize(CAPACITY)

func sample(physics_ms: float, preparation_ms: float, physics_ticks: int = 0, simulated_seconds: float = 0.0) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := float(now - previous_usec) / 1000.0
	previous_usec = now
	# Background/resume is a different session, not a crawl-route frame.
	if elapsed > 1000.0:
		count = 0
		cursor = 0
		return
	ticks[cursor] = physics_ticks
	simulated[cursor] = simulated_seconds
	frames[cursor] = elapsed
	physics[cursor] = physics_ms
	preparation[cursor] = preparation_ms
	cursor = (cursor + 1) % CAPACITY
	count = mini(count + 1, CAPACITY)
	if now - summary_usec < 1000000 or count < 10:
		return
	summary_usec = now
	var sorted := frames.slice(0, count)
	sorted.sort()
	var total_ticks := 0
	var total_simulated := 0.0
	var wall_ms := 0.0
	var max_ticks := 0
	var cpu := 0.0
	var prep := 0.0
	var long_frames := 0
	for i in range(count):
		total_ticks += ticks[i]
		max_ticks = maxi(max_ticks, ticks[i])
		total_simulated += simulated[i]
		wall_ms += frames[i]
		cpu += physics[i]
		prep += preparation[i]
		long_frames += int(frames[i] > 50.0)
	summary = {"median_ms": sorted[int((count - 1) * .5)], "p95_ms": sorted[int((count - 1) * .95)],
		"p99_ms": sorted[int((count - 1) * .99)], "worst_ms": sorted[count - 1], "over50": long_frames,
		"samples": count, "physics_ticks_per_frame": float(total_ticks) / count, "max_physics_ticks": max_ticks,
		"simulated_to_wall_ratio": total_simulated * 1000.0 / maxf(wall_ms, 0.001), "physics_ms": cpu / count, "preparation_ms": prep / count}
