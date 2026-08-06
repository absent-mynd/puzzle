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
##     stack of folds (subspaces), ARBITRARILY DEEP. Each level derives purely:
##     the level's base pieces are the parent level's strip content of the
##     entered fold, and its fold list is that fold's persistent interiors.
##   - ONE SPACE AT A TIME. There is no world-level path and subspace path;
##     there is the CURRENT LEVEL, and the region world is the level with an
##     empty context. Its periodicity is a `FoldLattice`: no periods in a
##     region, one inside a fold, TWO inside a fold whose creases run across
##     the fold outside it — at which point you are walking on a torus. Every
##     part of the view (terrain, the body, the hands, the markers, the lights,
##     the colliders, the camera) asks that one object how the space repeats,
##     which is why folding yourself deeper needed no new rendering.
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
## The wrap has exactly one implementation, and it is not in this file:
## STATIC content (the sheet) bakes its copies into batched vertices at rebuild
## (`TileBatch`), and anything that MOVES is a `WrapCanvas` and repeats without
## being asked. Adding something to the world does not mean teaching it about
## folds.
##
## Known limits: fold extent is infinite-crease (a fold here guts a structure
## over there — the live design argument for barrier-scoped folds), and the
## fold/unfold animation plays only for newest-fold unfolds.

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
## How far out the lamps of a repeating space are copied. The space repeats
## forever; only the nearest `LightRig.MAX_LIGHTS` reach the shader anyway, so
## copying every visible band would just crowd the near ones out.
const LIGHT_COPY_REACH := 10.0 * CS
## Ceiling on how many copies of a repeating space are drawn. A one-cell fold
## repeats every cell and a torus squares whatever a cylinder costs, so the
## count the frame asks for has to be bounded somewhere.
const MAX_WRAP_COPIES := 121

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

## Hands you have PUT DOWN but not yet spent on a fold.
##
## An anchor is {"bid", "bp", "hand", "region"} — a base-frame point, the kind of hand
## pinned there, and the region it belongs to. Frame-independent: it rides folds and
## survives subspace exit, and it is inert (unresolvable) anywhere it does not belong.
## A pinned anchor is a hand that has LEFT you: out of its slot from the moment you
## place it, back only when you go and release it.
##
## `unpaired` holds anchors still waiting for a partner. `primed` holds PAIRS, each
## counting its own fuse down independently — so several folds can be armed at once,
## and they go off in the order their fuses run out rather than the order you placed
## them. A swift pair laid second fires before a patient pair laid first.
##
## There is no fixed number of either. Two registers is what wedged the game: an
## anchor left in another region sat in one of them forever, so every pair you formed
## afterwards contained a partner you could not reach and never fired.
var unpaired: Array = []
var primed: Array = []

## The hands you are carrying: one entry per slot, a `HandTypes` id or null.
## See `AnchorStock` — this array is the whole of your possession.
var hands: Array = []

# --- Fold-key hold tracking (tap = place a hand, hold = pull one back) ---
var _hold_active := false
var _hold_fired := false
var _hold_elapsed := 0.0

## Seconds left on the burst ring the overlay draws.
var _burst_flash_left := 0.0

# --- The fuse lives on each primed pair; see `primed`. ---

# --- The CURRENT LEVEL (derived from `context` by _apply_context) ---
# One set of these, not one per mode. The region world is the level whose context
# is empty; everything below reads these regardless of how deep you are folded in.

## Identity pieces of this level: the region's base at the top, the entered
## fold's strip content at every level below it.
var level_base: Array = []
## ...with this level's folds replayed over it. The geometry on screen.
var current_pieces: Array = []
var pieces_by_pos: Dictionary = {}
var wall_polys: Array = []
var goal_polys: Array = []
var _on_goal := false

## How this level repeats. Flat in a region, a cylinder inside a fold, a torus
## inside two crossing ones. The single source of truth for the wrap — copies,
## colliders, the body's wrap-around, the camera's framing and the lights all
## come off this.
var lattice: FoldLattice = FoldLattice.flat()
## Where the copies of this level are drawn, nearest first, always including
## ZERO. Handed to every `WrapCanvas` and baked into the terrain batch.
var wrap_offsets: Array = [Vector2.ZERO]
## Content extent along the one direction a cylinder does NOT repeat in — the way
## you can run off the end of a band. Unused when the space is flat or a torus.
var free_extent: Dictionary = {}

## The innermost entered fold, or null at region level. Convenience: it is always
## `context.back()`.
var sub_fold: Fold = null

var _on_screen_lights: Array = []

# --- Animation ---
var anim_enabled := true
var _anim: Dictionary = {}

var player: PlayerBody
var player_visual: PlayerVisual
var hand_orbit: HandOrbit
## The sheet, batched into two Polygon2Ds (see TileBatch), and its colliders.
var geo: TileBatch
var solid: StaticBody2D
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

	light_rig = LightRig.new()
	light_rig.cell_size = CS
	light_rig.z_index = 20

	# The sheet: batched tiles, and one body carrying the colliders of the copies
	# the player could reach. Both are rebuilt whenever the level changes.
	geo = TileBatch.new()
	geo.z_index = 0
	pixel_view.add_child(geo)
	solid = StaticBody2D.new()
	pixel_view.add_child(solid)

	pixel_view.add_child(light_rig)

	player = PlayerBody.new()
	player.z_index = 40
	pixel_view.add_child(player)

	# Everything that MOVES is a WrapCanvas, so it stands in every copy of the
	# space without being told there is more than one.
	player_visual = PlayerVisual.new()
	player_visual.player = player
	player_visual.z_index = 40
	pixel_view.add_child(player_visual)

	hand_orbit = HandOrbit.new()
	hand_orbit.z_index = 45   # over the terrain, under nothing that matters
	pixel_view.add_child(hand_orbit)

	overlay = WorldOverlay.new()
	overlay.world = self
	overlay.z_index = 50
	pixel_view.add_child(overlay)

	_build_hud()
	_setup_all()


## Every canvas that repeats with the space. One list, so a new one is registered
## in exactly one place — and forgetting to register it is a thing you can see.
func _wrap_canvases() -> Array:
	return [player_visual, hand_orbit, overlay]


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
	unpaired = []
	primed = []
	hand_pickups = {}

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
# The current level: derived state -> visuals + colliders
# ---------------------------------------------------------------------------
# ONE space is on screen at a time — the region world is simply the level whose
# context is empty. There is no second set of anything here: one derivation, one
# batch of geometry, one body of colliders, one lattice saying how it repeats.

## Rebuild the geometry of the current level from its base pieces and fold list.
##
## Everything that draws is either baked here (the sheet, whose copies cost only
## vertices) or a `WrapCanvas` that repeats itself (the body, the hands you carry,
## the markers). Nothing in between, and nothing that has to be taught about folds.
func rebuild() -> void:
	current_pieces = level_base.duplicate()
	for fold in level_folds():
		current_pieces = FoldReplay.apply_one_fold(current_pieces, fold, CS)
	pieces_by_pos = BaseFrame.index_by_pos(current_pieces)
	wall_polys = WorldCore.solid_polys_of(current_pieces)
	goal_polys = WorldCore.polys_of_type(current_pieces, TileTypes.GOAL)
	_build_terrain()
	_build_colliders()
	_refresh_lights()


## Draw the sheet. Every fragment of every visible copy goes into one batch, which
## resolves to two Polygon2Ds — one for what stops you, one for what you move
## through. A region is ~800 tiles and a strip is drawn in every band it repeats
## into; a node per fragment per copy was thousands of nodes torn down and rebuilt
## on every fold, and it was the most expensive thing the game did.
func _build_terrain() -> void:
	geo.setup(_atlas, light_rig, base)
	var frags: Array = []
	for piece in current_pieces:
		frags.append({"piece": piece, "poly": piece.polygon})
	geo.rebuild(frags, wrap_offsets)


## Colliders for the fundamental domain and the copies immediately around it.
##
## One body, many shapes: the player is wrapped back into the domain every frame,
## so it can never be more than one copy out — three bands down a cylinder, nine
## around a torus, and exactly one in a region, where `neighbour_offsets` is just
## the origin and this reads as the plain world it is.
func _build_colliders() -> void:
	# Freed outright, not queued: `queue_free` lands at the end of the frame, and a
	# body carrying both the old shapes and the new ones for a step is a body the
	# player can be standing inside. A rebuild is always driven from our own code
	# (a fold settling, a context change), never from inside a physics callback of
	# the body itself, so there is nothing mid-notification to pull out from under.
	for child in solid.get_children():
		solid.remove_child(child)
		child.free()
	var near: Array = lattice.neighbour_offsets()
	for poly in wall_polys:
		for off in near:
			var col := CollisionPolygon2D.new()
			col.polygon = CollisionCore.shift(poly, off)
			solid.add_child(col)


## Re-resolve the region's lights against whatever is now on screen and hand
## the result to the rig. Called from the rebuild, because a light can only
## move when the geometry does.
func _refresh_lights() -> void:
	if light_rig == null:
		return
	light_rig.set_depth(context.size())
	light_rig.set_lights(lights_here())


## The lights burning in the CURRENT configuration, as view records
## (`{pos, color, radius, energy, flicker}`), radius already in world px.
##
## This is the whole fold-awareness of lighting: a light is asked where it is,
## and a light whose base tile has been folded away has no answer here — it is
## not in this list, casts nothing, and shows no lamp. Step into that fold's
## subspace and the same question, asked of the strip content, answers.
##
## A repeating space repeats its lamps, or you would walk through the cylinder
## into a dark copy of a lit room. Only the near copies: the shader takes the
## nearest `LightRig.MAX_LIGHTS`, so copying every visible band would crowd out
## the ones actually lighting you.
func lights_here() -> Array:
	var lights: Array = region_lights.get(region_id, [])
	if lights.is_empty():
		return []
	var offsets: Array = lattice.offsets(LIGHT_COPY_REACH, LightRig.MAX_LIGHTS)
	var out: Array = []
	for entry in LightSource.resolve_all(current_pieces, lights):
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
## fold's persistent interiors — at whatever depth that is.
func level_folds() -> Array:
	if context.is_empty():
		return folds
	return _ensure_interiors(context.back().fold_id)


func _ensure_interiors(fid: int) -> Array:
	if not interiors.has(fid):
		var arr: Array[Fold] = []
		interiors[fid] = arr
	return interiors[fid]


## Derive the state of a level addressed by a fold path (pure, from region
## working state). Returns {"base_pieces", "level_folds", "pieces"}.
##
## Recursive in the path, so it is indifferent to depth: each step captures the
## strip of the next fold out of the prefix of its own level. That is why folding
## yourself deeper needed nothing new here.
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


## Make the view match `context` — at any depth. The region world is the empty
## context and takes the same path as everything else.
func _apply_context() -> void:
	sub_fold = null if context.is_empty() else context.back()
	mode = Mode.WORLD if context.is_empty() else Mode.SUBSPACE
	level_base = _compute_level(context)["base_pieces"]
	lattice = FoldLattice.for_path(context, CS)

	# How many copies to draw: enough to fill the WIDEST frame the camera can pull
	# out to, not the current one. The count is fixed when the level is built, and
	# a visible end to the repetition would break the wrap the moment the lens
	# opened.
	var reach := WorldCore.camera_view_radius(get_viewport_rect().size, WorldCore.ZOOM_WIDEST)
	wrap_offsets = lattice.offsets(reach, MAX_WRAP_COPIES)
	for canvas in _wrap_canvases():
		canvas.set_offsets(wrap_offsets)

	# The one direction a cylinder does not repeat in — the way you can run off
	# the end of a band, and so the only one that needs a turn-back.
	var free := lattice.free_axis()
	free_extent = WorldCore.strip_extent(level_base, free) if free != Vector2.ZERO else {}

	# Deeper reads darker and more lavender; the sheet's tint follows in the rig.
	_bg.color = Color("0a0b12").lerp(Color("140a2a"), minf(float(context.size()) * 0.7, 1.0))
	geo.visible = true
	rebuild()
	_update_music()


## The glue lines of the current space: where its copies are identified. Two down
## a cylinder, four around a torus — one pair per axis of the lattice, drawn so
## the wrap reads as a real join rather than a rendering glitch.
func glue_lines() -> Array:
	if lattice.is_flat() or level_base.is_empty():
		return []
	var out: Array = []
	for period in lattice.periods():
		var n: Vector2 = (period as Vector2).normalized()
		var t := Vector2(-n.y, n.x)
		var ext := WorldCore.strip_extent(level_base, t)
		var base_d := lattice.domain_start(n)
		for d in [base_d, base_d + (period as Vector2).length()]:
			out.append(PackedVector2Array([
				n * d + t * ext["min"], n * d + t * ext["max"]]))
	return out


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


## Where an anchor lies in THIS frame, or null if it is not here — wrong region, or
## its base tile is folded away.
##
## The region check is not belt-and-braces: base ids are per-region and DO overlap
## between regions, so without it a west anchor could quietly resolve onto whatever
## east tile happens to share its id.
func anchor_point(entry):
	if entry == null or String(entry["region"]) != region_id:
		return null
	return BaseFrame.world_point_from_base(current_pieces, entry["bid"], entry["bp"])


func anchor_cell(entry):
	var wp = anchor_point(entry)
	if wp == null:
		return null
	return Vector2i((Vector2(wp) / CS).floor())


func anchor_here(entry) -> bool:
	return anchor_point(entry) != null


## The cells your placed hands are on, in this frame. Anchors that are elsewhere —
## another region, or sealed inside a fold — are simply not in the list, because the
## question this answers is "where are my hands", not "how many do I have out".
func anchor_cells() -> Array:
	var out: Array = []
	for entry in all_anchors():
		var cell = anchor_cell(entry)
		if cell != null:
			out.append(cell)
	return out


## Every anchor you have put down, paired or not.
func all_anchors() -> Array:
	var out: Array = []
	out.append_array(unpaired)
	for pair in primed:
		out.append(pair["a"])
		out.append(pair["b"])
	return out


func place_hand(dir: Vector2i) -> void:
	if animating():
		return
	var cand := candidate_anchor(dir)
	var center := (Vector2(cand) + Vector2(0.5, 0.5)) * CS
	# The ONLY thing placement asks of a spot is that there be sheet there to pin to.
	# That is not a rule, it is storage: an anchor is a base identity plus a point in
	# a tile, and over void there is no tile to be a point in.
	#
	# Everything else — whether the pair makes a fold, whether the surface will hold
	# it, whether you have anywhere to land — is checked WHEN THE FUSE FIRES, not
	# here. The fuse is a window in which you can go and make a doubtful fold work:
	# put both hands down, then run to somewhere the fold can put you. Refusing at
	# placement would close that window before it opened.
	var piece = BaseFrame.piece_containing(pieces_by_pos, center, CS)
	if piece == null:
		_deny("Nothing there to pin to.")
		return
	# Placing puts a HAND down: it leaves your slot now, and its kind travels with
	# the anchor because the fold will need to know what it was pinned with. Re-siting
	# an anchor you already placed reuses the hand already in it.
	var from_slot := AnchorStock.first_held(hands)
	if from_slot < 0:
		_deny("No hand to place.")
		return
	var kind := int(hands[from_slot])
	hands[from_slot] = null
	AudioManager.play_sfx(Sounds.HAND_PLACE)
	var entry := {"bid": piece.base_id, "bp": center - piece.src_offset,
		"hand": kind, "region": region_id}

	# Pair with the most recently placed unpaired anchor YOU CAN CURRENTLY SEE. An
	# anchor left in another region (or sealed inside a fold) is not a partner you
	# could finish a fold with, so it waits where it is and this hand starts a fresh
	# pair instead of being wasted on one that could never fire.
	for i in range(unpaired.size() - 1, -1, -1):
		if anchor_here(unpaired[i]):
			var partner = unpaired[i]
			unpaired.remove_at(i)
			_prime(partner, entry)
			return
	unpaired.append(entry)


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


## TAP: put a hand down. That is all it ever does.
##
## The second hand of a pair lights that pair's fuse and it commits ITSELF; the next
## hand after that starts another pair, which arms alongside the first. There is no
## committing press and no limit but the hands you are carrying.
func tap_action(dir: Vector2i) -> void:
	if animating():
		return
	place_hand(dir)


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
	# An unpaired anchor in reach simply comes back.
	for i in range(unpaired.size() - 1, -1, -1):
		if _anchor_within(unpaired[i], origin, BURST_RADIUS):
			_release_anchor(unpaired[i], true)
			unpaired.remove_at(i)
			freed += 1
	# A primed pair with EITHER anchor in reach is broken: you cannot half-defuse a
	# fold. What you can reach comes back to your hands, what you cannot drops where
	# it was pinned — so reaching into an armed pair always costs you the far hand.
	for pair in primed.duplicate():
		if _anchor_within(pair["a"], origin, BURST_RADIUS) \
				or _anchor_within(pair["b"], origin, BURST_RADIUS):
			_break_pair(pair, origin, BURST_RADIUS)
			freed += 1

	# Inside a fold, the glue anchor in reach is the exit.
	if mode == Mode.SUBSPACE and _glue_within(origin, BURST_RADIUS):
		AudioManager.play_sfx(Sounds.BURST)
		try_exit()
		return

	# Then the folds — the ones that were unfoldable WHEN THE BURST FIRED, decided up
	# front. A stack under one diamond clears one layer per burst: releasing the newer
	# fold is what unblocks the older, and cascading into it would mean a single press
	# undid work you never asked it to reach. Snapshotting also makes the burst
	# deterministic, rather than depending on which unfolds happen to animate.
	# The burst itself, before the folds it releases: it is the gesture, and the
	# unfold it sets off should sound like a consequence of it. Only when
	# something actually came loose — the flash always fires, but a burst into
	# empty air is exactly the case the refusal below is for.
	var releasing: Array = _unfoldable_within(origin, BURST_RADIUS)
	if freed > 0 or not releasing.is_empty():
		AudioManager.play_sfx(Sounds.BURST)

	for fold in releasing:
		if animating():
			break
		unfold_level_fold(fold)
		freed += 1

	if freed == 0:
		_deny("Nothing here to release.")


## Is this anchor within `radius` of a point? False when it is unresolvable in the
## frame we are looking at — an anchor you cannot see is not one you can reach.
func _anchor_within(entry, origin: Vector2, radius: float) -> bool:
	var wp = anchor_point(entry)
	return wp != null and Vector2(wp).distance_to(origin) <= radius


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


## Arm a pair. Its fuse is its own — the mean of its two hands' — so pairs laid at
## different moments with different kinds go off in whatever order their fuses run
## out, not the order you laid them.
func _prime(a, b) -> void:
	var total: float = HandTypes.fuse_for(int(a["hand"]), int(b["hand"]))
	primed.append({"a": a, "b": b, "left": total, "total": total})
	# The fuse is the one thing in this game that goes off without you: it is
	# the only warning there is, and it plays over the hand you just placed.
	AudioManager.play_sfx(Sounds.PAIR_ARMED)


## Put an anchor back where it belongs: into a slot if you have one free and can
## reach it, otherwise onto the ground exactly where it was pinned.
func _release_anchor(entry, into_hand: bool) -> void:
	if into_hand and AnchorStock.first_empty(hands) >= 0:
		hands[AnchorStock.first_empty(hands)] = int(entry["hand"])
		return
	# Caught, and it is silent — the burst that caught it already spoke. Only a
	# hand that reaches the GROUND makes a sound of its own, because a hand on
	# the ground is a thing you now have to go and fetch.
	AudioManager.play_sfx(Sounds.HAND_DROP)
	var p := HandPickup.new()
	p.kind = int(entry["hand"])
	p.region = String(entry["region"])
	p.authored = false
	p.base_id = int(entry["bid"])
	p.bp = entry["bp"]
	_ensure_pickups(p.region).append(p)
	_refresh_pickup_visuals()


## Break a primed pair without folding it. Anchors within `reach` of `origin` come
## back to your hands; the rest drop where they were pinned.
##
## An anchor is already stored as exactly what a loose hand is — a base identity plus
## a point in that tile — so dropping one is a conversion rather than a placement, and
## it lands on the spot you chose rather than at your feet.
func _break_pair(pair: Dictionary, origin: Vector2, reach: float) -> void:
	primed.erase(pair)
	for entry in [pair["a"], pair["b"]]:
		var wp = anchor_point(entry)
		var caught: bool = wp != null and Vector2(wp).distance_to(origin) <= reach
		_release_anchor(entry, caught)


## A fold that would not go: every anchor of the pair drops where it was pinned.
## None of them come back to your slots — returning them would make a mistimed fold
## free, and the hands lying on the spots you chose still hold the shape of the fold
## you tried to make. Go and pick them up, or leave them and pin somewhere better.
func _scatter_pair(pair: Dictionary) -> void:
	primed.erase(pair)
	# The one place a refused fold is heard. Every refusal in `fire_pair` and
	# `do_fold` funnels through here, so the sound sits where the OUTCOME is
	# rather than being repeated at each of the six ways to reach it — and it
	# lands under the two hands hitting the ground, which say the rest.
	AudioManager.play_sfx(Sounds.FOLD_REFUSED)
	for entry in [pair["a"], pair["b"]]:
		_release_anchor(entry, false)


## Fire one primed pair. Called by its fuse, never by a keypress.
func fire_pair(pair: Dictionary) -> void:
	if animating():
		return
	var ca = anchor_cell(pair["a"])
	var cb = anchor_cell(pair["b"])
	if ca == null or cb == null:
		_show_flash("A hand lies beyond this fold.")
		_scatter_pair(pair)
		return
	if not WorldCore.anchors_valid(ca, cb):
		_show_flash("Both hands came down on one spot.")
		_scatter_pair(pair)
		return
	# The surface rules are asked HERE, not at placement: a tile that refuses to be
	# gripped is a fact about the fold, and the fold is what is happening now.
	if not WorldCore.can_anchor_at(pieces_by_pos, ca) \
			or not WorldCore.can_anchor_at(pieces_by_pos, cb):
		_show_flash("That surface would not hold a fold.")
		_scatter_pair(pair)
		return
	var pinned: Array[int] = [int(pair["a"]["hand"]), int(pair["b"]["hand"])]
	var committed := do_fold(ca, cb, pinned)
	if committed:
		# The fold is holding the SAME two hands that were pinned — they went from
		# your slots to the anchors to the fold without ever being duplicated.
		primed.erase(pair)
	else:
		# `do_fold` has already said why. The hands falling where they stood is the
		# rest of the answer, and it needs no words.
		_scatter_pair(pair)


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
	return unpaired.size() + primed.size() * AnchorStock.HANDS_PER_FOLD


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

## Is any pair counting down?
func fuse_running() -> bool:
	return not primed.is_empty()


## How far through its fuse a pair is, 0 (just lit) to 1 (folding now). The overlay
## pulses each pair's own anchors on its own number, so two armed folds beat at
## different rates and you can see which is closer to going.
func fuse_progress_of(pair: Dictionary) -> float:
	var total: float = pair["total"]
	if total <= 0.0:
		return 0.0
	return clampf(1.0 - float(pair["left"]) / total, 0.0, 1.0)


## The progress of whichever pair is closest to firing, or 0 if none is armed.
func fuse_progress() -> float:
	var best := 0.0
	for pair in primed:
		best = maxf(best, fuse_progress_of(pair))
	return best


## Run every armed pair's fuse down. A pair whose anchors are not BOTH resolvable in
## the frame we are looking at is PAUSED — walk through a door mid-count and that fold
## waits for you rather than firing somewhere you cannot see. It resumes when you come
## back, which is what makes leaving one armed a thing you can choose to do.
##
## Iterated over a copy: firing a pair re-derives the world and can scatter or move
## the others, so the list must not be mutated underneath the loop.
func _tick_fuse(delta: float) -> void:
	for pair in primed.duplicate():
		if animating():
			return
		if not primed.has(pair):
			continue
		if not anchor_here(pair["a"]) or not anchor_here(pair["b"]):
			continue
		pair["left"] = maxf(float(pair["left"]) - delta, 0.0)
		if pair["left"] <= 0.0:
			fire_pair(pair)


# ---------------------------------------------------------------------------
# Folding
# ---------------------------------------------------------------------------

## What a committed fold takes custody of.
##
## `fire_pair` passes the two hands that were actually pinned — they left your
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


## Commit a fold in the CURRENT space — the region, or a fold you are already
## inside, at any depth. One path, because a fold is a fold: what changes with
## depth is only which list it joins and which base pieces it is cut from.
##
## The fold takes custody of the two hands that were pinned — kinds and all — and
## gives those same two back when it is unfolded. (Authored pre-folds and trigger
## folds are anchored by the world and hold none: `Fold.held_hands` defaults to
## empty.)
##
## Two outcomes, and which one you get is decided by where the fold leaves YOU:
##
##   - **Ride.** Your base tile survives the fold, so you go where it goes.
##   - **PINCH.** It does not: you were in the band being excised, and the fold
##     swallows you. The fold is applied for real and the space it cut out becomes
##     the place you are standing in — pushed onto the context stack, however
##     many folds deep that already is. Folding yourself deeper used to be
##     refused here; there is no longer anything to refuse, because there is no
##     longer a second code path to be missing.
func do_fold(a1: Vector2i, a2: Vector2i, pinned: Array[int] = []) -> bool:
	var fold := Fold.create(next_fold_id, a1, a2, CS)
	var pre: Array = current_pieces
	var dropped := WorldCore.capture_strip(pre, fold, CS)
	if dropped.is_empty():
		_show_flash("Nothing there to fold.")
		return false
	if WorldCore.fold_blocked_by_tile(pre, fold, CS):
		_show_flash("Something in that span refuses to fold.")
		return false

	var from_piece = BaseFrame.piece_containing(pieces_by_pos, player.global_position, CS)
	var new_pieces := FoldReplay.apply_one_fold(pre, fold, CS)
	var dest = null
	if from_piece != null:
		dest = BaseFrame.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	else:
		# Over void: no fragment to ride, so fall back to crease arithmetic. Only
		# a point in the excised band has no side at all, and that is the pinch.
		var side := WorldCore.side_of_fold(player.global_position, fold)
		if side != 0:
			dest = player.global_position + WorldCore.fold_shift_for_side(side, fold, CS)

	if dest == null:
		# PINCH. The fold is applied for real, and you are inside what it took.
		_commit_fold(fold, dropped, pinned)
		var p := player.global_position
		var finalize_pinch := func() -> void:
			context.append(fold)
			_apply_context()
			_show_flash("Folded in." if context.size() == 1
				else "Folded in again — %d deep." % context.size())
		AudioManager.play_sfx(Sounds.PINCH)
		_play_transition(pre, fold, true, false, p, p, finalize_pinch)
		return true

	var landed := WorldCore.depenetrate(dest, PlayerBody.RADIUS,
		WorldCore.solid_polys_of(new_pieces))
	if landed == Vector2.INF:
		_show_flash("Fold blocked — nowhere for you to land.")
		return false
	_commit_fold(fold, dropped, pinned)
	var finalize_ride := func() -> void:
		rebuild()
		player.teleport(landed)
	AudioManager.play_sfx(Sounds.FOLD)
	_play_transition(pre, fold, true, true, player.global_position, landed, finalize_ride)
	return true


## Folding inside a fold is the same act as folding outside one. Kept as a name
## because that is how the tests and the design docs say it.
func do_sub_fold(a1: Vector2i, a2: Vector2i, pinned: Array[int] = []) -> bool:
	return do_fold(a1, a2, pinned)


## Take the fold into the world: claim its id, take custody of the hands, record
## its seam and add it to THIS level's list.
##
## Called at the point of no return, after every refusal — `_hands_for_fold`
## empties slots, and a fold rejected for a pin in its span must not have cost you
## the hands it never took.
func _commit_fold(fold: Fold, dropped: Array, pinned: Array[int]) -> void:
	next_fold_id += 1
	fold.held_hands = _hands_for_fold(pinned)
	seam_segs[fold.fold_id] = WorldCore.seam_segment(fold, dropped, CS)
	level_folds().append(fold)


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
		var piece = BaseFrame.piece_containing(pieces_by_pos, at + off, CS)
		if piece != null:
			loose_hands.append(
				HandPickup.dropped_at(kind, piece, at + off + fan, region_id))
			_refresh_pickup_visuals()
			AudioManager.play_sfx(Sounds.HAND_DROP)
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
		_deny("Blocked — a newer fold crosses this seam.")
		return
	var lvl_base: Array = level_base
	if _interior_glue_blocker(fold, lvl_base, list, idx) != null:
		_deny("Blocked — a fold inside it crosses its seam.")
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
	var from_piece = BaseFrame.piece_containing(pieces_by_pos, player.global_position, CS)
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
		_deny("Unfold blocked — nowhere for you to land.")
		return

	var was_newest := idx == list.size() - kids.size()
	var regained: int = fold.held_hands.size()
	# Before `_take_back`, which can drop a hand it cannot give you — this
	# should be the sound underneath that, not the other way round.
	AudioManager.play_sfx(Sounds.UNFOLD)
	_take_back(fold)
	var finalize := func() -> void:
		rebuild()
		player.teleport(landed)
		if regained > 0:
			_show_flash("Released — %d hands." % regained)
	if was_newest and kids.is_empty():
		_play_transition(new_pieces, fold, false, true,
			player.global_position, landed, finalize)
	else:
		finalize.call()


## Interior fold crossing the glue that locks the exit, or null.
##
## The glue asked about is the ENTERED fold's own — the seam you would come out
## through — not every axis the space repeats on. On a torus the other pair of
## glue lines belongs to a fold further out, and crossing those blocks that fold,
## which is a question for when you get there.
func exit_blocker() -> Fold:
	if sub_fold == null:
		return null
	for fold in level_folds():
		for seg in WorldCore.glue_segments(sub_fold, level_base):
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
		_deny("Blocked — an inner fold crosses the outer seam.")
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
				_deny("Blocked — a newer fold outside crosses this seam.")
				return

	var kids: Array = level_folds()
	plist.remove_at(idx)
	for k in range(kids.size()):
		plist.insert(idx + k, kids[k])
	interiors.erase(outer.fold_id)
	seam_segs.erase(outer.fold_id)

	var new_plvl := _compute_level(parent_path)
	var new_pieces: Array = new_plvl["pieces"]
	var from_piece = BaseFrame.piece_containing(pieces_by_pos, player.global_position, CS)
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
	# Coming out. The mirror of `PINCH`, and the pair is deliberate: going in
	# and coming out are one gesture heard from its two sides. `_apply_context`
	# swaps the music back in the finalize below.
	AudioManager.play_sfx(Sounds.SURFACE)
	_take_back(outer)
	var kept := not kids.is_empty()
	var surfaced := context.is_empty()
	var finalize := func() -> void:
		_apply_context()
		player.teleport(landed)
		if kept:
			_show_flash("Unfolded — your inner folds came out with you.")
		elif surfaced:
			_show_flash("Unfolded — you emerge where you walked to.")
		else:
			_show_flash("Up one — still %d folds in." % context.size())
	# The reverse transform is exact only for the newest fold of the level being
	# returned to, and only when nothing spliced into it. That holds at any depth,
	# so surfacing from three folds deep animates exactly as surfacing to the world
	# does — drawn against the PARENT's copies, which is the space it lands in.
	if idx == plist.size() - kids.size() and kids.is_empty():
		var parent_lattice := FoldLattice.for_path(parent_path, CS)
		var reach := WorldCore.camera_view_radius(
			get_viewport_rect().size, WorldCore.ZOOM_WIDEST)
		_play_transition(new_pieces, outer, false, true,
			player.global_position, landed, finalize,
			parent_lattice.offsets(reach, MAX_WRAP_COPIES))
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
	return BaseFrame.resolve_base_point(current_pieces, d["bid"], d["bp"])


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
	# Never mid-transition. A fold in flight owns the player's position until it
	# finalizes, and a door that moved them in the meantime would have its work
	# undone by that finalize — in the wrong region's coordinates.
	if animating():
		return
	var pair_id: String = doors[id]["pair"]
	var res = resolve_door(pair_id)
	if res == null:
		_deny("The door is dormant — its far side is split.")
		return
	var landed := WorldCore.depenetrate(
		res["pos"], PlayerBody.RADIUS, WorldCore.solid_polys_of(res["pieces"]))
	if landed == Vector2.INF:
		_deny("The way is blocked — something is folded over the door.")
		return
	_door_latch[pair_id] = true
	var into_fold: bool = not res["path"].is_empty()
	# A door you come out of INSIDE a fold is the pinch by another route, and it
	# should land as one — the door sound alone would undersell arriving
	# somewhere that is not the world.
	AudioManager.play_sfx(Sounds.PINCH if into_fold else Sounds.DOOR)
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
		p_from: Vector2, p_to: Vector2, finalize: Callable, copies: Array = []) -> void:
	if not anim_enabled:
		finalize.call()
		return
	var offs: Array = wrap_offsets if copies.is_empty() else copies
	var layer := Node2D.new()
	layer.z_index = 30
	# Inside `pixel_view`, with the geometry it stands in for. Parented to the
	# FoldWorld node instead it would be outside the render target and so outside
	# the camera's transform, drawing world coordinates as raw window pixels: the
	# map appears to fly off to one side for the length of the transition and snap
	# back when the real geometry returns.
	pixel_view.add_child(layer)

	# Three batches, not a node per fragment. The two flaps move by a TRANSLATION,
	# so each is one assignment per frame however many thousand fragments it holds;
	# only the strip, which collapses onto the meeting line, touches vertices at
	# all. A fold used to build (and immediately throw away) one Polygon2D per
	# fragment per copy, which is why folding a large region hitched.
	var shift_a := fold.shift_a_px(CS)
	var shift_b := fold.shift_b_px(CS)
	var groups := {"a": [], "b": [], "strip": []}
	for piece in pre_pieces:
		var res := CollisionCore.fold_polygons([piece.polygon], fold, CS)
		for poly in res["a"]:
			groups["a"].append({"piece": piece, "poly": CollisionCore.shift(poly, -shift_a)})
		for poly in res["b"]:
			groups["b"].append({"piece": piece, "poly": CollisionCore.shift(poly, -shift_b)})
		for poly in res["dropped"]:
			groups["strip"].append({"piece": piece, "poly": poly})
	var batches: Dictionary = {}
	for key in groups:
		var batch := TileBatch.new()
		layer.add_child(batch)
		batch.setup(_atlas, light_rig, base)
		batch.rebuild(groups[key], offs)
		batches[key] = batch

	geo.visible = false
	# The lamps belong to the pre-fold arrangement; the lighting itself stays
	# lit through the transition, so the flaps slide through standing light.
	light_rig.visible = false
	player.frozen = true
	_anim = {
		"layer": layer, "batches": batches, "fold": fold, "forward": forward,
		"collapse": collapse_strip, "progress": 0.0,
		"p_from": p_from, "p_to": p_to, "finalize": finalize,
	}
	_apply_anim_frame()


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
		geo.visible = true
		finalize.call()


func _apply_anim_frame() -> void:
	var p: float = _anim["progress"]
	var eased := p * p * (3.0 - 2.0 * p)
	var t := eased if _anim["forward"] else 1.0 - eased
	var fold: Fold = _anim["fold"]
	var batches: Dictionary = _anim["batches"]
	# The flaps: a whole batch each, moved by setting a position.
	(batches["a"] as Node2D).position = fold.shift_a_px(CS) * t
	(batches["b"] as Node2D).position = fold.shift_b_px(CS) * t
	if _anim["collapse"]:
		# The strip: a scale along the crease normal, about the meeting line. Applied
		# per COPY (see `TileBatch.deform`), because inside a fold every band
		# collapses onto its own seam rather than all of them onto one.
		var n := fold.crease_normal
		var meet_d := fold.shift_a_px(CS).dot(n)
		var c1 := fold.crease_point1
		(batches["strip"] as TileBatch).deform(func(v: Vector2) -> Vector2:
			return v + n * ((meet_d - (v - c1).dot(n)) * t))
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
		# A repeating space already shows every copy there is along the axes it
		# repeats on, so leading along one slides the view across identical bands
		# for nothing. On a torus that is both axes, and the lead is the body's
		# alone.
		"flat_axes": lattice.periods(),
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


## World points that would be a mistake to leave off screen right now.
func _camera_focus() -> PackedVector2Array:
	var pts := PackedVector2Array([player.global_position])
	# Every hand you have put down is part of a fold you are still composing or one
	# already ticking. Walk away and the frame opens to keep the spans you are
	# judging in view — the camera showing you how big your folds have got.
	for entry in all_anchors():
		var wp = anchor_point(entry)
		if wp != null:
			pts.append(Vector2(wp))
	# Inside a fold the band IS the room: frame the fundamental domain, so a wide
	# strip reads as the cylinder it is rather than a corridor with no visible
	# walls. On a torus that is all four walls, and it comes out of the same call.
	pts.append_array(lattice.domain_edges(player.global_position))
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

	_wrap_body()
	if lattice.is_flat() and player.global_position.y > (base.grid_size.y + 6) * CS:
		player.teleport(_spawn, false)
		AudioManager.play_sfx(Sounds.RESPAWN)
		_show_flash("You fell out of the world — respawned.")
	_tick_fuse(delta)
	# A fuse that just fired has started a fold TRANSITION, and the rest of this
	# frame belongs to it. Everything below reads the player's position and the
	# current fragment list, and during a transition both are mid-flight: the body
	# is frozen at where it started and the geometry does not rebuild until the
	# animation finalizes. Letting a door fire from that state teleported the player
	# to another region and then finalized the fold's landing — computed in the
	# region they had just left — on top of it, which is how you ended up in a wall.
	if animating():
		return
	_check_goal()
	_check_pickups()
	_check_triggers()
	_check_doors()


## Keep the body in the fundamental domain of whatever space it is in, and turn
## it back if it runs off an end that does not repeat.
##
## Walking through a glue line lands you in the next copy of the space — which is
## this one. The body slides back by a whole period and the CAMERA slides by the
## same vector: the space repeats with exactly that period, so the rendered frame
## is unchanged and the crossing is invisible. (Snapping the camera instead would
## throw away its smoothing lag and jolt the view by it.)
##
## Every axis at once, so a torus wraps in both directions in one step, and a
## region — with no axes at all — does nothing here.
func _wrap_body() -> void:
	var delta := lattice.wrap_delta(player.global_position)
	if delta != Vector2.ZERO:
		player.global_position += delta
		player.shift_camera(delta)

	# Running off the far end of a band does NOT force an exit (the exit can be
	# blocked by a crossing fold): the fold turns you back into itself. Only a
	# cylinder has such an end — a torus has nowhere to go, and a region has the
	# fall-out-of-the-world respawn instead.
	var free := lattice.free_axis()
	if free == Vector2.ZERO or free_extent.is_empty():
		return
	var tproj := player.global_position.dot(free)
	if tproj < float(free_extent["min"]) - 4.0 * CS \
			or tproj > float(free_extent["max"]) + 4.0 * CS:
		var period: Vector2 = lattice.periods()[0]
		var back := sub_fold.crease_point1 + period * 0.5
		var landed := WorldCore.depenetrate(back, PlayerBody.RADIUS, wall_polys)
		player.teleport(back if landed == Vector2.INF else landed, false)
		_cut_camera()
		# Same sound as falling out of the world, because it is the same event
		# seen from inside a fold: you left the sheet and were put back.
		AudioManager.play_sfx(Sounds.RESPAWN)
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
	rebuild()
	var landed := WorldCore.depenetrate(
		settled["player_pos"], PlayerBody.RADIUS, WorldCore.solid_polys_of(current_pieces))
	player.teleport(settled["player_pos"] if landed == Vector2.INF else landed)
	AudioManager.play_sfx(Sounds.TRIGGER)
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
		var wp = pickup.position_in(current_pieces)
		if wp == null:
			continue                # folded away — not here to be picked up
		if player.global_position.distance_to(Vector2(wp)) > PlayerBody.RADIUS + 8.0:
			continue
		hands[AnchorStock.first_empty(hands)] = pickup.kind
		loose_hands.remove_at(i)
		_refresh_pickup_visuals()
		AudioManager.play_sfx(Sounds.HAND_PICKUP)
		_show_flash("Picked up a %s hand." % HandTypes.type_name(pickup.kind))
		return


## Where every loose hand in the current view lies right now, as
## `[{"pickup", "pos"}, ...]`. The overlay draws these; a hand folded away resolves
## to nothing and is simply not in the list.
func loose_hand_points() -> Array:
	return HandPickup.resolve_all(current_pieces, loose_hands)


## Loose hands are drawn by the overlay, which redraws itself every frame, so there is
## nothing to rebuild — but taking or dropping one should also relight the scene, since
## a hand is a thing the player is looking for.
func _refresh_pickup_visuals() -> void:
	if overlay != null:
		overlay.queue_redraw()


func _check_goal() -> void:
	var touching := false
	for poly in goal_polys:
		if WorldCore.circle_overlaps_polygon(player.global_position, PlayerBody.RADIUS, poly):
			touching = true
			break
	if touching and not _on_goal:
		AudioManager.play_sfx(Sounds.GOAL)
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
		geo.visible = true       # the transition had hidden the sheet it stands in for
	_hold_active = false
	_hold_fired = false
	_burst_flash_left = 0.0
	context.clear()
	_setup_all()
	AudioManager.play_sfx(Sounds.RESET)
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
	help.text = "A/D move   Space tap/hold: jump   W/S aim   F tap: place hand · hold: pull back   R reset"
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
	if not primed.is_empty():
		stock += "   %d armed" % primed.size()
	if context.is_empty():
		_status.text = "Region: %s   Folds: %d   Mode: WORLD\n%s" \
			% [region_id, folds.size(), stock]
	else:
		# How deep, and what shape the space you are in has come out: one period is
		# a cylinder you can run off the ends of, two is a torus with no outside.
		_status.text = "Region: %s   Folds: %d   Mode: INSIDE FOLD x%d — %s (%d inner)\n%s" \
			% [region_id, folds.size(), context.size(), _space_name(),
				level_folds().size(), stock]


## What shape the space you are standing in is, from how many ways it repeats.
func _space_name() -> String:
	match lattice.depth():
		0: return "cut open"
		1: return "cylinder"
		_: return "torus"


func _show_flash(text: String) -> void:
	if text.is_empty():
		return
	_flash.text = text
	_flash.visible = true
	_flash_left = 2.5


## A refusal: the message, and the sound that goes with every refusal that has
## no more specific one of its own.
##
## Refusals are the one class of event worth funnelling, because there are a
## dozen of them and they all mean the same thing to the player — "that did not
## happen". Kept apart from `_show_flash` because that also carries good news
## ("Folded in.", "Picked up a plain hand."), and a game that beeps at you for
## succeeding is worse than one that says nothing. `Sounds.DENY` carries the
## retrigger floor that keeps a per-frame refusal from becoming a drone.
func _deny(text: String) -> void:
	AudioManager.play_sfx(Sounds.DENY)
	_show_flash(text)


## Match the bed to where the player is. `play_music` ignores a request for the
## track already playing, so this is safe to call whenever the context changes
## and costs nothing when it has not.
##
## Inside a fold is a different PLACE, and the open question in AGENTS.md is
## whether it reads as one. This is the cheapest honest answer: the interior
## has its own bed, and crossing the boundary crossfades between them.
func _update_music() -> void:
	AudioManager.play_music(Sounds.MUSIC_SUBSPACE if mode == Mode.SUBSPACE
		else Sounds.MUSIC_OVERWORLD)
