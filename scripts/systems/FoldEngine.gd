class_name FoldEngine extends RefCounted

## FoldEngine
##
## Stateful owner of the derived-state model. The AUTHORITATIVE state is the base
## grid + the player's starting tile + an ordered log of steps (fold / unfold /
## move — see FoldStep). Everything else — the active fold list, the folded
## geometry, and the player's position — is DERIVED by replaying that log
## (StepReplay). Promoting the source of truth from a fold-only list to a full
## action log (F2) is what makes future mutations (destruction, triggered folds)
## replay-reachable, and therefore undoable, by construction.
##
## `folds`, `current_state`, `player_base_id`, and `player_plane_pos` are kept as
## LIVE DERIVED CACHES (refreshed from the top checkpoint after every step) so all
## existing readers — FoldController, validation, tests — see the same surface.
##
## Incremental derivation: a stack of checkpoints (one per step prefix) means
## appending a step extends the last checkpoint by ONE operation (a single fold
## clip, or an O(1) move that shares geometry by reference) instead of replaying
## the whole log; undo pops a checkpoint in O(1).
##
## The player is tracked by the BASE TILE it rides (player_base_id): after any
## re-derive the player's plane position is wherever that base tile now sits, so
## folds/unfolds move the player for free (no bespoke shift-tracking).

var base_grid: BaseGrid = null
var folds: Array[Fold] = []
var current_state: FoldedState = null
var next_fold_id: int = 0

## Player identity. The player rides a SET of base tiles (player_base_ids) — normally
## one, but more once a fold splits it into bodies. player_base_id / player_plane_pos
## are the PRIMARY body (largest fragment), kept for single-body callers and the
## single-sprite live view.
var player_base_id: int = -1
var player_plane_pos: Vector2i = Vector2i.ZERO
var player_base_ids: Array[int] = []

## Authoritative log + its derived initial condition, and the incremental cache.
var steps: Array[FoldStep] = []
var initial_player_base_id: int = -1
var _checkpoints: Array[Dictionary] = []


## Load a base grid and reset the log. Derives the identity state.
func load_base(bg: BaseGrid) -> void:
	base_grid = bg
	steps = []
	next_fold_id = 0
	initial_player_base_id = -1
	_rebuild_all()


## Place the player on the base tile at a base grid position. This is the log's
## initial condition (not a step); changing it re-derives from the start.
func set_player_start(pos: Vector2i) -> void:
	var t := base_grid.tile_at(pos) if base_grid else null
	initial_player_base_id = t.base_id if t else -1
	_rebuild_all()


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
	var f_probe := Fold.create(-1, anchor1, anchor2, base_grid.cell_size)
	if fold_blocked_by_tile(f_probe)["blocks"]:
		return false

	var fid := next_fold_id
	_append_step(FoldStep.fold(fid, anchor1, anchor2))
	next_fold_id += 1
	return true


## Remove (unfold) the fold with the given id by logging an UNFOLD step. The player
## rides whatever base tile it stood on. Returns false if the id is unknown/blocked.
func remove_fold(fold_id: int) -> bool:
	if not can_remove_fold(fold_id):
		return false
	if _fold_index(fold_id) < 0:
		return false
	_append_step(FoldStep.unfold(fold_id))
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
		if not trial_state.is_walkable(pos, base_grid.cell_size):
			return false
	return true


func get_fold(fold_id: int) -> Fold:
	var idx := _fold_index(fold_id)
	return folds[idx] if idx >= 0 else null


func fold_count() -> int:
	return folds.size()


## Move the player one step in `direction`. Every player body advances if it can
## (blocked bodies stay; a body may push a box). Returns false — logging nothing — if
## the step would change nothing (all bodies blocked, no box pushed).
func move_player(direction: Vector2i) -> bool:
	var prev: Dictionary = _checkpoints[-1]
	var trial := StepReplay.apply_step(base_grid, prev, FoldStep.move(direction))
	if _occupancy_signature(prev) == _occupancy_signature(trial):
		return false  # no-op move: don't pollute the log/undo
	steps.append(FoldStep.move(direction))
	_checkpoints.append(trial)
	_sync_from_top()
	return true


## Player-occupied plane cells (one per body; several when a fold has split a body).
func player_positions() -> Array:
	return StepReplay.player_positions(player_base_ids, current_state)


## Box-occupant positions (for the view / tests). Each entry is one box's cells.
func box_positions() -> Array:
	var out: Array = []
	for occ in _checkpoints[-1]["occupants"]:
		if occ["kind"] == StepReplay.KIND_BOX:
			out.append(StepReplay.occupant_positions(occ, current_state))
	return out


## Anchor-occupant positions (one entry per anchor; >1 cell if split by a fold).
func anchor_positions() -> Array:
	var out: Array = []
	for occ in _checkpoints[-1]["occupants"]:
		if occ["kind"] == StepReplay.KIND_ANCHOR:
			out.append(StepReplay.occupant_positions(occ, current_state))
	return out


## Place a persistent anchor occupant on the tile currently at `pos` (an undoable
## step). The anchor rides folds and splits on a seam like any occupant.
func place_anchor(pos: Vector2i, channel: String = "") -> void:
	_append_step(FoldStep.place_anchor(pos, channel))


## Sub-cell world/local center of the PRIMARY player body — the centroid of its own
## fragment, so the sprite sits on its sub-region (not the averaged cell center).
func player_center(cell_size: float) -> Vector2:
	return current_state.center_of_base_at(player_base_id, player_plane_pos, cell_size)


## The player occupant's current geometry (plane-LOCAL polygons; several when split).
## The collision engine gates moves against this shape rather than a cell/area.
func player_footprint() -> Array:
	var occ = StepReplay._player_occ(_checkpoints[-1]["occupants"])
	return StepReplay.occupant_footprint(occ, current_state, base_grid.cell_size) if occ != null else []


## Per-occupant current geometry for occupants of `kind`: [{polys: Array}], one entry
## per occupant. Used by footprint rendering and occupant-occupant collision.
func occupant_footprints(kind: int) -> Array:
	var out: Array = []
	for occ in _checkpoints[-1]["occupants"]:
		if occ["kind"] == kind:
			out.append({"polys": StepReplay.occupant_footprint(occ, current_state, base_grid.cell_size)})
	return out


## One entry per fragment of every occupant of `kind`: {base_id, pos, center}. `center`
## is the fragment's sub-cell centroid — where its marker should be drawn.
func occupant_fragment_centers(kind: int, cell_size: float) -> Array:
	var out: Array = []
	for occ in _checkpoints[-1]["occupants"]:
		if occ["kind"] == kind:
			for bid in occ["base_ids"]:
				for pos in current_state.plane_positions_of_base(bid):
					out.append({"base_id": bid, "pos": pos, "center": current_state.center_of_base_at(bid, pos, cell_size)})
	return out


## A stable signature of every occupant's ridden base ids — identical signatures mean
## nothing moved (geometry is unchanged across a MOVE, so identity determines position).
func _occupancy_signature(cp: Dictionary) -> String:
	var parts: Array = []
	for occ in cp["occupants"]:
		var ids: Array = occ["base_ids"].duplicate()
		ids.sort()
		parts.append(str(occ["kind"]) + ":" + str(ids))
	parts.sort()
	return str(parts)


## True if any player body stands on a goal tile.
func is_on_goal() -> bool:
	for p in player_positions():
		if current_state.has_type_at(p, FoldedState.TYPE_GOAL):
			return true
	return false


## Record a player move that was already performed elsewhere (the live game drives
## the single-body Player node itself). Logs it as a MOVE step (direction from the
## primary body) so it is part of the replayable history.
func sync_player_moved(to: Vector2i) -> void:
	_append_step(FoldStep.move(to - player_plane_pos))


## Drop the most recent step and re-derive (O(1) via the checkpoint stack). Returns
## false if the log is already empty. This is the engine-level "undo == drop last
## step" primitive; the live game layers a richer snapshot undo on top.
func undo_step() -> bool:
	if steps.is_empty():
		return false
	steps.pop_back()
	_checkpoints.pop_back()
	_sync_from_top()
	return true


## Snapshot the mutable state for the history/undo system. The step log IS the
## state; the derived caches (folds/player) are rebuilt from it on restore.
func capture_state() -> Dictionary:
	return {
		"steps": steps.duplicate(),  # FoldSteps are never mutated; shallow copy is safe
		"next_fold_id": next_fold_id,
		"initial_player_base_id": initial_player_base_id,
	}


## Restore from a snapshot produced by capture_state() and re-derive.
func restore_state(snap: Dictionary) -> void:
	var restored: Array[FoldStep] = []
	for s in snap.get("steps", []):
		restored.append(s)
	steps = restored
	next_fold_id = snap.get("next_fold_id", steps.size())
	initial_player_base_id = snap.get("initial_player_base_id", -1)
	_rebuild_all()


# ---------------------------------------------------------------------------
# Internals — step log + incremental checkpoint cache
# ---------------------------------------------------------------------------

## Replay the whole log from a fresh initial checkpoint (used on load / restore /
## when the initial condition changes). Rebuilds the checkpoint stack.
func _rebuild_all() -> void:
	if base_grid == null:
		return
	_checkpoints = [StepReplay.initial(base_grid, initial_player_base_id)]
	for s in steps:
		_checkpoints.append(StepReplay.apply_step(base_grid, _checkpoints[-1], s))
	_sync_from_top()


## Append one step, extend the checkpoint stack by that single operation, refresh.
func _append_step(step: FoldStep) -> void:
	steps.append(step)
	_checkpoints.append(StepReplay.apply_step(base_grid, _checkpoints[-1], step))
	_sync_from_top()


## Refresh the live derived caches from the top checkpoint.
func _sync_from_top() -> void:
	var top: Dictionary = _checkpoints[-1]
	current_state = top["state"]
	player_base_id = top["base_id"]
	player_plane_pos = top["plane_pos"]
	player_base_ids = top["base_ids"]
	var f: Array[Fold] = []
	for fold in top["folds"]:
		f.append(fold)
	folds = f


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


## General "occupant blocks fold" predicate (F5). A fold is blocked if any surface
## piece whose type has blocks_fold=true would be EXCISED or cut by it — i.e. any
## part of that piece lies in the strip strictly between the two creases. Tiles that
## sit wholly on a flap merely translate and never block. Unlike player_fold_result
## (bespoke player geometry), this scans all occupants and is driven by TileTypes, so
## new fold-proof elements need no engine changes. Returns {blocks, pos}.
func fold_blocked_by_tile(f: Fold) -> Dictionary:
	var gap: float = f.gap_distance()
	var eps := GeometryCore.EPSILON
	for pos in current_state.stacks:
		for p in current_state.surface_pieces_at(pos):
			if not TileTypes.blocks_fold(p.type):
				continue
			for v in p.polygon:
				var d: float = (v - f.crease_point1).dot(f.crease_normal)
				if d > eps and d < gap - eps:
					# Part of a fold-proof tile falls in the excised strip -> block.
					return {"blocks": true, "pos": pos}
	return {"blocks": false, "pos": Vector2i(-1, -1)}
