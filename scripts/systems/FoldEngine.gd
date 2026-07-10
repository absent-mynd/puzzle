class_name FoldEngine extends RefCounted

## FoldEngine
##
## Thin stateful owner of the derived-state model. Holds the immutable base grid,
## the ordered fold list, and a cached FoldedState. Every mutating operation is
## "edit the fold list, then re-derive from scratch" — there is no in-place grid
## mutation, no snapshot, and no null-piece bookkeeping.
##
## The player is tracked by the BASE TILE it rides (player_base_id): after any
## re-derive the player's plane position is wherever that base tile now sits, so
## folds/unfolds move the player for free (no bespoke shift-tracking).
##
## Stage 3 keeps this headless (no Godot nodes). Stage 5 wires it to GridManager,
## Player, and MainScene behind FoldSystem's old method names.

var base_grid: BaseGrid = null
var folds: Array[Fold] = []
var current_state: FoldedState = null
var next_fold_id: int = 0

## Player identity: the base tile the player currently stands on (-1 = none).
var player_base_id: int = -1
var player_plane_pos: Vector2i = Vector2i.ZERO


## Load a base grid and reset the fold list. Derives the identity state.
func load_base(bg: BaseGrid) -> void:
	base_grid = bg
	folds = []
	next_fold_id = 0
	_rederive()


## Place the player on the base tile at a base grid position.
func set_player_start(pos: Vector2i) -> void:
	var t := base_grid.tile_at(pos) if base_grid else null
	player_base_id = t.base_id if t else -1
	_ride_player()


func get_state() -> FoldedState:
	return current_state


## Apply a fold between two anchors (current plane positions). Returns false if the
## fold is degenerate or would fold through the player.
func apply_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	if base_grid == null:
		return false
	if anchor1 == anchor2:
		return false
	if not current_state.is_occupied(anchor1) or not current_state.is_occupied(anchor2):
		return false
	if _fold_hits_player(anchor1, anchor2):
		return false

	var f := Fold.create(next_fold_id, anchor1, anchor2, base_grid.cell_size)
	folds.append(f)
	next_fold_id += 1
	_rederive()
	return true


## Remove (unfold) the fold with the given id. Erase + re-derive. The player rides
## whatever base tile it stood on. Returns false if the id is unknown or blocked.
func remove_fold(fold_id: int) -> bool:
	if not can_remove_fold(fold_id):
		return false
	var idx := _fold_index(fold_id)
	if idx < 0:
		return false
	folds.remove_at(idx)
	_rederive()
	return true


## Whether a fold may currently be unfolded. Blocked if unfolding would strand the
## player (their base tile would no longer resolve to a walkable surface). The
## newer-fold-ordering UX rule is layered on in Stage 5 via is_independent_of_newer.
func can_remove_fold(fold_id: int) -> bool:
	var idx := _fold_index(fold_id)
	if idx < 0:
		return false
	# Tentatively remove and re-derive; player's base must still land on a walkable cell.
	if player_base_id >= 0:
		var trial := folds.duplicate()
		trial.remove_at(idx)
		var trial_state := FoldReplay.derive(base_grid, trial)
		if not trial_state.has_base(player_base_id):
			return false
		var pos := trial_state.plane_pos_of_base(player_base_id)
		if trial_state.dominant_type_at(pos) == FoldedState.TYPE_WALL:
			return false
	return true


func get_fold(fold_id: int) -> Fold:
	var idx := _fold_index(fold_id)
	return folds[idx] if idx >= 0 else null


func fold_count() -> int:
	return folds.size()


## Move the player one step to an adjacent plane position, adopting the top-of-stack
## base there. Returns false if the target is unoccupied or a wall.
func move_player(direction: Vector2i) -> bool:
	var target := player_plane_pos + direction
	# Not walkable if unoccupied, a wall, or an incomplete (partially-void) tile.
	if not current_state.is_walkable(target, base_grid.cell_size):
		return false
	var top: FoldedPiece = current_state.surface_pieces_at(target)[0]
	player_base_id = top.base_id
	player_plane_pos = target
	return true


## Snapshot the mutable state for the history/undo system.
func capture_state() -> Dictionary:
	return {
		"folds": folds.duplicate(),  # Fold records are immutable; shallow copy is safe
		"next_fold_id": next_fold_id,
		"player_base_id": player_base_id,
		"player_plane_pos": player_plane_pos,
	}


## Restore from a snapshot produced by capture_state() and re-derive.
func restore_state(snap: Dictionary) -> void:
	folds = (snap.get("folds", []) as Array).duplicate()
	next_fold_id = snap.get("next_fold_id", folds.size())
	player_base_id = snap.get("player_base_id", -1)
	player_plane_pos = snap.get("player_plane_pos", Vector2i.ZERO)
	_rederive(false)  # player state already restored explicitly


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _rederive(ride := true) -> void:
	current_state = FoldReplay.derive(base_grid, folds)
	if ride:
		_ride_player()


func _ride_player() -> void:
	if player_base_id < 0 or current_state == null:
		return
	if current_state.has_base(player_base_id):
		player_plane_pos = current_state.plane_pos_of_base(player_base_id)


func _fold_index(fold_id: int) -> int:
	for i in range(folds.size()):
		if folds[i].fold_id == fold_id:
			return i
	return -1


## Assess how a prospective fold interacts with the player.
##
## Returns { blocks: bool, reason: String, blocking_pos: Vector2i }:
##   - reason "in_region": the player is fully inside the excised strip -> block flat.
##   - reason "lands_blocked": the fold cuts the player's cell and the tile they would
##     ride to is not navigable (wall/void) -> block; blocking_pos is that tile.
##   - reason "": permitted (player is clear of the fold, or their cell is cut but they
##     land on a navigable tile and ride there).
func player_fold_result(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	var ok := {"blocks": false, "reason": "", "blocking_pos": player_plane_pos}
	if player_base_id < 0:
		return ok

	var f := Fold.create(-1, anchor1, anchor2, base_grid.cell_size)
	var gap: float = f.gap_distance()
	var eps := GeometryCore.EPSILON

	# Classify the player's surface geometry against the two creases.
	var has_a := false
	var has_between := false
	var has_b := false
	for p in current_state.surface_pieces_at(player_plane_pos):
		for v in p.polygon:
			var d: float = (v - f.crease_point1).dot(f.crease_normal)
			if d <= eps:
				has_a = true
			elif d >= gap - eps:
				has_b = true
			else:
				has_between = true

	# Fully inside the excised strip (no material on either flap) -> reject outright.
	if has_between and not has_a and not has_b:
		return {"blocks": true, "reason": "in_region", "blocking_pos": player_plane_pos}

	# Cell entirely on one flap -> the fold never touches the player.
	var is_cut := has_between or (has_a and has_b)
	if not is_cut:
		return ok

	# Edge case: the fold cuts the player's cell. Permit iff the tile they ride to is
	# navigable; otherwise block and report the offending landing tile.
	var trial := folds.duplicate()
	trial.append(f)
	var trial_state := FoldReplay.derive(base_grid, trial)
	if not trial_state.has_base(player_base_id):
		return {"blocks": true, "reason": "lands_blocked", "blocking_pos": player_plane_pos}
	var landing: Vector2i = trial_state.plane_pos_of_base(player_base_id)
	if not trial_state.is_walkable(landing, base_grid.cell_size):
		return {"blocks": true, "reason": "lands_blocked", "blocking_pos": landing}
	return {"blocks": false, "reason": "", "blocking_pos": landing}


## Boolean convenience wrapper (used by apply_fold's guard).
func _fold_hits_player(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	return player_fold_result(anchor1, anchor2)["blocks"]
