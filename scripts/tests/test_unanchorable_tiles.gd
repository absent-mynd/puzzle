## Unanchorable tile type integration tests (F6)
##
## Verifies that UNANCHORABLE_FLOOR and UNANCHORABLE_WALL:
##   1. Block anchor placement via TileTypes.blocks_anchor (the contract that
##      GridManager.is_anchor_eligible delegates to).
##   2. Do NOT block fold excision (blocks_fold = false), so they can be freely
##      folded away — unlike PIN.
##
## Note on GridManager: is_anchor_eligible is a method on GridManager, which is a
## Node2D and requires a running scene tree to initialise properly. Rather than
## spinning up a full scene, we test the underlying contract (TileTypes.blocks_anchor)
## and the fold-engine behaviour directly. GridManager's delegation to
## TileTypes.blocks_anchor is a one-liner covered by code review and the registry
## tests above; the fold-engine path (apply_fold ignores blocks_anchor) is tested here.

extends GutTest

const UF := TileTypes.UNANCHORABLE_FLOOR
const UW := TileTypes.UNANCHORABLE_WALL


func _engine(cells: Dictionary, grid := Vector2i(10, 10)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = cells
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	return e


# --- TileTypes contract (what GridManager.is_anchor_eligible delegates to) ---

func test_unanchorable_floor_blocks_anchor_placement():
	assert_true(TileTypes.blocks_anchor(UF),
		"UNANCHORABLE_FLOOR must be rejected as an anchor target")


func test_unanchorable_wall_blocks_anchor_placement():
	assert_true(TileTypes.blocks_anchor(UW),
		"UNANCHORABLE_WALL must be rejected as an anchor target")


func test_empty_does_not_block_anchor_placement():
	assert_false(TileTypes.blocks_anchor(TileTypes.EMPTY),
		"EMPTY cells must remain valid anchor targets")


# --- Fold excision: unanchorable tiles are freely foldable ---

func test_unanchorable_floor_in_excised_region_does_not_block_fold():
	# UF at column 4 sits in the excised strip of a fold from col 3 to col 5.
	# Unlike PIN it must NOT block the fold.
	var e := _engine({Vector2i(4, 5): UF})
	assert_true(e.apply_fold(Vector2i(3, 5), Vector2i(5, 5)),
		"UNANCHORABLE_FLOOR in excised strip must not block a fold")
	assert_eq(e.fold_count(), 1, "fold was applied")


func test_unanchorable_wall_in_excised_region_does_not_block_fold():
	var e := _engine({Vector2i(4, 5): UW})
	assert_true(e.apply_fold(Vector2i(3, 5), Vector2i(5, 5)),
		"UNANCHORABLE_WALL in excised strip must not block a fold")
	assert_eq(e.fold_count(), 1, "fold was applied")


func test_unanchorable_floor_on_flap_does_not_block_fold():
	# Tile on the B-flap just translates; must not block.
	var e := _engine({Vector2i(9, 5): UF})
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(4, 5)),
		"UNANCHORABLE_FLOOR on flap does not block")
	assert_eq(e.fold_count(), 1, "fold applied")
