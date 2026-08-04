## Trigger cascade tests
##
## A TRIGGER_FOLD tile fires a channel-tagged fold when the player enters it. The
## cascade iterates because a triggered fold RIDES the player — possibly onto another
## trigger. These tests pin: firing, anchors following earlier folds, idempotence per
## channel, the reserved id range, and the bounded-fixpoint cap.
##
## The resolver works on a fragment list and a continuous player position, so these are
## pure — no scene, no physics.

extends GutTest

const TRIGGER := TileTypes.TRIGGER_FOLD
const CELL := 64.0


func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## A 10x10 grid with a fold-on-enter trigger at (5,5) that folds channel "A" between
## base cells (1,1) and (1,3).
func _base(extra := {}) -> BaseGrid:
	var types := {
		Vector2i(5, 5): {"type": TRIGGER, "channel": "A", "anchors": [[1, 1], [1, 3]]},
	}
	types.merge(extra, true)
	return BaseGrid.from_types(Vector2i(10, 10), CELL, types)


func _ctx(base: BaseGrid, at: Vector2i, folds: Array = []) -> Dictionary:
	return {
		"folds": folds,
		"pieces": FoldReplay.derive_pieces(base, folds),
		"player_pos": _center(at),
		"next_trigger_id": TriggerResolver.TRIGGER_FOLD_ID_BASE,
	}


func test_standing_off_the_trigger_fires_nothing():
	var base := _base()
	var out := TriggerResolver.resolve(base, _ctx(base, Vector2i(4, 5)))
	assert_eq((out["folds"] as Array).size(), 0,
		"no cascade unless the player is on a trigger tile")


func test_entering_the_trigger_creates_a_fold():
	var base := _base()
	var out := TriggerResolver.resolve(base, _ctx(base, Vector2i(5, 5)))
	assert_eq((out["folds"] as Array).size(), 1, "entering the trigger created one fold")
	var f: Fold = out["folds"][0]
	assert_eq(f.channel, "A", "the triggered fold carries the tile's channel")
	assert_true(f.fold_id >= TriggerResolver.TRIGGER_FOLD_ID_BASE,
		"triggered folds use the reserved id range, never colliding with player folds")
	assert_eq(out["next_trigger_id"], TriggerResolver.TRIGGER_FOLD_ID_BASE + 1,
		"the reserved counter advances")


func test_geometry_actually_changes():
	var base := _base()
	var before := FoldReplay.derive_pieces(base, [])
	var out := TriggerResolver.resolve(base, _ctx(base, Vector2i(5, 5)))
	assert_ne((out["pieces"] as Array).size(), before.size(),
		"the triggered fold is applied to the fragment list, not just recorded")


func test_channel_is_idempotent():
	# Once channel A holds a fold, resolving again must NOT add a duplicate — standing on
	# a trigger does not spawn folds every tick.
	var base := _base()
	var first := TriggerResolver.resolve(base, _ctx(base, Vector2i(5, 5)))
	var again := TriggerResolver.resolve(base, {
		"folds": first["folds"],
		"pieces": first["pieces"],
		"player_pos": first["player_pos"],
		"next_trigger_id": first["next_trigger_id"],
	})
	assert_eq((again["folds"] as Array).size(), 1,
		"channel A already has a fold — no duplicate")


func test_trigger_without_anchors_does_not_fire():
	var base := BaseGrid.from_types(Vector2i(10, 10), CELL, {
		Vector2i(5, 5): {"type": TRIGGER, "channel": "B"},
	})
	var out := TriggerResolver.resolve(base, _ctx(base, Vector2i(5, 5)))
	assert_eq((out["folds"] as Array).size(), 0, "a trigger with no anchor pair is inert")


func test_degenerate_anchor_pair_does_not_fire():
	var base := BaseGrid.from_types(Vector2i(10, 10), CELL, {
		Vector2i(5, 5): {"type": TRIGGER, "channel": "C", "anchors": [[2, 2], [2, 2]]},
	})
	var out := TriggerResolver.resolve(base, _ctx(base, Vector2i(5, 5)))
	assert_eq((out["folds"] as Array).size(), 0, "coincident anchors make no fold")


func test_player_transports_with_the_triggered_fold():
	# The trigger sits on the source side of its own fold, so firing rides the player.
	var base := BaseGrid.from_types(Vector2i(10, 10), CELL, {
		Vector2i(7, 5): {"type": TRIGGER, "channel": "D", "anchors": [[2, 5], [5, 5]]},
	})
	var ctx := _ctx(base, Vector2i(7, 5))
	var out := TriggerResolver.resolve(base, ctx)
	assert_eq((out["folds"] as Array).size(), 1, "the trigger fired")
	assert_ne(out["player_pos"], ctx["player_pos"],
		"the player rode the flap the fold moved them onto")


func test_anchors_resolve_through_an_existing_fold():
	# An earlier fold shifts cells around; the resolver must map the trigger's authored
	# anchor cells to their CURRENT plane positions, not use the raw authored ones. The
	# prior fold also moves the trigger tile itself, so the player must be placed where
	# that tile actually IS now — which is exactly what the world does.
	var base := _base()
	var prior := Fold.create(0, Vector2i(6, 0), Vector2i(8, 0), CELL)
	var pieces := FoldReplay.derive_pieces(base, [prior])
	var trigger_bid: int = base.tile_at(Vector2i(5, 5)).base_id
	var here = BaseFrame.world_point_from_base(pieces, trigger_bid, _center(Vector2i(5, 5)))
	assert_not_null(here, "the trigger tile survived the prior fold")

	var out := TriggerResolver.resolve(base, {
		"folds": [prior],
		"pieces": pieces,
		"player_pos": here,
		"next_trigger_id": TriggerResolver.TRIGGER_FOLD_ID_BASE,
	})
	assert_eq((out["folds"] as Array).size(), 2,
		"the prior fold survives and the trigger still fires")
	var triggered: Fold = out["folds"][1]
	assert_eq(triggered.channel, "A", "the new fold is the triggered one")


func test_trigger_refuses_to_cut_a_pin():
	# A plate must not become a back door around the one tile type that promises it
	# cannot be folded away. The trigger still "fires" (and is spent), but no fold lands.
	var base := BaseGrid.from_types(Vector2i(10, 10), CELL, {
		Vector2i(5, 5): {"type": TRIGGER, "channel": "E", "anchors": [[1, 1], [4, 1]]},
		Vector2i(2, 7): TileTypes.PIN,   # inside the band the trigger would excise
	})
	var out := TriggerResolver.resolve(base, _ctx(base, Vector2i(5, 5)))
	assert_eq((out["folds"] as Array).size(), 0, "the pin refuses the triggered fold")


func test_trigger_still_fires_when_the_pin_is_clear_of_the_band():
	var base := BaseGrid.from_types(Vector2i(10, 10), CELL, {
		Vector2i(5, 5): {"type": TRIGGER, "channel": "E", "anchors": [[1, 1], [4, 1]]},
		Vector2i(8, 7): TileTypes.PIN,   # well outside the band
	})
	var out := TriggerResolver.resolve(base, _ctx(base, Vector2i(5, 5)))
	assert_eq((out["folds"] as Array).size(), 1, "a pin elsewhere does not veto the fold")


func test_run_to_fixpoint_respects_the_cap():
	# A step function that never reports done must still terminate, silently.
	var calls := [0]
	var never_done := func(c):
		calls[0] += 1
		return {"done": false, "cp": c}
	var out = TriggerResolver.run_to_fixpoint({"n": 0}, never_done)
	assert_eq(calls[0], TriggerResolver.MAX_CASCADE, "the cap bounds the iteration count")
	assert_eq(out["n"], 0, "it returns the latest value rather than erroring")


func test_run_to_fixpoint_stops_when_done():
	var calls := [0]
	var done_after_three := func(c):
		calls[0] += 1
		return {"done": calls[0] >= 3, "cp": c}
	TriggerResolver.run_to_fixpoint({}, done_after_three)
	assert_eq(calls[0], 3, "stops as soon as the step reports done")
