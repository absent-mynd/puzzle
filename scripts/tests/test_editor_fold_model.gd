## EditorFoldModel unit tests
##
## Locks the pre-placed fold entry shape (must match LevelData.folds / fold_pairs) and the
## add/remove/describe helpers used by the editor's folds mode.

extends GutTest


func test_make_produces_leveldata_fold_shape():
	var f := EditorFoldModel.make(Vector2i(3, 1), Vector2i(7, 1))
	assert_eq(f["anchor1"], {"x": 3, "y": 1}, "anchor1 stored as {x,y}")
	assert_eq(f["anchor2"], {"x": 7, "y": 1}, "anchor2 stored as {x,y}")


func test_make_matches_leveldata_fold_pairs():
	# A LevelData carrying this fold must decode it back to the same anchors.
	var ld := LevelData.new()
	ld.folds = [EditorFoldModel.make(Vector2i(2, 4), Vector2i(6, 4))]
	var pairs := ld.fold_pairs()
	assert_eq(pairs.size(), 1, "one fold pair")
	assert_eq(pairs[0][0], Vector2i(2, 4), "first anchor round-trips through LevelData")
	assert_eq(pairs[0][1], Vector2i(6, 4), "second anchor round-trips through LevelData")


func test_add_appends():
	var folds: Array = []
	EditorFoldModel.add(folds, Vector2i(0, 0), Vector2i(3, 0))
	EditorFoldModel.add(folds, Vector2i(1, 1), Vector2i(4, 1))
	assert_eq(folds.size(), 2, "two folds appended")
	assert_eq(EditorFoldModel.anchors_of(folds[1]), [Vector2i(1, 1), Vector2i(4, 1)], "second fold anchors")


func test_remove_at():
	var folds: Array = []
	EditorFoldModel.add(folds, Vector2i(0, 0), Vector2i(3, 0))
	EditorFoldModel.add(folds, Vector2i(1, 1), Vector2i(4, 1))
	EditorFoldModel.remove_at(folds, 0)
	assert_eq(folds.size(), 1, "one fold removed")
	assert_eq(EditorFoldModel.anchors_of(folds[0]), [Vector2i(1, 1), Vector2i(4, 1)], "the right fold remains")


func test_remove_at_out_of_range_is_noop():
	var folds: Array = [EditorFoldModel.make(Vector2i(0, 0), Vector2i(1, 0))]
	EditorFoldModel.remove_at(folds, 5)
	EditorFoldModel.remove_at(folds, -1)
	assert_eq(folds.size(), 1, "out-of-range removals do nothing")


func test_describe():
	var f := EditorFoldModel.make(Vector2i(3, 1), Vector2i(7, 1))
	assert_string_contains(EditorFoldModel.describe(f), "3,1", "describe shows anchor A")
	assert_string_contains(EditorFoldModel.describe(f), "7,1", "describe shows anchor B")


func test_survives_leveldata_serialization():
	var ld := LevelData.new()
	EditorFoldModel.add(ld.folds, Vector2i(4, 1), Vector2i(7, 1))
	var restored := LevelData.new()
	restored.from_dict(ld.to_dict())
	assert_eq(restored.fold_pairs()[0], [Vector2i(4, 1), Vector2i(7, 1)],
		"authored fold survives save/load")
