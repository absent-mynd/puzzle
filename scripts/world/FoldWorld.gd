extends Node2D

## FoldWorld
##
## The game. The fold kernel (BaseGrid / Fold / FoldReplay / CollisionCore /
## BaseFrame) drives a side-view world with gravity and a free-moving player.
##
## Structure:
##   - REGIONS: each region is its own sheet — a BaseGrid + persistent fold
##     list + per-fold interior folds. Fold state survives leaving.
##   - CONTEXT STACK: the player is in a region, and optionally inside a
##     stack of folds (subspaces). Each level derives purely: the level's
##     base pieces are the parent level's strip content of the entered fold,
##     and its fold list is that fold's persistent interiors.
##   - DOORS are warp POINTS at base-tile centers: they ride folds with the
##     tile, and traversal resolves the partner point RECURSIVELY — region
##     world first, then fold strips, then interiors — so a folded-away door
##     delivers you INSIDE that fold's subspace, and a door inside a strip
##     leads out to wherever its partner is. A point exactly on a cut (door
##     split down the middle) is DORMANT until the halves rejoin. Traversal
##     is auto-on-overlap, edge-triggered, refused if the far side is
##     dormant or the landing is blocked ("something folded over the door").
##   - Exiting a subspace by its glue anchor UNFOLDS it (interiors splice
##     into the parent at its index); walking out through a door leaves the
##     fold folded, interior state and all. Unfold blocking is uniform:
##     newer folds crossing a seam block it, interior folds crossing a glue
##     block the outer fold from either side.
##
## Known limits: no nested pinch (you cannot fold yourself deeper while inside),
## fold extent is infinite-crease (a fold here guts a structure over there — the
## live design argument for barrier-scoped folds), and unfold animation plays only
## for newest-fold unfolds at world level.

enum Mode { WORLD, SUBSPACE }

const WORLD_PATH := "res://worlds/overworld.json"
const CS := WorldCore.CELL
## Anchors are pinned at arm's length: the cell immediately in the pointed
## direction. What you can fold is exactly what you can stand next to.
const ANCHOR_REACH := 1
const ANIM_TIME := 0.24
const TYPE_COLORS := {
	TileTypes.EMPTY: Color(0.13, 0.14, 0.20),   # faint: the "paper" exists
	TileTypes.WALL: Color(0.55, 0.60, 0.70),
	TileTypes.WATER: Color(0.25, 0.45, 0.75),
	TileTypes.GOAL: Color(0.91, 0.76, 0.35),
	TileTypes.TRIGGER_FOLD: Color(0.85, 0.45, 0.75),
	TileTypes.PIN: Color(0.90, 0.30, 0.28),             # fold-proof: reads as "solid fact"
	TileTypes.UNANCHORABLE_FLOOR: Color(0.20, 0.22, 0.26),
	TileTypes.UNANCHORABLE_WALL: Color(0.42, 0.44, 0.50),
}
const SUB_TINT := Color(0.72, 0.62, 0.95)  # subspace pieces shift hue

## The authored world (regions, doors, pre-placed folds).
var world_data: WorldData

# --- Regions ---
## region id -> {"base", "folds", "seam_segs", "interiors", "spawn"}
var regions: Dictionary = {}
var region_id := ""
## Doors: id -> {"region", "cell", "bid", "bp", "pair"}. Points, not tiles.
var doors: Dictionary = {}
var _door_latch: Dictionary = {}

# --- Current region working state (views into regions[region_id]) ---
var base: BaseGrid
var folds: Array[Fold] = []
var seam_segs: Dictionary = {}
## fold_id -> Array[Fold]: a fold's interior folds, persistent while it lives.
var interiors: Dictionary = {}
var _spawn := Vector2.ZERO

var next_fold_id := 0
## Triggered folds draw ids from a reserved high range so they never collide with
## player-fold ids (which count up from 0).
var _next_trigger_id := TriggerResolver.TRIGGER_FOLD_ID_BASE
## Base tile the player last fired a trigger check against — triggers are edge-fired
## on entering a tile, not re-fired every frame you stand on it.
var _trigger_latch := -1
var mode: Mode = Mode.WORLD
## Path of entered folds (outermost first). Empty = region world.
var context: Array[Fold] = []

## Pending anchors: null or {"bid": int, "bp": Vector2} — a base-frame point.
## Frame-independent: rides folds, survives subspace exit; inert (unresolvable)
## outside its region.
var pending_a = null
var pending_b = null

var current_pieces: Array[FoldedPiece] = []
var pieces_by_pos: Dictionary = {}
var wall_polys: Array = []
var goal_polys: Array = []
var _on_goal := false

# --- Subspace view state (derived from `context` by _apply_context) ---
var sub_fold: Fold = null
var sub_base_pieces: Array = []
var sub_pieces: Array = []
var sub_by_pos: Dictionary = {}
var sub_wall_polys: Array = []
var sub_goal_polys: Array = []
var sub_extent: Dictionary = {}
var sub_glue_segs: Array = []
var sub_copies := 1

# --- Animation ---
var anim_enabled := true
var _anim: Dictionary = {}

var player: PlayerBody
var world_geo: Node2D
var world_solid: StaticBody2D
var sub_geo: Node2D
var overlay: WorldOverlay
var _bg: ColorRect
var _status: Label
var _flash: Label
var _flash_left := 0.0


func _ready() -> void:
	world_geo = Node2D.new()
	add_child(world_geo)
	sub_geo = Node2D.new()
	add_child(sub_geo)

	overlay = WorldOverlay.new()
	overlay.world = self
	overlay.z_index = 50
	add_child(overlay)

	player = PlayerBody.new()
	player.z_index = 40
	add_child(player)

	_build_hud()
	_setup_all()


func _setup_all() -> void:
	next_fold_id = 0
	regions = {}
	_door_latch = {}
	pending_a = null
	pending_b = null

	world_data = WorldData.load_from(WORLD_PATH)
	if world_data == null:
		push_error("FoldWorld: could not load %s" % WORLD_PATH)
		return

	# Each region is its own sheet: a BaseGrid plus its persistent fold state. A region's
	# authored folds are applied here, before the player spawns — a pre-placed fold ships
	# the region already folded, with content sealed inside that unfolding (or a door
	# whose far side resolves in there) reveals.
	for id in world_data.regions:
		var rbase := world_data.build_base(id)
		var rfolds: Array[Fold] = []
		var rsegs: Dictionary = {}
		var pieces: Array = FoldReplay.identity_pieces(rbase)
		for pair in world_data.fold_pairs(id):
			var f := Fold.create(_take_fold_id(), pair[0], pair[1], CS)
			var dropped := WorldCore.capture_strip(pieces, f, CS)
			rsegs[f.fold_id] = WorldCore.seam_segment(f, dropped, CS)
			rfolds.append(f)
			pieces = FoldReplay.apply_one_fold(pieces, f, CS)
		regions[id] = {"base": rbase, "folds": rfolds, "seam_segs": rsegs,
			"interiors": {}, "spawn": world_data.spawn_px(id)}

	# Doors are warp POINTS at base-tile centers: they ride folds with their tile, so a
	# door's current location is resolved from its base identity, never stored.
	doors = {}
	for id in world_data.doors:
		var src: Dictionary = world_data.doors[id]
		var d: Dictionary = src.duplicate()
		var b: BaseGrid = regions[d["region"]]["base"]
		var tile := b.tile_at(d["cell"])
		if tile == null:
			push_error("FoldWorld: door %s sits outside region %s" % [id, d["region"]])
			continue
		d["bid"] = tile.base_id
		d["bp"] = (Vector2(d["cell"]) + Vector2(0.5, 0.5)) * CS
		doors[id] = d

	_load_region(world_data.start_region)
	context.clear()
	_apply_context()
	player.teleport(_spawn, false)
	player.snap_camera()


func _take_fold_id() -> int:
	next_fold_id += 1
	return next_fold_id - 1


func _load_region(id: String) -> void:
	region_id = id
	var r: Dictionary = regions[id]
	base = r["base"]
	folds = r["folds"]
	seam_segs = r["seam_segs"]
	interiors = r["interiors"]
	_spawn = r["spawn"]


# ---------------------------------------------------------------------------
# Derived state -> visuals + colliders
# ---------------------------------------------------------------------------

func rebuild_world() -> void:
	current_pieces = FoldReplay.derive_pieces(base, folds)
	pieces_by_pos = BaseFrame.index_by_pos(current_pieces)
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
		# Solidity comes from the registry, not a type check: a new blocking tile
		# collides correctly without touching this loop.
		if not TileTypes.is_walkable(piece.type):
			wall_polys.append(piece.polygon)
			var col := CollisionPolygon2D.new()
			col.polygon = piece.polygon
			world_solid.add_child(col)
		elif piece.type == TileTypes.GOAL:
			goal_polys.append(piece.polygon)


func rebuild_sub() -> void:
	sub_pieces = sub_base_pieces.duplicate()
	for fold in level_folds():
		sub_pieces = FoldReplay.apply_one_fold(sub_pieces, fold, CS)
	sub_by_pos = BaseFrame.index_by_pos(sub_pieces)
	sub_wall_polys = WorldCore.solid_polys_of(sub_pieces)
	sub_goal_polys = WorldCore.polys_of_type(sub_pieces, TileTypes.GOAL)

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
			vis.color = c.lerp(SUB_TINT, 0.35) if piece.type != TileTypes.EMPTY else c
			copy.add_child(vis)
			if not TileTypes.is_walkable(piece.type) and solid != null:
				var col := CollisionPolygon2D.new()
				col.polygon = piece.polygon
				solid.add_child(col)


## The fold list of the CURRENT level: the region's folds, or the entered
## fold's persistent interiors.
func level_folds() -> Array:
	if context.is_empty():
		return folds
	return _ensure_interiors(context.back().fold_id)


func _ensure_interiors(fid: int) -> Array:
	if not interiors.has(fid):
		var arr: Array[Fold] = []
		interiors[fid] = arr
	return interiors[fid]


## Base (identity) pieces of the CURRENT level: region identity, or the
## entered fold's strip content.
func _level_base_pieces() -> Array:
	if context.is_empty():
		return FoldReplay.identity_pieces(base)
	return sub_base_pieces


## Derive the state of a level addressed by a fold path (pure, from region
## working state). Returns {"base_pieces", "level_folds", "pieces"}.
func _compute_level(path: Array) -> Dictionary:
	var lvl_base: Array = FoldReplay.identity_pieces(base)
	var lvl_folds: Array = folds
	for F in path:
		var i: int = lvl_folds.find(F)
		var prefix: Array = lvl_base.duplicate()
		for k in range(i):
			prefix = FoldReplay.apply_one_fold(prefix, lvl_folds[k], CS)
		lvl_base = WorldCore.capture_strip(prefix, F, CS)
		lvl_folds = _ensure_interiors(F.fold_id)
	var pieces: Array = lvl_base.duplicate()
	for f in lvl_folds:
		pieces = FoldReplay.apply_one_fold(pieces, f, CS)
	return {"base_pieces": lvl_base, "level_folds": lvl_folds, "pieces": pieces}


## Make the view match `context`: world level or the entered fold's interior.
func _apply_context() -> void:
	if context.is_empty():
		mode = Mode.WORLD
		sub_fold = null
		sub_base_pieces = []
		sub_pieces = []
		sub_by_pos = {}
		for child in sub_geo.get_children():
			child.queue_free()
		world_geo.visible = true
		_bg.color = Color("14151f")
		rebuild_world()
		return
	mode = Mode.SUBSPACE
	sub_fold = context.back()
	var lvl := _compute_level(context)
	sub_base_pieces = lvl["base_pieces"]
	var tangent := Vector2(-sub_fold.crease_normal.y, sub_fold.crease_normal.x)
	sub_extent = WorldCore.strip_extent(sub_base_pieces, tangent)
	sub_glue_segs = WorldCore.glue_segments(sub_fold, sub_base_pieces)
	world_geo.visible = false
	sub_geo.visible = true
	_bg.color = Color("191030")
	rebuild_world()   # keeps world colliders synced (and inert)
	rebuild_sub()


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


func player_cell() -> Vector2i:
	return Vector2i((player.global_position / CS).floor())


func candidate_anchor(dir: Vector2i = Vector2i.ZERO) -> Vector2i:
	var d := dir if dir != Vector2i.ZERO else Vector2i(player.point_dir())
	return player_cell() + d * ANCHOR_REACH


## The current cell of a pending anchor in THIS frame, or null if unset or if
## its base tile has no fragment here (other region, or folded elsewhere).
func pending_cell(slot: int):
	var p = pending_a if slot == 0 else pending_b
	if p == null:
		return null
	var wp = BaseFrame.world_point_from_base(_frame_pieces(), p["bid"], p["bp"])
	if wp == null:
		return null
	return Vector2i((Vector2(wp) / CS).floor())


func place_pending(slot: int, dir: Vector2i) -> void:
	if animating():
		return
	var cand := candidate_anchor(dir)
	var center := (Vector2(cand) + Vector2(0.5, 0.5)) * CS
	var piece = BaseFrame.piece_containing(_frame_index(), center, CS)
	if piece == null:
		_show_flash("Nothing there to anchor to.")
		return
	if not WorldCore.can_anchor_at(_frame_index(), cand):
		_show_flash("Nothing to grip there.")
		return
	var entry := {"bid": piece.base_id, "bp": center - piece.src_offset}
	if slot == 0:
		pending_a = null if pending_cell(0) != null and pending_cell(0) == cand else entry
	else:
		pending_b = null if pending_cell(1) != null and pending_cell(1) == cand else entry


func aimed_fold(dir: Vector2i = Vector2i.ZERO) -> Fold:
	var cand := candidate_anchor(dir)
	var here := player_cell()
	for fold in level_folds():
		if fold.meeting_pos == cand or fold.meeting_pos == here:
			return fold
	return null


## Inside a subspace, is the player aiming at (or standing on) the outer
## fold's anchor point? Both outer anchors are the SAME point on the glue.
func aiming_at_glue(dir: Vector2i = Vector2i.ZERO) -> bool:
	if mode != Mode.SUBSPACE:
		return false
	var cand := candidate_anchor(dir)
	var here := player_cell()
	for c in [sub_fold.anchor_a, sub_fold.anchor_b]:
		if c == cand or c == here:
			return true
	return false


func commit_or_unfold(dir: Vector2i) -> void:
	if animating():
		return
	if aiming_at_glue(dir):
		try_exit()
		return
	var aimed := aimed_fold(dir)
	if aimed != null:
		unfold_level_fold(aimed)
		return
	if pending_a == null or pending_b == null:
		_show_flash("Pin both anchors first (Q and E).")
		return
	var ca = pending_cell(0)
	var cb = pending_cell(1)
	if ca == null or cb == null:
		_show_flash("An anchor lies beyond this fold.")
		return
	if not WorldCore.anchors_valid(ca, cb):
		_show_flash("Anchors must be at least 2 tiles apart.")
		return
	var committed := do_sub_fold(ca, cb) if mode == Mode.SUBSPACE else do_fold(ca, cb)
	if committed:
		pending_a = null
		pending_b = null


# ---------------------------------------------------------------------------
# Folding
# ---------------------------------------------------------------------------

func do_fold(a1: Vector2i, a2: Vector2i) -> bool:
	var fold := Fold.create(next_fold_id, a1, a2, CS)
	var dropped := WorldCore.capture_strip(current_pieces, fold, CS)
	if dropped.is_empty():
		_show_flash("Nothing there to fold.")
		return false
	if WorldCore.fold_blocked_by_tile(current_pieces, fold, CS):
		_show_flash("Something in that span refuses to fold.")
		return false

	var pre := current_pieces
	var from_piece = BaseFrame.piece_containing(pieces_by_pos, player.global_position, CS)
	var new_pieces := FoldReplay.apply_one_fold(current_pieces, fold, CS)
	var dest = null
	if from_piece != null:
		dest = BaseFrame.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	else:
		# Over void: fall back to crease arithmetic.
		var side := WorldCore.side_of_fold(player.global_position, fold)
		if side != 0:
			dest = player.global_position + WorldCore.fold_shift_for_side(side, fold, CS)

	if dest == null:
		# PINCH — the fold swallows the player. Applied to the world for real.
		next_fold_id += 1
		seam_segs[fold.fold_id] = WorldCore.seam_segment(fold, dropped, CS)
		folds.append(fold)
		var p := player.global_position
		var finalize_pinch := func() -> void:
			context.append(fold)
			_apply_context()
			_show_flash("Folded IN. F at the seam anchor (white diamond) unfolds it.")
		_play_transition(pre, fold, true, false, p, p, false, finalize_pinch)
		return true

	var landed := WorldCore.depenetrate(dest, PlayerBody.RADIUS, WorldCore.solid_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Fold blocked — nowhere for you to land.")
		return false
	next_fold_id += 1
	seam_segs[fold.fold_id] = WorldCore.seam_segment(fold, dropped, CS)
	folds.append(fold)
	var finalize_ride := func() -> void:
		rebuild_world()
		player.teleport(landed)
	_play_transition(pre, fold, true, true, player.global_position, landed, false, finalize_ride)
	return true


func do_sub_fold(a1: Vector2i, a2: Vector2i) -> bool:
	var fold := Fold.create(next_fold_id, a1, a2, CS)
	var dropped := WorldCore.capture_strip(sub_pieces, fold, CS)
	if dropped.is_empty():
		_show_flash("Nothing there to fold.")
		return false

	if WorldCore.fold_blocked_by_tile(sub_pieces, fold, CS):
		_show_flash("Something in that span refuses to fold.")
		return false

	var pre := sub_pieces
	var from_piece = BaseFrame.piece_containing(sub_by_pos, player.global_position, CS)
	var new_pieces := FoldReplay.apply_one_fold(sub_pieces, fold, CS)
	var dest = null
	if from_piece != null:
		dest = BaseFrame.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	if dest == null:
		_show_flash("You cannot fold yourself deeper — not yet.")
		return false
	var landed := WorldCore.depenetrate(dest, PlayerBody.RADIUS, WorldCore.solid_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Fold blocked — nowhere for you to land.")
		return false

	next_fold_id += 1
	seam_segs[fold.fold_id] = WorldCore.seam_segment(fold, dropped, CS)
	level_folds().append(fold)
	var finalize := func() -> void:
		rebuild_sub()
		player.teleport(landed)
	_play_transition(pre, fold, true, true, player.global_position, landed, true, finalize)
	return true


# ---------------------------------------------------------------------------
# Unfolding (uniform blocking rules at every level)
# ---------------------------------------------------------------------------

## Newer folds in the same list whose band crosses this fold's seam block it.
func can_unfold_fold(fold: Fold) -> bool:
	var list: Array = level_folds()
	var idx := list.find(fold)
	if idx < 0:
		return false
	var seg: PackedVector2Array = seam_segs.get(fold.fold_id, PackedVector2Array())
	if seg.size() < 2:
		return true
	for j in range(idx + 1, list.size()):
		if WorldCore.segment_intersects_band(seg[0], seg[1], list[j]):
			return false
	return true


## An interior fold of `fold` whose band crosses `fold`'s glue blocks
## unfolding it from EITHER side (the outer seam isn't the newest fold
## affecting itself). Returns the blocker or null.
func _interior_glue_blocker(fold: Fold, lvl_base: Array, list: Array, idx: int) -> Fold:
	var kids: Array = interiors.get(fold.fold_id, [])
	if kids.is_empty():
		return null
	var prefix: Array = lvl_base.duplicate()
	for k in range(idx):
		prefix = FoldReplay.apply_one_fold(prefix, list[k], CS)
	var strip := WorldCore.capture_strip(prefix, fold, CS)
	for seg in WorldCore.glue_segments(fold, strip):
		for kf in kids:
			if WorldCore.segment_intersects_band(seg[0], seg[1], kf):
				return kf
	return null


## Unfold a fold of the CURRENT level. Its interior folds (if any) splice
## into this level at its index — they were made in exactly this frame.
func unfold_level_fold(fold: Fold) -> void:
	var list: Array = level_folds()
	var idx := list.find(fold)
	if idx < 0:
		return
	if not can_unfold_fold(fold):
		_show_flash("Blocked — a newer fold crosses this seam.")
		return
	var lvl_base := _level_base_pieces()
	if _interior_glue_blocker(fold, lvl_base, list, idx) != null:
		_show_flash("Blocked — a fold inside it crosses its seam.")
		return

	var kids: Array = interiors.get(fold.fold_id, [])
	list.remove_at(idx)
	for k in range(kids.size()):
		list.insert(idx + k, kids[k])
	interiors.erase(fold.fold_id)
	seam_segs.erase(fold.fold_id)

	var new_pieces: Array = lvl_base.duplicate()
	for f in list:
		new_pieces = FoldReplay.apply_one_fold(new_pieces, f, CS)
	var from_piece = BaseFrame.piece_containing(_frame_index(), player.global_position, CS)
	var dest = null
	if from_piece != null:
		dest = BaseFrame.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	if dest == null:
		dest = player.global_position + WorldCore.unfold_shift(player.global_position, fold, CS)
	var landed := WorldCore.depenetrate(dest, PlayerBody.RADIUS, WorldCore.solid_polys_of(new_pieces))
	if landed == Vector2.INF:
		# Undo the splice and bail.
		for k in range(kids.size()):
			list.remove_at(idx)
		list.insert(idx, fold)
		if not kids.is_empty():
			interiors[fold.fold_id] = kids
		_show_flash("Unfold blocked — nowhere for you to land.")
		return

	var was_newest := idx == list.size() - kids.size()
	var in_sub := mode == Mode.SUBSPACE
	var finalize := func() -> void:
		if in_sub:
			rebuild_sub()
		else:
			rebuild_world()
		player.teleport(landed)
	if was_newest and kids.is_empty():
		_play_transition(new_pieces, fold, false, true,
			player.global_position, landed, in_sub, finalize)
	else:
		finalize.call()


func pop_fold() -> void:
	if folds.is_empty():
		_show_flash("Nothing to unfold.")
		return
	unfold_level_fold(folds.back())


## Interior fold crossing the glue that locks the exit, or null.
func exit_blocker() -> Fold:
	for fold in level_folds():
		for seg in sub_glue_segs:
			if WorldCore.segment_intersects_band(seg[0], seg[1], fold):
				return fold
	return null


## Exit = unfold the entered fold from inside. Interior folds splice into the
## parent level at its index; the strip (and you, and any pinned anchors)
## land exactly where the interior showed them.
func try_exit() -> void:
	if mode != Mode.SUBSPACE or animating():
		return
	if exit_blocker() != null:
		_show_flash("Blocked — an inner fold crosses the outer seam. Unfold it first.")
		return
	var outer := sub_fold
	var parent_path := context.slice(0, context.size() - 1)
	var plvl := _compute_level(parent_path)
	var plist: Array = plvl["level_folds"]
	var idx := plist.find(outer)
	if idx < 0:
		return
	# The parent's newer folds can cross this fold's seam (door-entered
	# mid-list folds): same blocking rule as everywhere.
	var seg: PackedVector2Array = seam_segs.get(outer.fold_id, PackedVector2Array())
	if seg.size() >= 2:
		for j in range(idx + 1, plist.size()):
			if WorldCore.segment_intersects_band(seg[0], seg[1], plist[j]):
				_show_flash("Blocked — a newer fold outside crosses this seam.")
				return

	var kids: Array = level_folds()
	plist.remove_at(idx)
	for k in range(kids.size()):
		plist.insert(idx + k, kids[k])
	interiors.erase(outer.fold_id)
	seam_segs.erase(outer.fold_id)

	var new_plvl := _compute_level(parent_path)
	var new_pieces: Array = new_plvl["pieces"]
	var from_piece = BaseFrame.piece_containing(sub_by_pos, player.global_position, CS)
	var dest = player.global_position
	if from_piece != null:
		var mapped = BaseFrame.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
		if mapped != null:
			dest = mapped
	var landed := WorldCore.depenetrate(dest, PlayerBody.RADIUS, WorldCore.solid_polys_of(new_pieces))
	if landed == Vector2.INF:
		landed = Vector2(dest)

	context = parent_path
	var kept := not kids.is_empty()
	var to_world := context.is_empty()
	var finalize := func() -> void:
		_apply_context()
		player.teleport(landed)
		if kept:
			_show_flash("Unfolded — your inner folds came out with you.")
		else:
			_show_flash("Unfolded — you emerge where you walked to.")
	if to_world and idx == plist.size() - kids.size() and kids.is_empty():
		_bg.color = Color("14151f")
		_play_transition(new_pieces, outer, false, true,
			player.global_position, landed, false, finalize)
	else:
		finalize.call()


# ---------------------------------------------------------------------------
# Doors: warp points at base-tile centers, resolved recursively
# ---------------------------------------------------------------------------

## Resolve a base point inside one level; recurse into whichever fold's strip
## holds it. Returns {"path", "pos", "pieces"} or null (dormant: the point is
## on a cut, or nowhere).
func _resolve_in(base_pieces: Array, list: Array, ints: Dictionary,
		bid: int, bp: Vector2, path: Array) -> Variant:
	var pieces: Array = base_pieces.duplicate()
	for f in list:
		pieces = FoldReplay.apply_one_fold(pieces, f, CS)
	var wp = BaseFrame.resolve_base_point(pieces, bid, bp)
	if wp != null:
		return {"path": path, "pos": Vector2(wp), "pieces": pieces}
	var prefix: Array = base_pieces.duplicate()
	for f in list:
		var strip := WorldCore.capture_strip(prefix, f, CS)
		if BaseFrame.resolve_base_point(strip, bid, bp) != null:
			var inner: Array = ints.get(f.fold_id, [])
			return _resolve_in(strip, inner, ints, bid, bp, path + [f])
		prefix = FoldReplay.apply_one_fold(prefix, f, CS)
	return null


## Full resolution of a door's point in its own region (which may not be the
## current one). Pure over region storage.
func resolve_door(id: String) -> Variant:
	var d: Dictionary = doors[id]
	var r: Dictionary = regions[d["region"]]
	return _resolve_in(FoldReplay.identity_pieces(r["base"]), r["folds"],
		r["interiors"], d["bid"], d["bp"], [])


## A door's current position in the CURRENT view level, or null (not here /
## dormant here). Used for overlap checks and rendering.
func door_point_here(id: String) -> Variant:
	var d: Dictionary = doors[id]
	if d["region"] != region_id:
		return null
	return BaseFrame.resolve_base_point(_frame_pieces(), d["bid"], d["bp"])


func _check_doors() -> void:
	for id in doors:
		var wp = door_point_here(id)
		var over := false
		if wp != null:
			over = player.global_position.distance_to(Vector2(wp)) < PlayerBody.RADIUS
		if over and not _door_latch.get(id, false):
			_door_latch[id] = true
			_traverse(id)
			return
		_door_latch[id] = over


func _traverse(id: String) -> void:
	var pair_id: String = doors[id]["pair"]
	var res = resolve_door(pair_id)
	if res == null:
		_show_flash("The door is dormant — its far side is split.")
		return
	var landed := WorldCore.depenetrate(
		res["pos"], PlayerBody.RADIUS, WorldCore.solid_polys_of(res["pieces"]))
	if landed == Vector2.INF:
		_show_flash("The way is blocked — something is folded over the door.")
		return
	_door_latch[pair_id] = true
	var into_fold: bool = not res["path"].is_empty()
	var rid: String = doors[pair_id]["region"]
	if rid != region_id:
		_load_region(rid)
	context.clear()
	for f in res["path"]:
		context.append(f)
	_apply_context()
	player.teleport(landed)
	player.snap_camera()
	_show_flash("You emerge INSIDE a fold." if into_fold else "You step through the door.")


# ---------------------------------------------------------------------------
# Fold / unfold animation
# ---------------------------------------------------------------------------
# Fragments of the PRE-state are split by the fold's creases: flaps translate
# toward the meeting line, the strip collapses onto it (or expands from it,
# reversed). The player rides linearly between its known start/end positions.
# State math happens BEFORE the animation; visuals rebuild in `finalize`.

func _play_transition(pre_pieces: Array, fold: Fold, forward: bool, collapse_strip: bool,
		p_from: Vector2, p_to: Vector2, sub_tint: bool, finalize: Callable) -> void:
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
		if sub_tint and piece.type != BaseTile.TYPE_EMPTY:
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
		if player.global_position.y > (base.grid_size.y + 6) * CS:
			player.teleport(_spawn, false)
			_show_flash("You fell out of the world — respawned.")
	_check_goal()
	_check_triggers()
	_check_doors()


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

	# Falling out of the strip's tangential extent doesn't force-exit (exit
	# can be blocked by crossing folds): the fold turns you back to its anchor.
	var tangent := Vector2(-n.y, n.x)
	var tproj := player.global_position.dot(tangent)
	if tproj < sub_extent["min"] - 4.0 * CS or tproj > sub_extent["max"] + 4.0 * CS:
		var back := sub_fold.crease_point1 + n * (gap * 0.5)
		var landed := WorldCore.depenetrate(back, PlayerBody.RADIUS, sub_wall_polys)
		player.teleport(back if landed == Vector2.INF else landed, false)
		player.snap_camera()
		_show_flash("The fold turns back on itself here.")


## Fold-on-enter tiles. The cascade is resolved by TriggerResolver against the region's
## fold list, then the settled result is adopted: the player transports with the folds
## that carried them, exactly as if they had folded by hand.
##
## Only fires at world level — a trigger inside a subspace would have to splice folds
## into an interior list mid-cascade, which the resolver does not model yet.
func _check_triggers() -> void:
	if mode != Mode.WORLD or base == null:
		return
	var here = BaseFrame.piece_containing(pieces_by_pos, player.global_position, CS)
	if here == null:
		_trigger_latch = -1
		return
	# Edge-trigger on the tile: re-entering is what fires, not standing still.
	if here.base_id == _trigger_latch:
		return
	_trigger_latch = here.base_id
	var tile := base.tile_by_id(here.base_id)
	if tile == null or TileTypes.on_enter_kind(tile.type) != "fold":
		return

	var settled := TriggerResolver.resolve(base, {
		"folds": folds,
		"pieces": current_pieces,
		"player_pos": player.global_position,
		"next_trigger_id": _next_trigger_id,
	})
	var new_folds: Array = settled["folds"]
	if new_folds.size() == folds.size():
		return  # nothing fired (channel already taken, anchors unresolvable, ...)

	for f in new_folds:
		if not seam_segs.has(f.fold_id):
			seam_segs[f.fold_id] = WorldCore.seam_segment(
				f, WorldCore.capture_strip(current_pieces, f, CS), CS)
	folds.assign(new_folds)
	regions[region_id]["folds"] = folds
	_next_trigger_id = settled["next_trigger_id"]
	rebuild_world()
	var landed := WorldCore.depenetrate(
		settled["player_pos"], PlayerBody.RADIUS, WorldCore.solid_polys_of(current_pieces))
	player.teleport(settled["player_pos"] if landed == Vector2.INF else landed)
	_show_flash("The ground answers — space folds around you.")


func _check_goal() -> void:
	var polys: Array = sub_goal_polys if mode == Mode.SUBSPACE else goal_polys
	var touching := false
	for poly in polys:
		if WorldCore.circle_overlaps_polygon(player.global_position, PlayerBody.RADIUS, poly):
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
	context.clear()
	_setup_all()
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
		+ "Green rings are DOORS — walk into one to warp. A folded-away door\n" \
		+ "leads INSIDE the fold. Doors exit folds without unfolding them."
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
		_status.text = "Region: %s   Folds: %d   Mode: WORLD" % [region_id, folds.size()]
	else:
		_status.text = "Region: %s   Folds: %d   Mode: INSIDE FOLD x%d (%d inner)" \
			% [region_id, folds.size(), context.size(), level_folds().size()]


func _show_flash(text: String) -> void:
	if text.is_empty():
		return
	_flash.text = text
	_flash.visible = true
	_flash_left = 2.5
