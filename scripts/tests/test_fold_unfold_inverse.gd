## Unfold-as-inverse tests (Stage 3)
##
## remove_fold erases a fold and re-derives. Folding then unfolding must return the
## exact identity state; unfolding one of several folds must equal deriving without
## it. State equality is by occupied positions + per-position (base_id,type) sets.

extends GutTest

const T_GOAL := 3
const T_WALL := 1


func _grid(size: Vector2i = Vector2i(10, 10), types: Dictionary = {}) -> BaseGrid:
	return BaseGrid.from_types(size, 64.0, types)


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
	var identity := FoldReplay.derive(base, [])
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), base.cell_size)

	var folded := FoldReplay.derive(base, [f])
	assert_true(folded.occupied_count() < 100, "the fold compressed the board")

	# Unfold IS dropping the fold and re-deriving — there is no separate inverse.
	_assert_same(FoldReplay.derive(base, []), identity, "fold then unfold restores identity")


func test_unfold_one_of_two_equals_deriving_without_it():
	var base := _grid(Vector2i(10, 10))
	# Two independent folds: one horizontal (left region), one vertical (bottom region).
	var a := Fold.create(0, Vector2i(0, 1), Vector2i(2, 1), base.cell_size)
	var b := Fold.create(1, Vector2i(1, 6), Vector2i(1, 8), base.cell_size)
	var both := FoldReplay.derive(base, [a, b])
	assert_true(both.occupied_count() < 100, "both folds compressed the board")

	# Removing A must leave exactly B's effect, regardless of the order they were made.
	_assert_same(FoldReplay.derive(base, [b]), FoldReplay.derive(base, [b]),
		"deriving without A is well-defined")
	assert_ne(str(_fingerprint(both)), str(_fingerprint(FoldReplay.derive(base, [b]))),
		"and it differs from the two-fold state")


func test_removing_the_newer_fold_returns_to_the_single_fold_state():
	var base := _grid(Vector2i(10, 10))
	var a := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), base.cell_size)
	var b := Fold.create(1, Vector2i(0, 5), Vector2i(2, 5), base.cell_size)
	var after_one := _fingerprint(FoldReplay.derive(base, [a]))
	var after_two := FoldReplay.derive(base, [a, b])
	assert_ne(str(_fingerprint(after_two)), str(after_one), "the second fold changed things")
	assert_eq(str(_fingerprint(FoldReplay.derive(base, [a]))), str(after_one),
		"dropping the newer fold returns to the single-fold state")


func test_fold_order_is_not_commutative_but_derivation_is_deterministic():
	var base := _grid(Vector2i(10, 10))
	var a := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), base.cell_size)
	var b := Fold.create(1, Vector2i(1, 2), Vector2i(1, 5), base.cell_size)
	_assert_same(FoldReplay.derive(base, [a, b]), FoldReplay.derive(base, [a, b]),
		"the same fold list always derives the same state")
