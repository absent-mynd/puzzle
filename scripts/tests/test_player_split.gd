## Multi-body player tests (F4)
##
## The player is generalized from a single point to a SET of bodies (base tiles it
## rides). These tests pin the machinery: fragments are no longer discarded, a move
## applies to every body, blocked bodies stay, coinciding bodies merge, and goal is
## satisfied by any body.
##
## NOTE ON GEOMETRY: with the current fold model (creases at cell centers) a single
## fold never leaves a tile with material on BOTH flaps, so it does not split a body
## in two — see the fragment experiment. The multi-body model is therefore in place
## and future-proof (it activates the moment split-producing geometry lands: F6
## multi-anchor / sub-cell folds), and is exercised here with hand-built states.

extends GutTest

const T_EMPTY := 0
const T_GOAL := 3


func _square(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o, o + Vector2(cell, 0), o + Vector2(cell, cell), o + Vector2(0, cell)])


func _base(grid := Vector2i(6, 3), cells := {}) -> BaseGrid:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = cells
	return BaseGrid.from_level_data(ld)


# --- F4a: fragments are surfaced, not collapsed ------------------------------

func test_pieces_of_base_returns_all_fragments():
	# Hand-build a state where base 7 has TWO fragments at two plane positions.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(7, T_EMPTY, _square(Vector2i(1, 0)), Vector2i(1, 0), 0))
	s.add_piece(FoldedPiece.new(7, T_EMPTY, _square(Vector2i(4, 0)), Vector2i(4, 0), 0))
	s.add_piece(FoldedPiece.new(3, T_EMPTY, _square(Vector2i(2, 0)), Vector2i(2, 0), 0))
	s.finalize()
	assert_eq(s.pieces_of_base(7).size(), 2, "both fragments of base 7 are kept")
	var positions := s.plane_positions_of_base(7)
	assert_true(Vector2i(1, 0) in positions and Vector2i(4, 0) in positions,
		"both plane positions of the split base are reported")
	assert_eq(s.plane_positions_of_base(3).size(), 1, "an unsplit base has one position")
	assert_eq(s.plane_positions_of_base(99).size(), 0, "an excised/absent base has none")


func test_player_positions_unions_bodies():
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(1, T_EMPTY, _square(Vector2i(1, 0)), Vector2i(1, 0), 0))
	s.add_piece(FoldedPiece.new(2, T_EMPTY, _square(Vector2i(3, 0)), Vector2i(3, 0), 0))
	s.finalize()
	var pos := StepReplay.player_positions([1, 2], s)
	assert_eq(pos.size(), 2, "two bodies occupy two cells")


# --- single-body compatibility ------------------------------------------------

func test_single_body_engine_is_unchanged():
	var e := FoldEngine.new()
	e.load_base(_base())
	e.set_player_start(Vector2i(0, 1))
	assert_eq(e.player_base_ids.size(), 1, "one body at start")
	assert_eq(e.player_positions().size(), 1, "one occupied cell")
	assert_eq(e.player_positions()[0], Vector2i(0, 1), "at the start cell")


func test_is_on_goal_any_body():
	var e := FoldEngine.new()
	e.load_base(_base(Vector2i(6, 3), {Vector2i(1, 1): T_GOAL}))
	e.set_player_start(Vector2i(0, 1))
	assert_false(e.is_on_goal(), "not on goal at start")
	assert_true(e.move_player(Vector2i(1, 0)), "step onto goal")
	assert_true(e.is_on_goal(), "on goal after stepping there")


# --- F4b: multi-body movement (injected two-body player) ----------------------

func _two_body_cp(base: BaseGrid, a: Vector2i, b: Vector2i) -> Dictionary:
	var cp := StepReplay.initial(base, -1).duplicate()
	var ids: Array[int] = [base.tile_at(a).base_id, base.tile_at(b).base_id]
	# Inject a two-body player occupant (simulates a post-split diverged player).
	cp["occupants"] = [{"kind": StepReplay.KIND_PLAYER, "base_ids": ids, "latents": []}]
	cp["base_ids"] = ids
	cp["plane_pos"] = a
	return cp


func test_move_applies_to_every_body():
	var base := _base(Vector2i(6, 3))
	var cp := _two_body_cp(base, Vector2i(1, 1), Vector2i(3, 1))
	var cp2 := StepReplay._apply_move_step(base, cp, FoldStep.move(Vector2i(1, 0)))
	var pos := StepReplay.player_positions(cp2["base_ids"], cp2["state"])
	assert_true(Vector2i(2, 1) in pos and Vector2i(4, 1) in pos,
		"both bodies advanced one cell right")
	assert_eq(pos.size(), 2, "still two distinct bodies")


func test_blocked_body_stays_while_others_move():
	# Wall at (4,1) blocks the right body; the left body still moves.
	var base := _base(Vector2i(6, 3), {Vector2i(4, 1): 1})
	var cp := _two_body_cp(base, Vector2i(1, 1), Vector2i(3, 1))
	var cp2 := StepReplay._apply_move_step(base, cp, FoldStep.move(Vector2i(1, 0)))
	var pos := StepReplay.player_positions(cp2["base_ids"], cp2["state"])
	assert_true(Vector2i(2, 1) in pos, "unblocked body moved to (2,1)")
	assert_true(Vector2i(3, 1) in pos, "blocked body stayed at (3,1)")


func test_coinciding_bodies_merge():
	# Bodies at (1,1) and (2,1); wall at (3,1). Moving right: left body -> (2,1), right
	# body blocked stays at (2,1). They land on the same cell and merge into one.
	var base := _base(Vector2i(6, 3), {Vector2i(3, 1): 1})
	var cp := _two_body_cp(base, Vector2i(1, 1), Vector2i(2, 1))
	var cp2 := StepReplay._apply_move_step(base, cp, FoldStep.move(Vector2i(1, 0)))
	var pos := StepReplay.player_positions(cp2["base_ids"], cp2["state"])
	assert_eq(pos.size(), 1, "two bodies merged into one cell")
	assert_true(Vector2i(2, 1) in pos, "merged at (2,1)")
