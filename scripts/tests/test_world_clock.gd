extends GutTest

## `WorldClock` — the one clock things in the world move on.
##
## The class itself is four lines, and almost nothing here is about those four lines.
## What matters is that it is the ONLY clock: everything that drifts, throbs or
## flickers without being pushed has to read it, or the world does not really stop
## when it stops.
##
## That was three clocks before it existed — `Time.get_ticks_msec()` read directly in
## `HandOrbit.draw_hand` and again in `WorldOverlay._pulse_at`, plus a private `_time`
## accumulator in `LightRig`. Nothing was wrong with any of them while the world always
## ran. The moment it could be stopped they became three things that could disagree
## about whether it had, and all three kept going: a frozen frame with the hands still
## bobbing and the lamps still breathing over it, which reads as a paused game rather
## than as time being held.

const WORLD_DIR := "res://scripts/world"


func test_the_clock_moves_only_when_it_is_advanced() -> void:
	var before := WorldClock.now()
	WorldClock.advance(0.25)
	assert_almost_eq(WorldClock.now(), before + 0.25, 0.0001,
		"A frame's worth of time is a frame's worth of world")

	WorldClock.advance(0.0)
	assert_almost_eq(WorldClock.now(), before + 0.25, 0.0001,
		"...and a frame it is not given does not age it")


func test_the_clock_is_shared_rather_than_per_reader() -> void:
	# `HandOrbit.draw_hand` is static and shared by every hand in the game — carried,
	# loose, and in flight — so the clock it reads has to be too. A hand that kept its
	# own would restart its float whenever the game handed you a different object.
	var before := HandOrbit.drift_time()
	WorldClock.advance(0.5)
	assert_almost_eq(HandOrbit.drift_time(), before + 0.5, 0.0001,
		"The hands' drift clock IS the world clock")


## Every .gd file under a directory.
func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func test_nothing_in_the_world_keeps_a_clock_of_its_own() -> void:
	# The guard, and the reason this file exists. Reading the wall clock to animate
	# something in the world is not a bug you can see — it looks perfect until the day
	# the world stops, and then it is the one thing still moving.
	#
	# `scripts/systems/` is deliberately outside the scan: `AudioManager` uses wall
	# time for its retrigger floors, which are about the speaker rather than the world
	# and must not stop when it does.
	var offenders: Array[String] = []
	var scanned := 0
	for path in _gd_files(WORLD_DIR):
		scanned += 1
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in range(lines.size()):
			var line := String(lines[i]).strip_edges()
			if line.begins_with("#"):
				continue                    # prose about the rule is not a breach of it
			if line.contains("Time.get_ticks"):
				offenders.append("%s:%d — %s" % [path, i + 1, line])

	assert_gt(scanned, 0, "found world scripts to scan (otherwise this proves nothing)")
	assert_eq(offenders, ([] as Array[String]),
		"nothing in the world animates on the wall clock; use WorldClock.now()\n%s"
			% "\n".join(offenders))
