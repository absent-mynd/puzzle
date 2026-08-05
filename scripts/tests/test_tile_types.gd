## TileTypes registry unit tests (F1)
##
## Pins the per-type facts (walkable, merge_rank, blocks_fold) and the dominant-type
## resolution so the registry provably reproduces the two legacy orderings it
## replaces: FoldedState (goal > wall > water > empty) and Cell view code
## (null > goal > wall > water > empty).

extends GutTest

const NULL := TileTypes.NULL
const EMPTY := TileTypes.EMPTY
const WALL := TileTypes.WALL
const WATER := TileTypes.WATER
const GOAL := TileTypes.GOAL


func test_all_canonical_types_registered():
	for t in [NULL, EMPTY, WALL, WATER, GOAL]:
		assert_true(TileTypes.is_registered(t), "type %d should be registered" % t)


func test_walkability_matches_legacy():
	assert_true(TileTypes.is_walkable(EMPTY), "empty is walkable")
	assert_true(TileTypes.is_walkable(WATER), "water is walkable")
	assert_true(TileTypes.is_walkable(GOAL), "goal is walkable")
	assert_false(TileTypes.is_walkable(WALL), "wall is not walkable")
	assert_false(TileTypes.is_walkable(NULL), "null/void is not walkable")


func test_merge_rank_ordering():
	# null > goal > wall > water > empty
	assert_gt(TileTypes.merge_rank(NULL), TileTypes.merge_rank(GOAL), "null beats goal")
	assert_gt(TileTypes.merge_rank(GOAL), TileTypes.merge_rank(WALL), "goal beats wall")
	assert_gt(TileTypes.merge_rank(WALL), TileTypes.merge_rank(WATER), "wall beats water")
	assert_gt(TileTypes.merge_rank(WATER), TileTypes.merge_rank(EMPTY), "water beats empty")


func test_dominant_type_reproduces_foldedstate_ordering():
	# No null pieces in the derive/replay world.
	assert_eq(TileTypes.dominant_type([EMPTY, GOAL]), GOAL, "goal beats empty")
	assert_eq(TileTypes.dominant_type([WATER, WALL]), WALL, "wall beats water")
	assert_eq(TileTypes.dominant_type([GOAL, WALL, WATER, EMPTY]), GOAL, "goal is dominant")
	assert_eq(TileTypes.dominant_type([WALL, WATER]), WALL, "wall over water")


func test_dominant_type_reproduces_cell_ordering_with_null():
	assert_eq(TileTypes.dominant_type([GOAL, NULL]), NULL, "null beats goal in view code")
	assert_eq(TileTypes.dominant_type([EMPTY, WALL, NULL, GOAL]), NULL, "null is most dominant")


func test_dominant_type_empty_list_is_empty():
	assert_eq(TileTypes.dominant_type([]), EMPTY, "no pieces resolves to empty")


func test_dominant_type_single():
	assert_eq(TileTypes.dominant_type([WATER]), WATER, "single type dominates itself")


func test_blocks_fold_default_false():
	for t in [NULL, EMPTY, WALL, WATER, GOAL]:
		assert_false(TileTypes.blocks_fold(t), "no current type blocks folding")


func test_unknown_type_is_safe():
	var unknown := 999
	assert_false(TileTypes.is_registered(unknown), "999 is not registered")
	assert_false(TileTypes.is_walkable(unknown), "unknown type is not walkable (safe default)")
	assert_eq(TileTypes.merge_rank(unknown), 0, "unknown type has lowest rank")
	assert_false(TileTypes.blocks_fold(unknown), "unknown type does not block folds by default")


## --- Unanchorable tile types (F6) ---

const UNANCHORABLE_FLOOR := TileTypes.UNANCHORABLE_FLOOR
const UNANCHORABLE_WALL := TileTypes.UNANCHORABLE_WALL


func test_unanchorable_types_registered():
	assert_true(TileTypes.is_registered(UNANCHORABLE_FLOOR), "UNANCHORABLE_FLOOR should be registered")
	assert_true(TileTypes.is_registered(UNANCHORABLE_WALL), "UNANCHORABLE_WALL should be registered")


func test_unanchorable_walkability():
	assert_true(TileTypes.is_walkable(UNANCHORABLE_FLOOR), "UNANCHORABLE_FLOOR is walkable")
	assert_false(TileTypes.is_walkable(UNANCHORABLE_WALL), "UNANCHORABLE_WALL is not walkable")


func test_unanchorable_blocks_anchor():
	assert_true(TileTypes.blocks_anchor(UNANCHORABLE_FLOOR), "UNANCHORABLE_FLOOR blocks anchor placement")
	assert_true(TileTypes.blocks_anchor(UNANCHORABLE_WALL), "UNANCHORABLE_WALL blocks anchor placement")


func test_unanchorable_does_not_block_fold():
	assert_false(TileTypes.blocks_fold(UNANCHORABLE_FLOOR), "UNANCHORABLE_FLOOR does not block folds")
	assert_false(TileTypes.blocks_fold(UNANCHORABLE_WALL), "UNANCHORABLE_WALL does not block folds")


func test_unanchorable_merge_ranks():
	assert_eq(TileTypes.merge_rank(UNANCHORABLE_FLOOR), TileTypes.merge_rank(EMPTY),
		"UNANCHORABLE_FLOOR has same merge rank as EMPTY")
	assert_eq(TileTypes.merge_rank(UNANCHORABLE_WALL), TileTypes.merge_rank(WALL),
		"UNANCHORABLE_WALL has same merge rank as WALL")


func test_blocks_anchor_false_for_existing_types():
	for t in [NULL, EMPTY, WALL, WATER, GOAL]:
		assert_false(TileTypes.blocks_anchor(t), "existing type %d should not block anchors" % t)


func test_unknown_type_does_not_block_anchor():
	assert_false(TileTypes.blocks_anchor(999), "unknown type does not block anchors by default")


## --- Anchor caches ---

const ANCHOR_CACHE := TileTypes.ANCHOR_CACHE


func test_anchor_cache_registered_and_walkable():
	assert_true(TileTypes.is_registered(ANCHOR_CACHE), "ANCHOR_CACHE should be registered")
	assert_true(TileTypes.is_walkable(ANCHOR_CACHE), "you collect a cache by walking into it")


func test_anchor_cache_grants_a_fold_s_worth():
	assert_eq(TileTypes.anchor_grant(ANCHOR_CACHE), AnchorStock.COST_PER_FOLD,
		"a cache is worth exactly one more fold left standing")
	assert_eq(TileTypes.on_enter_kind(ANCHOR_CACHE), "anchors",
		"the registry names the reaction; the world interprets it")


func test_nothing_else_grants_anchors():
	for t in [NULL, EMPTY, WALL, WATER, GOAL, TileTypes.PIN, TileTypes.TRIGGER_FOLD,
			UNANCHORABLE_FLOOR, UNANCHORABLE_WALL, 999]:
		assert_eq(TileTypes.anchor_grant(t), 0, "type %d grants no anchors" % t)


func test_anchor_cache_is_inert_to_the_fold_rules():
	# A cache folded away is not lost — it is inside the fold, waiting.
	assert_false(TileTypes.blocks_fold(ANCHOR_CACHE), "a cache does not refuse folds")
	assert_false(TileTypes.blocks_anchor(ANCHOR_CACHE), "nor refuse being anchored on")
