## Custom-level solvability tests (dogfoods F1–F3)
##
## Each custom level ships with a scripted solution here; the test loads the level
## into a headless FoldEngine, plays the solution (moves + player folds; triggers
## fire automatically via the step-log replay), and asserts the player ends on a
## goal. This both guarantees the shipped levels are solvable and exercises the new
## trigger/step-log machinery end-to-end through the real level format.

extends GutTest

const GOAL := 3


func _load(path: String) -> FoldEngine:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "level file opens: " + path)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "level JSON parses: " + path)
	var ld := LevelData.new()
	ld.from_dict(parsed)
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	# Pre-placed folds apply before the player is placed (they ship the level folded).
	for pair in ld.fold_pairs():
		e.apply_fold(pair[0], pair[1])
	e.set_player_start(ld.player_start_position)
	return e


func _on_goal(e: FoldEngine) -> bool:
	return e.get_state().has_type_at(e.player_plane_pos, GOAL)


# Play a solution: each action is ["move", dx, dy] or ["fold", ax, ay, bx, by].
# Asserts each action succeeds so a broken level fails loudly at the offending step.
func _solve(e: FoldEngine, actions: Array, name: String) -> void:
	for i in range(actions.size()):
		var a: Array = actions[i]
		var ok := false
		if a[0] == "move":
			ok = e.move_player(Vector2i(a[1], a[2]))
		elif a[0] == "fold":
			ok = e.apply_fold(Vector2i(a[1], a[2]), Vector2i(a[3], a[4]))
		elif a[0] == "unfold":
			ok = e.remove_fold(a[1])
		assert_true(ok, "%s: action %d %s applies" % [name, i, str(a)])
	assert_true(_on_goal(e), "%s: player ends on the goal" % name)


func test_t1_pressure_gate():
	# Walk right; the first step lands on the plate, which folds the wall away.
	var e := _load("res://levels/custom/t1_pressure_gate.json")
	_solve(e, [
		["move", 1, 0],  # onto the plate -> triggers fold A (excises the wall)
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
	], "t1_pressure_gate")


func test_t2_hand_fold():
	# Player folds the wall away manually, then crosses.
	var e := _load("res://levels/custom/t2_hand_fold.json")
	_solve(e, [
		["fold", 3, 1, 5, 1],  # anchors astride the wall (col 4) -> excise it
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
	], "t2_hand_fold")


func test_t3_double_plate():
	# Two plates fire in turn as the player walks right; each folds its wall away.
	var e := _load("res://levels/custom/t3_double_plate.json")
	_solve(e, [
		["move", 1, 0],  # plate A -> fold A
		["move", 1, 0],
		["move", 1, 0],  # plate B -> fold B
		["move", 1, 0],
		["move", 1, 0],
	], "t3_double_plate")


func test_t5_mind_the_pin():
	# The pin at (2,0) refuses any fold that would excise it; the wall is removed by a
	# fold whose strip avoids the pin's column.
	var e := _load("res://levels/custom/t5_mind_the_pin.json")
	# A fold spanning the pin's column is rejected (does not consume a fold).
	assert_false(e.apply_fold(Vector2i(1, 1), Vector2i(3, 1)),
		"t5: a fold that would erase the pin is refused")
	assert_eq(e.fold_count(), 0, "t5: the refused fold changed nothing")
	# The intended solution folds the wall away without touching the pin.
	_solve(e, [
		["fold", 4, 1, 6, 1],  # excise the wall at col 5; pin (col 2) is on the flap
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
	], "t5_mind_the_pin")


func test_t7_hidden_chamber():
	# The goal ships folded away; unfold the pre-placed fold (id 0) to reveal it, then walk in.
	var e := _load("res://levels/custom/t7_hidden_chamber.json")
	assert_eq(e.fold_count(), 1, "level ships with one pre-placed fold")
	assert_false(_on_goal(e), "goal is hidden at start")
	_solve(e, [
		["unfold", 0],   # reveal the hidden chamber
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
	], "t7_hidden_chamber")


func test_t8_buried_crate():
	# Unfold to reveal the buried crate + alcove, then shove the crate down and pass.
	var e := _load("res://levels/custom/t8_buried_crate.json")
	assert_eq(e.fold_count(), 1, "ships pre-folded")
	_solve(e, [
		["unfold", 0],    # reveal crate + alcove
		["move", 0, -1],  # up to (0,0)
		["move", 1, 0],   # (1,0)
		["move", 1, 0],   # (2,0)
		["move", 0, 1],   # down: shove crate (2,1)->(2,2), player ->(2,1)
		["move", 1, 0],   # (3,1)
		["move", 1, 0],   # (4,1) goal
	], "t8_buried_crate")


func test_t9_sealed_switch():
	# Unfold to expose the sealed switch; stepping on it folds the wall away; reach goal.
	var e := _load("res://levels/custom/t9_sealed_switch.json")
	_solve(e, [
		["unfold", 0],   # expose the switch
		["move", 1, 0],
		["move", 1, 0],  # onto the switch -> triggers the wall-clearing fold
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
	], "t9_sealed_switch")


func test_t10_fold_the_wall_away():
	# Fold the wall into the seam (excised), then walk the clear path to the goal.
	var e := _load("res://levels/custom/t10_squeeze_by.json")
	_solve(e, [
		["fold", 3, 1, 5, 1],  # excise the wall at col 4
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
	], "t10_fold_the_wall_away")


func test_t6_shove():
	# Approach the crate from above and shove it down into the alcove, clearing the
	# corridor, then walk to the goal.
	var e := _load("res://levels/custom/t6_shove.json")
	_solve(e, [
		["move", 0, -1],  # up to (0,0)
		["move", 1, 0],   # (1,0)
		["move", 1, 0],   # (2,0)
		["move", 0, 1],   # down: shove crate (2,1)->(2,2), player ->(2,1)
		["move", 1, 0],   # (3,1)
		["move", 1, 0],   # (4,1) goal
	], "t6_shove")


func test_t4_two_ways():
	# Fold the first wall by hand, then walk right; the plate folds the second.
	var e := _load("res://levels/custom/t4_two_ways.json")
	_solve(e, [
		["fold", 1, 1, 3, 1],  # manual: excise the first wall (col 2)
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],  # onto the plate -> fold A (excises the second wall)
		["move", 1, 0],
		["move", 1, 0],
		["move", 1, 0],
	], "t4_two_ways")
