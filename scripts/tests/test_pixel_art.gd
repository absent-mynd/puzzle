## PixelArt tests — the art-pixel quantum
##
## The pixel pass changes resolution, not world size. These tests pin what the rest
## of the render path assumes: that a cell divides evenly into art pixels, that the
## target at rest shows what the window used to, and — since the camera zoom became
## dynamic — that showing more world RESIZES the target instead of moving the lens,
## because an art pixel must stay exactly WORLD_PER_PIXEL world units at every zoom
## or the tileset is resampled and the whole point is lost.

extends GutTest


func test_a_cell_is_a_whole_number_of_art_pixels():
	assert_almost_eq(WorldCore.CELL / PixelArt.WORLD_PER_PIXEL, float(PixelArt.TILE_PX), 0.001,
		"CELL / WORLD_PER_PIXEL must equal TILE_PX, or the tileset cannot align to cells")


func test_the_render_target_shows_the_same_world_as_the_window():
	assert_eq(PixelArt.view_world_size(), Vector2(1280, 720),
		"VIEW_PX * WORLD_PER_PIXEL is the window's world extent: the pixel pass "
		+ "changes how the world is drawn, not how much of it is on screen")


func test_camera_zoom_matches_the_render_target():
	var visible := Vector2(PixelArt.VIEW_PX) / PixelArt.CAMERA_ZOOM
	assert_almost_eq(visible.distance_to(PixelArt.view_world_size()), 0.0, 0.001,
		"the camera zoom is what keeps the target's world extent right")


# ---------------------------------------------------------------------------
# The target tracks the logical zoom
# ---------------------------------------------------------------------------

func test_zoom_one_gives_back_the_authored_target():
	# VIEW_PX is the 1:1 shape — window/WORLD_PER_PIXEL. The resting zoom is wider
	# than 1:1, so at rest the target is correspondingly LARGER than VIEW_PX.
	assert_eq(PixelArt.target_size(Vector2(1280, 720), 1.0), PixelArt.VIEW_PX,
		"At zoom 1.0 the target is exactly VIEW_PX — the shape the tileset assumes")
	assert_gt(PixelArt.target_size(Vector2(1280, 720), WorldCore.ZOOM_RESTING).x,
		PixelArt.VIEW_PX.x,
		"The resting zoom already shows more world than 1:1, so it needs more pixels")


func test_opening_the_frame_grows_the_target_rather_than_the_pixel():
	var rest := PixelArt.target_size(Vector2(1280, 720), WorldCore.ZOOM_RESTING)
	var wide := PixelArt.target_size(Vector2(1280, 720), WorldCore.ZOOM_WIDEST)
	assert_gt(wide.x, rest.x, "A wider frame means MORE art pixels, not bigger ones")
	assert_gt(wide.y, rest.y, "...on both axes")


func test_an_art_pixel_is_the_same_size_at_every_zoom():
	# The whole reason the target resizes: world-per-art-pixel is what makes the
	# 16px tileset land 1:1, and it must not drift as the camera opens.
	var window := Vector2(1280, 720)
	for z in [WorldCore.ZOOM_RESTING, 0.75, 0.7, WorldCore.ZOOM_WIDEST, 1.0]:
		var zoom: float = z
		var target := PixelArt.target_size(window, zoom)
		var per_pixel := (window / zoom).x / float(target.x)
		assert_almost_eq(per_pixel, PixelArt.WORLD_PER_PIXEL, 0.06,
			"zoom %.3f: one art pixel still covers ~WORLD_PER_PIXEL world units" % zoom)


func test_a_cell_still_spans_a_whole_tile_at_every_zoom():
	var window := Vector2(1280, 720)
	for z in [WorldCore.ZOOM_RESTING, 0.72, 0.66, WorldCore.ZOOM_WIDEST]:
		var zoom: float = z
		var target := PixelArt.target_size(window, zoom)
		var per_pixel := (window / zoom).x / float(target.x)
		var cell_px := WorldCore.CELL / per_pixel
		assert_almost_eq(cell_px, float(PixelArt.TILE_PX), 0.25,
			"zoom %.3f: a cell covers ~TILE_PX art pixels, so the tile is not resampled" % zoom)


func test_the_target_never_grows_without_bound():
	# A resize per zoom step is fine; an unbounded one is a memory leak with a
	# view attached. The clamp is what makes this safe to call every frame.
	var huge := PixelArt.target_size(Vector2(3840, 2160), 0.01)
	assert_lte(huge.x, PixelArt.MAX_VIEW_PX.x, "Width is capped")
	assert_lte(huge.y, PixelArt.MAX_VIEW_PX.y, "Height is capped")
	var tiny := PixelArt.target_size(Vector2(1, 1), 100.0)
	assert_gt(tiny.x, 0, "And never collapses to nothing")
	assert_gt(tiny.y, 0, "...on either axis")


func test_the_target_is_stable_for_the_same_input():
	# Called every frame: it must be a pure function of (window, zoom), or the
	# viewport would be resized on frames where nothing changed.
	var a := PixelArt.target_size(Vector2(1280, 720), 0.734)
	var b := PixelArt.target_size(Vector2(1280, 720), 0.734)
	assert_eq(a, b, "Same window and zoom give the same target")


func test_snap_lands_on_the_art_pixel_grid():
	var p := PixelArt.snap(Vector2(13.9, -2.1))
	assert_almost_eq(fmod(absf(p.x), PixelArt.WORLD_PER_PIXEL), 0.0, 0.001, "x is on the grid")
	assert_almost_eq(fmod(absf(p.y), PixelArt.WORLD_PER_PIXEL), 0.0, 0.001, "y is on the grid")
	assert_almost_eq(p.x, 12.0, 0.001, "snap floors: 13.9 is inside the pixel starting at 12")


func test_snap_round_goes_to_the_nearest_pixel():
	assert_almost_eq(PixelArt.snap_round(Vector2(14.1, 0)).x, 16.0, 0.001,
		"14.1 is past the halfway mark, so it rounds up to the pixel at 16")
	assert_almost_eq(PixelArt.snap_round(Vector2(13.9, 0)).x, 12.0, 0.001,
		"13.9 is not, so it stays on the pixel at 12 — where snap would also put it")


func test_snapping_an_already_snapped_point_is_a_no_op():
	var p := Vector2(64, -128)
	assert_eq(PixelArt.snap(p), p, "snap is idempotent on grid points")
	assert_eq(PixelArt.snap_round(p), p, "so is snap_round")


func test_art_pixel_coordinates_count_from_the_origin():
	assert_eq(PixelArt.art_pixel(Vector2(0, 0)), Vector2i(0, 0), "the origin is pixel 0,0")
	assert_eq(PixelArt.art_pixel(Vector2(WorldCore.CELL, 0)), Vector2i(PixelArt.TILE_PX, 0),
		"one cell along is TILE_PX pixels along")


func test_px_per_world_is_the_geometry_to_texture_scale():
	assert_almost_eq(PixelArt.px_per_world(WorldCore.CELL) * WorldCore.CELL,
		float(PixelArt.TILE_PX), 0.001,
		"scaling a full cell by px_per_world spans exactly one atlas tile")


# ---------------------------------------------------------------------------
# Hairlines: a one-pixel line, stepped rather than drawn
# ---------------------------------------------------------------------------
# `draw_line` one art pixel wide is a quad four world units across, and at an angle
# that quad covers a fraction of each pixel it crosses — a dim, thinned, broken line
# in a frame where every other edge is a hard step. So a hairline is stepped into
# pixels first. What matters about the stepping is on both sides of the same coin:
# every pixel along the line is painted, and none of them is painted twice, because
# these lines are translucent and a doubled pixel blends twice.

const P := PixelArt.WORLD_PER_PIXEL


## The art pixels a set of runs covers, duplicates included — a duplicate is the
## defect being tested for, so this must not quietly fold them together.
func _covered(runs: PackedVector2Array) -> Array:
	var out: Array = []
	for i in range(0, runs.size(), 2):
		var a: Vector2 = runs[i]
		var b: Vector2 = runs[i + 1]
		var flat: bool = absf(a.y - b.y) < 0.001
		var lo := int(floor((minf(a.x, b.x) if flat else minf(a.y, b.y)) / P))
		var hi := int(floor((maxf(a.x, b.x) if flat else maxf(a.y, b.y)) / P))
		var fixed := int(floor((a.y if flat else a.x) / P))
		for at in range(lo, hi):
			out.append(Vector2i(at, fixed) if flat else Vector2i(fixed, at))
	return out


func test_a_straight_hairline_is_a_single_run():
	var runs := PixelArt.hairline_runs(Vector2(0, 10), Vector2(400, 10))
	assert_eq(runs.size(), 2, "Two endpoints — the whole line is one span")
	assert_eq(_covered(runs).size(), 101, "...covering every pixel from end to end")
	assert_eq(PixelArt.hairline_runs(Vector2(10, 0), Vector2(10, 400)).size(), 2,
		"...and a vertical one is the same span turned on its side")


func test_a_single_pixel_hairline_still_has_a_length():
	# A 45° line is one pixel per run, and a zero-length segment draws nothing at all —
	# which would erase every diagonal in the game. Runs span pixel EDGES for exactly
	# this reason.
	var runs := PixelArt.hairline_runs(Vector2(2, 2), Vector2(2, 2))
	assert_eq(runs.size(), 2, "One run")
	assert_almost_eq(Vector2(runs[0]).distance_to(Vector2(runs[1])), P, 0.001,
		"...one pixel long, not nothing")


func test_a_diagonal_hairline_is_a_stair_of_whole_pixels():
	var runs := PixelArt.hairline_runs(Vector2(0, 0), Vector2(40, 40))
	assert_gt(runs.size(), 2, "A diagonal cannot be a single span")
	var covered := _covered(runs)
	assert_eq(covered.size(), 11, "It steps one pixel per pixel, corner to corner")

	var seen := {}
	for px in covered:
		assert_false(seen.has(px), "No pixel is painted twice: %s" % px)
		seen[px] = true


func test_a_hairline_covers_its_line_without_gaps():
	# Every angle, and both directions: the major axis is walked a pixel at a time, so
	# the count is fixed by the longer side however the line is turned.
	for to in [Vector2(97, 31), Vector2(-97, 31), Vector2(31, -97), Vector2(-31, -97)]:
		var runs := PixelArt.hairline_runs(Vector2(200, 200), Vector2(200, 200) + to)
		var span: Vector2i = (PixelArt.art_pixel(Vector2(200, 200) + to)
			- PixelArt.art_pixel(Vector2(200, 200))).abs()
		assert_eq(_covered(runs).size(), maxi(span.x, span.y) + 1,
			"One pixel per step of the major axis, toward %s" % to)


func test_every_run_lands_on_the_pixel_grid():
	# The whole point of stepping: a run that ended mid-pixel would be the smear this
	# replaced, drawn the long way round.
	var runs := PixelArt.hairline_runs(Vector2(13, 7), Vector2(211, 96))
	for i in range(0, runs.size(), 2):
		var a: Vector2 = runs[i]
		var b: Vector2 = runs[i + 1]
		assert_almost_eq(fposmod(a.x, P), 0.0, 0.001, "run starts on a pixel edge")
		assert_almost_eq(fposmod(b.x, P), 0.0, 0.001, "...and ends on one")
		assert_almost_eq(fposmod(a.y, P), P * 0.5, 0.001, "...down the middle of its row")
		assert_almost_eq(a.y, b.y, 0.001, "...which is one row")
