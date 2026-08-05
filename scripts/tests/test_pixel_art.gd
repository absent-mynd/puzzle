## PixelArt tests — the art-pixel quantum
##
## The pixel pass changes resolution, not world size. These tests pin the two things
## the rest of the render path assumes: that a cell divides evenly into art pixels,
## and that the low-resolution target shows exactly as much world as the window did
## before it existed.

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
