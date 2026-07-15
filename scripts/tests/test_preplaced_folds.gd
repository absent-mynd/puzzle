## Pre-placed folds tests (F7)
##
## A level can ship with an ordered fold list applied before the player. Because a
## fold hides the region between its creases, this is how a level ships "nested"
## content the player reveals by unfolding — no recursive sub-grids required.

extends GutTest


func _level(folds: Array, cells := {}, grid := Vector2i(8, 3)) -> LevelData:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = cells
	ld.folds = folds
	return ld


func test_folds_round_trip_through_json():
	var ld := _level([{"anchor1": {"x": 4, "y": 1}, "anchor2": {"x": 7, "y": 1}}])
	var round := LevelData.new()
	round.from_dict(ld.to_dict())
	assert_eq(round.folds.size(), 1, "fold list round-trips through serialization")
	var pairs := round.fold_pairs()
	assert_eq(pairs[0][0], Vector2i(4, 1), "anchor1 parsed")
	assert_eq(pairs[0][1], Vector2i(7, 1), "anchor2 parsed")


func test_empty_fold_list_is_default():
	var round := LevelData.new()
	round.from_dict(LevelData.new().to_dict())
	assert_eq(round.folds.size(), 0, "levels without pre-folds round-trip as empty")


func test_preplaced_fold_hides_a_region_until_unfolded():
	# A goal in the fold's excised strip is hidden at load and revealed on unfold.
	var ld := _level(
		[{"anchor1": {"x": 4, "y": 1}, "anchor2": {"x": 7, "y": 1}}],
		{Vector2i(6, 1): 3})
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	for pair in ld.fold_pairs():
		e.apply_fold(pair[0], pair[1])
	e.set_player_start(ld.player_start_position)

	assert_eq(e.fold_count(), 1, "the pre-placed fold is applied at load")
	assert_false(e.get_state().has_type_at(Vector2i(6, 1), 3), "goal is hidden while folded")
	assert_true(e.remove_fold(0), "player can unfold the pre-placed fold")
	assert_true(e.get_state().has_type_at(Vector2i(6, 1), 3), "goal revealed after unfolding")


func test_preplaced_folds_apply_in_order():
	var ld := _level([
		{"anchor1": {"x": 1, "y": 1}, "anchor2": {"x": 3, "y": 1}},
		{"anchor1": {"x": 4, "y": 1}, "anchor2": {"x": 6, "y": 1}},
	], {}, Vector2i(10, 3))
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	for pair in ld.fold_pairs():
		e.apply_fold(pair[0], pair[1])
	assert_eq(e.fold_count(), 2, "both pre-placed folds applied")
	assert_eq(e.folds[0].fold_id, 0, "first authored fold is id 0")
	assert_eq(e.folds[1].fold_id, 1, "second is id 1")
