extends GutTest
## PHASE 8 tests for InteractionController: the facing-interact state machine across
## config axes A (2nd-anchor), B (persistence), C (unfold priority).
##
## Tests drive handle_interact() directly and set player.grid_position/facing per step
## (facing places anchors on the tile immediately ahead of the player).

var grid_manager: GridManager
var fold_system: FoldController
var player: Player
var config: InteractionConfig
var controller: InteractionController


func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldController.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

	player = Player.new()
	add_child_autofree(player)
	player.initialize(grid_manager, Vector2i(1, 5))
	fold_system.set_player(player)

	config = InteractionConfig.new()
	config.null_anchor = InteractionConfig.NullAnchor.OFF  # avoid folded-null blocking
	grid_manager.fold_system = fold_system
	grid_manager.interaction_config = config

	controller = InteractionController.new()
	add_child_autofree(controller)
	# main_scene = null: unfold falls back to fold_system.unfold_seam; commit skips HUD
	controller.initialize(grid_manager, fold_system, player, null, config)


## Interact with the tile ahead of a chosen player pose
func _interact_from(pos: Vector2i, facing: Vector2i) -> void:
	player.grid_position = pos
	player.facing = facing
	controller.handle_interact()


## Place both anchors of a valid horizontal fold (2,5)-(5,5) approached from the sides,
## so the player never sits in the removed region or on a split cell.
func _place_two_anchors() -> void:
	_interact_from(Vector2i(1, 5), Vector2i(1, 0))   # faced (2,5) -> 1st anchor
	_interact_from(Vector2i(6, 5), Vector2i(-1, 0))  # faced (5,5) -> 2nd anchor


# ===== Axis A: second-anchor behavior =====

func test_place_then_confirm_waits_for_third_interact():
	config.second_anchor = InteractionConfig.SecondAnchor.PLACE_THEN_CONFIRM
	_place_two_anchors()

	assert_eq(controller.state, InteractionController.State.TWO_ANCHORS_PENDING,
		"State pending after 2nd anchor in place-then-confirm")
	assert_eq(grid_manager.get_selected_anchors().size(), 2, "Both anchors held")
	assert_eq(fold_system.fold_history.size(), 0, "No fold committed yet")

	# Third interact commits
	controller.handle_interact()
	await wait_seconds(1.2)
	assert_eq(fold_system.fold_history.size(), 1, "Fold committed on repeat interact")
	assert_eq(grid_manager.get_selected_anchors().size(), 0, "Selection cleared after commit")


func test_auto_fold_commits_on_second_anchor():
	config.second_anchor = InteractionConfig.SecondAnchor.AUTO_FOLD
	_place_two_anchors()
	await wait_seconds(1.2)
	assert_eq(fold_system.fold_history.size(), 1, "AUTO_FOLD commits immediately on 2nd anchor")
	assert_eq(grid_manager.get_selected_anchors().size(), 0, "Selection cleared after commit")


# ===== Movement during pending selection =====
# Axis B removed: anchors ALWAYS persist through movement (they ride their tiles).

func test_movement_keeps_anchors_pending():
	config.second_anchor = InteractionConfig.SecondAnchor.PLACE_THEN_CONFIRM
	_place_two_anchors()
	assert_eq(controller.state, InteractionController.State.TWO_ANCHORS_PENDING, "Pending")

	# A plain move must not drop the selection.
	player.attempt_move(Vector2i(0, 1))
	controller._reconcile_state()

	assert_eq(grid_manager.get_selected_anchors().size(), 2, "Both anchors retained through movement")


# ===== Axis C: unfold priority =====

func _setup_fold() -> int:
	# Meet-in-the-middle horizontal fold (2,3)-(5,3): halves meet at col 4, so the
	# crease dot lands at (4,3). Columns compress to 2..8 on every row.
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(5, 3), false)
	var newest := -1
	for record in fold_system.fold_history:
		newest = max(newest, record["fold_id"])
	return newest


func test_unfold_when_idle_unfolds_facing_dot():
	config.action_priority = InteractionConfig.ActionPriority.UNFOLD_WHEN_IDLE
	var fold_id = _setup_fold()
	assert_eq(fold_system.crease_dot_at(Vector2i(4, 3)), fold_id, "Dot present before")

	# Idle, facing the crease dot at (4,3)
	_interact_from(Vector2i(4, 2), Vector2i(0, 1))  # faced (4,3)
	assert_eq(fold_system.crease_dot_at(Vector2i(4, 3)), -1, "Dot unfolded when idle")


func test_unfold_when_idle_does_not_unfold_mid_selection():
	config.action_priority = InteractionConfig.ActionPriority.UNFOLD_WHEN_IDLE
	var fold_id = _setup_fold()

	# Place a first anchor so we are NOT idle (col 7 is occupied after the fold)
	_interact_from(Vector2i(6, 0), Vector2i(1, 0))  # faced (7,0) -> 1st anchor
	assert_eq(controller.state, InteractionController.State.ONE_ANCHOR, "One anchor down")

	# Now face the crease dot and interact - should NOT unfold under UNFOLD_WHEN_IDLE
	_interact_from(Vector2i(4, 2), Vector2i(0, 1))  # faced (4,3) = dot
	assert_eq(fold_system.crease_dot_at(Vector2i(4, 3)), fold_id,
		"Crease dot remains: mid-selection interact does not unfold")


func test_crease_dot_wins_unfolds_mid_selection():
	config.action_priority = InteractionConfig.ActionPriority.CREASE_DOT_WINS
	_setup_fold()

	_interact_from(Vector2i(6, 0), Vector2i(1, 0))  # faced (7,0) -> 1st anchor placed
	assert_eq(controller.state, InteractionController.State.ONE_ANCHOR, "One anchor down")

	# Facing the crease dot: CREASE_DOT_WINS unfolds regardless of selection
	_interact_from(Vector2i(4, 2), Vector2i(0, 1))  # faced (4,3) = dot
	assert_eq(fold_system.crease_dot_at(Vector2i(4, 3)), -1,
		"CREASE_DOT_WINS: crease unfolds even mid-selection")


# ===== State reconciliation with the debug mouse flow =====

func test_state_reconciles_with_mouse_selection():
	config.second_anchor = InteractionConfig.SecondAnchor.PLACE_THEN_CONFIRM
	# Debug mouse flow places one anchor directly at (2,5)
	grid_manager.select_cell(Vector2i(2, 5))
	assert_eq(grid_manager.get_selected_anchors().size(), 1, "Mouse placed 1 anchor")
	assert_eq(controller.state, InteractionController.State.IDLE,
		"Controller state is still stale (IDLE) before it reconciles")

	# Controller interact faces a DIFFERENT valid cell (5,5) from the right side;
	# it must reconcile to ONE_ANCHOR and place a valid 2nd anchor.
	_interact_from(Vector2i(6, 5), Vector2i(-1, 0))  # faced (5,5)
	assert_eq(grid_manager.get_selected_anchors().size(), 2,
		"Controller reconciled and placed a 2nd anchor from the mouse-seeded selection")
	assert_eq(controller.state, InteractionController.State.TWO_ANCHORS_PENDING,
		"State is pending after the reconciled 2nd anchor")


func test_auto_fold_no_double_commit_on_back_to_back_interact():
	# Back-to-back interacts must not double-commit (re-entrancy guard + refused-commit path)
	config.second_anchor = InteractionConfig.SecondAnchor.AUTO_FOLD
	_interact_from(Vector2i(1, 5), Vector2i(1, 0))   # 1st anchor (2,5)
	# Second + third interacts fired immediately: 2nd places+commits, 3rd is a no-op
	_interact_from(Vector2i(6, 5), Vector2i(-1, 0))  # 2nd anchor (5,5) -> auto commit
	controller.handle_interact()                     # extra interact, same frame
	await wait_seconds(1.2)
	assert_eq(fold_system.fold_history.size(), 1, "Exactly one fold committed, no double-commit")
