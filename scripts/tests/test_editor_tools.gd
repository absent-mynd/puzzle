## EditorTools tests
##
## The editor's pure half: the palette (which must agree with the two registries
## it is derived from), raster ops on ASCII rows, resize arithmetic, and the fold
## guides that show where a pre-placed fold would cut.

extends GutTest


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

func test_palette_leads_with_air():
	var pal := EditorTools.palette()
	assert_eq(String(pal[0]["char"]), EditorTools.AIR, "air comes first — it is the eraser")
	assert_eq(int(pal[0]["type"]), TileTypes.EMPTY, "...and it paints EMPTY")


func test_palette_covers_every_authoring_character():
	var chars: Array = []
	for entry in EditorTools.palette():
		chars.append(String(entry["char"]))
	for ch in WorldCore.CHARS:
		assert_true(chars.has(String(ch)),
			"the palette can paint '%s', which the loader understands" % ch)


func test_palette_has_no_duplicate_characters():
	var seen: Dictionary = {}
	for entry in EditorTools.palette():
		var ch := String(entry["char"])
		assert_false(seen.has(ch), "'%s' appears once in the palette" % ch)
		seen[ch] = true


func test_palette_names_come_from_the_registry():
	for entry in EditorTools.palette():
		assert_eq(String(entry["name"]), TileTypes.type_name(int(entry["type"])),
			"the palette label is the registry's name, not a copy")


func test_char_and_type_round_trip():
	for ch in WorldCore.CHARS:
		var type: int = WorldCore.CHARS[ch]
		assert_eq(EditorTools.char_of_type(type), String(ch), "%s round trips" % ch)
		assert_eq(EditorTools.type_of_char(String(ch)), type, "%s parses back" % ch)


func test_unknown_character_is_air_like_the_loader():
	assert_eq(EditorTools.type_of_char("?"), TileTypes.EMPTY,
		"an unlisted character is air, exactly as parse_map treats it")


# ---------------------------------------------------------------------------
# Reading and painting rows
# ---------------------------------------------------------------------------

func _rows() -> Array:
	return ["....", ".##.", "####"]


func test_grid_size_is_the_widest_row():
	assert_eq(EditorTools.grid_size(["..", "#####", "."]), Vector2i(5, 3),
		"width comes from the widest row, as parse_map pads the rest")


func test_char_at_reads_the_grid():
	assert_eq(EditorTools.char_at(_rows(), Vector2i(1, 1)), "#", "reads a wall")
	assert_eq(EditorTools.char_at(_rows(), Vector2i(0, 0)), ".", "reads air")


func test_char_at_out_of_bounds_is_empty_string():
	assert_eq(EditorTools.char_at(_rows(), Vector2i(-1, 0)), "", "left of the grid")
	assert_eq(EditorTools.char_at(_rows(), Vector2i(0, 9)), "", "below the grid")
	assert_eq(EditorTools.char_at(_rows(), Vector2i(9, 0)), "", "right of the grid")


func test_short_rows_read_as_air():
	assert_eq(EditorTools.char_at(["#", "####"], Vector2i(2, 0)), EditorTools.AIR,
		"a short row is padded with air, not read as out of bounds")


func test_paint_writes_one_cell():
	var out := EditorTools.paint_rows(_rows(), Vector2i(0, 0), "#")
	assert_eq(EditorTools.char_at(out, Vector2i(0, 0)), "#", "the cell changed")
	assert_eq(EditorTools.char_at(out, Vector2i(1, 0)), ".", "its neighbour did not")


func test_paint_out_of_bounds_changes_nothing():
	var out := EditorTools.paint_rows(_rows(), Vector2i(9, 9), "#")
	assert_eq(out, _rows(), "a stroke past the edge does not reshape the region")


func test_paint_pads_ragged_rows():
	var out := EditorTools.paint_rows(["#", "####"], Vector2i(0, 0), "~")
	assert_eq(String(out[0]).length(), 4, "the short row is squared off on the way")


func test_paint_many_writes_every_cell():
	var out := EditorTools.paint_many(_rows(), [Vector2i(0, 0), Vector2i(3, 0)], "G")
	assert_eq(EditorTools.char_at(out, Vector2i(0, 0)), "G", "first cell")
	assert_eq(EditorTools.char_at(out, Vector2i(3, 0)), "G", "last cell")


func test_line_cells_is_continuous():
	var cells := EditorTools.line_cells(Vector2i(0, 0), Vector2i(4, 2))
	assert_eq(cells[0], Vector2i(0, 0), "starts at the first sample")
	assert_eq(cells[cells.size() - 1], Vector2i(4, 2), "ends at the second")
	for i in range(1, cells.size()):
		var step: Vector2i = cells[i] - cells[i - 1]
		assert_true(absi(step.x) <= 1 and absi(step.y) <= 1,
			"no gap between %s and %s — a drag must not dot the line" % [cells[i - 1], cells[i]])


func test_line_cells_of_one_point():
	assert_eq(EditorTools.line_cells(Vector2i(2, 2), Vector2i(2, 2)), [Vector2i(2, 2)],
		"a click is a one-cell line")


func test_rect_of_works_in_either_drag_direction():
	var forward := EditorTools.rect_of(Vector2i(1, 1), Vector2i(3, 2))
	var backward := EditorTools.rect_of(Vector2i(3, 2), Vector2i(1, 1))
	assert_eq(forward, backward, "dragging up-left is the same rectangle")
	assert_eq(forward, Rect2i(1, 1, 3, 2), "and it includes both corners")


func test_rect_cells_covers_the_whole_rectangle():
	assert_eq(EditorTools.rect_cells(Vector2i(0, 0), Vector2i(2, 1)).size(), 6, "3x2 cells")


# ---------------------------------------------------------------------------
# Resizing
# ---------------------------------------------------------------------------

func test_resize_growing_right_keeps_content_in_place():
	var out := EditorTools.resize_rows(_rows(), Vector2i.ZERO, Vector2i(6, 3))
	assert_eq(EditorTools.grid_size(out), Vector2i(6, 3), "the grid grew")
	assert_eq(EditorTools.char_at(out, Vector2i(1, 1)), "#", "the wall did not move")
	assert_eq(EditorTools.char_at(out, Vector2i(5, 1)), ".", "new space is air")


func test_resize_growing_left_shifts_content():
	var out := EditorTools.resize_rows(_rows(), Vector2i(2, 0), Vector2i(6, 3))
	assert_eq(EditorTools.char_at(out, Vector2i(3, 1)), "#",
		"growing the left edge slides the content right so it stays put on screen")
	assert_eq(EditorTools.char_at(out, Vector2i(0, 1)), ".", "the new column is air")


func test_resize_cropping_drops_what_falls_outside():
	var out := EditorTools.resize_rows(_rows(), Vector2i(-2, 0), Vector2i(2, 3))
	assert_eq(EditorTools.grid_size(out), Vector2i(2, 3), "the grid shrank")
	assert_eq(EditorTools.char_at(out, Vector2i(0, 2)), "#", "what remained kept its shape")


func test_shift_cell_keys_moves_and_drops():
	var moved := EditorTools.shift_cell_keys(
		{"0,0": {"a": 1}, "3,2": {"b": 2}}, Vector2i(1, 0), Vector2i(4, 3))
	assert_true(moved.has("1,0"), "an entry inside the new grid moved with the terrain")
	assert_false(moved.has("4,2"), "an entry pushed outside was dropped")
	assert_eq(moved.size(), 1, "...and only that one")


# ---------------------------------------------------------------------------
# Fold guides
# ---------------------------------------------------------------------------

func _guides(a: Vector2i, b: Vector2i) -> Dictionary:
	return EditorTools.fold_guides(a, b, Vector2i(10, 6), 64.0)


func test_fold_guides_report_orientation():
	assert_eq(_guides(Vector2i(1, 2), Vector2i(6, 2))["orientation"], "horizontal", "same row")
	assert_eq(_guides(Vector2i(2, 1), Vector2i(2, 4))["orientation"], "vertical", "same column")
	assert_eq(_guides(Vector2i(1, 1), Vector2i(4, 3))["orientation"], "diagonal", "neither")


func test_fold_guides_draw_two_creases_and_a_meeting_line():
	var g := _guides(Vector2i(1, 2), Vector2i(6, 2))
	assert_eq((g["crease1"] as PackedVector2Array).size(), 2, "the first crease is a segment")
	assert_eq((g["crease2"] as PackedVector2Array).size(), 2, "so is the second")
	assert_eq((g["meeting"] as PackedVector2Array).size(), 2, "and so is the meeting line")


func test_fold_guides_creases_sit_on_the_anchor_centres():
	# A horizontal fold's creases are vertical lines through each anchor's centre.
	var g := _guides(Vector2i(1, 2), Vector2i(6, 2))
	var c1: PackedVector2Array = g["crease1"]
	assert_almost_eq(c1[0].x, 1.5 * 64.0, 0.01, "the crease passes through anchor a's centre")
	assert_almost_eq(c1[0].x, c1[1].x, 0.01, "and it is vertical")


func test_fold_guides_band_is_the_strip_the_fold_excises():
	var g := _guides(Vector2i(1, 2), Vector2i(6, 2))
	var band: Array = g["band"]
	assert_gt(band.size(), 0, "the fold has something to excise")
	var area := 0.0
	for poly in band:
		area += GeometryCore.polygon_area(poly)
	# Five cells of gap across a six-cell-tall region.
	assert_almost_eq(area, 5.0 * 64.0 * 6.0 * 64.0, 1.0,
		"the band is exactly the space between the creases")


func test_fold_guides_band_matches_what_the_kernel_would_drop():
	# The editor must not draw a lookalike: the shaded strip is the same
	# computation FoldReplay runs when the fold is actually applied.
	var a := Vector2i(2, 1)
	var b := Vector2i(5, 4)
	var g := EditorTools.fold_guides(a, b, Vector2i(8, 6), 64.0)
	var fold := Fold.create(0, a, b, 64.0)
	var rect := EditorTools.rect_polygon(Rect2(Vector2.ZERO, Vector2(8, 6) * 64.0))
	var expected: Array = CollisionCore.fold_polygons([rect], fold, 64.0)["dropped"]
	var got := 0.0
	var want := 0.0
	for poly in g["band"]:
		got += GeometryCore.polygon_area(poly)
	for poly in expected:
		want += GeometryCore.polygon_area(poly)
	assert_almost_eq(got, want, 0.01, "the drawn band is the kernel's excised strip")


func test_fold_guides_refuse_a_degenerate_pair():
	var g := _guides(Vector2i(3, 3), Vector2i(3, 3))
	assert_true(g["degenerate"], "two anchors on one cell have no crease direction")
	assert_eq((g["band"] as Array).size(), 0, "and nothing to excise")


func test_clip_line_to_rect_finds_the_crossing():
	var seg := EditorTools.clip_line_to_rect(
		Vector2(50, 50), Vector2(0, 1), Rect2(0, 0, 100, 100))
	assert_eq(seg.size(), 2, "a vertical line through the middle crosses the box")
	assert_almost_eq(seg[0].y, 0.0, 0.01, "entering at the top")
	assert_almost_eq(seg[1].y, 100.0, 0.01, "and leaving at the bottom")


func test_clip_line_to_rect_misses_cleanly():
	var seg := EditorTools.clip_line_to_rect(
		Vector2(-50, 50), Vector2(0, 1), Rect2(0, 0, 100, 100))
	assert_eq(seg.size(), 0, "a line outside the box yields no segment")


func test_clip_line_to_rect_handles_a_diagonal():
	var seg := EditorTools.clip_line_to_rect(
		Vector2(0, 0), Vector2(1, 1).normalized(), Rect2(0, 0, 100, 100))
	assert_eq(seg.size(), 2, "the diagonal crosses corner to corner")
	assert_almost_eq(seg[0].distance_to(Vector2(0, 0)), 0.0, 0.01, "from one corner")
	assert_almost_eq(seg[1].distance_to(Vector2(100, 100)), 0.0, 0.01, "to the other")
