## Trigger cascade tests (F3)
##
## A TRIGGER_FOLD tile fires a channel-tagged fold when the player enters it. The
## cascade is resolved INSIDE the derivation (StepReplay.apply_step), so triggered
## folds are deterministic and undo drops the whole cascade with its authored step.
## These tests pin: firing, undo, replay determinism, idempotence, no-fire-at-load,
## and the bounded-fixpoint cap.

extends GutTest

const TRIGGER := TileTypes.TRIGGER_FOLD


# A 10x10 grid with a fold-on-enter trigger at (5,5) that folds channel "A" between
# base cells (1,1) and (1,3). Player starts just left of the trigger.
func _trigger_engine() -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = Vector2i(10, 10)
	ld.cell_size = 64.0
	ld.cell_data = {
		Vector2i(5, 5): {"type": TRIGGER, "channel": "A", "anchors": [[1, 1], [1, 3]]},
	}
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(Vector2i(4, 5))
	return e


func test_trigger_does_not_fire_at_load():
	var e := _trigger_engine()
	assert_eq(e.fold_count(), 0, "no cascade runs at load — only on a step")


func test_step_onto_trigger_creates_fold():
	var e := _trigger_engine()
	assert_true(e.move_player(Vector2i(1, 0)), "player steps onto the trigger")
	assert_eq(e.fold_count(), 1, "entering the trigger created one fold")
	var f: Fold = e.folds[0]
	assert_eq(f.channel, "A", "the triggered fold carries the tile's channel")
	assert_true(f.fold_id >= TriggerResolver.TRIGGER_FOLD_ID_BASE,
		"triggered folds use the reserved id range, never colliding with player folds")


func test_undo_drops_the_triggered_cascade():
	var e := _trigger_engine()
	e.move_player(Vector2i(1, 0))
	assert_eq(e.fold_count(), 1, "fold present after firing")
	assert_true(e.undo_step(), "undo the move")
	assert_eq(e.fold_count(), 0, "undo drops the whole cascade with its step")
	assert_eq(e.steps.size(), 0, "log empty again")


func test_capture_restore_reproduces_trigger_fold():
	var e := _trigger_engine()
	e.move_player(Vector2i(1, 0))
	var snap := e.capture_state()  # log holds only the MOVE; the fold is re-derived
	# Mutate, then restore: the triggered fold must come back identically.
	e.undo_step()
	assert_eq(e.fold_count(), 0, "reset")
	e.restore_state(snap)
	assert_eq(e.fold_count(), 1, "restore replays the cascade")
	assert_eq(e.folds[0].channel, "A", "same channel after restore")


func test_trigger_is_idempotent_when_channel_already_folded():
	# Once channel A holds a fold, resolving again from the same state must NOT add a
	# duplicate — standing on a trigger does not spawn folds every tick.
	var e := _trigger_engine()
	e.move_player(Vector2i(1, 0))
	var cp: Dictionary = e._checkpoints[-1]
	var again := TriggerResolver.resolve(e.base_grid, cp)
	assert_eq((again["folds"] as Array).size(), (cp["folds"] as Array).size(),
		"resolving again adds no duplicate fold for an existing channel")


func test_run_to_fixpoint_stops_at_cap():
	# A step that never reports done must terminate at MAX_CASCADE (silently), not hang.
	var never_done := func(c): return {"done": false, "cp": c + 1}
	var result = TriggerResolver.run_to_fixpoint(0, never_done)
	assert_eq(result, TriggerResolver.MAX_CASCADE,
		"cap bounds the loop to MAX_CASCADE iterations")


func test_run_to_fixpoint_returns_on_done():
	# Reports done on the 3rd step; loop must stop there.
	var stop_at_three := func(c):
		var n: int = c + 1
		return {"done": n >= 3, "cp": n}
	var result = TriggerResolver.run_to_fixpoint(0, stop_at_three)
	assert_eq(result, 3, "loop stops as soon as the step reports done")


func test_view_grid_carries_trigger_data_to_engine():
	# Mirrors the live path: MainScene sets a trigger type + tile_data on view Cells,
	# and the engine's base is built from the view via BaseGrid.from_grid_manager.
	# Per-instance data must survive that hop, or triggers never fire in the game.
	var gm := GridManager.new()
	gm.grid_size = Vector2i(7, 3)
	gm.cell_size = 64.0
	gm.create_grid()
	var plate = gm.get_cell(Vector2i(1, 1))
	plate.set_cell_type(TRIGGER)
	plate.tile_data = {"channel": "A", "anchors": [[3, 1], [5, 1]]}
	gm.get_cell(Vector2i(4, 1)).set_cell_type(1)  # wall

	var base := BaseGrid.from_grid_manager(gm)
	var t := base.tile_at(Vector2i(1, 1))
	assert_eq(t.type, TRIGGER, "trigger type carried from view Cell to BaseTile")
	assert_eq(str(t.data.get("channel", "")), "A", "trigger params carried from view Cell")

	var e := FoldEngine.new()
	e.load_base(base)
	e.set_player_start(Vector2i(0, 1))
	assert_true(e.move_player(Vector2i(1, 0)), "player steps onto the plate")
	assert_eq(e.fold_count(), 1, "a view-built base fires the trigger on enter")

	for c in gm.cells.values():
		if c:
			c.free()
	gm.free()


func test_level_data_round_trips_trigger_params():
	# The richer cell_data value (F7 slice) survives JSON serialization and reads back
	# via type_at / data_at.
	var ld := LevelData.new()
	ld.grid_size = Vector2i(6, 6)
	ld.cell_data = {
		Vector2i(2, 2): 1,  # plain int tile still works
		Vector2i(5, 5): {"type": TRIGGER, "channel": "B", "anchors": [[0, 0], [2, 0]]},
	}
	var round := LevelData.new()
	round.from_dict(ld.to_dict())
	assert_eq(round.type_at(Vector2i(2, 2)), 1, "plain int tile round-trips")
	assert_eq(round.data_at(Vector2i(2, 2)), {}, "plain tile has no params")
	assert_eq(round.type_at(Vector2i(5, 5)), TRIGGER, "trigger type round-trips")
	assert_eq(str(round.data_at(Vector2i(5, 5)).get("channel", "")), "B",
		"trigger channel round-trips")
