## Space-Folding Puzzle Game - InteractionController
##
## PHASE 8: Owns the player-facing interaction state machine (the primary game input
## mode). The player interacts (SPACE) with the tile immediately in their facing
## direction to place fold anchors, commit folds, or unfold creases.
##
## Behavior is governed by an InteractionConfig (Axes A-D), so gameplay combinations can
## be explored from the inspector. This controller is decoupled from the debug MOUSE flow
## (GridManager mouse select + MainScene Enter-to-fold), which keeps working independently.
## Both flows write to the SAME grid_manager.selected_anchors, so the controller reconciles
## its state from that array on every interact.
##
## Input note: the `interact` action (SPACE) is handled in _input and marked handled, so
## the debug Enter/Space (ui_accept) fold in MainScene effectively responds to ENTER only.

extends Node
class_name InteractionController

## Selection progress within the facing-interact flow
enum State { IDLE, ONE_ANCHOR, TWO_ANCHORS_PENDING }

var state: State = State.IDLE

## Injected references
var grid_manager: GridManager = null
var fold_system: FoldController = null
var player: Player = null
var main_scene: Node = null            # for _finalize_fold_success() / perform_unfold()
var config: InteractionConfig = null


## Wire up references and connect to the player's move signals (Axis B)
func initialize(p_grid_manager: GridManager, p_fold_system: FoldController, p_player: Player,
		p_main_scene: Node, p_config: InteractionConfig) -> void:
	grid_manager = p_grid_manager
	fold_system = p_fold_system
	player = p_player
	main_scene = p_main_scene
	config = p_config if p_config else InteractionConfig.new()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		handle_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if grid_manager and not grid_manager.get_selected_anchors().is_empty():
			cancel_selection()
			get_viewport().set_input_as_handled()


## Cancel any in-progress selection
func cancel_selection() -> void:
	if grid_manager:
		grid_manager.clear_selection()
	state = State.IDLE
	# Cancelling a selection is an undoable input (Baba-style history).
	if fold_system:
		fold_system.commit_input()


## Reconcile `state` from the shared anchor array so the controller tolerates the
## debug mouse flow (or a rejected placement) changing the selection underneath it.
func _reconcile_state() -> void:
	if not grid_manager:
		state = State.IDLE
		return
	match grid_manager.get_selected_anchors().size():
		0:
			state = State.IDLE
		1:
			state = State.ONE_ANCHOR
		_:
			# 2 anchors present. If AUTO_FOLD, this is transient; treat as pending.
			state = State.TWO_ANCHORS_PENDING


## Core interact handler: the state machine
func handle_interact() -> void:
	if not grid_manager or not fold_system or not player:
		return

	# Ignore interacts while a fold animation is in progress (re-entrancy guard).
	if fold_system.is_animating:
		return

	_reconcile_state()

	var faced_pos: Vector2i = player.grid_position + player.facing

	# Axis C: unfold priority
	var dot_fold_id: int = fold_system.crease_dot_at(faced_pos)
	var crease_wins := config.action_priority == InteractionConfig.ActionPriority.CREASE_DOT_WINS
	if dot_fold_id >= 0 and (crease_wins or state == State.IDLE):
		_try_unfold(dot_fold_id)
		return

	# Anchor / commit flow
	match state:
		State.IDLE:
			grid_manager.select_cell(faced_pos, _anchor_point(faced_pos))
			_reconcile_state()

		State.ONE_ANCHOR:
			var placed := grid_manager.select_cell(faced_pos, _anchor_point(faced_pos))
			_reconcile_state()
			if placed and state == State.TWO_ANCHORS_PENDING:
				# Axis A: what happens on 2nd-anchor placement
				if config.second_anchor == InteractionConfig.SecondAnchor.AUTO_FOLD:
					_commit_fold()
				# else PLACE_THEN_CONFIRM: leave pending until next interact

		State.TWO_ANCHORS_PENDING:
			_commit_fold()


## Sub-cell anchor point for a faced tile, biased toward the player so that on a merged
## (seamed) cell the anchor pins to the side nearest the player rather than landing on
## the seam itself. For a plain cell this is still well inside the single piece.
func _anchor_point(faced_pos: Vector2i) -> Vector2:
	var cs: float = grid_manager.cell_size
	var center := Vector2(faced_pos) * cs + Vector2(cs / 2.0, cs / 2.0)
	return center - Vector2(player.facing) * (cs * 0.25)


## Attempt to unfold a crease via the player-facing flow (delegates to MainScene)
func _try_unfold(fold_id: int) -> void:
	var can_undo: bool = fold_system.has_newer_seam_intersections(fold_id)["valid"]
	if main_scene and main_scene.has_method("perform_unfold"):
		main_scene.perform_unfold(fold_id, can_undo)
	elif can_undo:
		fold_system.unfold_seam(fold_id)


## Commit the currently-selected 2-anchor fold
func _commit_fold() -> void:
	var anchors = grid_manager.get_selected_anchors()
	if anchors.size() != 2:
		return

	# Capture anchors before the await; execute_fold clears nothing but be explicit.
	var a1 = anchors[0]
	var a2 = anchors[1]
	var success = await fold_system.execute_fold(a1, a2, true)

	if success:
		grid_manager.clear_selection()
		state = State.IDLE
		if main_scene and main_scene.has_method("_finalize_fold_success"):
			main_scene._finalize_fold_success()
	else:
		# Commit refused (e.g. the player would land on a blocked tile): flash the invalid
		# region briefly and keep the selection so the player can adjust and retry rather
		# than silently losing both anchors.
		grid_manager.flash_invalid_fold(a1, a2)
		_reconcile_state()
