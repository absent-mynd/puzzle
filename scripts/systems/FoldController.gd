## FoldController
##
## Godot-node adapter over the pure, tested FoldEngine (derive/replay core). It owns
## the live integration: snapshotting the base grid, driving GridManager's view via
## refresh_from_state, riding the Player on its base tile, and rendering crease-dot
## unfold handles. It exposes the SAME public surface the old FoldSystem did, so
## GridManager / InteractionController / MainScene need only swap the type.
##
## Truth = FoldEngine (base grid + fold list). This node holds no fold state of its
## own beyond view/render bookkeeping; every op is "edit the fold list, re-derive,
## refresh the view, ride the player."
##
## Anchor selection is ALSO part of the undoable state (see capture_ui_state): placing
## an anchor and cancelling a selection are inputs the HistoryManager can step back.

extends Node2D
class_name FoldController

const _CREASE_DOT_Z := 3

var grid_manager: GridManager = null
var player: Player = null

## The derive/replay core.
var engine: FoldEngine = null

## Animating guard (consumers check this to gate input during a fold tween).
var is_animating: bool = false
var shift_duration: float = 0.35

## Unfold-blocking mode (Axis E): 0 = ALLOW_ANY, 1 = BLOCK_ON_INTERSECTION. Set by
## MainScene from InteractionConfig.unfold_blocking.
var unfold_blocking_mode: int = 0

## Compatibility fold history: lightweight records mirroring the fold list, so
## existing HUD/bookkeeping that reads fold_history keeps working.
var fold_history: Array[Dictionary] = []

## Crease-dot markers, keyed by fold_id -> Polygon2D. Each dot is the unfold handle for
## its fold; its position is DERIVED from the fold list (see _current_seam_point) rather
## than tracked via a captured base tile — so out-of-order unfolds stay correct.
var crease_dot_by_fold: Dictionary = {}

## Baba-style global input history. A snapshot bundles engine state + anchor
## selection + player heading + view bookkeeping. Undo pops the current state and
## restores the prior.
var history: HistoryManager = HistoryManager.new()

## Last committed player facing, used to detect a heading change without a move
## (a blocked bump or turn) so it can be recorded as its own undoable input.
var _last_facing: Vector2i = Vector2i(1, 0)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Initialize from a GridManager whose cells already hold the level (pre-fold).
func initialize(gm: GridManager) -> void:
	grid_manager = gm
	engine = FoldEngine.new()
	engine.load_base(BaseGrid.from_grid_manager(gm))
	_refresh_view()


func set_player(p: Player) -> void:
	player = p
	if engine and player:
		engine.set_player_start(player.grid_position)
		_ride_player_visual()
	if player:
		_last_facing = player.facing
		# A completed move is an undoable input (Baba-style).
		if not player.moved.is_connected(_on_player_moved):
			player.moved.connect(_on_player_moved)
		# A heading change WITHOUT a move (blocked bump / turn) is also an input.
		if not player.move_attempted.is_connected(_on_player_move_attempted):
			player.move_attempted.connect(_on_player_move_attempted)


func _on_player_moved(_from: Vector2i, to: Vector2i) -> void:
	# Player self-drives movement; keep the engine's rider in sync, then record.
	# A move carries the heading change with it (single input), so record here.
	if engine:
		var top := engine.get_state().surface_pieces_at(to)
		if not top.is_empty():
			engine.player_base_id = top[0].base_id
		engine.player_plane_pos = to
	_last_facing = player.facing
	commit_input()


## A move attempt that did NOT move but DID change heading is its own undoable input
## (successful moves are recorded by _on_player_moved instead, to avoid double-record).
func _on_player_move_attempted(_direction: Vector2i, success: bool) -> void:
	if success or player == null:
		return
	if player.facing != _last_facing:
		_last_facing = player.facing
		commit_input()


# ---------------------------------------------------------------------------
# Undo history (Baba-style: record after each committed input; undo restores prior)
# ---------------------------------------------------------------------------

## Full presentation snapshot: engine truth + anchor selection + view bookkeeping.
func snapshot_state() -> Dictionary:
	var snap := engine.capture_state()
	snap["selected_anchors"] = grid_manager.selected_anchors.duplicate() if grid_manager else []
	snap["selected_anchor_points"] = grid_manager.selected_anchor_points.duplicate() if grid_manager else []
	snap["fold_history"] = fold_history.duplicate(true)
	snap["player_facing"] = player.facing if player else Vector2i(1, 0)
	return snap


## Seed the history with the initial state. Call once after initialize + set_player.
func seed_history() -> void:
	if player:
		_last_facing = player.facing
	history.clear()
	history.record_snapshot(snapshot_state())


## Record the current state as a new undo point. Call AFTER each committed input
## (anchor place, cancel, fold, unfold, move).
func commit_input() -> void:
	history.record_snapshot(snapshot_state())


## True if there is a prior state to step back to (beyond the seed).
func can_undo() -> bool:
	return history.depth() > 1


## Step back one input: reverse a move, fold, unfold, OR anchor place/cancel.
func undo() -> bool:
	if history.depth() <= 1:
		return false
	history.pop_snapshot()               # discard the current state
	var prev := history.peek_snapshot()  # the state to restore
	if prev.is_empty():
		return false
	engine.restore_state(prev)
	fold_history = (prev.get("fold_history", []) as Array).duplicate(true)
	_refresh_view()
	_ride_player_visual()
	_render_crease_dots()
	if grid_manager:
		grid_manager.set_selection(prev.get("selected_anchors", []), prev.get("selected_anchor_points", []))
	# Restore player heading (undo must reverse a turn, not just a move).
	if player and prev.has("player_facing"):
		player.set_facing(prev["player_facing"])
		_last_facing = player.facing
	return true


func get_state() -> FoldedState:
	return engine.get_state() if engine else null


# ---------------------------------------------------------------------------
# Validation (same names/shape as the old FoldSystem)
# ---------------------------------------------------------------------------

func validate_fold(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	if engine == null:
		return {"valid": false, "reason": "engine not initialized"}
	if anchor1 == anchor2:
		return {"valid": false, "reason": "anchors are the same cell"}
	var state := engine.get_state()
	if not state.is_occupied(anchor1) or not state.is_occupied(anchor2):
		return {"valid": false, "reason": "anchor cell does not exist"}
	return {"valid": true, "reason": ""}


func validate_fold_with_player(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	if engine == null:
		return {"valid": true, "reason": "", "blocking_pos": Vector2i(-1, -1)}
	var r := engine.player_fold_result(anchor1, anchor2)
	return {"valid": not r["blocks"], "reason": r["reason"], "blocking_pos": r["blocking_pos"]}


## Perpendicular cut lines for a prospective fold, in LOCAL coords. Kept for the
## GridManager region-preview. Mirrors the old FoldSystem.calculate_cut_lines.
func calculate_cut_lines(anchor1_local: Vector2, anchor2_local: Vector2) -> Dictionary:
	var normal := (anchor2_local - anchor1_local).normalized()
	return {
		"line1": {"point": anchor1_local, "normal": normal},
		"line2": {"point": anchor2_local, "normal": normal},
		"fold_axis": {"start": anchor1_local, "end": anchor2_local},
	}


# ---------------------------------------------------------------------------
# Fold / unfold (coroutine-compatible: `await` friendly)
# ---------------------------------------------------------------------------

## Apply a fold. Returns true on success. `animated` tweens the view; the truth
## (derive) is instantaneous either way.
func execute_fold(anchor1: Vector2i, anchor2: Vector2i, animated: bool = true) -> bool:
	if engine == null or is_animating:
		return false
	if not validate_fold(anchor1, anchor2).valid:
		AudioManager.play_sfx("error")
		return false
	if not validate_fold_with_player(anchor1, anchor2).valid:
		AudioManager.play_sfx("error")
		return false

	var fold_id := engine.next_fold_id
	var f := Fold.create(fold_id, anchor1, anchor2, engine.base_grid.cell_size)

	# Capture the player's pre-fold plane/world position so it can slide if it rides.
	var pre_player_plane := engine.player_plane_pos
	var pre_player_world := player.global_position if player else Vector2.ZERO

	if not engine.apply_fold(anchor1, anchor2):
		AudioManager.play_sfx("error")
		return false

	AudioManager.play_sfx("fold")
	_record_fold(f)

	# Defer player movement input until the fold finishes (avoids mid-fold move glitches).
	if player:
		player.movement_locked = true

	# Animate the (still pre-fold) view sliding into the folded configuration, THEN
	# snap the view to the exact derived geometry. The engine truth is already folded.
	if animated:
		await _animate_fold(f, pre_player_plane, pre_player_world)
	_refresh_view()
	_reset_view_transforms()
	_ride_player_visual()
	_render_crease_dots()

	if player:
		player.movement_locked = false
	return true


## Unfold (remove) a fold by id. Returns true on success.
func unfold_seam(fold_id: int) -> bool:
	if engine == null:
		return false
	if not engine.remove_fold(fold_id):
		return false
	AudioManager.play_sfx("unfold")
	_remove_fold_record(fold_id)
	_refresh_view()
	_ride_player_visual()
	_render_crease_dots()
	# Placed anchors ride their tiles through the unfold (and drop if now ambiguous).
	if grid_manager and grid_manager.has_method("reresolve_anchors"):
		grid_manager.reresolve_anchors()
	return true


## Compat alias: the old undo button routed through undo_fold_by_id. With Baba-style
## history this is superseded by HistoryManager, but keep it delegating so any legacy
## caller still unfolds the given fold.
func undo_fold_by_id(fold_id: int) -> bool:
	return unfold_seam(fold_id)


# ---------------------------------------------------------------------------
# Crease-dot / seam detection (derived from the fold list + current state)
# ---------------------------------------------------------------------------

## fold_id whose crease dot currently sits at a plane position, or -1.
func crease_dot_at(grid_pos: Vector2i) -> int:
	var best := -1
	for f in engine.folds:
		if _crease_plane_pos(f.fold_id) == grid_pos and f.fold_id > best:
			best = f.fold_id
	return best


func detect_crease_dot_click(click_pos_local: Vector2) -> Dictionary:
	if grid_manager == null or engine == null:
		return {}
	var tolerance := grid_manager.cell_size * 0.35
	var best := {}
	var best_fold := -1
	for f in engine.folds:
		var center := _crease_center(f.fold_id)
		if click_pos_local.distance_to(center) <= tolerance and f.fold_id > best_fold:
			best_fold = f.fold_id
			best = {"fold_id": f.fold_id, "can_undo": has_newer_seam_intersections(f.fold_id)["valid"]}
	return best


## Seam clicking maps to the same crease-dot handles in this model.
func detect_seam_click(click_pos_local: Vector2):
	var r := detect_crease_dot_click(click_pos_local)
	return r if not r.is_empty() else null


## Whether a fold may currently be unfolded. Always requires:
##   - the crease dot is visible (not hidden/excised), and
##   - the player is safe (won't be stranded by removing this fold).
## Under BLOCK_ON_INTERSECTION, additionally requires that no NEWER fold's seam CROSSES
## this fold's seam (collinear/parallel seams never block — that was the buggy case).
func has_newer_seam_intersections(fold_id: int) -> Dictionary:
	if engine == null:
		return {"valid": false, "reason": "engine not initialized"}
	if not _seam_visible(fold_id):
		return {"valid": false, "reason": "seam is hidden"}
	if not engine.can_remove_fold(fold_id):
		return {"valid": false, "reason": "player would be stranded"}
	if unfold_blocking_mode == 1 and not _independent_of_newer(fold_id):
		return {"valid": false, "reason": "blocked by a newer crossing fold"}
	return {"valid": true, "reason": ""}


## True if no strictly-newer fold's seam transversally crosses this fold's seam.
## Uses segment intersection, which treats parallel/collinear seams as non-crossing.
func _independent_of_newer(fold_id: int) -> bool:
	var seg := _seam_segment(fold_id)
	if seg.is_empty():
		return true
	for f in engine.folds:
		if f.fold_id <= fold_id:
			continue
		var other := _seam_segment(f.fold_id)
		if other.is_empty():
			continue
		if GeometryCore.segments_intersect(seg[0], seg[1], other[0], other[1]):
			return false
	return true


## Current seam as a long segment through the fold's meeting point, oriented along the
## crease (perpendicular to the normal). [] if the seam is hidden. Folds are pure
## translations so the crease orientation is preserved across later folds.
func _seam_segment(fold_id: int) -> Array:
	var c := _current_seam_point(fold_id)
	if c == Vector2.INF:
		return []
	var f := engine.get_fold(fold_id)
	if f == null:
		return []
	var perp := Vector2(-f.crease_normal.y, f.crease_normal.x)
	var span := Vector2(engine.base_grid.grid_size).length() * engine.base_grid.cell_size
	return [c - perp * span, c + perp * span]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _refresh_view() -> void:
	if grid_manager and engine:
		grid_manager.refresh_from_state(engine.get_state())


## Ride the player: set its plane position + world position from the engine.
func _ride_player_visual() -> void:
	if player == null or engine == null:
		return
	player.grid_position = engine.player_plane_pos
	var cell = grid_manager.get_cell(player.grid_position)
	if cell:
		player.global_position = grid_manager.to_global(cell.get_center())
		player.target_position = player.global_position


## Animate the fold via true POLYGON INTERPOLATION. The engine is ALREADY folded;
## this renders the PRE-fold geometry into a transient overlay and continuously
## vertex-maps it toward the folded configuration: the two flaps translate inward
## while the excised strip collapses onto the meeting line. The real view (hidden
## during the animation) is snapped to the derived truth by the caller afterwards.
func _animate_fold(f: Fold, pre_player_plane: Vector2i, pre_player_world: Vector2) -> void:
	is_animating = true
	var cs: float = engine.base_grid.cell_size

	# Pre-fold derived state = the fold list without the fold just applied.
	var folds_before: Array = engine.folds.slice(0, engine.folds.size() - 1)
	var before := FoldReplay.derive(engine.base_grid, folds_before)

	# Hide the real cells and build a transient overlay of the pre-fold surface.
	for pos in grid_manager.cells.keys():
		var c = grid_manager.cells[pos]
		if is_instance_valid(c):
			c.visible = false

	var overlay := Node2D.new()
	overlay.z_index = 1
	grid_manager.add_child(overlay)

	# Each item: {poly: Polygon2D, orig: PackedVector2Array}
	var items: Array = []
	for pos in before.stacks.keys():
		for piece in before.surface_pieces_at(pos):
			var p2d := Polygon2D.new()
			p2d.polygon = piece.polygon
			p2d.color = _type_color(piece.type)
			overlay.add_child(p2d)
			items.append({"poly": p2d, "orig": piece.polygon})

	# Fold vertex-map parameters.
	var c1 := f.crease_point1
	var normal := f.crease_normal
	var gap := f.gap_distance()
	var shift_a := f.shift_a_px(cs)
	var shift_b := f.shift_b_px(cs)
	var m := shift_a.dot(normal)  # normal-distance of the meeting line from crease1

	var setter := func(t: float):
		for it in items:
			if is_instance_valid(it["poly"]):
				it["poly"].polygon = _fold_map_polygon(
					it["orig"], t, c1, normal, gap, m, shift_a, shift_b)

	var tween := create_tween()
	tween.tween_method(setter, 0.0, 1.0, shift_duration)

	# Slide the player if it rides a shifted cell (its plane position changed).
	if player and engine.player_plane_pos != pre_player_plane:
		var final_center_local := Vector2(engine.player_plane_pos) * cs + Vector2(cs / 2.0, cs / 2.0)
		var final_world := grid_manager.to_global(final_center_local)
		player.global_position = pre_player_world
		create_tween().tween_property(player, "global_position", final_world, shift_duration)

	# Close the region preview (both creases + fill sweep onto the meeting line).
	if grid_manager.has_method("animate_region_close"):
		grid_manager.animate_region_close(c1, f.crease_point2, c1 + shift_a, normal, shift_duration)

	await tween.finished
	overlay.queue_free()
	is_animating = false


## Vertex-map a pre-fold polygon toward its folded shape at time t in [0,1].
## A-side (d<=0) translates by shift_a; B-side (d>=gap) by shift_b; the between strip
## collapses onto the meeting line (normal-distance m) so it vanishes at t=1.
func _fold_map_polygon(poly: PackedVector2Array, t: float, c1: Vector2, normal: Vector2,
		gap: float, m: float, shift_a: Vector2, shift_b: Vector2) -> PackedVector2Array:
	var eps := GeometryCore.EPSILON
	var out := PackedVector2Array()
	for v in poly:
		var d: float = (v - c1).dot(normal)
		if d <= eps:
			out.append(v + shift_a * t)
		elif d >= gap - eps:
			out.append(v + shift_b * t)
		else:
			out.append(v + normal * ((m - d) * t))
	return out


## Reset transient animation state after a view refresh (cells were hidden and may
## carry leftover transforms/modulate from an earlier slide implementation).
func _reset_view_transforms() -> void:
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		if is_instance_valid(cell):
			cell.position = Vector2.ZERO
			cell.modulate = Color.WHITE
			cell.visible = true


## Fill color for a cell type (mirrors Cell.get_cell_color_for_type for the overlay).
func _type_color(type: int) -> Color:
	match type:
		1: return Color(0.2, 0.2, 0.2)   # wall
		2: return Color(0.2, 0.4, 1.0)   # water
		3: return Color(0.2, 1.0, 0.2)   # goal
		_: return Color(0.8, 0.8, 0.8)   # empty/default


func _record_fold(f: Fold) -> void:
	fold_history.append({
		"fold_id": f.fold_id,
		"anchor1": f.anchor1,
		"anchor2": f.anchor2,
		"orientation": f.orientation,
	})


func _remove_fold_record(fold_id: int) -> void:
	for i in range(fold_history.size() - 1, -1, -1):
		if fold_history[i]["fold_id"] == fold_id:
			fold_history.remove_at(i)
			return


## Current LOCAL position of a fold's seam/meeting point, DERIVED from the fold list.
##
## A fold's meeting point is fixed in the frame it was applied; only folds AFTER it in
## the list can move it, so we transform the meeting point forward through each
## subsequent fold. This is independent of earlier folds — so unfolding an earlier
## (e.g. collinear) fold out of order no longer shifts this fold's dot off its seam.
func _current_seam_point(fold_id: int) -> Vector2:
	if engine == null:
		return Vector2.INF
	var cs: float = engine.base_grid.cell_size
	var idx := engine._fold_index(fold_id)
	if idx < 0:
		return Vector2.INF
	var f: Fold = engine.folds[idx]
	var p := Vector2(f.meeting_pos) * cs + Vector2(cs / 2.0, cs / 2.0)
	for j in range(idx + 1, engine.folds.size()):
		p = _fold_point_forward(p, engine.folds[j], cs)
	return p


## Transform a point forward through one fold. A point on the target flap (d<=0) moves
## by shift_a, on the source flap (d>=gap) by shift_b — these ride to the meeting line.
## A point STRICTLY inside the excised strip (0<d<gap) is removed by this fold, so it is
## HIDDEN -> returns INF (propagated). This makes hiding depend only on WHICH folds are
## present, not the order they were made/removed: a point excised by a still-present
## fold stays hidden regardless of what else is unfolded.
func _fold_point_forward(p: Vector2, g: Fold, cs: float) -> Vector2:
	if p == Vector2.INF:
		return Vector2.INF
	var eps := GeometryCore.EPSILON
	var normal := g.crease_normal
	var gap := g.gap_distance()
	var d: float = (p - g.crease_point1).dot(normal)
	if d <= eps:
		return p + g.shift_a_px(cs)
	elif d >= gap - eps:
		return p + g.shift_b_px(cs)
	return Vector2.INF  # strictly between the creases -> excised -> hidden


## Map a CURRENT-space LOCAL point back to base (unfolded) space, or INF if the point
## is ambiguous (on a seam / in a void). Probes neighbours like anchor_base_at so a
## point sitting on a seam yields INF (the anchor will not survive geometry changes).
func base_point_at(point: Vector2) -> Vector2:
	if engine == null:
		return Vector2.INF
	var state := engine.get_state()
	var cs: float = engine.base_grid.cell_size
	var probe := 1.0
	var offsets := [Vector2.ZERO, Vector2(probe, 0), Vector2(-probe, 0),
		Vector2(0, probe), Vector2(0, -probe)]
	var offsets_seen := {}
	var found: FoldedPiece = null
	for off in offsets:
		var q: Vector2 = point + off
		var cell_pos := Vector2i(int(floor(q.x / cs)), int(floor(q.y / cs)))
		for piece in state.surface_pieces_at(cell_pos):
			if GeometryCore.point_in_polygon(q, piece.polygon):
				offsets_seen[piece.src_offset] = true
				found = piece
	# One consistent source offset across all probes -> unambiguous.
	if offsets_seen.size() != 1 or found == null:
		return Vector2.INF
	return point - found.src_offset


## Transform a base-space point to its current LOCAL position by replaying every fold.
## Returns INF if the point is hidden (excised) by any fold, or the input is INF.
func forward_point(base_point: Vector2) -> Vector2:
	if engine == null or base_point == Vector2.INF:
		return Vector2.INF
	var cs: float = engine.base_grid.cell_size
	var p := base_point
	for f in engine.folds:
		p = _fold_point_forward(p, f, cs)
		if p == Vector2.INF:
			return Vector2.INF
	return p


func _crease_plane_pos(fold_id: int) -> Vector2i:
	var p := _current_seam_point(fold_id)
	if p == Vector2.INF:
		return Vector2i(-99999, -99999)
	var cs: float = engine.base_grid.cell_size
	return Vector2i(int(floor(p.x / cs)), int(floor(p.y / cs)))


func _crease_center(fold_id: int) -> Vector2:
	var p := _current_seam_point(fold_id)
	return p if p != Vector2.INF else Vector2(-99999, -99999)


## Is the CENTER of a derived cell covered by a surface piece (vs sitting in a void
## within a partially-covered cell)? This is the visibility test for anchors/dots: the
## point they rest on must be real ground, not empty space.
func cell_center_covered(cell: Vector2i) -> bool:
	if engine == null:
		return false
	var cs: float = engine.base_grid.cell_size
	var center := Vector2(cell) * cs + Vector2(cs / 2.0, cs / 2.0)
	for piece in engine.get_state().surface_pieces_at(cell):
		if GeometryCore.point_in_polygon(center, piece.polygon):
			return true
	return false


## A fold's seam is visible if the center of its derived seam cell rests on real ground.
## A seam whose point falls in a void (fully excised, or the void side of a partial cell)
## is hidden -> its crease dot isn't drawn and it can't be picked for unfolding.
func _seam_visible(fold_id: int) -> bool:
	var p := _current_seam_point(fold_id)
	if p == Vector2.INF or engine == null:
		return false
	var cs: float = engine.base_grid.cell_size
	var cell := Vector2i(int(floor(p.x / cs)), int(floor(p.y / cs)))
	return cell_center_covered(cell)


## Render one crease-dot handle per current fold at its derived seam point.
func _render_crease_dots() -> void:
	if grid_manager == null or engine == null:
		return
	var active := {}
	for f in engine.folds:
		active[f.fold_id] = true
	# Drop dots for folds that no longer exist.
	for fold_id in crease_dot_by_fold.keys():
		if not active.has(fold_id):
			var d = crease_dot_by_fold[fold_id]
			if is_instance_valid(d):
				d.queue_free()
			crease_dot_by_fold.erase(fold_id)
	# Ensure/position a dot per current fold; hide those whose seam is fully hidden.
	for f in engine.folds:
		var p := _current_seam_point(f.fold_id)
		var visible := p != Vector2.INF and _seam_visible(f.fold_id)
		var dot: Polygon2D = crease_dot_by_fold.get(f.fold_id, null)
		if not visible:
			if dot != null and is_instance_valid(dot):
				dot.visible = false
			continue
		if dot == null or not is_instance_valid(dot):
			dot = _make_crease_dot()
			crease_dot_by_fold[f.fold_id] = dot
			grid_manager.add_child(dot)
		dot.position = p
		dot.visible = true


func _make_crease_dot() -> Polygon2D:
	var dot := Polygon2D.new()
	var r := 6.0
	var pts := PackedVector2Array()
	for i in range(12):
		var a := TAU * i / 12.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	dot.polygon = pts
	dot.color = Color(1.0, 0.9, 0.2, 0.95)
	dot.z_index = _CREASE_DOT_Z
	return dot
