extends Node2D

## ProtoWorld
##
## Playable proof-of-concept for the metroidvania pivot: the REAL fold model
## (BaseGrid / Fold / FoldReplay / CollisionCore, unchanged) driving a
## side-view world with gravity and a free-moving blob player.
##
## Current mechanics:
##   - EXACT RIDING: player and pinned anchors map through every fold/unfold
##     via base-frame points (fragment src_offset), never crease arithmetic.
##   - Q/E pin two anchors (embodied: the cell you point at); F commits.
##     Standing inside the band at commit = PINCH: the fold is applied to the
##     world FOR REAL and you enter its SUBSPACE — the excised strip rendered
##     as a cylinder (repeating across the glue), gravity on.
##   - Folding INSIDE a subspace works (same machinery over the strip
##     fragments). Interior folds persist into the world when you exit.
##   - The outer fold's anchors coincide at one point on the glue line; F
##     aimed there unfolds the subspace (exit). Unfold BLOCKING applies
##     everywhere: a fold cannot be unfolded while a newer fold's band crosses
##     its seam segment — so interior folds crossing the glue lock the exit.
##   - Fold/unfold animation: flaps translate, the strip collapses onto (or
##     expands from) the meeting line; physics freezes for the duration.
##
## Deliberate prototype limits: no nested pinch (you cannot fold yourself
## deeper while inside), fold extent is still infinite-crease (barrier
## scoping deferred), animation plays only for newest-fold unfolds.

enum Mode { WORLD, SUBSPACE }

const CS := ProtoCore.CELL
## Anchors are pinned at arm's length: the cell immediately in the pointed
## direction. What you can fold is exactly what you can stand next to.
const ANCHOR_REACH := 1
const ANIM_TIME := 0.24
const TYPE_COLORS := {
	BaseTile.TYPE_EMPTY: Color(0.13, 0.14, 0.20),   # faint: the "paper" exists
	BaseTile.TYPE_WALL: Color(0.55, 0.60, 0.70),
	BaseTile.TYPE_WATER: Color(0.25, 0.45, 0.75),
	BaseTile.TYPE_GOAL: Color(0.91, 0.76, 0.35),
}
const SUB_TINT := Color(0.72, 0.62, 0.95)  # subspace pieces shift hue

var base: BaseGrid
var folds: Array[Fold] = []
var next_fold_id := 0
var mode: Mode = Mode.WORLD

## Pending anchors: null or {"bid": int, "bp": Vector2} — a base-frame point.
## Frame-independent: the anchor rides folds/unfolds and survives subspace
## exit, resolving to a cell wherever its base tile currently lies.
var pending_a = null
var pending_b = null

var current_pieces: Array[FoldedPiece] = []
var pieces_by_pos: Dictionary = {}
var wall_polys: Array = []
var goal_polys: Array = []
var _on_goal := false

## fold_id -> PackedVector2Array [from, to]: the fold's seam segment, used for
## newer-fold unfold blocking.
var seam_segs: Dictionary = {}

# --- Subspace state (interior view of the newest world fold) ---
var sub_fold: Fold = null
var sub_base_pieces: Array = []       # excised strip content (outer pre-fold frame)
var sub_folds: Array[Fold] = []       # folds made INSIDE; persist on exit
var sub_pieces: Array = []            # derived interior (strip + sub_folds)
var sub_by_pos: Dictionary = {}
var sub_wall_polys: Array = []
var sub_extent: Dictionary = {}
var sub_glue_segs: Array = []
var sub_copies := 1

# --- Animation ---
var anim_enabled := true
var _anim: Dictionary = {}

var _spawn := Vector2((4.0 + 0.5) * CS, (12.0 + 0.5) * CS)
var player: ProtoPlayer
var world_geo: Node2D
var world_solid: StaticBody2D
var sub_geo: Node2D
var overlay: ProtoOverlay
var _bg: ColorRect
var _status: Label
var _flash: Label
var _flash_left := 0.0


func _ready() -> void:
	base = ProtoCore.parse_map(_make_map())

	world_geo = Node2D.new()
	add_child(world_geo)
	sub_geo = Node2D.new()
	add_child(sub_geo)

	overlay = ProtoOverlay.new()
	overlay.world = self
	overlay.z_index = 50
	add_child(overlay)

	player = ProtoPlayer.new()
	player.position = _spawn
	player.z_index = 40
	add_child(player)

	_build_hud()
	rebuild_world()


# ---------------------------------------------------------------------------
# Map: authored programmatically so beats are easy to retune (no ASCII counting)
# ---------------------------------------------------------------------------
# Beats, left to right: start plateau | 8-wide unjumpable pit | tower with a
# goal on top | flat run | fully sealed chamber with a goal inside.
func _make_map() -> Array:
	var w := 44
	var h := 18
	var rows: Array = []
	for y in range(h):
		rows.append(".".repeat(w))

	var put := func(x: int, y: int, ch: String) -> void:
		var row: String = rows[y]
		rows[y] = row.substr(0, x) + ch + row.substr(x + 1)

	for y in range(14, 18):            # ground, with the pit at x 10..17
		for x in range(0, 10):
			put.call(x, y, "#")
		for x in range(18, w):
			put.call(x, y, "#")
	for y in range(7, 14):             # tower
		for x in range(22, 25):
			put.call(x, y, "#")
	put.call(23, 6, "G")               # goal on the tower top
	for x in range(32, 41):            # chamber roof
		put.call(x, 9, "#")
	for y in range(10, 14):            # chamber side walls
		put.call(32, y, "#")
		put.call(40, y, "#")
	put.call(36, 13, "G")              # goal sealed inside the chamber
	return rows


# ---------------------------------------------------------------------------
# Derived state -> visuals + colliders
# ---------------------------------------------------------------------------

func rebuild_world() -> void:
	current_pieces = FoldReplay.derive_pieces(base, folds)
	pieces_by_pos = ProtoCore.index_by_pos(current_pieces)
	for child in world_geo.get_children():
		child.queue_free()
	wall_polys = []
	goal_polys = []

	world_solid = StaticBody2D.new()
	# The world's colliders must be inert while the player is inside a
	# subspace (hidden geometry still collides otherwise).
	world_solid.collision_layer = 1 if mode == Mode.WORLD else 0
	world_geo.add_child(world_solid)
	for piece in current_pieces:
		var vis := Polygon2D.new()
		vis.polygon = piece.polygon
		vis.color = TYPE_COLORS.get(piece.type, Color.MAGENTA)
		world_geo.add_child(vis)
		if piece.type == BaseTile.TYPE_WALL:
			wall_polys.append(piece.polygon)
			var col := CollisionPolygon2D.new()
			col.polygon = piece.polygon
			world_solid.add_child(col)
		elif piece.type == BaseTile.TYPE_GOAL:
			goal_polys.append(piece.polygon)


func rebuild_sub() -> void:
	sub_pieces = sub_base_pieces.duplicate()
	for fold in sub_folds:
		sub_pieces = FoldReplay.apply_one_fold(sub_pieces, fold, CS)
	sub_by_pos = ProtoCore.index_by_pos(sub_pieces)
	sub_wall_polys = ProtoCore.wall_polys_of(sub_pieces)

	for child in sub_geo.get_children():
		child.queue_free()
	var gap := sub_fold.gap_distance()
	sub_copies = clampi(int(ceil(1400.0 / gap)), 1, 24)
	for k in range(-sub_copies, sub_copies + 1):
		var copy := Node2D.new()
		copy.position = sub_fold.crease_normal * (k * gap)
		sub_geo.add_child(copy)
		var solid: StaticBody2D = null
		if absi(k) <= 1:
			solid = StaticBody2D.new()
			copy.add_child(solid)
		for piece in sub_pieces:
			var vis := Polygon2D.new()
			vis.polygon = piece.polygon
			var c: Color = TYPE_COLORS.get(piece.type, Color.MAGENTA)
			vis.color = c.lerp(SUB_TINT, 0.35) if piece.type != BaseTile.TYPE_EMPTY else c
			copy.add_child(vis)
			if piece.type == BaseTile.TYPE_WALL and solid != null:
				var col := CollisionPolygon2D.new()
				col.polygon = piece.polygon
				solid.add_child(col)


func _frame_pieces() -> Array:
	return sub_pieces if mode == Mode.SUBSPACE else current_pieces


func _frame_index() -> Dictionary:
	return sub_by_pos if mode == Mode.SUBSPACE else pieces_by_pos


func animating() -> bool:
	return not _anim.is_empty()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if animating():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q:
				place_pending(0, player.point_dir())
			KEY_E:
				place_pending(1, player.point_dir())
			KEY_F:
				commit_or_unfold(player.point_dir())
			KEY_U:
				if mode == Mode.SUBSPACE:
					try_exit()
				else:
					pop_fold()
			KEY_ESCAPE:
				pending_a = null
				pending_b = null
			KEY_R:
				_reset()


## The grid cell the player's center is in.
func player_cell() -> Vector2i:
	return Vector2i((player.global_position / CS).floor())


## Where Q/E/F aim right now: the adjacent cell in the pointed direction.
func candidate_anchor(dir: Vector2i = Vector2i.ZERO) -> Vector2i:
	var d := dir if dir != Vector2i.ZERO else Vector2i(player.point_dir())
	return player_cell() + d * ANCHOR_REACH


## The current cell of a pending anchor in THIS frame, or null if unset or if
## its base tile has no fragment here (e.g. pinned outside, viewed inside).
func pending_cell(slot: int):
	var p = pending_a if slot == 0 else pending_b
	if p == null:
		return null
	var wp = ProtoCore.world_point_from_base(_frame_pieces(), p["bid"], p["bp"])
	if wp == null:
		return null
	return Vector2i((Vector2(wp) / CS).floor())


## Pin (or move) one of the two pending anchors on the aimed cell. Pinning a
## slot on its own current cell clears it. Anchors are stored as base-frame
## points, so they ride folds and survive subspace entry/exit.
func place_pending(slot: int, dir: Vector2i) -> void:
	if animating():
		return
	var cand := candidate_anchor(dir)
	var center := (Vector2(cand) + Vector2(0.5, 0.5)) * CS
	var piece = ProtoCore.piece_containing(_frame_index(), center, CS)
	if piece == null:
		_show_flash("Nothing there to anchor to.")
		return
	var entry := {"bid": piece.base_id, "bp": center - piece.src_offset}
	if slot == 0:
		pending_a = null if pending_cell(0) != null and pending_cell(0) == cand else entry
	else:
		pending_b = null if pending_cell(1) != null and pending_cell(1) == cand else entry


## The fold (of the current frame) whose seam anchor the player is aiming at
## or standing on. Post-fold, both anchors coincide at the meeting cell.
func aimed_fold(dir: Vector2i = Vector2i.ZERO) -> Fold:
	var cand := candidate_anchor(dir)
	var here := player_cell()
	var list: Array = sub_folds if mode == Mode.SUBSPACE else folds
	for fold in list:
		if fold.meeting_pos == cand or fold.meeting_pos == here:
			return fold
	return null


## Inside a subspace, is the player aiming at (or standing on) the outer
## fold's anchor point? Both outer anchors are the SAME point on the glue
## line (the fold identifies them), so either anchor cell counts.
func aiming_at_glue(dir: Vector2i = Vector2i.ZERO) -> bool:
	if mode != Mode.SUBSPACE:
		return false
	var cand := candidate_anchor(dir)
	var here := player_cell()
	for c in [sub_fold.anchor_a, sub_fold.anchor_b]:
		if c == cand or c == here:
			return true
	return false


## Interact (F): aimed at the glue anchor, exit (unfold the subspace); aimed
## at a seam anchor, unfold that fold; otherwise commit the pending pair.
func commit_or_unfold(dir: Vector2i) -> void:
	if animating():
		return
	if aiming_at_glue(dir):
		try_exit()
		return
	var aimed := aimed_fold(dir)
	if aimed != null:
		if mode == Mode.SUBSPACE:
			unfold_sub_fold(aimed)
		else:
			unfold_world_fold(aimed)
		return
	if pending_a == null or pending_b == null:
		_show_flash("Pin both anchors first (Q and E).")
		return
	var ca = pending_cell(0)
	var cb = pending_cell(1)
	if ca == null or cb == null:
		_show_flash("An anchor lies beyond this fold.")
		return
	if not ProtoCore.anchors_valid(ca, cb):
		_show_flash("Anchors must be at least 2 tiles apart.")
		return
	var committed := do_sub_fold(ca, cb) if mode == Mode.SUBSPACE else do_fold(ca, cb)
	if committed:
		pending_a = null
		pending_b = null


# ---------------------------------------------------------------------------
# World folds
# ---------------------------------------------------------------------------

func do_fold(a1: Vector2i, a2: Vector2i) -> bool:
	var fold := Fold.create(next_fold_id, a1, a2, CS)
	var dropped := ProtoCore.capture_strip(current_pieces, fold, CS)
	if dropped.is_empty():
		_show_flash("Nothing there to fold.")
		return false

	var pre := current_pieces
	var from_piece = ProtoCore.piece_containing(pieces_by_pos, player.global_position, CS)
	var new_pieces := FoldReplay.apply_one_fold(current_pieces, fold, CS)
	var dest = null
	if from_piece != null:
		dest = ProtoCore.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	else:
		# Over void: fall back to crease arithmetic.
		var side := ProtoCore.side_of_fold(player.global_position, fold)
		if side != 0:
			dest = player.global_position + ProtoCore.fold_shift_for_side(side, fold, CS)

	if dest == null:
		# PINCH — the fold swallows the player. Applied to the world for real.
		next_fold_id += 1
		seam_segs[fold.fold_id] = ProtoCore.seam_segment(fold, dropped, CS)
		folds.append(fold)
		var p := player.global_position
		var finalize_pinch := func() -> void:
			rebuild_world()
			_enter_subspace(fold, dropped)
		_play_transition(pre, fold, true, false, p, p, finalize_pinch)
		return true

	var landed := ProtoCore.depenetrate(dest, ProtoPlayer.RADIUS, ProtoCore.wall_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Fold blocked — nowhere for you to land.")
		return false
	next_fold_id += 1
	seam_segs[fold.fold_id] = ProtoCore.seam_segment(fold, dropped, CS)
	folds.append(fold)
	var finalize_ride := func() -> void:
		rebuild_world()
		player.teleport(landed)
	_play_transition(pre, fold, true, true, player.global_position, landed, finalize_ride)
	return true


## Can this world fold be unfolded, or does a newer fold's band cross its seam?
func can_unfold_world(fold: Fold) -> bool:
	var idx := folds.find(fold)
	if idx < 0:
		return false
	var seg: PackedVector2Array = seam_segs.get(fold.fold_id, PackedVector2Array())
	if seg.size() < 2:
		return true
	for j in range(idx + 1, folds.size()):
		if ProtoCore.segment_intersects_band(seg[0], seg[1], folds[j]):
			return false
	return true


func unfold_world_fold(fold: Fold) -> void:
	var idx := folds.find(fold)
	if idx < 0:
		return
	if not can_unfold_world(fold):
		_show_flash("Blocked — a newer fold crosses this seam.")
		return
	var without: Array[Fold] = folds.duplicate()
	without.remove_at(idx)
	var new_pieces := FoldReplay.derive_pieces(base, without)

	var from_piece = ProtoCore.piece_containing(pieces_by_pos, player.global_position, CS)
	var dest = null
	if from_piece != null:
		dest = ProtoCore.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	if dest == null:
		dest = player.global_position + ProtoCore.unfold_shift(player.global_position, fold, CS)
	var landed := ProtoCore.depenetrate(dest, ProtoPlayer.RADIUS, ProtoCore.wall_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Unfold blocked — nowhere for you to land.")
		return

	var was_newest := idx == folds.size() - 1
	folds = without
	seam_segs.erase(fold.fold_id)
	var finalize := func():
		rebuild_world()
		player.teleport(landed)
	if was_newest:
		# Reverse animation is exact only for the newest fold.
		_play_transition(new_pieces, fold, false, true, player.global_position, landed, finalize)
	else:
		finalize.call()


func pop_fold() -> void:
	if folds.is_empty():
		_show_flash("Nothing to unfold.")
		return
	unfold_world_fold(folds.back())


# ---------------------------------------------------------------------------
# Subspace: interior of the newest world fold, same rules as outside
# ---------------------------------------------------------------------------

func _enter_subspace(fold: Fold, dropped: Array) -> void:
	mode = Mode.SUBSPACE
	sub_fold = fold
	sub_base_pieces = dropped
	sub_folds = []
	var tangent := Vector2(-fold.crease_normal.y, fold.crease_normal.x)
	sub_extent = ProtoCore.strip_extent(dropped, tangent)
	sub_glue_segs = ProtoCore.glue_segments(fold, dropped)

	world_geo.visible = false
	world_solid.collision_layer = 0
	sub_geo.visible = true
	_bg.color = Color("191030")
	rebuild_sub()
	_show_flash("Folded IN. F at the seam anchor (white diamond) unfolds it.")


func _clear_sub_view() -> void:
	mode = Mode.WORLD
	sub_fold = null
	sub_base_pieces = []
	sub_folds = []
	sub_pieces = []
	sub_by_pos = {}
	for child in sub_geo.get_children():
		child.queue_free()
	world_geo.visible = true
	if world_solid != null:
		world_solid.collision_layer = 1
	_bg.color = Color("14151f")


func do_sub_fold(a1: Vector2i, a2: Vector2i) -> bool:
	var fold := Fold.create(next_fold_id, a1, a2, CS)
	var dropped := ProtoCore.capture_strip(sub_pieces, fold, CS)
	if dropped.is_empty():
		_show_flash("Nothing there to fold.")
		return false

	var pre := sub_pieces
	var from_piece = ProtoCore.piece_containing(sub_by_pos, player.global_position, CS)
	var new_pieces := FoldReplay.apply_one_fold(sub_pieces, fold, CS)
	var dest = null
	if from_piece != null:
		dest = ProtoCore.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	if dest == null:
		_show_flash("You cannot fold yourself deeper — not yet.")
		return false
	var landed := ProtoCore.depenetrate(dest, ProtoPlayer.RADIUS, ProtoCore.wall_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Fold blocked — nowhere for you to land.")
		return false

	next_fold_id += 1
	seam_segs[fold.fold_id] = ProtoCore.seam_segment(fold, dropped, CS)
	sub_folds.append(fold)
	var finalize := func() -> void:
		rebuild_sub()
		player.teleport(landed)
	_play_transition(pre, fold, true, true, player.global_position, landed, finalize)
	return true


func can_unfold_sub(fold: Fold) -> bool:
	var idx := sub_folds.find(fold)
	if idx < 0:
		return false
	var seg: PackedVector2Array = seam_segs.get(fold.fold_id, PackedVector2Array())
	if seg.size() < 2:
		return true
	for j in range(idx + 1, sub_folds.size()):
		if ProtoCore.segment_intersects_band(seg[0], seg[1], sub_folds[j]):
			return false
	return true


func unfold_sub_fold(fold: Fold) -> void:
	var idx := sub_folds.find(fold)
	if idx < 0:
		return
	if not can_unfold_sub(fold):
		_show_flash("Blocked — a newer fold crosses this seam.")
		return
	var without: Array[Fold] = sub_folds.duplicate()
	without.remove_at(idx)
	var new_pieces: Array = sub_base_pieces.duplicate()
	for f in without:
		new_pieces = FoldReplay.apply_one_fold(new_pieces, f, CS)

	var from_piece = ProtoCore.piece_containing(sub_by_pos, player.global_position, CS)
	var dest = null
	if from_piece != null:
		dest = ProtoCore.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	if dest == null:
		dest = player.global_position + ProtoCore.unfold_shift(player.global_position, fold, CS)
	var landed := ProtoCore.depenetrate(dest, ProtoPlayer.RADIUS, ProtoCore.wall_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Unfold blocked — nowhere for you to land.")
		return

	var was_newest := idx == sub_folds.size() - 1
	sub_folds = without
	seam_segs.erase(fold.fold_id)
	var finalize := func():
		rebuild_sub()
		player.teleport(landed)
	if was_newest:
		_play_transition(new_pieces, fold, false, true, player.global_position, landed, finalize)
	else:
		finalize.call()


## Does an interior fold's band cross the glue (the outer fold's seam as seen
## from inside)? Folds PARALLEL to the glue never do; crossing folds must be
## unfolded before the subspace can be exited — the outer fold is not the
## newest fold affecting its own seam anymore.
func exit_blocker() -> Fold:
	for fold in sub_folds:
		for seg in sub_glue_segs:
			if ProtoCore.segment_intersects_band(seg[0], seg[1], fold):
				return fold
	return null


## Exit = unfold the outer fold from inside. Interior folds persist: they
## become world folds applied after the remaining ones (same frame, so
## geometry and every anchor land exactly where the interior showed them).
func try_exit() -> void:
	if mode != Mode.SUBSPACE or animating():
		return
	if exit_blocker() != null:
		_show_flash("Blocked — an inner fold crosses the outer seam. Unfold it first.")
		return
	var outer := sub_fold
	var idx := folds.find(outer)
	var new_folds: Array[Fold] = folds.duplicate()
	if idx >= 0:
		new_folds.remove_at(idx)
	for f in sub_folds:
		new_folds.append(f)
	var new_pieces := FoldReplay.derive_pieces(base, new_folds)

	var from_piece = ProtoCore.piece_containing(sub_by_pos, player.global_position, CS)
	var dest = player.global_position
	if from_piece != null:
		var mapped = ProtoCore.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
		if mapped != null:
			dest = mapped
	var landed := ProtoCore.depenetrate(dest, ProtoPlayer.RADIUS, ProtoCore.wall_polys_of(new_pieces))
	if landed == Vector2.INF:
		landed = Vector2(dest)

	folds = new_folds
	seam_segs.erase(outer.fold_id)
	var kept_subs: Array[Fold] = sub_folds.duplicate()
	_clear_sub_view()
	var p := player.global_position
	var finalize := func() -> void:
		rebuild_world()
		player.teleport(landed)
		if kept_subs.is_empty():
			_show_flash("Unfolded — you emerge where you walked to.")
		else:
			_show_flash("Unfolded — your inner folds came out with you.")
	_play_transition(new_pieces, outer, false, true, p, landed, finalize)


# ---------------------------------------------------------------------------
# Fold / unfold animation (task 8)
# ---------------------------------------------------------------------------
# Fragments of the PRE-state are split by the fold's creases: flaps translate
# toward the meeting line, the strip collapses onto it (or expands from it,
# reversed). The player rides linearly between its known start/end positions.
# State math happens BEFORE the animation; visuals rebuild in `finalize`.

func _play_transition(pre_pieces: Array, fold: Fold, forward: bool, collapse_strip: bool,
		p_from: Vector2, p_to: Vector2, finalize: Callable) -> void:
	if not anim_enabled:
		finalize.call()
		return
	var layer := Node2D.new()
	layer.z_index = 30
	add_child(layer)
	var frags: Array = []
	var shift_a := fold.shift_a_px(CS)
	var shift_b := fold.shift_b_px(CS)
	for piece in pre_pieces:
		var res := CollisionCore.fold_polygons([piece.polygon], fold, CS)
		var color: Color = TYPE_COLORS.get(piece.type, Color.MAGENTA)
		if mode == Mode.SUBSPACE and piece.type != BaseTile.TYPE_EMPTY:
			color = color.lerp(SUB_TINT, 0.35)
		for poly in res["a"]:
			frags.append(_make_frag(layer, CollisionCore.shift(poly, -shift_a), color, "a"))
		for poly in res["b"]:
			frags.append(_make_frag(layer, CollisionCore.shift(poly, -shift_b), color, "b"))
		for poly in res["dropped"]:
			frags.append(_make_frag(layer, poly, color, "strip"))
	world_geo.visible = false
	sub_geo.visible = false
	player.frozen = true
	_anim = {
		"layer": layer, "frags": frags, "fold": fold, "forward": forward,
		"collapse": collapse_strip, "progress": 0.0,
		"p_from": p_from, "p_to": p_to, "finalize": finalize,
	}
	_apply_anim_frame()


func _make_frag(layer: Node2D, poly: PackedVector2Array, color: Color, kind: String) -> Dictionary:
	var node := Polygon2D.new()
	node.polygon = poly
	node.color = color
	layer.add_child(node)
	return {"node": node, "base": poly, "kind": kind}


func _process(delta: float) -> void:
	if _anim.is_empty():
		return
	_anim["progress"] = minf(_anim["progress"] + delta / ANIM_TIME, 1.0)
	_apply_anim_frame()
	if _anim["progress"] >= 1.0:
		var layer: Node2D = _anim["layer"]
		var finalize: Callable = _anim["finalize"]
		_anim = {}
		layer.queue_free()
		player.frozen = false
		world_geo.visible = mode == Mode.WORLD
		sub_geo.visible = mode == Mode.SUBSPACE
		finalize.call()


func _apply_anim_frame() -> void:
	var p: float = _anim["progress"]
	var eased := p * p * (3.0 - 2.0 * p)
	var t := eased if _anim["forward"] else 1.0 - eased
	var fold: Fold = _anim["fold"]
	var n := fold.crease_normal
	var meet_d := fold.shift_a_px(CS).dot(n)
	for frag in _anim["frags"]:
		match frag["kind"]:
			"a":
				frag["node"].position = fold.shift_a_px(CS) * t
			"b":
				frag["node"].position = fold.shift_b_px(CS) * t
			"strip":
				if _anim["collapse"]:
					var basep: PackedVector2Array = frag["base"]
					var out := PackedVector2Array()
					for v in basep:
						var d := (Vector2(v) - fold.crease_point1).dot(n)
						out.append(Vector2(v) + n * ((meet_d - d) * t))
					frag["node"].polygon = out
	player.global_position = Vector2(_anim["p_from"]).lerp(Vector2(_anim["p_to"]), eased)


# ---------------------------------------------------------------------------
# Per-frame world logic
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left == 0.0 and _flash != null:
		_flash.visible = false
	_update_status()
	if animating():
		return

	if mode == Mode.SUBSPACE:
		_subspace_wrap_and_turnback()
	else:
		_check_goal()
		if player.global_position.y > (base.grid_size.y + 6) * CS:
			player.teleport(_spawn, false)
			_show_flash("You fell out of the world — respawned.")


func _subspace_wrap_and_turnback() -> void:
	var n := sub_fold.crease_normal
	var gap := sub_fold.gap_distance()
	var c1 := sub_fold.crease_point1.dot(n)
	var proj := player.global_position.dot(n)
	if proj < c1:
		player.global_position += n * gap
		player.snap_camera()
	elif proj >= c1 + gap:
		player.global_position -= n * gap
		player.snap_camera()

	# Falling out of the strip's tangential extent no longer force-exits (exit
	# can be blocked by crossing folds): the fold turns you back to its anchor.
	var tangent := Vector2(-n.y, n.x)
	var tproj := player.global_position.dot(tangent)
	if tproj < sub_extent["min"] - 4.0 * CS or tproj > sub_extent["max"] + 4.0 * CS:
		var back := sub_fold.crease_point1 + n * (gap * 0.5)
		var landed := ProtoCore.depenetrate(back, ProtoPlayer.RADIUS, sub_wall_polys)
		player.teleport(back if landed == Vector2.INF else landed, false)
		player.snap_camera()
		_show_flash("The fold turns back on itself here.")


func _check_goal() -> void:
	var touching := false
	for poly in goal_polys:
		if ProtoCore.circle_overlaps_polygon(player.global_position, ProtoPlayer.RADIUS, poly):
			touching = true
			break
	if touching and not _on_goal:
		_show_flash("★ GOAL reached! ★")
	_on_goal = touching


func _reset() -> void:
	if not _anim.is_empty():
		var layer: Node2D = _anim["layer"]
		layer.queue_free()
		_anim = {}
		player.frozen = false
	_clear_sub_view()
	folds.clear()
	seam_segs.clear()
	pending_a = null
	pending_b = null
	rebuild_world()
	player.teleport(_spawn, false)
	_show_flash("Reset.")


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	_bg = ColorRect.new()
	_bg.color = Color("14151f")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Controls default to MOUSE_FILTER_STOP; a full-screen rect would eat every
	# click before _unhandled_input sees it. HUD must never take the mouse.
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(_bg)

	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	var help := Label.new()
	help.text = "Move: A/D or arrows   Jump: Space\n" \
		+ "Point: hold Up/W or Down/S — otherwise you point where you face\n" \
		+ "Q / E: pin anchor 1 / anchor 2 on the cell you point at\n" \
		+ "F: commit the fold — or, aimed at a seam anchor, unfold that fold\n" \
		+ "   (inside a fold, the white diamond on the glue is its seam anchor)\n" \
		+ "Esc: clear anchors   U: unfold newest / exit fold   R: reset\n" \
		+ "If the red band covers YOU at commit, you get folded in.\n" \
		+ "Folding inside a fold works — crossing folds lock the exit."
	help.position = Vector2(12, 8)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	hud.add_child(help)

	_status = Label.new()
	_status.position = Vector2(12, 168)
	_status.add_theme_color_override("font_color", Color("59e0d0"))
	hud.add_child(_status)

	_flash = Label.new()
	_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash.position = Vector2(340, 130)
	_flash.add_theme_font_size_override("font_size", 22)
	_flash.add_theme_color_override("font_color", Color("ffd27f"))
	_flash.visible = false
	hud.add_child(_flash)


func _update_status() -> void:
	if _status == null:
		return
	if mode == Mode.WORLD:
		_status.text = "Folds: %d   Mode: WORLD" % folds.size()
	else:
		_status.text = "Folds: %d (+%d inside)   Mode: INSIDE FOLD" % [folds.size(), sub_folds.size()]


func _show_flash(text: String) -> void:
	if text.is_empty():
		return
	_flash.text = text
	_flash.visible = true
	_flash_left = 2.5
