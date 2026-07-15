## Fold-block predicate tests (F5)
##
## A fold is rejected if any fold-proof tile (blocks_fold=true, e.g. PIN) would be
## excised or cut by it. Tiles that merely sit on a flap and translate never block.
## The predicate is general (driven by TileTypes), not player-specific.

extends GutTest

const PIN := TileTypes.PIN


func _engine(cells: Dictionary, grid := Vector2i(10, 10)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = cells
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	return e


func test_pin_in_excised_region_blocks_fold():
	# PIN at column 4 sits strictly between the creases of a fold anchored at 3 and 5,
	# so that fold would erase it -> rejected.
	var e := _engine({Vector2i(4, 5): PIN})
	assert_false(e.apply_fold(Vector2i(3, 5), Vector2i(5, 5)),
		"a fold that would excise a pin is blocked")
	assert_eq(e.fold_count(), 0, "no fold was applied")


func test_fold_predicate_reports_blocking_position():
	var e := _engine({Vector2i(4, 5): PIN})
	var probe := Fold.create(-1, Vector2i(3, 5), Vector2i(5, 5), e.base_grid.cell_size)
	var r := e.fold_blocked_by_tile(probe)
	assert_true(r["blocks"], "predicate reports a block")
	assert_eq(r["pos"], Vector2i(4, 5), "predicate reports the offending pin cell")


func test_pin_on_a_flap_does_not_block():
	# PIN far to the right of the fold sits wholly on the B-flap: it just translates,
	# so the fold is allowed.
	var e := _engine({Vector2i(9, 5): PIN})
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(4, 5)),
		"a pin outside the excised strip does not block the fold")
	assert_eq(e.fold_count(), 1, "fold applied")


func test_no_pin_no_block():
	var e := _engine({Vector2i(4, 5): 1})  # an ordinary wall in the region
	assert_true(e.apply_fold(Vector2i(3, 5), Vector2i(5, 5)),
		"walls are foldable — only fold-proof tiles block")
	assert_eq(e.fold_count(), 1, "fold applied over the wall")


func test_pin_is_not_walkable():
	assert_false(TileTypes.is_walkable(PIN), "a pin cannot be stood on")
	assert_true(TileTypes.blocks_fold(PIN), "a pin blocks folds")
