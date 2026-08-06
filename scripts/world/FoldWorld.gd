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
##   - ANCHORS ARE A CARRIED, CONSERVED RESOURCE (`AnchorStock`). A standing
##     fold is holding two of yours, so the budget is how many folds may stand
##     at once, not how many you may ever make; unfolding refunds them because
##     the fold leaves the list. Anchor caches raise the ceiling permanently.
##   - LIGHTS are occupants like doors: base identity + a point in the tile,
##     resolved through BaseFrame against whatever is on screen. Fold a lamp
##     away and it leaves the overworld and lights the fold's interior
##     instead (see LightSource). Fold something else and it rides the flap.
##
## ONE KEY drives all of it. Tap = push anchors in (pin, pin, commit); hold =
## pull them back out (retrieve a pending anchor, unfold the fold you point at,
## or exit a subspace by its glue anchor). There is no remote unfold: to get the
## anchors out of a fold you must go back to its seam.
##
## Rendering is a PIXEL pass: the world draws into a low-resolution SubViewport
## (see PixelArt) that is scaled up with nearest filtering, tiles are textured
## from a 16px tileset through base-space UVs (see TileAtlas), and lighting is
## quantized per art pixel (see LightRig). The HUD stays outside the pixel
## viewport, at window resolution, so text stays legible.
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
## How long the fold key must be held before it reads as "pull back" rather than
## "push in". Long enough that a committing tap never trips it by accident.
const HOLD_TIME := 0.35
## Reach of the release burst, in world units. About a tile — the burst is a thing you
## do to the space you are standing in, not a thing you aim.
const BURST_RADIUS := 1.2 * CS
## How long the burst ring stays drawn.
const BURST_FLASH := 0.35
## How many wrap copies either side of the strip carry their lights. The subspace
## repeats forever; its lamps do not need to.
const SUB_LIGHT_COPIES := 2

## The authored world (regions, doors, pre-placed folds).
var world_data: WorldData

# --- Regions ---
## region id -> {"base", "folds", "seam_segs", "interiors", "spawn"}
var regions: Dictionary = {}
var region_id := ""
## Doors: id -> {"region", "cell", "bid", "bp", "pair"}. Points, not tiles.
var doors: Dictionary = {}
var _door_latch: Dictionary = {}
## Lights: region id -> Array[LightSource], bound to their base tiles.
var region_lights: Dictionary = {}

# --- Current region working state (views into regions[region_id]) ---
var base: BaseGrid
var folds: Array[Fold] = []
var seam_segs: Dictionary = {}
## fold_id -> Array[Fold]: a fold's interior folds, persistent while it lives.
var interiors: Dictionary = {}
## Loose hands lying in THIS region (a view into `hand_pickups`).
var loose_hands: Array = []
var _spawn := Vector2.ZERO

## Loose hands, region id -> Array[HandPickup]. Authored caches and hands that popped
## out of a burst are the SAME list and the same object — to the player they are the
## same thing, a hand on the ground — and only `_reset` reads `authored` to tell them
## apart. Lives outside `regions` so a region rebuild cannot silently drop them.
var hand_pickups: Dictionary = {}

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

## Pending anchors: null or {"bid": int, "bp": Vector2, "hand": int} — a base-frame
## point plus the KIND of hand pinned there. Frame-independent: rides folds, survives
## subspace exit; inert (unresolvable) outside its region. A pinned anchor is a hand
## that has LEFT you — it is out of its slot from the moment you place it, and comes
## back only when you pull it out again.
var pending_a = null
var pending_b = null

## The hands you are carrying: one entry per slot, a `HandTypes` id or null.
## See `AnchorStock` — this array is the whole of your possession.
var hands: Array = []

# --- Fold-key hold tracking (tap = place a hand, hold = pull one back) ---
var _hold_active := false
var _hold_fired := false
var _hold_elapsed := 0.0

## Seconds left on the burst ring the overlay draws.
var _burst_flash_left := 0.0

# --- The fuse: a completed pair commits itself ---
## Seconds left before the pinned pair folds, and what it started at (for the pulse).
## Zero total = no fuse running.
var _fuse_left := 0.0
var _fuse_total := 0.0

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
## One Polygon2D per wrap copy except the one the real body occupies — see
## `_update_player_ghosts`.
var sub_player_ghosts: Array = []

# --- Animation ---
var anim_enabled := true
var _anim: Dictionary = {}

var player: PlayerBody
var hand_orbit: HandOrbit
var world_geo: Node2D
var world_solid: StaticBody2D
var sub_geo: Node2D
var overlay: WorldOverlay
var light_rig: LightRig
## The low-resolution render target everything in the world is drawn into.
var pixel_view: SubViewport
var _atlas: Texture2D
var _bg: ColorRect
var _status: Label
var _flash: Label
var _flash_left := 0.0


func _ready() -> void:
	# Run the per-frame world logic AFTER the player has moved this step — the
	# wrap, doors and triggers should see where the body actually ended up, not
	# where it was a frame ago. Children process after their parent by default,
	# and the player is a child, so raise this node's priority past it.
	process_physics_priority = 1

	_atlas = TileAtlas.texture()
	_build_pixel_view()

	world_geo = Node2D.new()
	pixel_view.add_child(world_geo)
	sub_geo = Node2D.new()
	pixel_view.add_child(sub_geo)

	light_rig = LightRig.new()
	light_rig.cell_size = CS
	light_rig.z_index = 20
	pixel_view.add_child(light_rig)

	overlay = WorldOverlay.new()
	overlay.world = self
	overlay.z_index = 50
	pixel_view.add_child(overlay)

	hand_orbit = HandOrbit.new()
	hand_orbit.z_index = 45   # over the terrain, under nothing that matters
	pixel_view.add_child(hand_orbit)

	player = PlayerBody.new()
	player.z_index = 40
	pixel_view.add_child(player)

	_build_hud()
	_setup_all()


## The pixel pass. The world renders into a low-resolution target and a
## TextureRect scales it up with nearest filtering; the HUD is added later on its
## own CanvasLayer, outside this viewport, so it stays at window resolution.
##
## The target is RESIZED as the camera's logical zoom changes (`_size_pixel_view`)
## rather than the lens moving, which is what keeps an art pixel exactly
## `PixelArt.WORLD_PER_PIXEL` world units at every zoom. See `PixelArt`.
##
## Note this node is OUTSIDE `pixel_view`, so `get_viewport_rect()` here is still
## the window — which is what the zoom decision needs.
func _build_pixel_view() -> void:
	pixel_view = SubViewport.new()
	pixel_view.size = PixelArt.target_size(
		get_viewport_rect().size, WorldCore.ZOOM_RESTING)
	pixel_view.transparent_bg = true            # the background ColorRect shows through
	pixel_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pixel_view.snap_2d_transforms_to_pixel = true
	pixel_view.snap_2d_vertices_to_pixel = true
	pixel_view.canvas_item_default_texture_filter = \
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	pixel_view.audio_listener_enable_2d = true
	add_child(pixel_view)

	var screen := CanvasLayer.new()
	screen.layer = -5
	add_child(screen)
	var view := TextureRect.new()
	view.texture = pixel_view.get_texture()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(view)


func _setup_all() -> void:
	next_fold_id = 0
	regions = {}
	region_lights = {}
	_door_latch = {}
	pending_a = null
	pending_b = null
	hand_pickups = {}
	_cancel_fuse()

	world_data = WorldData.load_from(WORLD_PATH)
	if world_data == null:
		push_error("FoldWorld: could not load %s" % WORLD_PATH)
		return
	hands = world_data.starting_hand_slots()

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

		# Authored loose hands bind exactly as lights do — a hand on the ground has no
		# world position either, only a base identity the configuration is asked about.
		var region_hands: Array = []
		for pickup in world_data.hands_of(id):
			if pickup.bind(rbase):
				region_hands.append(pickup)
			else:
				push_error("FoldWorld: hand pickup in %s sits outside the region" % id)
		hand_pickups[id] = region_hands

		# Lights bind to base tiles exactly as doors do: from here on a light has
		# no world position, only a base identity that the current configuration
		# is asked about (see LightSource).
		var bound: Array = []
		for light in world_data.lights_of(id):
			if light.bind(rbase):
				bound.append(light)
			else:
				push_error("FoldWorld: light %s sits outside region %s" % [light.id, id])
		region_lights[id] = bound

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
	_cut_camera()


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
	loose_hands = _ensure_pickups(id)


## The loose hands in a region, creating the list on first ask.
func _ensure_pickups(id: String) -> Array:
	if not hand_pickups.has(id):
		hand_pickups[id] = []
	return hand_pickups[id]


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
		world_geo.add_child(_make_tile(piece, piece.polygon, false))
		# Solidity comes from the registry, not a type check: a new blocking tile
		# collides correctly without touching this loop.
		if not TileTypes.is_walkable(piece.type):
			wall_polys.append(piece.polygon)
			var col := CollisionPolygon2D.new()
			col.polygon = piece.polygon
			world_solid.add_child(col)
		elif piece.type == TileTypes.GOAL:
			goal_polys.append(piece.polygon)
	_refresh_lights()


## One drawn fragment: tileset texture, base-space UVs, lit material.
##
## `poly` is passed separately from `piece` because the fold ANIMATION draws
## sub-fragments of a piece — cut again by the crease being applied. They share
## the piece's `src_offset`, so their UVs come out of the same base tile and the
## art slides with the geometry instead of swimming across it.
func _make_tile(piece, poly: PackedVector2Array, in_sub: bool) -> Polygon2D:
	var vis := Polygon2D.new()
	vis.polygon = poly
	var kind := _kind_of(piece)
	if _atlas != null:
		vis.texture = _atlas
		vis.uv = TileAtlas.uv_for(poly, piece.src_offset, kind,
			TileAtlas.variant_for(piece.base_id), CS)
		vis.color = Color.WHITE
	else:
		vis.color = TileAtlas.base_color(piece.type)
	if light_rig != null:
		var mat := light_rig.material_for(piece.type, in_sub)
		if mat != null:
			vis.material = mat
	return vis


## Which tileset row a fragment draws from. The "open sky above" edge kind is
## decided in BASE space, so a wall keeps its lit cap when a fold slides it under
## something else — material belongs to the sheet, not to the current stacking.
func _kind_of(piece) -> int:
	var open_above := false
	if piece.type == TileTypes.WALL and base != null:
		var tile := base.tile_by_id(piece.base_id)
		if tile != null:
			var above := base.tile_at(tile.grid_position + Vector2i(0, -1))
			open_above = above == null or above.type == TileTypes.EMPTY
	return TileAtlas.kind_for(piece.type, open_above)


func rebuild_sub() -> void:
	sub_pieces = sub_base_pieces.duplicate()
	for fold in level_folds():
		sub_pieces = FoldReplay.apply_one_fold(sub_pieces, fold, CS)
	sub_by_pos = BaseFrame.index_by_pos(sub_pieces)
	sub_wall_polys = WorldCore.solid_polys_of(sub_pieces)
	sub_goal_polys = WorldCore.polys_of_type(sub_pieces, TileTypes.GOAL)

	for child in sub_geo.get_children():
		child.queue_free()
	sub_player_ghosts = []
	var gap := sub_fold.gap_distance()
	# Enough copies to fill the WIDEST frame the camera can pull out to, not the
	# current one: the count is fixed when the subspace is built, and a visible
	# end to the repetition would break the cylinder the moment the lens opened.
	var reach := WorldCore.camera_view_radius(get_viewport_rect().size, WorldCore.ZOOM_WIDEST)
	sub_copies = clampi(int(ceil(reach / gap)), 1, 24)
	for k in range(-sub_copies, sub_copies + 1):
		var copy := Node2D.new()
		copy.position = sub_fold.crease_normal * (k * gap)
		sub_geo.add_child(copy)
		var solid: StaticBody2D = null
		if absi(k) <= 1:
			solid = StaticBody2D.new()
			copy.add_child(solid)
		for piece in sub_pieces:
			copy.add_child(_make_tile(piece, piece.polygon, true))
			if not TileTypes.is_walkable(piece.type) and solid != null:
				var col := CollisionPolygon2D.new()
				col.polygon = piece.polygon
				solid.add_child(col)
		# The real body lives in copy 0; every other copy gets a drawn twin.
		if k != 0:
			var ghost := player.make_visual_copy()
			# Above all terrain, not just this copy's: a twin standing near a
			# band edge overlaps the neighbouring copy, which draws later.
			ghost.z_index = player.z_index
			copy.add_child(ghost)
			sub_player_ghosts.append(ghost)
	_update_player_ghosts()
	_refresh_lights()


## The strip renders repeating across the glue, and the player repeats with it:
## you are in every band at once, because they are all the same band. One lone
## body would make the wrap read as a jump between worlds instead of a lap
## around a cylinder. Copies are children of their band's node, so the offset
## is the parent transform and their local position is just the body's.
func _update_player_ghosts() -> void:
	if sub_player_ghosts.is_empty():
		return
	var p := player.global_position
	var squash := player.visual_squash()
	for ghost in sub_player_ghosts:
		ghost.position = p
		ghost.scale = squash


## Re-resolve the region's lights against whatever is now on screen and hand
## the result to the rig. Called from the rebuilds, because a light can only
## move when the geometry does.
func _refresh_lights() -> void:
	if light_rig == null:
		return
	light_rig.set_lights(lights_here())


## The lights burning in the CURRENT configuration, as view records
## (`{pos, color, radius, energy, flicker}`), radius already in world px.
##
## This is the whole fold-awareness of lighting: a light is asked where it is,
## and a light whose base tile has been folded away has no answer here — it is
## not in this list, casts nothing, and shows no lamp. Step into that fold's
## subspace and the same question, asked of the strip content, answers.
##
## Inside a subspace the strip repeats across the glue, so its lights repeat
## with it — otherwise you would walk through the cylinder into a dark copy of
## a lit room.
func lights_here() -> Array:
	var lights: Array = region_lights.get(region_id, [])
	if lights.is_empty():
		return []
	var offsets: Array = [Vector2.ZERO]
	if mode == Mode.SUBSPACE and sub_fold != null:
		offsets = []
		var step := sub_fold.crease_normal * sub_fold.gap_distance()
		for k in range(-SUB_LIGHT_COPIES, SUB_LIGHT_COPIES + 1):
			offsets.append(step * k)
	var out: Array = []
	for entry in LightSource.resolve_all(_frame_pieces(), lights):
		var light: LightSource = entry["light"]
		for off in offsets:
			out.append({
				"id": light.id,
				"pos": Vector2(entry["pos"]) + off,
				"color": light.color,
				"radius": light.radius_px(CS),
				"energy": light.energy,
				"flicker": light.flicker,
			})
	return out


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
		sub_player_ghosts = []
		world_geo.visible = true
		_bg.color = Color("0a0b12")
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
	_bg.color = Color("140a2a")
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

## One key for the whole verb. TAP pushes an anchor in (pin, pin, then commit);
## HOLD pulls one back out (your last anchor, or the fold you are pointing at).
## The two directions of a conserved resource are the two ways to press one key.
##
## The tap fires on RELEASE, so a press that grows into a hold never also commits.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	if event.physical_keycode == KEY_R:
		if event.pressed:
			_reset()
		return
	if event.physical_keycode != KEY_F:
		return
	if event.pressed:
		if animating():
			return
		_hold_active = true
		_hold_fired = false
		_hold_elapsed = 0.0
		return
	var tapped := _hold_active and not _hold_fired
	_hold_active = false
	_hold_fired = false
	if tapped and not animating():
		tap_action(player.point_dir())


## How far through the hold the key currently is (0 = not holding / already fired).
## Drawn as a filling ring by the overlay so the two gestures are distinguishable
## before either of them lands.
func hold_progress() -> float:
	if not _hold_active or _hold_fired:
		return 0.0
	return clampf(_hold_elapsed / HOLD_TIME, 0.0, 1.0)


func _tick_hold(delta: float) -> void:
	if not _hold_active or _hold_fired:
		return
	if animating():
		_hold_active = false
		return
	_hold_elapsed += delta
	if _hold_elapsed >= HOLD_TIME:
		_hold_fired = true
		hold_action()   # the burst is not aimed; where you stand is the whole input


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


func pending_slot(slot: int):
	return pending_a if slot == 0 else pending_b


func _set_pending(slot: int, entry) -> void:
	if slot == 0:
		pending_a = entry
	else:
		pending_b = entry


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
	# Checked at PLACEMENT, not at commit: with one key the next tap is the commit,
	# so an un-committable pair has to be refused while you can still see why.
	# (Skipped when the other anchor is inert — pinned in a frame we cannot resolve.)
	var other = pending_cell(1 - slot)
	if other != null and not WorldCore.anchors_valid(other, cand):
		_show_flash("Too close to your other anchor.")
		return
	# Placing puts a HAND down: it leaves your slot now, and its kind travels with
	# the anchor because the fold will need to know what it was pinned with. Re-siting
	# an anchor you already placed reuses the hand already in it.
	var kind: int = HandTypes.PLAIN
	var existing = pending_slot(slot)
	if existing != null:
		kind = int(existing["hand"])
	else:
		var from_slot := AnchorStock.first_held(hands)
		if from_slot < 0:
			_show_flash("No hand to place.")
			return
		kind = int(hands[from_slot])
		hands[from_slot] = null
	_set_pending(slot, {"bid": piece.base_id, "bp": center - piece.src_offset, "hand": kind})
	_refresh_fuse()


## The fold that F should unfold from where you are standing / aiming. Several
## folds can meet in the SAME cell — a horizontal pair and a vertical pair whose
## halves happen to join at one spot — and then one diamond stands for all of
## them. Search NEWEST FIRST and prefer one that can actually come out, because
## the older of a stacked pair is exactly the one the newer is blocking: taking
## the first match in fold order would offer you nothing but the refusal.
##
## Falls back to the newest match when none is unfoldable, so the message you get
## is still about the fold you were pointing at.
func aimed_fold(dir: Vector2i = Vector2i.ZERO) -> Fold:
	var cand := candidate_anchor(dir)
	var here := player_cell()
	var list: Array = level_folds()
	var blocked: Fold = null
	for i in range(list.size() - 1, -1, -1):
		var fold: Fold = list[i]
		if fold.meeting_pos != cand and fold.meeting_pos != here:
			continue
		if can_unfold_fold(fold):
			return fold
		if blocked == null:
			blocked = fold
	return blocked


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


## TAP: put a hand down. The first fills anchor 1, the second anchor 2 — and the
## second also lights the fuse, because a completed pair commits ITSELF (see
## `_refresh_fuse`). There is no committing press: what you do is place hands, and
## what the fold does is go off.
func tap_action(dir: Vector2i) -> void:
	if animating():
		return
	if pending_a == null:
		place_pending(0, dir)
	elif pending_b == null:
		place_pending(1, dir)
	else:
		_show_flash("Both hands are down — it is about to fold.")


## HOLD: a release BURST around you.
##
## Not an aimed action — a small sphere of influence centred on your body
## (`BURST_RADIUS`, about a tile). Everything of yours inside it comes loose at once:
##
##   - hands you have placed as anchors come back;
##   - folds whose seam is in reach come apart, if nothing newer is blocking them;
##   - inside a subspace, the glue anchor in reach is the way out;
##   - and any hand with nowhere to go POPS INTO THE WORLD at your feet.
##
## That last clause is what makes the burst safe to fire blind. Nothing is ever
## refused for want of a slot and nothing is ever destroyed: a hand that cannot be
## caught is simply a hand on the ground, which is the same object a cache is.
##
## Folds come apart one at a time and the first to animate takes the burst with it,
## so a stack under one diamond clears over several bursts rather than all at once.
func hold_action(_dir: Vector2i = Vector2i.ZERO) -> void:
	if animating():
		return
	var origin := player.global_position
	_burst_flash_left = BURST_FLASH
	var freed := 0

	# Your own placed hands first: cheap, and they change no geometry.
	for slot in [1, 0]:
		if pending_slot(slot) != null and _pending_within(slot, origin, BURST_RADIUS):
			_retrieve_pending(slot)
			freed += 1

	# Inside a fold, the glue anchor in reach is the exit.
	if mode == Mode.SUBSPACE and _glue_within(origin, BURST_RADIUS):
		try_exit()
		return

	# Then the folds — the ones that were unfoldable WHEN THE BURST FIRED, decided up
	# front. A stack under one diamond clears one layer per burst: releasing the newer
	# fold is what unblocks the older, and cascading into it would mean a single press
	# undid work you never asked it to reach. Snapshotting also makes the burst
	# deterministic, rather than depending on which unfolds happen to animate.
	for fold in _unfoldable_within(origin, BURST_RADIUS):
		if animating():
			break
		unfold_level_fold(fold)
		freed += 1

	if freed == 0:
		_show_flash("Nothing here to release.")


## A pending anchor's current distance from a point, or false if it is unresolvable
## in this frame (pinned in another region, or folded away).
func _pending_within(slot: int, origin: Vector2, radius: float) -> bool:
	var cell = pending_cell(slot)
	if cell == null:
		return false
	return ((Vector2(cell) + Vector2(0.5, 0.5)) * CS).distance_to(origin) <= radius


func _glue_within(origin: Vector2, radius: float) -> bool:
	if mode != Mode.SUBSPACE or sub_fold == null:
		return false
	for c in [sub_fold.anchor_a, sub_fold.anchor_b]:
		if ((Vector2(c) + Vector2(0.5, 0.5)) * CS).distance_to(origin) <= radius:
			return true
	return false


## Folds of this level whose seam is in reach AND can come out right now, newest
## first — the older of a stacked pair is exactly the one the newer is blocking, so
## working backwards offers the ones that can actually move.
func _unfoldable_within(origin: Vector2, radius: float) -> Array:
	var out: Array = []
	var list: Array = level_folds()
	for i in range(list.size() - 1, -1, -1):
		var fold: Fold = list[i]
		var seam: Vector2 = (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * CS
		if seam.distance_to(origin) <= radius and can_unfold_fold(fold):
			out.append(fold)
	return out


## Seams a burst from here would reach, for the overlay to mark. Includes blocked
## ones: the marker should show what is in range, and its own colour says whether it
## will move.
func seams_within_burst() -> Array:
	var out: Array = []
	var origin := player.global_position
	for fold in level_folds():
		var seam: Vector2 = (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * CS
		if seam.distance_to(origin) <= BURST_RADIUS:
			out.append(fold)
	return out


## Is the subspace's glue anchor within burst reach? The overlay lights the white
## diamond on this.
func glue_within_burst() -> bool:
	return _glue_within(player.global_position, BURST_RADIUS)


func burst_flash() -> float:
	return clampf(_burst_flash_left / BURST_FLASH, 0.0, 1.0)


## Take a placed hand back. Usually there is a slot for it — the one it came from —
## but you may have filled that from a pickup in the meantime, in which case it lands
## on the ground rather than vanishing.
func _retrieve_pending(slot: int) -> void:
	var entry = pending_slot(slot)
	if entry == null:
		return
	_set_pending(slot, null)
	_give_hand(int(entry["hand"]))
	_cancel_fuse()


func commit_pending() -> void:
	if animating():
		return
	if pending_a == null or pending_b == null:
		return
	var ca = pending_cell(0)
	var cb = pending_cell(1)
	if ca == null or cb == null:
		_show_flash("An anchor lies beyond this fold.")
		_retrieve_pending(1)
		return
	if not WorldCore.anchors_valid(ca, cb):
		_show_flash("Anchors must be at least 2 tiles apart.")
		_retrieve_pending(1)
		return
	var pinned: Array[int] = [int(pending_a["hand"]), int(pending_b["hand"])]
	var committed := do_sub_fold(ca, cb, pinned) if mode == Mode.SUBSPACE \
		else do_fold(ca, cb, pinned)
	if committed:
		# The fold is holding the SAME two hands that were pinned — they went from
		# your slots to the anchors to the fold without ever being duplicated.
		pending_a = null
		pending_b = null
		_cancel_fuse()
	else:
		_retrieve_pending(1)


# ---------------------------------------------------------------------------
# The anchor ledger (see AnchorStock)
# ---------------------------------------------------------------------------
# Nothing is stored. `held` is summed from the live fold lists and `pending` from
# the two slots, so unfolding refunds without any bookkeeping — the fold leaves the
# list and stops being counted.

## Every live fold list in the world: each region's, plus every fold's interiors.
## The working `folds` / `interiors` vars are references INTO `regions`, so walking
## the regions counts the current one exactly once.
func _all_fold_lists() -> Array:
	var out: Array = []
	for id in regions:
		var r: Dictionary = regions[id]
		out.append(r["folds"])
		var ints: Dictionary = r["interiors"]
		for fid in ints:
			out.append(ints[fid])
	return out


## Hands in your slots right now.
func hands_held() -> int:
	return AnchorStock.held_count(hands)


## Empty slots — how many hands you could be given, and so whether a fold's two can
## come home.
func hands_free_slots() -> int:
	return AnchorStock.free_slots(hands)


## Hands committed to standing folds, everywhere in the world.
func hands_in_folds() -> int:
	return AnchorStock.held_in(_all_fold_lists())


func hands_pending() -> int:
	return (1 if pending_a != null else 0) + (1 if pending_b != null else 0)


func can_place_hand() -> bool:
	return AnchorStock.has_hand(hands)


## The kind of hand the next tap would put down, or -1 if you have none. Drives the
## aim ring's colour: what you are about to spend is visible before you spend it.
func next_hand_type() -> int:
	var i := AnchorStock.first_held(hands)
	return -1 if i < 0 else int(hands[i])


## Hands lying on the ground, everywhere in the world.
func hands_loose() -> int:
	var n := 0
	for id in hand_pickups:
		n += (hand_pickups[id] as Array).size()
	return n


## Every hand that exists, in all four places. NOTHING in the game changes this:
## placing, committing, unfolding, bursting and picking up all just move one.
func hands_total() -> int:
	return AnchorStock.total(hands, hands_pending(), _all_fold_lists(), hands_loose())


# ---------------------------------------------------------------------------
# The fuse: a completed pair folds itself
# ---------------------------------------------------------------------------

## Light, re-time or drop the fuse to match the pending pair. Called whenever an
## anchor lands: two down starts it, anything less means there is nothing to count
## down. Re-siting an anchor restarts it from full, so adjusting a pair always buys
## back the whole delay rather than folding under your hands.
func _refresh_fuse() -> void:
	if pending_a == null or pending_b == null:
		_cancel_fuse()
		return
	_fuse_total = HandTypes.fuse_for(int(pending_a["hand"]), int(pending_b["hand"]))
	_fuse_left = _fuse_total


func _cancel_fuse() -> void:
	_fuse_left = 0.0
	_fuse_total = 0.0


func fuse_running() -> bool:
	return _fuse_total > 0.0


## How far through the fuse we are, 0 (just lit) to 1 (folding now). The overlay
## pulses the pending rings on this.
func fuse_progress() -> float:
	if _fuse_total <= 0.0:
		return 0.0
	return clampf(1.0 - _fuse_left / _fuse_total, 0.0, 1.0)


## Run the fuse down. PAUSED while either anchor is unresolvable in the frame we are
## looking at — walk through a door mid-count and the fold waits for you rather than
## firing somewhere you cannot see, or failing on an anchor that is merely elsewhere.
func _tick_fuse(delta: float) -> void:
	if not fuse_running() or animating():
		return
	if pending_cell(0) == null or pending_cell(1) == null:
		return
	_fuse_left = maxf(_fuse_left - delta, 0.0)
	if _fuse_left <= 0.0:
		commit_pending()


# ---------------------------------------------------------------------------
# Folding
# ---------------------------------------------------------------------------

## What a committed fold takes custody of.
##
## `commit_pending` passes the two hands that were actually pinned — they left your
## slots when you placed them, so they are already accounted for. Any other caller
## (`do_fold` as a bare primitive: tests, debug) is folding without having placed
## anything, so the hands come STRAIGHT OUT OF YOUR SLOTS here.
##
## If your hands are empty the fold holds nothing, exactly like a fold the world made.
## Inventing hands instead would be the one thing this whole ledger exists to prevent:
## a fold holding anchors nobody paid for, which unfolding would then hand you.
##
## CALL THIS LATE — at the point of no return, after every refusal has been checked.
## It empties slots, and a fold that gets rejected for a pin in its span or nowhere to
## land must not have cost you the hands it never took.
func _hands_for_fold(pinned: Array[int]) -> Array[int]:
	if pinned.size() == AnchorStock.HANDS_PER_FOLD:
		return pinned.duplicate()
	var out: Array[int] = []
	for _i in range(AnchorStock.HANDS_PER_FOLD):
		var from_slot := AnchorStock.first_held(hands)
		if from_slot < 0:
			break
		out.append(int(hands[from_slot]))
		hands[from_slot] = null
	return out


## Commit a fold at world level. The fold takes custody of the two hands that were
## pinned — kinds and all — and gives those same two back when it is unfolded.
## (Authored pre-folds and trigger folds are anchored by the world and hold none:
## `Fold.held_hands` defaults to empty.)
func do_fold(a1: Vector2i, a2: Vector2i, pinned: Array[int] = []) -> bool:
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
		fold.held_hands = _hands_for_fold(pinned)
		seam_segs[fold.fold_id] = WorldCore.seam_segment(fold, dropped, CS)
		folds.append(fold)
		var p := player.global_position
		var finalize_pinch := func() -> void:
			context.append(fold)
			_apply_context()
			_show_flash("Folded in.")
		_play_transition(pre, fold, true, false, p, p, false, finalize_pinch)
		return true

	var landed := WorldCore.depenetrate(dest, PlayerBody.RADIUS, WorldCore.solid_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Fold blocked — nowhere for you to land.")
		return false
	next_fold_id += 1
	fold.held_hands = _hands_for_fold(pinned)
	seam_segs[fold.fold_id] = WorldCore.seam_segment(fold, dropped, CS)
	folds.append(fold)
	var finalize_ride := func() -> void:
		rebuild_world()
		player.teleport(landed)
	_play_transition(pre, fold, true, true, player.global_position, landed, false, finalize_ride)
	return true


## Commit a fold INSIDE a subspace. Interior folds hold hands exactly like world
## folds do — and they persist into the world when you exit, so the hands stay
## committed across the boundary.
func do_sub_fold(a1: Vector2i, a2: Vector2i, pinned: Array[int] = []) -> bool:
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
	fold.held_hands = _hands_for_fold(pinned)
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


## The seam diamonds to draw: meeting cell -> can anything there come out.
## Several folds can meet in one cell, so the marker is one diamond for all of
## them and reads unblocked when F there would DO something — the same choice
## `aimed_fold` makes, so the colour never promises what the act refuses.
func seam_markers() -> Dictionary:
	var out: Dictionary = {}
	for fold in level_folds():
		var cell: Vector2i = fold.meeting_pos
		out[cell] = bool(out.get(cell, false)) or can_unfold_fold(fold)
	return out


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


## Give the player a hand: into a free slot if there is one, otherwise onto the
## GROUND at their feet as a loose pickup.
##
## The overflow case is the whole reason nothing in this file has to refuse a hand.
## A hand you cannot catch is not a hand destroyed and not an action denied — it is a
## hand lying where you were standing, which is exactly the object an authored cache
## already is. Conservation holds without anyone having to check for room first.
func _give_hand(kind: int) -> void:
	var into := AnchorStock.first_empty(hands)
	if into >= 0:
		hands[into] = kind
		return
	_drop_hand(kind, player.global_position)


## Put a hand on the ground at a world point. It binds to whatever fragment is under
## that point, so from then on it rides folds like any other occupant. If the point is
## over void there is no sheet to lie on, so we search outward a little before giving
## up — a dropped hand landing nowhere would be the one way this system loses one.
func _drop_hand(kind: int, at: Vector2) -> void:
	# Fan successive drops apart a little, so two hands out of one fold read as two.
	# The fan is applied AFTER the fragment is chosen, never before: a burst usually
	# happens standing on a seam, and picking the fragment from a fanned point would
	# put one hand either side of the crease — which the unfold then carries to
	# opposite ends of the world. Same base tile, different spot on it.
	var fan := Vector2((loose_hands.size() % 3) - 1, 0) * (0.28 * CS)
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for step in range(1, 5):
		offsets.append(Vector2(0, -0.5 * CS * step))
		offsets.append(Vector2(-0.5 * CS * step, 0))
		offsets.append(Vector2(0.5 * CS * step, 0))
		offsets.append(Vector2(0, 0.5 * CS * step))
	for off in offsets:
		var piece = BaseFrame.piece_containing(_frame_index(), at + off, CS)
		if piece != null:
			loose_hands.append(
				HandPickup.dropped_at(kind, piece, at + off + fan, region_id))
			_refresh_pickup_visuals()
			return
	push_warning("FoldWorld: nowhere to drop a hand near %s" % at)


## Move a fold's hands back to the player. Call BEFORE the fold leaves the list, so
## the hands are never in two places at once.
func _take_back(fold: Fold) -> void:
	for kind in fold.held_hands:
		_give_hand(int(kind))
	fold.held_hands = [] as Array[int]


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
	var regained: int = fold.held_hands.size()
	_take_back(fold)
	var finalize := func() -> void:
		if in_sub:
			rebuild_sub()
		else:
			rebuild_world()
		player.teleport(landed)
		if regained > 0:
			_show_flash("Released — %d hands." % regained)
	if was_newest and kids.is_empty():
		_play_transition(new_pieces, fold, false, true,
			player.global_position, landed, in_sub, finalize)
	else:
		finalize.call()


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
		_show_flash("Blocked — an inner fold crosses the outer seam.")
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
	_take_back(outer)
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
		_bg.color = Color("0a0b12")
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
	_cut_camera()
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
	# Inside `pixel_view`, with the geometry it stands in for. Parented to this
	# node instead it would be outside the render target and so outside the
	# camera's transform, drawing world coordinates as raw window pixels: the map
	# appears to fly off to one side for the length of the transition and snap
	# back when the real geometry returns.
	pixel_view.add_child(layer)
	var frags: Array = []
	var shift_a := fold.shift_a_px(CS)
	var shift_b := fold.shift_b_px(CS)
	for piece in pre_pieces:
		var res := CollisionCore.fold_polygons([piece.polygon], fold, CS)
		for poly in res["a"]:
			frags.append(_make_frag(layer, piece, CollisionCore.shift(poly, -shift_a), sub_tint, "a"))
		for poly in res["b"]:
			frags.append(_make_frag(layer, piece, CollisionCore.shift(poly, -shift_b), sub_tint, "b"))
		for poly in res["dropped"]:
			frags.append(_make_frag(layer, piece, poly, sub_tint, "strip"))
	world_geo.visible = false
	sub_geo.visible = false
	# The lamps belong to the pre-fold arrangement; the lighting itself stays
	# lit through the transition, so the flaps slide through standing light.
	light_rig.visible = false
	player.frozen = true
	_anim = {
		"layer": layer, "frags": frags, "fold": fold, "forward": forward,
		"collapse": collapse_strip, "progress": 0.0,
		"p_from": p_from, "p_to": p_to, "finalize": finalize,
	}
	_apply_anim_frame()


func _make_frag(layer: Node2D, piece, poly: PackedVector2Array, in_sub: bool,
		kind: String) -> Dictionary:
	var node := _make_tile(piece, poly, in_sub)
	layer.add_child(node)
	return {"node": node, "base": poly, "kind": kind}


func _process(delta: float) -> void:
	_tick_hold(delta)
	if hand_orbit != null and player != null:
		hand_orbit.follow(hands, player.global_position, player.velocity, player.facing, delta)
	# Before the early-out: the lens has to keep working while a fold plays.
	_update_camera()
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
		light_rig.visible = true
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
# Camera framing
# ---------------------------------------------------------------------------
# The player owns the camera (see PlayerBody); this decides what it should be
# SHOWING — how much (zoom) and from where (lookahead). The body supplies motion
# and the look keys, because it knows its own limits and its own input; the world
# supplies the focus set and the flat axis, because only the world knows what the
# moment is about.

## `center` overrides where the BODY is taken to be — the cut path needs the
## framing of where it is going, not of where the lens still is.
func _update_camera(center: Vector2 = Vector2.INF) -> void:
	if player == null:
		return
	var body: Vector2 = player.global_position if center == Vector2.INF else center
	# The lead first: it moves the camera, and the zoom's focus distances are
	# measured from where the camera ends up. Decided in the other order, a hard
	# lead would quietly crop the very things the focus set exists to keep on screen.
	player.lookahead_target = WorldCore.camera_lookahead_for({
		"velocity": player.motion_fraction(),
		"look": player.look_dir(),
		# Inside a fold the strip repeats along the crease normal, so the frame
		# already shows every band there is that way: leading along it would slide
		# the view across identical copies for nothing.
		"flat_axis": sub_fold.crease_normal if _in_subspace() else Vector2.ZERO,
		"frozen": animating(),
	})
	var eye := (player.camera_position() if center == Vector2.INF
		else body + player.lookahead_target)
	player.zoom_target = WorldCore.camera_zoom_for({
		"viewport": get_viewport_rect().size,
		"center": eye,
		"motion": player.motion_intensity(),
		# A fold rearranging the world is its own reason to step back and watch.
		"widen": 1.0 if animating() else 0.0,
		"focus": _camera_focus(),
	})
	_size_pixel_view()


## Give the render target the resolution the CURRENT zoom asks for. The camera's
## lens never moves — inside a render target, zoom is what sets the size of an art
## pixel, so moving it would resample the 16px tileset and soften the world. A
## wider frame is therefore MORE pixels, not bigger ones.
##
## Sized from `camera_zoom()` (the eased value) rather than the target, so the
## buffer tracks what is actually on screen while the frame is still opening.
func _size_pixel_view() -> void:
	if pixel_view == null:
		return
	var want := PixelArt.target_size(get_viewport_rect().size, player.camera_zoom())
	# Only on change: assigning size re-allocates the render target.
	if pixel_view.size != want:
		pixel_view.size = want


## Cut the camera — position, lens AND lead — to where the body now is. For hard
## relocations (spawn, doors, being turned back by the fold): the destination's
## framing is computed first, because easing into it would read as the new room
## inflating around you.
func _cut_camera() -> void:
	_update_camera(player.global_position)
	player.snap_camera()


func _in_subspace() -> bool:
	return mode == Mode.SUBSPACE and sub_fold != null


## World points that would be a mistake to leave off screen right now.
func _camera_focus() -> PackedVector2Array:
	var pts := PackedVector2Array([player.global_position])
	# A pinned anchor is one half of a fold you are still composing. Walk away
	# from it and the frame opens to keep the span you are judging in view — the
	# camera showing you how big the fold has got.
	for slot in [0, 1]:
		var cell = pending_cell(slot)
		if cell != null:
			pts.append((Vector2(cell) + Vector2(0.5, 0.5)) * CS)
	# Inside a fold the band IS the room: frame it glue to glue, so a wide strip
	# reads as the cylinder it is rather than a corridor with no visible walls.
	if _in_subspace():
		var n := sub_fold.crease_normal
		var d := (player.global_position - sub_fold.crease_point1).dot(n)
		pts.append(player.global_position - n * d)
		pts.append(player.global_position + n * (sub_fold.gap_distance() - d))
	# A fold ride can carry you further than a frame's width. Hold both ends.
	if animating():
		pts.append(_anim["p_from"])
		pts.append(_anim["p_to"])
	return pts


# ---------------------------------------------------------------------------
# Per-frame world logic
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_burst_flash_left = maxf(_burst_flash_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left == 0.0 and _flash != null:
		_flash.visible = false
	_update_status()
	# Only the nearest handful of lights reach the shader; "nearest" is measured
	# from the player, not the origin.
	if light_rig != null:
		light_rig.set_focus(player.global_position)
	if animating():
		return

	if mode == Mode.SUBSPACE:
		_subspace_wrap_and_turnback()
		_update_player_ghosts()
	else:
		if player.global_position.y > (base.grid_size.y + 6) * CS:
			player.teleport(_spawn, false)
			_show_flash("You fell out of the world — respawned.")
	_tick_fuse(delta)
	_check_goal()
	_check_pickups()
	_check_triggers()
	_check_doors()


func _subspace_wrap_and_turnback() -> void:
	var n := sub_fold.crease_normal
	var gap := sub_fold.gap_distance()
	var c1 := sub_fold.crease_point1.dot(n)
	var proj := player.global_position.dot(n)
	# Walking through a glue line lands you in the next copy of the strip —
	# which is this one. Slide the body back by one band width and slide the
	# CAMERA by the same vector: the strip repeats with exactly that period, so
	# the rendered frame is unchanged and the crossing is invisible. (Snapping
	# the camera instead would throw away its smoothing lag and jolt the view.)
	if proj < c1:
		player.global_position += n * gap
		player.shift_camera(n * gap)
	elif proj >= c1 + gap:
		player.global_position -= n * gap
		player.shift_camera(-n * gap)

	# Falling out of the strip's tangential extent doesn't force-exit (exit
	# can be blocked by crossing folds): the fold turns you back to its anchor.
	var tangent := Vector2(-n.y, n.x)
	var tproj := player.global_position.dot(tangent)
	if tproj < sub_extent["min"] - 4.0 * CS or tproj > sub_extent["max"] + 4.0 * CS:
		var back := sub_fold.crease_point1 + n * (gap * 0.5)
		var landed := WorldCore.depenetrate(back, PlayerBody.RADIUS, sub_wall_polys)
		player.teleport(back if landed == Vector2.INF else landed, false)
		_cut_camera()
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


## Loose hands: walk onto one and it is yours, if you have a slot free.
##
## One object covers both the caches a world ships and the hands that pop out of a
## burst, because to the player they are one thing. It only takes if a slot is free,
## and a slot is free because you PUT A HAND DOWN — so a cache is not a stockpile you
## raid on the way past, it is the second half of a fold you have already started.
##
## Works at world level AND inside a subspace: a hand the fold swallowed is lying in
## there with everything else, and taking it in there counts.
func _check_pickups() -> void:
	if loose_hands.is_empty():
		return
	if AnchorStock.first_empty(hands) < 0:
		return                      # full hands walk over it, and it waits
	for i in range(loose_hands.size()):
		var pickup: HandPickup = loose_hands[i]
		var wp = pickup.position_in(_frame_pieces())
		if wp == null:
			continue                # folded away — not here to be picked up
		if player.global_position.distance_to(Vector2(wp)) > PlayerBody.RADIUS + 8.0:
			continue
		hands[AnchorStock.first_empty(hands)] = pickup.kind
		loose_hands.remove_at(i)
		_refresh_pickup_visuals()
		_show_flash("Picked up a %s hand." % HandTypes.type_name(pickup.kind))
		return


## Where every loose hand in the current view lies right now, as
## `[{"pickup", "pos"}, ...]`. The overlay draws these; a hand folded away resolves
## to nothing and is simply not in the list.
func loose_hand_points() -> Array:
	return HandPickup.resolve_all(_frame_pieces(), loose_hands)


## Loose hands are drawn by the overlay, which redraws itself every frame, so there is
## nothing to rebuild — but taking or dropping one should also relight the scene, since
## a hand is a thing the player is looking for.
func _refresh_pickup_visuals() -> void:
	if overlay != null:
		overlay.queue_redraw()


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


## Put everything back — the world AND your hands.
##
## `_setup_all` rebuilds the loose-hand lists from the authored world, so caches
## respawn and hands dropped during play are forgotten. That is the coherent reading
## now that the number you can hold does not grow: a pickup is another hand for an
## empty slot, not a permanent upgrade, and hands are exactly what a reset restores —
## leaving caches spent would strand you at fewer hands than you started with, which
## is the opposite of what an escape hatch is for.
func _reset() -> void:
	if not _anim.is_empty():
		var layer: Node2D = _anim["layer"]
		layer.queue_free()
		_anim = {}
		player.frozen = false
		light_rig.visible = true
	_hold_active = false
	_hold_fired = false
	_burst_flash_left = 0.0
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
	_bg.color = Color("0a0b12")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Controls default to MOUSE_FILTER_STOP; a full-screen rect would eat every
	# click before _unhandled_input sees it. HUD must never take the mouse.
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(_bg)

	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	# Controls only — what the keys are, not what they mean. The mechanics are the
	# game's to teach: the aim ring, the preview band, the seam diamonds and the
	# anchor readout all say their piece in place, and a wall of text on top of
	# them explains away the thing the player is meant to work out.
	var help := Label.new()
	help.text = "A/D move   Space jump   W/S aim   F tap: place hand · hold: pull back   R reset"
	help.position = Vector2(12, 8)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hud.add_child(help)

	_status = Label.new()
	_status.position = Vector2(12, 30)
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
	var kinds: Array = []
	for h in hands:
		kinds.append("—" if h == null else HandTypes.type_name(int(h)))
	var stock := "Hands: %s   (%d down, %d in folds)" \
		% [" ".join(kinds), hands_pending(), hands_in_folds()]
	if mode == Mode.WORLD:
		_status.text = "Region: %s   Folds: %d   Mode: WORLD\n%s" \
			% [region_id, folds.size(), stock]
	else:
		_status.text = "Region: %s   Folds: %d   Mode: INSIDE FOLD x%d (%d inner)\n%s" \
			% [region_id, folds.size(), context.size(), level_folds().size(), stock]


func _show_flash(text: String) -> void:
	if text.is_empty():
		return
	_flash.text = text
	_flash.visible = true
	_flash_left = 2.5
