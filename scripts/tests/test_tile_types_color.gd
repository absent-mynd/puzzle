## TileTypes appearance (color / display_name) unit tests
##
## TileTypes is now the single source of truth for tile APPEARANCE, not just behavior.
## These tests lock the exact legacy colors (so a later "cleanup" can't silently shift
## gameplay colors) and assert the anti-regression contract that every consumer which
## used to own its own copy of the palette now agrees with the registry.

extends GutTest

const NULL := TileTypes.NULL
const EMPTY := TileTypes.EMPTY
const WALL := TileTypes.WALL
const WATER := TileTypes.WATER
const GOAL := TileTypes.GOAL
const TRIGGER_FOLD := TileTypes.TRIGGER_FOLD
const PIN := TileTypes.PIN
const UNANCHORABLE_FLOOR := TileTypes.UNANCHORABLE_FLOOR
const UNANCHORABLE_WALL := TileTypes.UNANCHORABLE_WALL

## The exact colors previously hardcoded in Cell.get_cell_color_for_type.
const LEGACY_COLORS := {
	NULL: Color(0.0, 0.0, 0.0, 0.0),
	EMPTY: Color(0.8, 0.8, 0.8),
	WALL: Color(0.2, 0.2, 0.2),
	WATER: Color(0.2, 0.4, 1.0),
	GOAL: Color(0.2, 1.0, 0.2),
	TRIGGER_FOLD: Color(1.0, 0.6, 0.1),
	PIN: Color(0.55, 0.1, 0.5),
	UNANCHORABLE_FLOOR: Color(0.75, 0.7, 0.85),
	UNANCHORABLE_WALL: Color(0.25, 0.15, 0.3),
}


func test_color_for_matches_legacy_values():
	for t in LEGACY_COLORS:
		assert_eq(TileTypes.color_for(t), LEGACY_COLORS[t],
			"color_for(%d) must equal the legacy color" % t)


func test_unknown_type_color_is_white_fallback():
	# Matches the legacy `_: return Color(1,1,1)` fallback.
	assert_eq(TileTypes.color_for(999), Color(1.0, 1.0, 1.0), "unknown type -> white")


func test_null_is_transparent():
	assert_eq(TileTypes.color_for(NULL).a, 0.0, "null/void tile is fully transparent")


func test_display_names_present_for_all_registered_types():
	for t in LEGACY_COLORS:
		assert_ne(TileTypes.display_name(t), "", "type %d has a display name" % t)


func test_display_name_unknown_fallback():
	assert_eq(TileTypes.display_name(999), "Unknown", "unknown type -> 'Unknown'")


## The anti-regression contract for the de-dup: the Cell view's color accessor must
## agree with the registry for every type. If a future edit reintroduces a divergent
## copy in Cell, this fails.
func test_cell_delegates_to_registry():
	# Constructor args are dummy geometry; get_cell_color_for_type uses no instance state.
	var cell := Cell.new(Vector2i.ZERO, Vector2.ZERO, 64.0)
	for t in [NULL, EMPTY, WALL, WATER, GOAL, TRIGGER_FOLD, PIN, UNANCHORABLE_FLOOR, UNANCHORABLE_WALL, 999]:
		assert_eq(cell.get_cell_color_for_type(t), TileTypes.color_for(t),
			"Cell.get_cell_color_for_type(%d) must delegate to TileTypes" % t)
	cell.free()
