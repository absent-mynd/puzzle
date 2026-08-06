## EditorDoc tests
##
## The editor's document: every mutation the tools can make, the undo behind them,
## and the validation that says what is wrong with a world before it ships.
##
## The invariant most of these are really about: **an edited world must still
## load.** So the assertions lean on `WorldData`'s own accessors and, at the end,
## on a real round trip through JSON.

extends GutTest


func _doc() -> EditorDoc:
	var doc := EditorDoc.create_empty("t")
	doc.add_region("west", Vector2i(8, 5), Vector2.ZERO)
	doc.end_gesture()
	return doc


# ---------------------------------------------------------------------------
# Canvases
# ---------------------------------------------------------------------------

func test_a_new_document_has_no_regions():
	var doc := EditorDoc.create_empty("t")
	assert_eq(doc.region_ids().size(), 0, "an empty world starts empty")
	assert_eq(doc.error_count(), 2, "and says so: no regions, no start region")


func test_add_region_creates_an_air_canvas():
	var doc := _doc()
	assert_eq(doc.size_of("west"), Vector2i(8, 5), "the canvas is the size asked for")
	assert_eq(doc.char_at("west", Vector2i(3, 3)), EditorTools.AIR, "and it starts empty")


func test_the_first_region_becomes_the_start_region():
	assert_eq(_doc().world.start_region, "west",
		"a world with nowhere to start cannot boot, so the first canvas volunteers")


func test_add_region_refuses_a_duplicate_name():
	var doc := _doc()
	assert_false(doc.add_region("west", Vector2i(4, 4)), "two canvases cannot share a name")


func test_add_region_refuses_an_empty_name():
	assert_false(_doc().add_region("  ", Vector2i(4, 4)), "a canvas needs a name")


func test_new_cards_do_not_land_on_top_of_each_other():
	var doc := _doc()
	doc.add_region("east", Vector2i(6, 4))
	var west := Rect2(doc.world.board_pos("west"), Vector2(doc.size_of("west")) * 64.0)
	var east := Rect2(doc.world.board_pos("east"), Vector2(doc.size_of("east")) * 64.0)
	assert_false(west.intersects(east), "a new canvas is placed clear of the others")


func test_move_region_is_authoring_only():
	var doc := _doc()
	doc.move_region("west", Vector2(500, -200))
	assert_eq(doc.world.board_pos("west"), Vector2(500, -200), "the card moved")
	assert_eq(doc.world.fold_pairs("west").size(), 0, "and the world is unchanged by it")


func test_remove_region_takes_its_doors_with_it():
	var doc := _doc()
	doc.add_region("east", Vector2i(6, 4))
	var a := doc.add_door("west", Vector2i(1, 1))
	var b := doc.add_door("east", Vector2i(2, 2))
	doc.link_doors(a, b)
	doc.remove_region("west")
	assert_false(doc.world.doors.has(a), "the door in the deleted region is gone")
	assert_true(doc.world.doors.has(b), "the door in the surviving region is not")
	assert_eq(String(doc.world.doors[b]["pair"]), "",
		"and it is left unpaired rather than silently deleted too")


func test_removing_the_start_region_hands_the_role_on():
	var doc := _doc()
	doc.add_region("east", Vector2i(6, 4))
	doc.remove_region("west")
	assert_eq(doc.world.start_region, "east", "the world still starts somewhere")


func test_rename_region_follows_through_to_the_doors_and_the_start():
	var doc := _doc()
	var d := doc.add_door("west", Vector2i(1, 1))
	assert_true(doc.rename_region("west", "sunken"), "the rename took")
	assert_eq(String(doc.world.doors[d]["region"]), "sunken", "the door came with it")
	assert_eq(doc.world.start_region, "sunken", "and so did the start region")


func test_rename_refuses_a_name_already_in_use():
	var doc := _doc()
	doc.add_region("east", Vector2i(4, 4))
	assert_false(doc.rename_region("west", "east"), "names stay unique")


# ---------------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------------

func test_paint_changes_a_cell():
	var doc := _doc()
	assert_true(doc.paint("west", Vector2i(2, 2), "#"), "the cell was painted")
	assert_eq(doc.char_at("west", Vector2i(2, 2)), "#", "and reads back")


func test_painting_the_same_cell_twice_is_not_a_change():
	var doc := _doc()
	doc.paint("west", Vector2i(2, 2), "#")
	doc.end_gesture()
	assert_false(doc.paint("west", Vector2i(2, 2), "#"),
		"a no-op must not report a change — or undo becomes a lottery")


func test_fill_rect_paints_the_whole_rectangle():
	var doc := _doc()
	doc.fill_rect("west", Vector2i(1, 1), Vector2i(3, 2), "#")
	assert_eq(doc.char_at("west", Vector2i(1, 1)), "#", "one corner")
	assert_eq(doc.char_at("west", Vector2i(3, 2)), "#", "the other")
	assert_eq(doc.char_at("west", Vector2i(4, 2)), ".", "and nothing beyond it")


func test_the_edited_rows_still_build_a_base_grid():
	var doc := _doc()
	doc.fill_rect("west", Vector2i(0, 4), Vector2i(7, 4), "#")
	var base := doc.world.build_base("west")
	assert_eq(base.grid_size, Vector2i(8, 5), "the loader sees the canvas the editor drew")
	assert_eq(base.tile_at(Vector2i(0, 4)).type, TileTypes.WALL, "...including the floor")


# ---------------------------------------------------------------------------
# Per-tile parameters
# ---------------------------------------------------------------------------

func _trigger_doc() -> EditorDoc:
	var doc := _doc()
	doc.paint("west", Vector2i(2, 2), "T")
	doc.end_gesture()
	return doc


func test_an_unconfigured_tile_reads_as_its_defaults():
	var doc := _trigger_doc()
	var data := doc.tile_data("west", Vector2i(2, 2))
	assert_eq(data["channel"], "", "the channel defaults")
	assert_eq(data["anchors"], [TileParams.UNSET, TileParams.UNSET], "with two slots to fill")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {},
		"...while the FILE says nothing at all about it")


func test_setting_a_parameter_stores_it():
	var doc := _trigger_doc()
	assert_true(doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault"), "it took")
	assert_eq(doc.tile_data("west", Vector2i(2, 2))["channel"], "vault", "and reads back")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {"channel": "vault"},
		"stored on its own — the untouched anchors are not written out")


func test_setting_a_parameter_back_to_its_default_removes_it():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {},
		"clearing a field really clears it, and the whole entry goes with the last one")


func test_setting_a_parameter_to_what_it_already_is_is_not_a_change():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	assert_false(doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault"),
		"a no-op must not push an undo step")


func test_cells_are_stored_in_the_files_own_form():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "anchors", [Vector2i(4, 1), Vector2i(6, 1)])
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2))["anchors"], [[4, 1], [6, 1]],
		"no Vector2i reaches the file")
	assert_eq(doc.tile_data("west", Vector2i(2, 2))["anchors"],
		[Vector2i(4, 1), Vector2i(6, 1)], "but the editor sees cells")


func test_a_half_filled_cell_pair_keeps_its_empty_slot():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "anchors", [Vector2i(4, 1), TileParams.UNSET])
	assert_eq(doc.tile_data("west", Vector2i(2, 2))["anchors"],
		[Vector2i(4, 1), TileParams.UNSET], "one chosen, one still to pick")


func test_an_unknown_parameter_is_kept_as_given():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "future_thing", {"a": 1})
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2))["future_thing"], {"a": 1},
		"a key with no spec is data somebody meant")


func test_clear_tile_data_removes_the_whole_entry():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	assert_true(doc.clear_tile_data("west", Vector2i(2, 2)), "there was something to clear")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {}, "and now there is not")
	assert_false(doc.clear_tile_data("west", Vector2i(2, 2)), "clearing nothing is not a change")


func test_tiles_with_data_lists_the_configured_cells():
	var doc := _trigger_doc()
	doc.paint("west", Vector2i(5, 2), "T")
	doc.set_tile_param("west", Vector2i(5, 2), "channel", "b")
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "a")
	assert_eq(doc.tiles_with_data("west"), [Vector2i(2, 2), Vector2i(5, 2)],
		"in reading order, and only the ones that actually carry something")


func test_parameters_are_undoable():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	doc.undo()
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {}, "the setting came back off")


func test_typing_a_channel_costs_one_undo():
	var doc := _trigger_doc()
	for text in ["v", "va", "vau", "vaul", "vault"]:
		doc.set_tile_param("west", Vector2i(2, 2), "channel", text, "param:channel")
	doc.end_gesture()
	doc.undo()
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {},
		"one undo takes back the whole word, not one letter of it")


func test_painting_a_tile_to_another_type_drops_its_parameters():
	# Otherwise a trigger's config lives on invisibly under a wall, and comes back
	# to life the day somebody paints a trigger there again.
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	doc.paint("west", Vector2i(2, 2), "#")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {}, "the settings went with the tile")


func test_that_drop_is_part_of_the_same_undo_as_the_paint():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	doc.paint("west", Vector2i(2, 2), "#")
	doc.end_gesture()
	doc.undo()
	assert_eq(doc.char_at("west", Vector2i(2, 2)), "T", "the tile is back")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {"channel": "vault"},
		"and so are its settings — one undo, one state")


func test_repainting_the_same_type_keeps_the_parameters():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	doc.paint("west", Vector2i(2, 2), "T")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {"channel": "vault"},
		"painting a trigger over a trigger changes nothing, so it costs nothing")


func test_a_rect_fill_drops_the_parameters_it_paints_over():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	doc.fill_rect("west", Vector2i(0, 0), Vector2i(7, 4), "#")
	assert_eq(doc.raw_tile_data("west", Vector2i(2, 2)), {},
		"a big stroke is held to the same rule as a single click")


func test_resizing_carries_the_parameters_with_the_terrain():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.end_gesture()
	doc.resize_region("west", Vector2i(3, 0), Vector2i(11, 5))
	assert_eq(doc.char_at("west", Vector2i(5, 2)), "T", "the trigger moved")
	assert_eq(doc.raw_tile_data("west", Vector2i(5, 2)), {"channel": "vault"},
		"and its settings moved with it")


# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------

func test_undo_puts_a_cell_back():
	var doc := _doc()
	doc.paint("west", Vector2i(2, 2), "#")
	doc.end_gesture()
	assert_true(doc.undo(), "there was something to undo")
	assert_eq(doc.char_at("west", Vector2i(2, 2)), ".", "the cell went back to air")


func test_redo_puts_it_back_again():
	var doc := _doc()
	doc.paint("west", Vector2i(2, 2), "#")
	doc.end_gesture()
	doc.undo()
	assert_true(doc.redo(), "there was something to redo")
	assert_eq(doc.char_at("west", Vector2i(2, 2)), "#", "the paint returned")


func test_a_stroke_is_one_undo_step():
	var doc := _doc()
	for x in range(6):
		doc.paint("west", Vector2i(x, 2), "#", "paint")
	doc.end_gesture()
	doc.undo()
	for x in range(6):
		assert_eq(doc.char_at("west", Vector2i(x, 2)), ".",
			"one undo takes back the whole drag, not one cell of it")


func test_two_strokes_are_two_undo_steps():
	var doc := _doc()
	doc.paint("west", Vector2i(0, 2), "#", "paint")
	doc.end_gesture()
	doc.paint("west", Vector2i(1, 2), "#", "paint")
	doc.end_gesture()
	doc.undo()
	assert_eq(doc.char_at("west", Vector2i(1, 2)), ".", "the second stroke came back")
	assert_eq(doc.char_at("west", Vector2i(0, 2)), "#", "the first one stayed")


func test_a_resize_is_one_undo_step():
	var doc := _doc()
	doc.add_light("west", Vector2i(1, 1))
	doc.end_gesture()
	doc.resize_region("west", Vector2i(2, 0), Vector2i(10, 5))
	assert_true(doc.undo(), "the resize is undoable")
	assert_eq(doc.size_of("west"), Vector2i(8, 5), "the canvas is back to its old shape")
	assert_eq(doc.light_at("west", Vector2i(1, 1)).cell, Vector2i(1, 1),
		"and the light it moved is back where it was, in the same step")


func test_a_new_edit_forgets_the_redo_branch():
	var doc := _doc()
	doc.paint("west", Vector2i(0, 0), "#")
	doc.end_gesture()
	doc.undo()
	doc.paint("west", Vector2i(1, 1), "~")
	doc.end_gesture()
	assert_false(doc.can_redo(), "editing after an undo drops the branch you left")


func test_undo_on_a_fresh_document_does_nothing():
	assert_false(EditorDoc.create_empty("t").undo(), "there is nothing behind the start")


func test_clear_history_leaves_the_world_alone():
	var doc := _doc()
	doc.paint("west", Vector2i(2, 2), "#")
	doc.clear_history()
	assert_false(doc.can_undo(), "the history is gone")
	assert_eq(doc.char_at("west", Vector2i(2, 2)), "#", "the edit is not")
	assert_false(doc.dirty, "and the document reads as saved")


# ---------------------------------------------------------------------------
# Resize
# ---------------------------------------------------------------------------

func test_growing_the_left_edge_carries_everything_with_the_terrain():
	var doc := _doc()
	doc.paint("west", Vector2i(0, 0), "#")
	doc.add_light("west", Vector2i(1, 1))
	doc.add_hand("west", Vector2i(2, 1), HandTypes.SWIFT)
	var door := doc.add_door("west", Vector2i(3, 1))
	doc.add_anchor("west", Vector2i(4, 1))
	doc.set_spawn("west", Vector2(5.5, 1.5))
	doc.end_gesture()

	doc.resize_region("west", Vector2i(3, 0), Vector2i(11, 5))

	assert_eq(doc.size_of("west"), Vector2i(11, 5), "the canvas grew by three columns")
	assert_eq(doc.char_at("west", Vector2i(3, 0)), "#", "the wall moved with the grid")
	assert_eq(doc.light_at("west", Vector2i(4, 1)).cell, Vector2i(4, 1), "so did the light")
	assert_eq(doc.hand_at("west", Vector2i(5, 1)).cell, Vector2i(5, 1), "and the hand")
	assert_eq(doc.world.doors[door]["cell"], Vector2i(6, 1), "and the door")
	assert_eq(doc.anchors_of("west"), [Vector2i(7, 1)], "and the loose anchor")
	assert_eq(doc.region("west")["spawn"], Vector2(8.5, 1.5), "and the spawn point")


func test_growing_an_edge_leaves_the_terrain_where_it_looked():
	# The card's board position moves the opposite way to the content shift, so
	# growing the left edge extends the card leftward instead of teleporting it.
	var doc := _doc()
	doc.move_region("west", Vector2.ZERO)
	doc.end_gesture()
	doc.resize_region("west", Vector2i(3, 0), Vector2i(11, 5))
	assert_eq(doc.world.board_pos("west"), Vector2(-3 * 64.0, 0),
		"the card's left edge moved out; its content did not move on screen")


func test_cropping_reports_what_it_dropped():
	var doc := _doc()
	doc.add_light("west", Vector2i(7, 1))
	doc.add_hand("west", Vector2i(6, 1))
	doc.end_gesture()
	var dropped := doc.resize_region("west", Vector2i.ZERO, Vector2i(4, 5))
	assert_eq(dropped, 2, "the light and the hand outside the new edge were dropped")
	assert_eq(doc.region("west")["lights"].size(), 0, "and are really gone")


func test_cropping_removes_a_door_and_unpairs_its_partner():
	var doc := _doc()
	doc.add_region("east", Vector2i(6, 4))
	var a := doc.add_door("west", Vector2i(7, 1))
	var b := doc.add_door("east", Vector2i(1, 1))
	doc.link_doors(a, b)
	doc.end_gesture()
	doc.resize_region("west", Vector2i.ZERO, Vector2i(4, 5))
	assert_false(doc.world.doors.has(a), "the cropped-out door is gone")
	assert_eq(String(doc.world.doors[b]["pair"]), "",
		"and its partner does not point at a door that no longer exists")


# ---------------------------------------------------------------------------
# Doors
# ---------------------------------------------------------------------------

func test_a_new_door_leads_nowhere():
	var doc := _doc()
	var id := doc.add_door("west", Vector2i(1, 1))
	assert_ne(id, "", "the door was placed")
	assert_eq(String(doc.world.doors[id]["pair"]), "", "connecting it is a separate act")


func test_only_one_door_per_cell():
	var doc := _doc()
	doc.add_door("west", Vector2i(1, 1))
	assert_eq(doc.add_door("west", Vector2i(1, 1)), "",
		"a door is a warp point at a tile centre; two would resolve to the same place")


func test_a_door_outside_the_canvas_is_refused():
	assert_eq(_doc().add_door("west", Vector2i(99, 99)), "", "there is no tile there to sit on")


func test_linking_doors_is_symmetric():
	var doc := _doc()
	doc.add_region("east", Vector2i(6, 4))
	var a := doc.add_door("west", Vector2i(1, 1))
	var b := doc.add_door("east", Vector2i(2, 2))
	assert_true(doc.link_doors(a, b), "the drag connected them")
	assert_eq(String(doc.world.doors[a]["pair"]), b, "a points at b")
	assert_eq(String(doc.world.doors[b]["pair"]), a, "and b points back")


func test_relinking_frees_the_old_partner():
	var doc := _doc()
	var a := doc.add_door("west", Vector2i(1, 1))
	var b := doc.add_door("west", Vector2i(2, 1))
	var c := doc.add_door("west", Vector2i(3, 1))
	doc.link_doors(a, b)
	doc.link_doors(a, c)
	assert_eq(String(doc.world.doors[b]["pair"]), "",
		"b is unpaired rather than left pointing at a door that has moved on")
	assert_eq(String(doc.world.doors[c]["pair"]), a, "and the new link is symmetric")


func test_a_door_cannot_be_linked_to_itself():
	var doc := _doc()
	var a := doc.add_door("west", Vector2i(1, 1))
	assert_false(doc.link_doors(a, a), "a door that leads to itself is not a door")


func test_removing_a_door_unpairs_its_partner():
	var doc := _doc()
	var a := doc.add_door("west", Vector2i(1, 1))
	var b := doc.add_door("west", Vector2i(2, 1))
	doc.link_doors(a, b)
	doc.remove_door(a)
	assert_eq(String(doc.world.doors[b]["pair"]), "", "no dangling pair is left behind")


# ---------------------------------------------------------------------------
# Pre-placed folds
# ---------------------------------------------------------------------------

func test_an_anchor_waits_on_the_board():
	var doc := _doc()
	assert_true(doc.add_anchor("west", Vector2i(1, 1)), "the anchor was placed")
	assert_eq(doc.anchors_of("west"), [Vector2i(1, 1)], "and is waiting for a partner")
	assert_eq(doc.folds_of("west").size(), 0, "one anchor is not a fold")


func test_the_same_cell_cannot_hold_two_anchors():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(1, 1))
	assert_false(doc.add_anchor("west", Vector2i(1, 1)), "one anchor per cell")


func test_connecting_two_anchors_makes_a_fold_and_consumes_them():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(1, 1))
	doc.add_anchor("west", Vector2i(5, 1))
	doc.end_gesture()
	assert_eq(doc.connect_anchors("west", Vector2i(1, 1), Vector2i(5, 1)), 0, "the fold was made")
	assert_eq(doc.anchors_of("west").size(), 0, "both anchors went into it")
	assert_eq(doc.folds_of("west")[0]["a"], Vector2i(1, 1), "and it kept them")


func test_a_connected_fold_is_what_the_world_boots_with():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(1, 1))
	doc.add_anchor("west", Vector2i(5, 1))
	doc.connect_anchors("west", Vector2i(1, 1), Vector2i(5, 1))
	var pairs := doc.world.fold_pairs("west")
	assert_eq(pairs.size(), 1, "the loader sees one pre-placed fold")
	assert_eq(pairs[0], [Vector2i(1, 1), Vector2i(5, 1)], "with the anchors that were drawn")


func test_a_degenerate_pair_is_refused():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(2, 2))
	assert_eq(doc.connect_anchors("west", Vector2i(2, 2), Vector2i(2, 2)), -1,
		"two anchors on one cell have no crease direction — the one impossible pair")


func test_connecting_needs_two_placed_anchors():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(1, 1))
	assert_eq(doc.connect_anchors("west", Vector2i(1, 1), Vector2i(4, 4)), -1,
		"you cannot connect to a cell where nothing was pinned")


func test_disconnecting_a_fold_returns_its_anchors():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(1, 1))
	doc.add_anchor("west", Vector2i(5, 1))
	doc.connect_anchors("west", Vector2i(1, 1), Vector2i(5, 1))
	doc.end_gesture()
	assert_true(doc.remove_fold("west", 0, true), "the fold came apart")
	assert_eq(doc.folds_of("west").size(), 0, "it no longer ships")
	assert_eq(doc.anchors_of("west").size(), 2, "but the two places you chose survive")


func test_deleting_a_fold_outright_keeps_nothing():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(1, 1))
	doc.add_anchor("west", Vector2i(5, 1))
	doc.connect_anchors("west", Vector2i(1, 1), Vector2i(5, 1))
	doc.remove_fold("west", 0, false)
	assert_eq(doc.anchors_of("west").size(), 0, "the anchors went with it")


func test_fold_at_finds_a_fold_by_either_anchor():
	var doc := _doc()
	doc.add_anchor("west", Vector2i(1, 1))
	doc.add_anchor("west", Vector2i(5, 1))
	doc.connect_anchors("west", Vector2i(1, 1), Vector2i(5, 1))
	assert_eq(doc.fold_at("west", Vector2i(5, 1)), 0, "the far anchor finds it too")
	assert_eq(doc.fold_at("west", Vector2i(3, 1)), -1, "a cell between them does not")


func test_a_nested_fold_is_saved_but_not_applied():
	# The format reserves `in` for folds inside another fold's interior. Nothing
	# applies them yet, so the loader must ignore them rather than fold the wrong
	# part of the region. See docs/features/WORLD_EDITOR.md.
	var doc := _doc()
	doc.world.regions["west"]["folds"] = [
		{"anchor1": {"x": 1, "y": 1}, "anchor2": {"x": 5, "y": 1}},
		{"anchor1": {"x": 2, "y": 2}, "anchor2": {"x": 4, "y": 2}, "in": [0]},
	]
	assert_eq(doc.world.fold_pairs("west").size(), 1, "only the world-level fold is applied")
	assert_eq(doc.folds_of("west").size(), 2, "the editor still sees and draws both")
	assert_eq(doc.folds_of("west")[1]["in"], [0], "and keeps the nesting path")


# ---------------------------------------------------------------------------
# Lights and hands
# ---------------------------------------------------------------------------

func test_a_light_lands_on_a_cell_with_a_unique_id():
	var doc := _doc()
	var a := doc.add_light("west", Vector2i(1, 1))
	var b := doc.add_light("west", Vector2i(2, 1))
	assert_ne(a, "", "the light was placed")
	assert_ne(a, b, "and ids do not collide")


func test_only_one_light_per_cell():
	var doc := _doc()
	doc.add_light("west", Vector2i(1, 1))
	assert_eq(doc.add_light("west", Vector2i(1, 1)), "", "the cell is taken")


func test_update_light_edits_it_in_place():
	var doc := _doc()
	doc.add_light("west", Vector2i(1, 1))
	doc.update_light("west", Vector2i(1, 1), {"radius_cells": 9.0, "flicker": 0.3})
	assert_almost_eq(doc.light_at("west", Vector2i(1, 1)).radius_cells, 9.0, 0.001, "radius took")
	assert_almost_eq(doc.light_at("west", Vector2i(1, 1)).flicker, 0.3, 0.001, "so did flicker")


func test_a_hand_keeps_its_kind():
	var doc := _doc()
	doc.add_hand("west", Vector2i(1, 1), HandTypes.PATIENT)
	assert_eq(doc.hand_at("west", Vector2i(1, 1)).kind, HandTypes.PATIENT, "the kind survives")


func test_starting_hands_are_written_as_authoring_keys():
	var doc := _doc()
	doc.set_starting_hands([HandTypes.SWIFT, HandTypes.PATIENT])
	assert_eq(doc.world.starting_hands, ["swift", "patient"], "stored as names, as the file wants")
	assert_eq(doc.world.starting_hand_slots()[0], HandTypes.SWIFT, "and read back as ids")


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func _messages(doc: EditorDoc, level: String) -> Array:
	var out: Array = []
	for issue in doc.validate():
		if issue["level"] == level:
			out.append(String(issue["message"]))
	return out


func test_a_plain_canvas_has_no_errors():
	assert_eq(_doc().error_count(), 0, "a fresh canvas is loadable")


func test_an_unpaired_door_is_a_warning_not_an_error():
	var doc := _doc()
	doc.add_door("west", Vector2i(1, 1))
	assert_eq(doc.error_count(), 0, "the world still loads")
	assert_gt(_messages(doc, "warn").size(), 0, "but you are told about it")


func test_a_one_way_door_is_an_error():
	var doc := _doc()
	var a := doc.add_door("west", Vector2i(1, 1))
	var b := doc.add_door("west", Vector2i(2, 1))
	doc.link_doors(a, b)
	doc.world.doors[b]["pair"] = ""   # hand-edited into a half-link
	assert_gt(doc.error_count(), 0, "a door you cannot come back through is broken")


func test_a_spawn_inside_a_wall_is_a_warning():
	var doc := _doc()
	doc.set_spawn("west", Vector2(2.5, 2.5))
	doc.paint("west", Vector2i(2, 2), "#")
	assert_eq(doc.error_count(), 0, "it loads")
	assert_true(_has(_messages(doc, "warn"), "spawn sits inside"), "and it is flagged")


func test_a_spawn_outside_the_canvas_is_an_error():
	var doc := _doc()
	doc.set_spawn("west", Vector2(99.5, 0.5))
	assert_gt(doc.error_count(), 0, "there is nowhere to put the player")


func test_an_anchor_on_an_unanchorable_tile_is_a_warning():
	var doc := _doc()
	doc.paint("west", Vector2i(1, 1), "_")
	doc.add_anchor("west", Vector2i(1, 1))
	doc.add_anchor("west", Vector2i(5, 1))
	doc.connect_anchors("west", Vector2i(1, 1), Vector2i(5, 1))
	assert_true(_has(_messages(doc, "warn"), "unanchorable"),
		"a fold pinned to a tile that refuses anchors is worth saying out loud")


func test_an_unconfigured_trigger_is_reported():
	var doc := _trigger_doc()
	assert_eq(doc.error_count(), 0, "the world still loads — the plate just does nothing")
	assert_true(_has(_messages(doc, "warn"), "not configured"),
		"but a plate that does nothing is exactly what you want told: %s"
			% [_messages(doc, "warn")])


func test_a_half_configured_trigger_says_which_slot():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "anchors", [Vector2i(4, 1), TileParams.UNSET])
	assert_true(_has(_messages(doc, "warn"), "1 of 2 not chosen"),
		"the count comes through: %s" % [_messages(doc, "warn")])


func test_a_finished_trigger_is_reported_no_further():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "channel", "vault")
	doc.set_tile_param("west", Vector2i(2, 2), "anchors", [Vector2i(4, 1), Vector2i(6, 1)])
	assert_false(_has(_messages(doc, "warn"), "trigger"),
		"a finished plate is quiet, but got: %s" % [_messages(doc, "warn")])


func test_an_anchor_outside_the_region_is_reported():
	var doc := _trigger_doc()
	doc.set_tile_param("west", Vector2i(2, 2), "anchors", [Vector2i(4, 1), Vector2i(99, 1)])
	assert_true(_has(_messages(doc, "warn"), "outside the region"),
		"a plate aimed off the map: %s" % [_messages(doc, "warn")])


func test_tile_data_stranded_outside_the_grid_is_an_error():
	var doc := _trigger_doc()
	doc.world.regions["west"]["tile_data"]["99,99"] = {"channel": "x"}
	assert_gt(doc.error_count(), 0, "the loader cannot make sense of that at all")


func test_tile_data_on_a_type_that_takes_none_is_a_warning():
	var doc := _trigger_doc()
	doc.world.regions["west"]["tile_data"]["0,0"] = {"channel": "x"}
	assert_eq(doc.error_count(), 0, "it loads, harmlessly")
	assert_true(_has(_messages(doc, "warn"), "leftover tile data"),
		"but it is dead weight and worth saying: %s" % [_messages(doc, "warn")])


func test_a_missing_start_region_is_an_error():
	var doc := _doc()
	doc.world.start_region = "nowhere"
	assert_gt(doc.error_count(), 0, "a world that starts nowhere cannot boot")


func _has(messages: Array, needle: String) -> bool:
	for m in messages:
		if String(m).findn(needle) >= 0:
			return true
	return false


# ---------------------------------------------------------------------------
# The file
# ---------------------------------------------------------------------------

func test_an_edited_world_survives_a_save_and_load():
	var doc := _doc()
	doc.fill_rect("west", Vector2i(0, 4), Vector2i(7, 4), "#")
	doc.add_region("east", Vector2i(6, 4))
	var a := doc.add_door("west", Vector2i(1, 3))
	var b := doc.add_door("east", Vector2i(2, 2))
	doc.link_doors(a, b)
	doc.add_anchor("west", Vector2i(1, 1))
	doc.add_anchor("west", Vector2i(5, 1))
	doc.connect_anchors("west", Vector2i(1, 1), Vector2i(5, 1))
	doc.add_anchor("east", Vector2i(3, 1))
	doc.add_light("west", Vector2i(2, 3))
	doc.add_hand("east", Vector2i(1, 1), HandTypes.SWIFT)
	doc.move_region("east", Vector2(1234, -567))

	var path := "user://test_editor_world.json"
	assert_true(doc.save_as(path), "the world wrote out")
	var back := EditorDoc.load_from(path)
	assert_not_null(back, "and read back")

	assert_eq(back.char_at("west", Vector2i(3, 4)), "#", "the terrain survived")
	assert_eq(String(back.world.doors[a]["pair"]), b, "the door pairing survived")
	assert_eq(back.world.fold_pairs("west")[0], [Vector2i(1, 1), Vector2i(5, 1)],
		"the pre-placed fold survived")
	assert_eq(back.anchors_of("east"), [Vector2i(3, 1)],
		"and so did the anchor still waiting for a partner")
	assert_eq(back.world.board_pos("east"), Vector2(1234, -567), "the board layout survived")
	assert_eq(back.hand_at("east", Vector2i(1, 1)).kind, HandTypes.SWIFT, "so did the loose hand")
	assert_eq(back.error_count(), 0, "and the result is a loadable world")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_saving_the_shipped_world_changes_nothing_but_the_board_layout():
	# The Ctrl+S guarantee. Opening the real world and saving it straight back
	# must be a no-op on everything the GAME reads — the only new thing in the
	# file is the authoring block that says where the cards sit.
	var doc := EditorDoc.load_from("res://worlds/overworld.json")
	var before: Dictionary = doc.world.to_dict()
	var path := "user://test_editor_resave.json"
	assert_true(doc.save_as(path), "the world wrote out")
	var after: Dictionary = WorldData.load_from(path).to_dict()

	for region in before["regions"].keys():
		(before["regions"][region] as Dictionary).erase("editor")
		(after["regions"][region] as Dictionary).erase("editor")
	assert_eq(after, before, "a save-through is a no-op on everything the game reads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_shipped_world_opens_cleanly_in_the_editor():
	# The editor has to be able to open the world the game actually ships, which
	# was authored by hand and has never had an `editor` block.
	var doc := EditorDoc.load_from("res://worlds/overworld.json")
	assert_not_null(doc, "the shipped world loads")
	assert_eq(doc.error_count(), 0, "with nothing that would stop it booting")
	assert_true(doc.has_region("west") and doc.has_region("east"), "both regions are there")
	assert_eq(doc.size_of("west"), Vector2i(44, 18), "west is the shape the file says")
	assert_eq(doc.folds_of("east").size(), 1, "east's shipped pre-fold is visible to the editor")
