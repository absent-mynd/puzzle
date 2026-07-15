## Swept collision movement tests (collision engine, Stage 3)
##
## A body may only SLIDE one cell if its actual shape stays on navigable ground along
## the whole path and at the final position: a whole body is refused a partial cell (its
## square can't fit), and a small body fits only where its path is continuously
## navigable. A fold's MERGE seam (a full cell of two contiguous halves) holds a whole
## body. (Replaces the earlier area-based size-fit heuristic.)

extends GutTest

const T_EMPTY := 0
const PLAYER := StepReplay.KIND_PLAYER


func _full(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o, o + Vector2(cell, 0), o + Vector2(cell, cell), o + Vector2(0, cell)])


func _left(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o, o + Vector2(cell / 2.0, 0), o + Vector2(cell / 2.0, cell), o + Vector2(0, cell)])


func _right(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o + Vector2(cell / 2.0, 0), o + Vector2(cell, 0), o + Vector2(cell, cell), o + Vector2(cell / 2.0, cell)])


func _bottom(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o + Vector2(0, cell / 2.0), o + Vector2(cell, cell / 2.0), o + Vector2(cell, cell), o + Vector2(0, cell)])


func _player(base_ids: Array) -> Dictionary:
	return {"kind": PLAYER, "base_ids": base_ids, "latents": [], "channel": ""}


func _move(state: FoldedState, occ: Dictionary, dir: Vector2i) -> Dictionary:
	return StepReplay._move_player(occ, dir, state, 64.0, [])


func test_walkable_area_sums_contiguous_merge():
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(1, T_EMPTY, _left(Vector2i(1, 0)), Vector2i(1, 0), 0))
	s.add_piece(FoldedPiece.new(2, T_EMPTY, _right(Vector2i(1, 0)), Vector2i(1, 0), 0))
	s.finalize()
	assert_almost_eq(s.walkable_area_at(Vector2i(1, 0)), 64.0 * 64.0, 1.0, "two halves sum to a full cell")


func test_full_body_blocked_from_half_cell():
	# Player is a full tile at (0,0); (1,0) is only a half-floor. It cannot fit.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _full(Vector2i(0, 0)), Vector2i(0, 0), -1))
	s.add_piece(FoldedPiece.new(1, T_EMPTY, _left(Vector2i(1, 0)), Vector2i(1, 0), -1))
	s.finalize()
	var out := _move(s, _player([0]), Vector2i(1, 0))
	assert_true(0 in out["base_ids"], "full body stayed on its own tile")
	assert_false(1 in out["base_ids"], "full body did NOT step onto the half-cell")


func test_small_body_slides_along_navigable_half_corridor():
	# A bottom-half body slides right along a continuous bottom-half floor strip — its
	# whole path stays navigable, so the swept move succeeds.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _bottom(Vector2i(0, 0)), Vector2i(0, 0), -1))
	s.add_piece(FoldedPiece.new(1, T_EMPTY, _bottom(Vector2i(1, 0)), Vector2i(1, 0), -1))
	s.finalize()
	var out := _move(s, _player([0]), Vector2i(1, 0))
	assert_true(1 in out["base_ids"], "small body slides onto the next half-cell (path clear)")
	assert_false(0 in out["base_ids"], "it left its old tile")


func test_full_body_cannot_slide_along_half_corridor():
	# A full-square body on a half-height corridor can't slide — its top half is over void.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _full(Vector2i(0, 0)), Vector2i(0, 0), -1))
	s.add_piece(FoldedPiece.new(1, T_EMPTY, _bottom(Vector2i(1, 0)), Vector2i(1, 0), -1))
	s.finalize()
	var out := _move(s, _player([0]), Vector2i(1, 0))
	assert_true(0 in out["base_ids"], "full body stays — its shape doesn't fit the half corridor")
	assert_false(1 in out["base_ids"], "did not slide")


func test_full_body_crosses_merge_seam():
	# (1,0) is a MERGE cell — two contiguous halves = a full cell. A full body fits.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _full(Vector2i(0, 0)), Vector2i(0, 0), -1))
	s.add_piece(FoldedPiece.new(1, T_EMPTY, _left(Vector2i(1, 0)), Vector2i(1, 0), 0))
	s.add_piece(FoldedPiece.new(2, T_EMPTY, _right(Vector2i(1, 0)), Vector2i(1, 0), 0))
	s.finalize()
	var out := _move(s, _player([0]), Vector2i(1, 0))
	assert_false(0 in out["base_ids"], "full body left its tile")
	assert_true(1 in out["base_ids"] or 2 in out["base_ids"], "full body crossed onto the merged full cell")


func test_normal_full_movement_unaffected():
	# Full-on-full movement (the common case) is unchanged by the size gate.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _full(Vector2i(0, 0)), Vector2i(0, 0), -1))
	s.add_piece(FoldedPiece.new(1, T_EMPTY, _full(Vector2i(1, 0)), Vector2i(1, 0), -1))
	s.finalize()
	var out := _move(s, _player([0]), Vector2i(1, 0))
	assert_true(1 in out["base_ids"], "full body moves freely onto a full cell")
