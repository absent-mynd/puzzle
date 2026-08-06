## WorldEditor tests
##
## **Scene-driven**: the real editor scene, opened on the real shipped world.
##
## `EditorDoc` and `EditorTools` are covered headlessly elsewhere; what is only
## testable here is the layer between a mouse and a mutation — hit-testing a
## board point back to a cell, the resize grips, the camera, and the gestures
## that turn a drag into a stroke, a link or a reshape.
##
## Nothing here saves. The editor writes to `res://worlds/overworld.json`, and a
## test suite that edits the shipped world would be a very slow way to lose one.

extends GutTest

const SCENE := "res://scenes/editor/WorldEditor.tscn"
const CS := 64.0

var ed


func before_each() -> void:
	ed = load(SCENE).instantiate()
	add_child_autofree(ed)


func _pos(id: String, cell: Vector2i) -> Vector2:
	## The board point at the centre of a cell of a card.
	return ed.doc.world.board_pos(id) + (Vector2(cell) + Vector2(0.5, 0.5)) * CS


# ---------------------------------------------------------------------------
# Opening
# ---------------------------------------------------------------------------

func test_the_editor_opens_the_shipped_world():
	assert_not_null(ed.doc, "a document was loaded")
	assert_true(ed.doc.has_region("west"), "with the world's regions in it")
	assert_eq(ed.doc.path, ed.WORLD_PATH, "and it knows where to write back")


func test_opening_does_not_mark_the_world_dirty():
	assert_false(ed.doc.dirty, "merely looking at a world is not editing it")
	assert_false(ed.doc.can_undo(), "and there is nothing behind the open state")


func test_hand_authored_regions_are_given_board_positions():
	var west: Rect2 = ed.card_rect("west")
	var east: Rect2 = ed.card_rect("east")
	assert_false(west.intersects(east),
		"a file that has never been through the editor still lays out as separate cards")


func test_a_region_is_selected_to_begin_with():
	assert_eq(ed.selected_region, ed.doc.world.start_region,
		"the editor opens on the region the world starts in")


# ---------------------------------------------------------------------------
# Hit testing
# ---------------------------------------------------------------------------

func test_a_board_point_resolves_to_its_card_and_cell():
	assert_eq(ed.region_at(_pos("west", Vector2i(3, 4))), "west", "the point is over west")
	assert_eq(ed.cell_at("west", _pos("west", Vector2i(3, 4))), Vector2i(3, 4), "on cell 3,4")


func test_a_point_off_every_card_belongs_to_no_region():
	assert_eq(ed.region_at(Vector2(-9999, -9999)), "", "empty board is empty board")


func test_the_title_bar_is_above_the_card_and_belongs_to_it():
	var header: Rect2 = ed.header_rect("west")
	assert_almost_eq(header.end.y, ed.card_rect("west").position.y, 0.01,
		"the title bar sits on top of the canvas")
	assert_eq(ed.region_at(header.get_center()), "west", "and grabbing it grabs that card")


func test_chrome_stays_a_constant_size_on_screen():
	var wide: float = ed.header_rect("west").size.y
	ed.zoom_at(Vector2.ZERO, 2.0)
	assert_lt(ed.header_rect("west").size.y, wide,
		"zooming in makes the title bar cover FEWER board units — it is furniture, not content")


func test_every_card_has_eight_resize_grips():
	assert_eq(ed.resize_handles("west").size(), 8, "four corners and four edges")


func test_the_grips_sit_on_the_card_corners():
	var corner := Vector2.INF
	for handle in ed.resize_handles("west"):
		if handle["dir"] == Vector2i(-1, -1):
			corner = (handle["rect"] as Rect2).get_center()
	assert_almost_eq(corner.distance_to(ed.card_rect("west").position), 0.0, 0.01,
		"the top-left grip is on the top-left corner")


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func test_zoom_keeps_the_point_under_the_cursor_still():
	# The one interaction that has to be exact: a drifting zoom makes a large
	# board unnavigable.
	# The anchor's offset from the camera in SCREEN px is what must not change;
	# in board units it necessarily does, which is what zooming is.
	var anchor := _pos("west", Vector2i(10, 5))
	var scale_before: float = ed.view_scale()
	var screen_before: Vector2 = (anchor - ed.cam.position) * scale_before
	ed.zoom_at(anchor, 1.5)
	ed.zoom_at(anchor, 1.5)
	ed.zoom_at(anchor, 1.0 / 1.5)
	var screen_after: Vector2 = (anchor - ed.cam.position) * ed.view_scale()
	assert_gt(ed.view_scale(), scale_before, "sanity: the zoom really did change")
	assert_almost_eq(screen_after.x, screen_before.x, 0.5, "the anchor held its place, x")
	assert_almost_eq(screen_after.y, screen_before.y, 0.5, "the anchor held its place, y")


func test_zoom_is_clamped():
	for i in range(80):
		ed.zoom_at(Vector2.ZERO, 2.0)
	assert_almost_eq(ed.view_scale(), ed.MAX_ZOOM, 0.001, "cannot zoom past the maximum")
	for i in range(200):
		ed.zoom_at(Vector2.ZERO, 0.5)
	assert_almost_eq(ed.view_scale(), ed.MIN_ZOOM, 0.001, "or below the minimum")


func test_the_board_is_framed_clear_of_the_panel():
	ed.frame_all()
	var free: Rect2 = ed.free_rect()
	assert_gt(free.position.x, 0.0, "the panel takes the left of the window")
	assert_lt(free.size.x, ed.get_viewport_rect().size.x, "and the board gets the rest")


func test_frame_all_fits_every_card():
	ed.frame_all()
	var bounds: Rect2 = ed.board_bounds()
	assert_true(bounds.size.x * ed.view_scale() <= ed.free_rect().size.x + 1.0,
		"the whole board fits across")
	assert_true(bounds.size.y * ed.view_scale() <= ed.free_rect().size.y + 1.0,
		"and down")


# ---------------------------------------------------------------------------
# Gestures
# ---------------------------------------------------------------------------

func test_a_drag_paints_a_continuous_stroke():
	ed.set_tool(ed.Tool.PAINT)
	ed.set_brush("~")
	ed._press(_pos("west", Vector2i(2, 2)), false)
	ed._drag(_pos("west", Vector2i(8, 2)), Vector2.ZERO)
	ed._release(_pos("west", Vector2i(8, 2)))
	for x in range(2, 9):
		assert_eq(ed.doc.char_at("west", Vector2i(x, 2)), "~",
			"the drag painted %d,2 — a stroke must not skip cells the mouse flew over" % x)


func test_a_whole_stroke_is_one_undo():
	ed.set_tool(ed.Tool.PAINT)
	ed.set_brush("#")
	ed._press(_pos("west", Vector2i(2, 2)), false)
	ed._drag(_pos("west", Vector2i(8, 2)), Vector2.ZERO)
	ed._release(_pos("west", Vector2i(8, 2)))
	ed.doc.undo()
	assert_eq(ed.doc.char_at("west", Vector2i(5, 2)), ".", "one undo took back the whole drag")


func test_right_dragging_erases():
	ed.set_tool(ed.Tool.PAINT)
	ed._press(_pos("west", Vector2i(0, 15)), true)
	ed._release(_pos("west", Vector2i(0, 15)))
	assert_eq(ed.doc.char_at("west", Vector2i(0, 15)), ".",
		"the right button is the eraser, whatever the brush is")


func test_a_rect_drag_fills_on_release_and_not_before():
	ed.set_tool(ed.Tool.RECT)
	ed.set_brush("#")
	ed.set_tool(ed.Tool.RECT)
	ed._press(_pos("west", Vector2i(2, 2)), false)
	ed._drag(_pos("west", Vector2i(4, 4)), Vector2.ZERO)
	assert_eq(ed.doc.char_at("west", Vector2i(3, 3)), ".",
		"the rectangle is a preview until the mouse comes up")
	ed._release(_pos("west", Vector2i(4, 4)))
	assert_eq(ed.doc.char_at("west", Vector2i(3, 3)), "#", "and lands when it does")


func test_dragging_a_title_bar_moves_the_card():
	var before: Vector2 = ed.doc.world.board_pos("west")
	var grab: Vector2 = ed.header_rect("west").get_center()
	ed._press(grab, false)
	ed._drag(grab + Vector2(10 * CS, 4 * CS), Vector2.ZERO)
	ed._release(grab + Vector2(10 * CS, 4 * CS))
	assert_eq(ed.doc.world.board_pos("west"), before + Vector2(10 * CS, 4 * CS),
		"the card followed the drag, snapped to whole cells")


func test_moving_a_card_does_not_touch_the_world():
	var rows: Array = (ed.doc.region("west")["rows"] as Array).duplicate()
	var grab: Vector2 = ed.header_rect("west").get_center()
	ed._press(grab, false)
	ed._drag(grab + Vector2(500, 500), Vector2.ZERO)
	ed._release(grab + Vector2(500, 500))
	assert_eq(ed.doc.region("west")["rows"], rows,
		"where a card sits is a note to yourself, not a fact about the region")


func test_the_paint_tool_ignores_a_press_on_the_empty_board():
	ed.set_tool(ed.Tool.PAINT)
	ed._press(Vector2(-9999, -9999), false)
	assert_eq(ed.selected_region, "", "pressing empty board deselects")
	assert_false(ed.doc.dirty, "and paints nothing")


func test_dragging_a_grip_reshapes_the_canvas():
	ed.select_region("west")
	var before: Vector2i = ed.doc.size_of("west")
	var grip := Vector2.ZERO
	for handle in ed.resize_handles("west"):
		if handle["dir"] == Vector2i(1, 0):
			grip = (handle["rect"] as Rect2).get_center()
	ed._press(grip, false)
	ed._drag(grip + Vector2(5 * CS, 0), Vector2.ZERO)
	assert_eq(ed.doc.size_of("west"), before,
		"a resize is a preview while the grip is held")
	ed._release(grip + Vector2(5 * CS, 0))
	assert_eq(ed.doc.size_of("west"), before + Vector2i(5, 0),
		"and commits five columns on release")


func test_dragging_the_left_grip_grows_the_canvas_leftwards():
	ed.select_region("west")
	var before: Vector2i = ed.doc.size_of("west")
	var wall_before: String = ed.doc.char_at("west", Vector2i(0, 15))
	var grip := Vector2.ZERO
	for handle in ed.resize_handles("west"):
		if handle["dir"] == Vector2i(-1, 0):
			grip = (handle["rect"] as Rect2).get_center()
	ed._press(grip, false)
	ed._drag(grip - Vector2(3 * CS, 0), Vector2.ZERO)
	ed._release(grip - Vector2(3 * CS, 0))
	assert_eq(ed.doc.size_of("west"), before + Vector2i(3, 0), "three columns were added")
	assert_eq(ed.doc.char_at("west", Vector2i(3, 15)), wall_before,
		"and the terrain came with them rather than being left behind")


func test_dragging_between_two_doors_connects_them():
	ed.set_tool(ed.Tool.DOOR)
	var a: String = ed.doc.add_door("west", Vector2i(5, 6))
	var b: String = ed.doc.add_door("west", Vector2i(9, 6))
	ed.doc.end_gesture()
	ed._press(_pos("west", Vector2i(5, 6)), false)
	ed._drag(_pos("west", Vector2i(9, 6)), Vector2.ZERO)
	ed._release(_pos("west", Vector2i(9, 6)))
	assert_eq(String(ed.doc.world.doors[a]["pair"]), b, "the drag paired them")
	assert_eq(String(ed.doc.world.doors[b]["pair"]), a, "in both directions")


func test_a_door_drag_reaches_across_cards():
	ed.set_tool(ed.Tool.DOOR)
	var a: String = ed.doc.add_door("west", Vector2i(5, 6))
	var b: String = ed.doc.add_door("east", Vector2i(5, 5))
	ed.doc.end_gesture()
	ed._press(_pos("west", Vector2i(5, 6)), false)
	ed._release(_pos("east", Vector2i(5, 5)))
	assert_eq(String(ed.doc.world.doors[a]["pair"]), b,
		"doors connect regions, so the drag has to leave the card it started on")


func test_the_fold_tool_places_an_anchor_then_connects_a_pair():
	ed.set_tool(ed.Tool.FOLD)
	ed._press(_pos("west", Vector2i(4, 4)), false)
	ed._release(_pos("west", Vector2i(4, 4)))
	assert_eq(ed.doc.anchors_of("west"), [Vector2i(4, 4)], "the first click leaves an anchor")
	assert_eq(ed.doc.folds_of("west").size(), 0, "one anchor is not a fold")

	ed._press(_pos("west", Vector2i(12, 4)), false)
	ed._drag(_pos("west", Vector2i(4, 4)), Vector2.ZERO)
	ed._release(_pos("west", Vector2i(4, 4)))
	assert_eq(ed.doc.folds_of("west").size(), 1, "dragging onto the first one connects them")
	assert_eq(ed.doc.anchors_of("west").size(), 0, "and both anchors went into the fold")


func test_a_pre_placed_fold_does_not_fold_the_canvas():
	ed.set_tool(ed.Tool.FOLD)
	var rows: Array = (ed.doc.region("west")["rows"] as Array).duplicate()
	ed.doc.add_anchor("west", Vector2i(4, 4))
	ed.doc.add_anchor("west", Vector2i(12, 4))
	ed.doc.connect_anchors("west", Vector2i(4, 4), Vector2i(12, 4))
	assert_eq(ed.doc.region("west")["rows"], rows,
		"a pre-placed fold is DRAWN, not applied — you must still be able to see what it seals")
	assert_eq(ed.doc.size_of("west"), EditorTools.grid_size(rows), "the canvas did not shrink")


func test_a_fold_cannot_be_drawn_across_two_cards():
	ed.set_tool(ed.Tool.FOLD)
	ed.doc.add_anchor("east", Vector2i(3, 3))
	ed.doc.end_gesture()
	ed._press(_pos("west", Vector2i(4, 4)), false)
	ed._release(_pos("east", Vector2i(3, 3)))
	assert_eq(ed.doc.folds_of("west").size(), 0,
		"a fold lives in one sheet; two regions have no shared space to crease")


func test_right_clicking_a_fold_anchor_disconnects_it():
	ed.set_tool(ed.Tool.FOLD)
	ed.doc.add_anchor("west", Vector2i(4, 4))
	ed.doc.add_anchor("west", Vector2i(12, 4))
	ed.doc.connect_anchors("west", Vector2i(4, 4), Vector2i(12, 4))
	ed.doc.end_gesture()
	ed._press(_pos("west", Vector2i(12, 4)), true)
	ed._release(_pos("west", Vector2i(12, 4)))
	assert_eq(ed.doc.folds_of("west").size(), 0, "the fold no longer ships")
	assert_eq(ed.doc.anchors_of("west").size(), 2, "but the two places you chose survive")


func test_the_pick_tool_loads_the_brush():
	ed.set_tool(ed.Tool.PICK)
	ed._press(_pos("west", Vector2i(0, 15)), false)
	ed._release(_pos("west", Vector2i(0, 15)))
	assert_eq(ed.brush, "#", "clicking the floor loaded a wall into the brush")


func test_the_spawn_tool_moves_the_spawn_point():
	ed.set_tool(ed.Tool.SPAWN)
	ed._press(_pos("west", Vector2i(7, 9)), false)
	ed._release(_pos("west", Vector2i(7, 9)))
	assert_eq(ed.doc.region("west")["spawn"], Vector2(7.5, 9.5),
		"the spawn lands at the centre of the cell you clicked")


func test_the_light_tool_places_and_removes():
	ed.set_tool(ed.Tool.LIGHT)
	ed._press(_pos("west", Vector2i(6, 6)), false)
	ed._release(_pos("west", Vector2i(6, 6)))
	assert_not_null(ed.doc.light_at("west", Vector2i(6, 6)), "a light was placed")
	ed._press(_pos("west", Vector2i(6, 6)), true)
	ed._release(_pos("west", Vector2i(6, 6)))
	assert_null(ed.doc.light_at("west", Vector2i(6, 6)), "and right-click takes it away")


func test_the_hand_tool_places_the_selected_kind():
	ed.set_tool(ed.Tool.HAND)
	ed.hand_kind = HandTypes.PATIENT
	ed._press(_pos("west", Vector2i(6, 6)), false)
	ed._release(_pos("west", Vector2i(6, 6)))
	assert_eq(ed.doc.hand_at("west", Vector2i(6, 6)).kind, HandTypes.PATIENT,
		"the panel's hand kind is what gets left on the ground")


# ---------------------------------------------------------------------------
# Canvases
# ---------------------------------------------------------------------------

func test_a_new_canvas_lands_clear_of_the_others():
	ed.new_region("north", Vector2i(20, 12))
	assert_true(ed.doc.has_region("north"), "the canvas was made")
	for id in ["west", "east"]:
		assert_false(ed.card_rect("north").intersects(ed.card_rect(String(id))),
			"and does not land on top of %s" % id)


func test_a_new_canvas_becomes_the_selection():
	ed.new_region("north", Vector2i(20, 12))
	assert_eq(ed.selected_region, "north", "you are put to work on what you just made")


func test_deleting_the_selected_canvas_moves_the_selection_somewhere_real():
	ed.select_region("east")
	ed.delete_region("east")
	assert_false(ed.doc.has_region("east"), "the canvas is gone")
	assert_true(ed.doc.has_region(ed.selected_region), "and the selection is not dangling")


func test_the_editor_never_leaves_the_shipped_world_broken():
	# A sanity net over the whole scene: opening and poking the real world must
	# not produce something that would fail to boot.
	ed.new_region("north", Vector2i(12, 8))
	ed.set_tool(ed.Tool.PAINT)
	ed.set_brush("#")
	ed._press(_pos("north", Vector2i(1, 6)), false)
	ed._drag(_pos("north", Vector2i(10, 6)), Vector2.ZERO)
	ed._release(_pos("north", Vector2i(10, 6)))
	ed.doc.set_spawn("north", Vector2(2.5, 5.5))
	assert_eq(ed.doc.error_count(), 0, "the edited world would still load")
