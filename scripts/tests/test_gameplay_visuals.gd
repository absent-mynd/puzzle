## GameplayVisuals unit tests
##
## The z-order was previously duplicated as bare literals across GridManager, Cell,
## Player, and FoldController, and had to stay mutually consistent by hand. These lock
## the layering invariant so a future edit to one file can't silently desync the stack.

extends GutTest


func test_z_order_is_strictly_increasing():
	# Bottom -> top. Each layer must sit strictly above the one below it.
	assert_lt(GameplayVisuals.Z_PIECE, GameplayVisuals.Z_FACING, "pieces below facing/anim")
	assert_lt(GameplayVisuals.Z_FACING, GameplayVisuals.Z_OCCUPANT, "facing below occupants")
	assert_lt(GameplayVisuals.Z_OCCUPANT, GameplayVisuals.Z_HIGHLIGHT, "occupants below highlight/crease")
	assert_lt(GameplayVisuals.Z_HIGHLIGHT, GameplayVisuals.Z_PREVIEW_FILL, "highlight below preview fill")
	assert_lt(GameplayVisuals.Z_PREVIEW_FILL, GameplayVisuals.Z_PREVIEW_LINE, "preview fill below preview lines")


func test_previews_draw_over_all_cell_content():
	# The whole point of the high preview z-values: previews must sit above anything a
	# cell renders (pieces AND the highlight dot), since previews are added first.
	assert_gt(GameplayVisuals.Z_PREVIEW_FILL, GameplayVisuals.Z_HIGHLIGHT,
		"preview shading draws over cell highlight dots")


func test_anchor_colors_distinct():
	assert_ne(GameplayVisuals.ANCHOR_FIRST, GameplayVisuals.ANCHOR_SECOND,
		"first and second anchors are visually distinguishable")
