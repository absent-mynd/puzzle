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
