## BaseGrid / BaseTile tests
##
## The immutable base model: every in-bounds position is a BaseTile, non-empty types
## come from the sparse type map, and the geometry helpers produce the canonical square.

extends GutTest

const EPSILON = 0.0001


func _make_grid() -> BaseGrid:
	return BaseGrid.from_types(Vector2i(4, 3), 64.0, {
		Vector2i(1, 0): TileTypes.WALL,
		Vector2i(3, 2): TileTypes.GOAL,
		Vector2i(2, 1): TileTypes.WATER,
	})


func test_from_types_materializes_every_position():
	var bg := _make_grid()
	assert_eq(bg.tiles.size(), 4 * 3, "every in-bounds position should be a BaseTile")
	assert_eq(bg.grid_size, Vector2i(4, 3), "grid size preserved")
	assert_almost_eq(bg.cell_size, 64.0, EPSILON, "cell size preserved")


func test_base_id_matches_index():
	var bg := _make_grid()
	for i in range(bg.tiles.size()):
		assert_eq(bg.tiles[i].base_id, i, "tiles[i].base_id should equal i")


func test_types_come_from_type_map():
	var bg := _make_grid()
	assert_eq(bg.tile_at(Vector2i(1, 0)).type, TileTypes.WALL, "wall placed")
	assert_eq(bg.tile_at(Vector2i(3, 2)).type, TileTypes.GOAL, "goal placed")
	assert_eq(bg.tile_at(Vector2i(2, 1)).type, TileTypes.WATER, "water placed")


func test_unspecified_positions_are_empty():
	var bg := _make_grid()
	assert_eq(bg.tile_at(Vector2i(0, 0)).type, TileTypes.EMPTY, "default floor is empty")
	assert_eq(bg.tile_at(Vector2i(2, 2)).type, TileTypes.EMPTY, "unspecified is empty")


func test_dictionary_entries_carry_per_tile_data():
	var bg := BaseGrid.from_types(Vector2i(3, 1), 64.0, {
		Vector2i(1, 0): {"type": TileTypes.TRIGGER_FOLD, "channel": "A", "anchors": [[0, 0], [2, 0]]},
	})
	var t := bg.tile_at(Vector2i(1, 0))
	assert_eq(t.type, TileTypes.TRIGGER_FOLD, "type read out of the dictionary form")
	assert_eq(t.data.get("channel", ""), "A", "per-tile params preserved")
	assert_false(t.data.has("type"), "`type` is not duplicated into data")


func test_tile_at_out_of_bounds_is_null():
	var bg := _make_grid()
	assert_null(bg.tile_at(Vector2i(-1, 0)), "negative out of bounds -> null")
	assert_null(bg.tile_at(Vector2i(4, 0)), "past-right out of bounds -> null")
	assert_null(bg.tile_at(Vector2i(0, 3)), "past-bottom out of bounds -> null")


func test_tile_by_id_and_bounds():
	var bg := _make_grid()
	assert_eq(bg.tile_by_id(0).grid_position, Vector2i(0, 0), "id 0 is top-left")
	assert_null(bg.tile_by_id(-1), "negative id -> null")
	assert_null(bg.tile_by_id(999), "out-of-range id -> null")
	assert_true(bg.is_in_bounds(Vector2i(3, 2)), "corner in bounds")
	assert_false(bg.is_in_bounds(Vector2i(4, 2)), "past-right not in bounds")


func test_unit_square_is_the_canonical_square():
	var bg := _make_grid()
	# Tile at (1,0) -> origin (64,0), CCW square of side 64.
	var sq := bg.unit_square_local(bg.tile_at(Vector2i(1, 0)).base_id)
	assert_eq(sq.size(), 4, "square has 4 vertices")
	assert_almost_eq(sq[0].distance_to(Vector2(64, 0)), 0.0, EPSILON, "top-left")
	assert_almost_eq(sq[1].distance_to(Vector2(128, 0)), 0.0, EPSILON, "top-right")
	assert_almost_eq(sq[2].distance_to(Vector2(128, 64)), 0.0, EPSILON, "bottom-right")
	assert_almost_eq(sq[3].distance_to(Vector2(64, 64)), 0.0, EPSILON, "bottom-left")


func test_square_at_arbitrary_position():
	var bg := BaseGrid.new(Vector2i(10, 10), 32.0)
	var sq := bg.square_at(Vector2i(2, 3))
	assert_almost_eq(sq[0].distance_to(Vector2(64, 96)), 0.0, EPSILON, "origin = pos * cell_size")
	assert_almost_eq(GeometryCore.polygon_area(sq), 32.0 * 32.0, EPSILON, "area = cell_size^2")
