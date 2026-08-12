extends GutTest

## What the overlay is allowed to hand the renderer.
##
## `draw_colored_polygon` fails on anything with fewer than three points —
## `Condition "pointcount < 3" is true` out of `canvas_item_add_polygon` — and it
## fails once per COPY of the space, every frame, for as long as the offending
## polygon sits in the view. So what is pinned here is not that the preview looks
## right; it is that nothing undrawable ever reaches a draw call.
##
## Two anchors pinned to one cell is the case that broke it, and it is a legal thing
## to do: `place_hand` checks only that there is sheet to pin to, and the pair is
## refused at the FUSE ("Both hands came down on one spot" — `WorldCore.anchors_valid`).
## For the length of that fuse the pair is armed and the overlay previews it every
## frame, and a pair whose anchors coincide has no crease direction at all, so
## `_strip_polygon` rightly returns no polygon.
##
## It only errored in a space that does NOT repeat — which is a region, which is where
## you play. `_clip` has two branches and only one of them dropped the empty strip:
## `Geometry2D.intersect_polygons` returns nothing for a degenerate subject, while the
## "no domain, nothing to clip to" branch passed it straight through to be drawn.

const CELL := 64.0
## The region the fake frames below stand in.
const GRID := Vector2(20, 12)

var overlay: WorldOverlay


func before_each() -> void:
	overlay = WorldOverlay.new()
	add_child_autofree(overlay)


## One copy of a repeating space — the quad `FoldLattice.domain_polygon` returns for
## a cylinder or a torus. A region gives back an empty array instead, and that is the
## `flat` argument to every builder here.
func _domain() -> PackedVector2Array:
	var px := GRID * CELL
	return PackedVector2Array([
		Vector2.ZERO, Vector2(px.x, 0.0), px, Vector2(0.0, px.y),
	])


## A frame with `pairs` armed and a hand down at each of `hands`, in a space that
## repeats only when `repeating` is true.
func _view(pairs: Array, hands: Array = [], repeating := false) -> OverlayView:
	var v := OverlayView.new()
	v.active = true
	v.cell_size = CELL
	v.world_px = GRID * CELL
	v.domain = _domain() if repeating else PackedVector2Array()
	for pair in pairs:
		v.pairs.append({"a": pair[0], "b": pair[1]})
	for at in hands:
		v.hands_down.append({"at": at, "kind": 0, "fuse": -1.0})
	return v


## The centre of a cell, the way `FoldWorld.anchor_point` resolves one.
func _cell(x: int, y: int) -> Vector2:
	return (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL


## Every polygon the overlay would hand to `draw_colored_polygon` for this frame.
func _preview_polys() -> Array:
	var out: Array = []
	out.append_array(overlay._guides)
	out.append_array(overlay._strips)
	return out


## The point count of the sparsest polygon, or -1 when there are none to draw.
func _fewest_points(polys: Array) -> int:
	var fewest := -1
	for poly in polys:
		var n: int = (poly as PackedVector2Array).size()
		if fewest < 0 or n < fewest:
			fewest = n
	return fewest


func test_a_pair_on_one_cell_previews_nothing_in_a_flat_space() -> void:
	# The reported crash. Both hands on cell (4, 5), region level, so no domain.
	var at := _cell(4, 5)
	overlay.set_view(_view([[at, at]]))
	assert_eq(overlay._strips, [],
		"a pair with no crease direction previews no strip at all")


func test_a_pair_on_one_cell_previews_nothing_in_a_repeating_space() -> void:
	# The branch that was already correct, pinned so the two stay agreed.
	var at := _cell(4, 5)
	overlay.set_view(_view([[at, at]], [], true))
	assert_eq(overlay._strips, [],
		"...and the same inside a fold, where the strip is clipped to one copy")


func test_a_real_pair_still_previews_a_band() -> void:
	# The guard must drop the degenerate strip and nothing else.
	overlay.set_view(_view([[_cell(4, 5), _cell(9, 5)]]))
	assert_eq(overlay._strips.size(), 1, "a pair a cell apart still previews its strip")
	assert_gte(_fewest_points(overlay._strips), 3, "and that strip is drawable")

	overlay.set_view(_view([[_cell(4, 5), _cell(9, 5)]], [], true))
	assert_gt(overlay._strips.size(), 0, "so does the same pair in a repeating space")
	assert_gte(_fewest_points(overlay._strips), 3, "and its clipped strip is drawable too")


func test_a_seam_is_drawn_as_a_muted_glue_line() -> void:
	# The two lines say the same kind of thing about the sheet — it is joined along
	# here — so they are one look at two strengths rather than two looks. What makes
	# the seam the quiet one is only its alpha, and that is the whole of the design:
	# a hue of its own would read as a different KIND of join, and equal weight would
	# have a region full of standing folds shouting over the markers you navigate by.
	assert_eq(Color(WorldOverlay.SEAM_COLOR, 1.0), Color(WorldOverlay.GLUE_COLOR, 1.0),
		"the seam is the glue line's own colour")
	assert_lt(WorldOverlay.SEAM_COLOR.a, WorldOverlay.GLUE_COLOR.a,
		"...drawn quieter than it")
	assert_gt(WorldOverlay.SEAM_COLOR.a, 0.0,
		"...but still drawn")


func test_nothing_the_overlay_would_draw_has_fewer_than_three_points() -> void:
	# The invariant itself, over a frame holding both kinds of pair and the guides
	# that a placed hand draws — in both kinds of space, because the bug lived in the
	# difference between them.
	var at := _cell(4, 5)
	var pairs := [[at, at], [at, _cell(9, 5)], [at, _cell(9, 9)]]
	var hands := [at, _cell(9, 5), _cell(0, 0)]
	for repeating in [false, true]:
		overlay.set_view(_view(pairs, hands, repeating))
		var polys := _preview_polys()
		assert_gt(polys.size(), 0,
			"there is something to draw (repeating: %s)" % repeating)
		assert_gte(_fewest_points(polys), 3,
			"every polygon drawn is a polygon (repeating: %s)" % repeating)
