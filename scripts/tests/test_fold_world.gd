extends GutTest

## Integration tests for the gravity-prototype scene (FoldWorld): exact
## base-frame riding through fold/unfold, pinch-into-subspace (applied for
## real), folding inside a subspace with persistence on exit, glue-crossing
## exit blocking, seam-aimed unfolding, and anchor transport. Runs the real
## scene with animation disabled; assertions are synchronous.

const SCENE := "res://scenes/world/World.tscn"
const CS := 64.0

var world


func before_each() -> void:
	world = load(SCENE).instantiate()
	add_child_autofree(world)
	world.anim_enabled = false


func _pinch_over_pit() -> void:
	# Stand mid-air over the pit (air tiles), fold across: player is swallowed.
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))


func test_player_rides_a_side_flap_and_unfold_returns() -> void:
	var start: Vector2 = world.player.global_position
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_eq(world.folds.size(), 1, "Fold applied")
	assert_eq(world.mode, world.Mode.WORLD, "Riding a flap stays in the world")
	assert_almost_eq(world.player.global_position.x, start.x + 4 * CS, 130.0,
		"A-side rides shift_a (4 cells right, +/- depenetration slack)")

	world.pop_fold()
	assert_eq(world.folds.size(), 0, "Unfold removes the fold")
	assert_almost_eq(world.player.global_position.x, start.x, 130.0,
		"Unfold carries the player back exactly")


func test_pinch_applies_fold_for_real_and_exit_restores() -> void:
	_pinch_over_pit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Player in the strip is folded IN")
	assert_eq(world.folds.size(), 1, "The pinch fold IS applied to the world")
	assert_gt(world.sub_geo.get_child_count(), 0, "Subspace geometry exists")
	assert_false(world.world_geo.visible, "Outside world is hidden")

	world.player.teleport(Vector2(15.5 * CS, 12.5 * CS), false)
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exit returns to the world")
	assert_eq(world.folds.size(), 0, "Exit unfolds the outer fold")
	assert_true(world.world_geo.visible, "World visible again")
	assert_almost_eq(world.player.global_position.x, 15.5 * CS, 130.0,
		"Moving inside the fold moved you in the world")


func test_two_slot_placement_then_commit_pinches() -> void:
	# Player spawns in cell (4,12); reach is the adjacent cell, facing right.
	world.place_pending(0, Vector2i(1, 0))
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Q pins anchor 1 on the aimed cell")
	world.place_pending(0, Vector2i(1, 0))
	assert_eq(world.pending_cell(0), null, "Re-pinning the same spot clears the slot")

	world.place_pending(0, Vector2i(1, 0))          # (5,12) again
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.place_pending(1, Vector2i(1, 0))          # (9,12)
	assert_eq(world.pending_cell(1), Vector2i(9, 12), "E pins anchor 2 independently")
	assert_eq(world.folds.size(), 0, "Placement alone never commits")

	world.commit_or_unfold(Vector2i(0, -1))         # aim up: no seam there
	assert_eq(world.mode, world.Mode.SUBSPACE,
		"F with the player inside the band folds them in")
	assert_eq(world.pending_a, null, "Pendings clear on commit")


func test_commit_requires_both_anchors_and_min_gap() -> void:
	world.commit_or_unfold(Vector2i(1, 0))
	assert_eq(world.folds.size(), 0, "No anchors pinned: nothing commits")

	world.place_pending(0, Vector2i(1, 0))          # (5,12)
	world.place_pending(1, Vector2i(0, 1))          # (4,13): dist sqrt(2)
	world.commit_or_unfold(Vector2i(0, -1))
	assert_eq(world.folds.size(), 0, "Too-close pair is rejected at commit")
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Pendings kept for adjustment")


func test_interact_aimed_at_seam_unfolds_that_fold() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))  # seam anchor at (24,12)
	assert_eq(world.folds.size(), 1, "Fold active")
	world.player.teleport(Vector2(23.5 * CS, 12.5 * CS), false)
	world.commit_or_unfold(Vector2i(1, 0))          # aiming at the seam diamond
	assert_eq(world.folds.size(), 0, "F aimed at the seam anchor unfolds it")


func test_unfold_blocked_by_newer_crossing_fold() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(24, 12))  # X: vertical seam at x=22.5c
	world.do_fold(Vector2i(30, 8), Vector2i(30, 11))   # Y: horizontal band, crosses X's seam
	assert_eq(world.folds.size(), 2, "Both folds applied")
	assert_false(world.can_unfold_fold(world.folds[0]), "Newer crossing fold blocks X")

	world.unfold_level_fold(world.folds[0])
	assert_eq(world.folds.size(), 2, "Blocked unfold changes nothing")

	world.unfold_level_fold(world.folds[1])            # newest first
	assert_eq(world.folds.size(), 1, "Y unfolds fine")
	world.unfold_level_fold(world.folds[0])
	assert_eq(world.folds.size(), 0, "X unfolds once nothing newer crosses it")


func test_off_axis_anchor_pair_makes_a_diagonal_fold() -> void:
	world.place_pending(0, Vector2i(1, 0))          # (5,12)
	world.player.teleport(Vector2(7.5 * CS, 10.5 * CS), false)
	world.place_pending(1, Vector2i(1, 0))          # (8,10): off-axis, dist ~3.6
	world.commit_or_unfold(Vector2i(0, -1))
	assert_eq(world.mode, world.Mode.SUBSPACE, "Off-axis pinch folds the player in")
	assert_eq(world.sub_fold.orientation, "diagonal", "The committed fold is diagonal")


func test_interior_fold_rides_player_and_persists_on_exit() -> void:
	_pinch_over_pit()
	world.player.teleport(Vector2(11.2 * CS, 12.5 * CS), false)
	# Interior fold PARALLEL to the glue (vertical creases, like the outer's).
	var ok: bool = world.do_sub_fold(Vector2i(12, 8), Vector2i(15, 8))
	assert_true(ok, "Interior fold commits")
	assert_eq(world.level_folds().size(), 1, "Interior fold recorded")
	assert_almost_eq(world.player.global_position.x, 13.2 * CS, 130.0,
		"Player rides the interior A-flap inward")

	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Parallel interior fold does not block exit")
	assert_eq(world.folds.size(), 1, "Interior fold PERSISTS as a world fold")
	assert_eq(world.folds[0].anchor1, Vector2i(12, 8), "It is the interior fold")
	assert_almost_eq(world.player.global_position.x, 13.2 * CS, 130.0,
		"Player emerges exactly where the interior showed them")


func test_exit_blocked_by_glue_crossing_interior_fold() -> void:
	_pinch_over_pit()
	# Interior fold whose band CROSSES the glue (horizontal band in a
	# vertical-band subspace): the outer seam is no longer the newest fold
	# affecting itself, so the exit locks until the inner fold is unfolded.
	var ok: bool = world.do_sub_fold(Vector2i(12, 8), Vector2i(12, 11))
	assert_true(ok, "Crossing interior fold commits")
	world.try_exit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Exit is blocked by the crossing fold")
	assert_eq(world.folds.size(), 1, "Outer fold still applied")

	world.unfold_level_fold(world.level_folds()[0])
	assert_eq(world.level_folds().size(), 0, "Inner fold unfolded from inside")
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exit works once nothing crosses the glue")
	assert_eq(world.folds.size(), 0, "Outer fold gone, no interior folds remained")


func test_pending_anchors_survive_subspace_exit() -> void:
	_pinch_over_pit()
	world.place_pending(0, Vector2i(1, 0))          # pinned INSIDE the fold, cell (14,12)
	assert_eq(world.pending_cell(0), Vector2i(14, 12), "Anchor pinned inside the subspace")
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exited")
	assert_eq(world.pending_cell(0), Vector2i(14, 12),
		"The anchor survived the unfold and landed where the strip content did")


func test_subspace_wrap_teleports_across_the_glue() -> void:
	_pinch_over_pit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Pinched in")
	# Band along x is (10.5, 18.5) cells. Step past the far crease and wrap.
	world.player.teleport(Vector2(18.9 * CS, 12.5 * CS), false)
	world._subspace_wrap_and_turnback()
	assert_almost_eq(world.player.global_position.x, (18.9 - 8.0) * CS, 0.01,
		"Crossing the glue wraps one band width back")
	assert_eq(world.mode, world.Mode.SUBSPACE, "Wrap does not eject")


func test_outside_unfold_splices_interiors() -> void:
	# Rule 4: unfolding a fold from the outside carries its interior folds
	# into the level at its index.
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	var x: Fold = world.folds[0]
	var inner := Fold.create(500, Vector2i(22, 3), Vector2i(25, 3), CS)
	var arr: Array[Fold] = [inner]
	world.interiors[x.fold_id] = arr
	world.unfold_level_fold(x)
	assert_eq(world.folds.size(), 1, "Interior spliced into the world on outside unfold")
	assert_eq(world.folds[0].fold_id, 500, "The spliced fold is the interior one")


func test_door_traversal_between_regions() -> void:
	# W2 (west, cell 42,13) pairs with E2 (east). East's shipped pre-fold has
	# ridden E2's tile 3 cells right, so the door point sits at (5.5c, 9.5c).
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Traversed to the east region")
	assert_eq(world.mode, world.Mode.WORLD, "E2 is in normal space")
	assert_almost_eq(world.player.global_position.x, 5.5 * CS, 130.0,
		"Arrived at E2's point, which rode the shipped fold")


func test_door_into_prefolded_subspace_and_back() -> void:
	# W1's partner E1 was excised by east's shipped fold: the doorway leads
	# INSIDE that fold's subspace.
	world.player.teleport(Vector2(1.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "In the east region")
	assert_eq(world.mode, world.Mode.SUBSPACE, "...inside the shipped fold")
	assert_eq(world.sub_fold.anchor1, Vector2i(10, 6), "It is the authored pre-fold")
	assert_almost_eq(world.player.global_position.x, 13.5 * CS, 130.0,
		"Standing at E1's point inside the strip")

	# Step off the door (unlatch), then walk back through it: out to W1,
	# leaving the fold folded (door exit does not unfold).
	world.player.teleport(Vector2(11.5 * CS, 9.5 * CS), false)
	world._check_doors()
	world.player.teleport(Vector2(13.5 * CS, 9.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "west", "Back in the west region")
	assert_eq(world.mode, world.Mode.WORLD, "In normal space")
	assert_eq(world.regions["east"]["folds"].size(), 1,
		"Door exit left the east fold folded")
	assert_almost_eq(world.player.global_position.x, 1.5 * CS, 130.0,
		"Arrived at W1")


func test_split_door_point_is_dormant() -> void:
	# Cut E2's tile exactly through its center: the door point resolves
	# nowhere, so its partner refuses traversal.
	var east: Dictionary = world.regions["east"]
	var cut := Fold.create(999, Vector2i(2, 9), Vector2i(2, 12), CS)
	east["folds"].append(cut)
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "west", "Dormant far side refuses traversal")
	assert_eq(world.mode, world.Mode.WORLD, "Player stayed put")


func test_pending_anchor_inert_across_regions() -> void:
	world.place_pending(0, Vector2i(1, 0))
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Anchor pinned in west")
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Traversed")
	assert_eq(world.pending_cell(0), null, "West anchor is inert in east")
	assert_true(world.pending_a != null, "...but still pinned, waiting")


## Stand in east's normal space, on the surface near door E2.
func _enter_east() -> void:
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Crossed into the east region")
	assert_eq(world.mode, world.Mode.WORLD, "...in normal space")


## Where an east base cell currently sits, or null if it is folded away.
func _east_point(cell: Vector2i):
	var tile: BaseTile = world.base.tile_at(cell)
	return BaseFrame.world_point_from_base(
		world.current_pieces, tile.base_id, (Vector2(cell) + Vector2(0.5, 0.5)) * CS)


func test_pinned_pillar_refuses_a_fold_that_spans_it() -> void:
	_enter_east()
	var pin = _east_point(Vector2i(21, 9))
	assert_not_null(pin, "The pinned pillar stands in normal space")
	var cell := Vector2i((Vector2(pin) / CS).floor())

	var before: int = world.folds.size()
	world.do_fold(cell - Vector2i(2, 0), cell + Vector2i(2, 0))
	assert_eq(world.folds.size(), before,
		"A fold spanning the pinned pillar is refused — you route around, not through")

	world.do_fold(cell + Vector2i(3, 0), cell + Vector2i(6, 0))
	assert_eq(world.folds.size(), before + 1, "A fold clear of the pillar still commits")


func test_pressure_plate_folds_the_wall_away() -> void:
	_enter_east()
	assert_not_null(_east_point(Vector2i(27, 9)), "The wall stands before the plate is pressed")
	var plate = _east_point(Vector2i(25, 9))
	assert_not_null(plate, "The plate is reachable in normal space")

	var before: int = world.folds.size()
	world.player.teleport(Vector2(plate), false)
	world._check_triggers()
	assert_eq(world.folds.size(), before + 1, "Standing on the plate fires one fold")
	assert_null(_east_point(Vector2i(27, 9)), "...which folds the wall away")
	assert_not_null(_east_point(Vector2i(29, 9)), "The reward behind it survives")
	assert_not_null(_east_point(Vector2i(21, 9)), "And so does the pinned pillar")


func test_pressure_plate_does_not_re_fire() -> void:
	_enter_east()
	world.player.teleport(Vector2(_east_point(Vector2i(25, 9))), false)
	world._check_triggers()
	var after_first: int = world.folds.size()

	# Still standing on it: the latch holds.
	world._check_triggers()
	assert_eq(world.folds.size(), after_first, "Standing still does not re-fire the plate")

	# Step off and back on: the channel is already taken, so still nothing.
	world.player.teleport(Vector2(5.5 * CS, 9.5 * CS), false)
	world._check_triggers()
	world.player.teleport(Vector2(_east_point(Vector2i(25, 9))), false)
	world._check_triggers()
	assert_eq(world.folds.size(), after_first,
		"Re-entering the plate spawns no duplicate for a channel that already folded")


func test_triggered_fold_persists_across_leaving_the_region() -> void:
	_enter_east()
	world.player.teleport(Vector2(_east_point(Vector2i(25, 9))), false)
	world._check_triggers()
	var east_folds: int = world.regions["east"]["folds"].size()
	assert_gt(east_folds, 1, "The plate's fold joined east's persistent fold list")

	# Door E2 RODE the triggered fold with its flap, so it is no longer where it was —
	# resolve its current point rather than assuming.
	var e2 = _east_point(Vector2i(2, 9))
	assert_not_null(e2, "E2 survived the triggered fold")
	assert_ne(e2, Vector2(2.5 * CS, 9.5 * CS), "...and moved with the flap that carried it")

	# Arriving through a door latches it; stepping off is what clears the latch (in play
	# that is just the next _physics_process tick away from the doorway).
	world._check_doors()
	world.player.teleport(Vector2(e2), false)
	world._check_doors()
	assert_eq(world.region_id, "west", "Back in west")
	assert_eq(world.regions["east"]["folds"].size(), east_folds,
		"East keeps the triggered fold while you are away")


func test_no_hud_control_swallows_mouse_input() -> void:
	# Anchor placement relies on _unhandled_input receiving input; any Control
	# with MOUSE_FILTER_STOP covering the screen consumes mouse events first
	# (this bit us: the background ColorRect blocked all anchor clicks).
	var stack: Array = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			assert_ne(node.mouse_filter, Control.MOUSE_FILTER_STOP,
				"%s must not stop mouse events" % node.get_path())
		stack.append_array(node.get_children())


# ---------------------------------------------------------------------------
# Pixel rendering & dynamic lights
# ---------------------------------------------------------------------------

func _light_ids() -> Array:
	var ids: Array = []
	for entry in world.lights_here():
		if not ids.has(entry["id"]):
			ids.append(entry["id"])
	ids.sort()
	return ids


func _light_pos(id: String):
	for entry in world.lights_here():
		if entry["id"] == id:
			return Vector2(entry["pos"])
	return null


func test_the_world_draws_through_the_pixel_viewport() -> void:
	assert_not_null(world.pixel_view, "there is a low-resolution render target")
	assert_eq(world.pixel_view.size, PixelArt.VIEW_PX, "sized in art pixels")
	# Everything that is part of the WORLD renders inside it; the HUD does not,
	# which is what keeps text legible over chunky tiles.
	for node in [world.world_geo, world.sub_geo, world.player, world.overlay, world.light_rig]:
		assert_eq(node.get_parent(), world.pixel_view,
			"%s draws at art-pixel resolution" % node.name)


func test_tiles_are_drawn_from_the_tileset_and_lit() -> void:
	var textured := 0
	for child in world.world_geo.get_children():
		if not (child is Polygon2D):
			continue
		var vis: Polygon2D = child
		assert_not_null(vis.texture, "every drawn fragment samples the tileset")
		assert_eq(vis.uv.size(), vis.polygon.size(), "with one UV per vertex")
		assert_not_null(vis.material, "and is drawn with a lit material")
		textured += 1
	assert_gt(textured, 0, "the world drew some tiles")


func test_lights_are_placed_in_the_world() -> void:
	assert_eq(_light_ids(), ["w_chamber", "w_pit", "w_spawn"],
		"west's three lamps are all burning at the start")


func test_folding_a_lamp_away_removes_it_from_the_overworld() -> void:
	# Fold the pit shut from outside it: the player rides a flap, and the lamp
	# standing over the pit goes into the excised strip with everything else.
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	assert_eq(world.mode, world.Mode.WORLD, "the player rode a flap rather than being pinched")
	assert_eq(_light_ids(), ["w_chamber", "w_spawn"],
		"the folded-away lamp is not in the world at all — it casts nothing here")

	world.pop_fold()
	assert_eq(_light_ids(), ["w_chamber", "w_pit", "w_spawn"],
		"unfolding re-derives it back into the world")


func test_a_lamp_rides_the_flap_that_carries_its_tile() -> void:
	var before = _light_pos("w_spawn")
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	var after = _light_pos("w_spawn")
	assert_not_null(after, "the spawn lamp is outside the band and survives")
	assert_almost_eq(Vector2(after).x, Vector2(before).x + 4 * CS, 0.001,
		"it moved by exactly its flap's shift — a light is an occupant, not an overlay")


func test_a_lamp_folded_in_with_you_lights_the_inside() -> void:
	_pinch_over_pit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "the fold swallowed the player")
	assert_eq(_light_ids(), ["w_pit"],
		"the lamp that was over the pit is in here with you, and the ones outside are not")
	# The strip repeats across the glue, so its lights repeat with it — walking
	# through the cylinder must not walk into a dark copy of a lit room.
	var copies: int = 2 * world.SUB_LIGHT_COPIES + 1
	assert_eq(world.lights_here().size(), copies, "one lamp per wrap copy")


func test_the_vault_lamp_is_dark_from_the_overworld() -> void:
	_enter_east()
	assert_eq(_light_ids(), ["e_reward"],
		"east ships pre-folded: the vault's lamp is inside that fold, not in the region")


func test_walking_into_the_folded_vault_finds_its_lamp_burning() -> void:
	# W1's partner is folded away, so the door delivers you INSIDE the fold.
	world._traverse("W1")
	assert_eq(world.region_id, "east", "the door crossed regions")
	assert_eq(world.mode, world.Mode.SUBSPACE, "...and landed inside the pre-placed fold")
	assert_true(_light_ids().has("e_vault"),
		"the lamp that is invisible from the overworld is what lights the vault")
