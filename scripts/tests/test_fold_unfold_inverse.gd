## Unfold-as-inverse tests (Stage 3)
##
## remove_fold erases a fold and re-derives. Folding then unfolding must return the
## exact identity state; unfolding one of several folds must equal deriving without
## it. State equality is by occupied positions + per-position (base_id,type) sets.

extends GutTest

const T_GOAL := 3
const T_WALL := 1


func _grid(size: Vector2i = Vector2i(10, 10), types: Dictionary = {}) -> BaseGrid:
	var ld := LevelData.new()
	ld.grid_size = size
	ld.cell_size = 64.0
	ld.cell_data = types
	return BaseGrid.from_level_data(ld)


## Canonical fingerprint of a folded state: pos -> sorted list of "base:type".
func _fingerprint(state: FoldedState) -> Dictionary:
	var fp := {}
	for pos in state.stacks:
		if not state.is_occupied(pos):
			continue
		var tags := []
		for p in state.surface_pieces_at(pos):
			tags.append("%d:%d" % [p.base_id, p.type])
		tags.sort()
		fp[pos] = tags
	return fp


func _assert_same(a: FoldedState, b: FoldedState, msg: String) -> void:
	var fa := _fingerprint(a)
	var fb := _fingerprint(b)
	assert_eq(fa.size(), fb.size(), msg + " (occupied count)")
	var mismatch := 0
	for pos in fa:
		if not fb.has(pos) or str(fb[pos]) != str(fa[pos]):
			mismatch += 1
	assert_eq(mismatch, 0, msg + " (per-cell identity)")


func test_fold_then_unfold_is_identity():
	var base := _grid(Vector2i(10, 10), {Vector2i(7, 3): T_WALL, Vector2i(1, 8): T_GOAL})
	var engine := FoldEngine.new()
	engine.load_base(base)
	var identity := FoldReplay.derive(base, [])

	assert_true(engine.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "fold applies")
	assert_true(engine.get_state().occupied_count() < 100, "fold compressed the board")

	assert_true(engine.remove_fold(0), "unfold succeeds")
	_assert_same(engine.get_state(), identity, "fold then unfold restores identity")


func test_unfold_one_of_two_equals_deriving_without_it():
	var base := _grid(Vector2i(10, 10))
	var engine := FoldEngine.new()
	engine.load_base(base)

	# Two independent folds: one horizontal (left region), one vertical (bottom region).
	assert_true(engine.apply_fold(Vector2i(0, 1), Vector2i(2, 1)), "fold A applies")
	assert_true(engine.apply_fold(Vector2i(1, 6), Vector2i(1, 8)), "fold B applies")

	# Remove fold A (id 0); result should equal deriving with only fold B.
	assert_true(engine.remove_fold(0), "unfold A succeeds")
	var only_b := FoldReplay.derive(base, [engine.get_fold(1)])
	_assert_same(engine.get_state(), only_b, "removing A leaves exactly B's effect")


func test_unfold_unknown_id_fails():
	var base := _grid()
	var engine := FoldEngine.new()
	engine.load_base(base)
	assert_false(engine.remove_fold(999), "removing a nonexistent fold fails")


func test_double_fold_unfold_returns_to_single():
	var base := _grid(Vector2i(10, 10))
	var engine := FoldEngine.new()
	engine.load_base(base)
	engine.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	var after_one := _fingerprint(engine.get_state())
	engine.apply_fold(Vector2i(0, 5), Vector2i(2, 5))
	engine.remove_fold(1)  # remove the second fold
	assert_eq(str(_fingerprint(engine.get_state())), str(after_one),
		"unfolding the newer fold returns to the single-fold state")
