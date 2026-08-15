extends Node2D

## FoldWorld
##
## The game. The fold kernel (BaseGrid / Fold / FoldReplay / CollisionCore /
## BaseFrame) drives a side-view world with gravity and a free-moving player.
##
## Structure:
##   - REGIONS: each region is its own sheet — a BaseGrid + persistent fold
##     list + per-fold inner folds. Fold state survives leaving.
##   - CONTEXT STACK: the player is in a region, and optionally inside a
##     stack of folds (subspaces), ARBITRARILY DEEP. Each space derives purely:
##     the space's base pieces are the parent space's strip content of the
##     entered fold, and its fold list is that fold's persistent inner folds.
##   - ONE SPACE AT A TIME. There is no region path and subspace path; there
##     is the CURRENT SPACE, and the region world is the space with an
##     empty context. Its periodicity is a `FoldLattice`: no periods in a
##     region, one inside a fold, TWO inside a fold whose creases run across
##     the fold outside it — at which point you are walking on a torus. Every
##     part of the view (terrain, the body, the hands, the markers, the lights,
##     the colliders, the camera) asks that one object how the space repeats,
##     which is why folding yourself deeper needed no new rendering.
##   - DOORS are warp POINTS at base-tile centers: they ride folds with the
##     tile, and traversal resolves the partner point RECURSIVELY — region
##     world first, then fold strips, then subspaces — so a folded-away door
##     delivers you INSIDE that fold's subspace, and a door inside a strip
##     leads out to wherever its partner is. A point exactly on a cut (door
##     split down the middle) is DORMANT until the halves rejoin. Traversal
##     is auto-on-overlap, edge-triggered, refused if the far side is
##     dormant or the landing is blocked ("something folded over the door").
##   - Exiting a subspace by its glue anchor UNFOLDS it (inner folds splice
##     into the parent at its index); walking out through a door leaves the
##     fold folded, subspace state and all. Unfold blocking is uniform:
##     newer folds crossing a seam block it, inner folds crossing a glue
##     block the outer fold from either side.
##   - HANDS ARE A CARRIED, CONSERVED RESOURCE (`HandStock`). A standing
##     fold is holding two of yours, so the budget is how many folds may stand
##     at once, not how many you may ever make; unfolding refunds them because
##     the fold leaves the list. A loose hand you walk over does NOT raise the
##     ceiling — two slots is forever; it refills one you emptied by pinning.
##   - LIGHTS are occupants like doors: base identity + a point in the tile,
##     resolved through BaseFrame against whatever is on screen. Fold a lamp
##     away and it leaves the region and lights the fold's subspace
##     instead (see LightSource). Fold something else and it rides the flap.
##
## ONE KEY drives all of it. Tap = push anchors in; hold and then LET GO = pull them
## back out (retrieve a pending anchor, unfold the fold you are standing at, or exit
## a subspace by its glue anchor). Both gestures land on the release: holding only
## charges the burst, and the body wears the charge as a colour. There is no remote
## unfold: to get the anchors out of a fold you must go back to its seam.
##
## Pushing one in takes TWO taps and STOPS TIME between them. The first raises the
## hand you are about to spend into a cursor and freezes the world; the movement keys
## walk that cursor over the cells within arm's reach, diagonals included; the second
## pins it there and time resumes with exactly the momentum, fuses and flight it was
## carrying. A charged release while the hand is up is still a pop — it cancels the
## placement, fires the burst and resumes the same way. See §"Placing a hand".
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

## The player has asked to leave this run — Escape.
##
## What leaving MEANS is deliberately not decided here: a run launched from the editor
## goes back to the editor, one launched from the launcher goes back to the launcher,
## and one launched from a command line has nowhere to go, so nothing is connected and
## Escape does nothing. `Shell` is what listens. See `docs/features/SHELL.md`.
signal left

## The world this scene plays when nothing says otherwise. See `WorldData.SHIPPED_WORLD`,
## which is where the path itself lives — the game, the editor and the launcher all
## mean the same file by it.
const WORLD_PATH := WorldData.SHIPPED_WORLD
const CS := WorldCore.CELL
## The screen effect that says the world is being held. See the shader's own header.
const HELD_SHADER_PATH := "res://assets/shaders/held.gdshader"
## How long the held look takes to close over the world, and to let go again. Short
## enough to feel like a grip rather than a transition, long enough that the dither
## dissolves in visibly rather than appearing whole.
const HELD_EASE := 0.09
## How much ground around the body the held look leaves entirely alone, in cells, and
## how far it takes to close in past that.
##
## The clear radius covers the reach box with room to spare — its far corner is 1.5
## cells out on both axes, so about 2.1 away — because the cells you are choosing
## between are the one part of the frame that must be seen through nothing at all. The
## fade is wide so the checker THINS toward you rather than ending at a line.
const HELD_CLEAR_CELLS := 2.6
const HELD_FADE_CELLS := 2.4
## Anchors are pinned at ARM'S LENGTH: any of the nine cells centred on the one you
## are standing in. What you can PIN is exactly what you can stand next to.
##
## Not to be confused with a hand's SPAN (`HandTypes.span`), which is how far a pinned
## anchor reaches for a PARTNER. This is how far your arm goes; that is how far the
## fold goes. They were both called reach once, which is why one of them is not now.
##
## A square of this radius, not a compass direction — the four axis-aligned cells the
## old 4-way pointing could name were a limit of the INPUT, not of your arm, and cells
## you could obviously touch were unpinnable for no reason a player could see.
##
## Raising this is a design change, not a tuning knob: a shell one tile thick keeps
## you out of what it encloses only while your reach is one cell (see
## `WorldCore.within_arm_reach`), and the sealed chamber is exactly that shell.
const ARM_REACH := 1
const ANIM_TIME := 0.24
## How long the fold key must be held before the release reads as "pull back"
## rather than "push in". Long enough that a tap never trips it by accident.
##
## It is a LOADING time, not a delay before something happens: nothing fires at the
## threshold, it only decides which way the release will go. Lengthening it costs
## the player nothing but the wait — no window closes while they hold.
const HOLD_TIME := 0.35
## Reach of the burst, in world units. About a tile and a third — the burst is a
## thing you do to the space you are standing in, not a thing you aim, so its reach wants
## to be forgiving enough that standing *near* a seam clears it. Tuned up from 1.2: at a
## tile the burst kept missing seams that looked well within it, which reads as the key
## not working rather than as a reach you misjudged.
const BURST_RADIUS := 1.3 * CS
## How long the burst ring stays drawn.
const BURST_FLASH := 0.35
## How far out the lamps of a repeating space are copied. The space repeats
## forever; only the nearest `LightRig.MAX_LIGHTS` reach the shader anyway, so
## copying every visible copy would just crowd the near ones out.
const LIGHT_COPY_REACH := 10.0 * CS
## Ceiling on how many copies of a repeating space are drawn. A one-cell fold
## repeats every cell and a torus squares whatever a cylinder costs, so the
## count the frame asks for has to be bounded somewhere.
const MAX_WRAP_COPIES := 121
## Sideways kick given to a hand thrown loose, in world units/s. Enough that two hands
## out of one fold visibly separate; small enough that neither sails away, since the
## ball's air drag eats it within a few tenths of a second.
##
## Bounded by something concrete: a burst fired standing still must leave its hands
## inside `PlayerBody.RADIUS + 8` of you, or bursting at your feet hands you a pair you
## then have to walk after — which reads as the game taking them away. At 90 they landed
## 30 units out against a 28-unit reach, which is exactly the sort of two-unit miss that
## feels like a bug rather than a distance. `test_a_burst_leaves_its_hands_within_reach`
## is what holds this honest if the physics is ever retuned.
const TOSS_SPEED := 55.0
## ...and the upward part of that kick. A hand that pops UP before it falls reads as
## released; one that only slides sideways reads as dropped.
const TOSS_LIFT := 110.0

## Which world THIS instance loads. Empty means "decide normally": the `--world=`
## flag if one was passed, else `WORLD_PATH`.
##
## Set it before the node enters the tree. It exists so the scene-driven tests can
## pin themselves to a world the SUITE owns rather than to whichever world happens
## to be shipping — the coupling that let one commit re-point `WORLD_PATH` and fail
## 60 kernel tests that had nothing to do with the change. See
## `worlds/fixtures/README.md`.
var world_override := ""

## The world to run as a document already in MEMORY rather than a file on disk. Set
## for a playtest: the editor hands over the world you are looking at, unsaved edits
## and all, so trying a change does not mean committing it to the file first.
##
## Wins over `world_override` and `--world=`, and is CLONED at every setup — a run
## binds lights, loose hands and anchors into what it is given, and what it was given
## is a document the editor is still holding. That clone is also why `R` is exact:
## it re-derives from the authored document rather than from what the last few
## minutes of play did to it.
var data_override: WorldData = null

## Where this run drops the player in: `{"region": String, "cell": Vector2i}`, or `{}`
## for wherever the world itself says. The cell is optional — naming only a region
## starts you at that region's authored spawn.
##
## It becomes that region's spawn for the whole run rather than just the first frame,
## so `R` and falling out of the world both bring you back to it. A playtest you have
## to walk back across two regions to resume is a playtest you run once.
var spawn_override := {}

## One line of chrome about how to leave, shown top-right: "Esc — back to the editor".
## Set by whoever opened this run, because where back IS is not a fact the world holds
## — see `left`.
var session_hint := ""

## The authored world (regions, doors, pre-placed folds).
var world_data: WorldData

# --- Regions ---
## region id -> {"base", "folds", "seam_segs", "inner_folds", "spawn"}
var regions: Dictionary = {}
## The space the player is standing in right now. Everything below that describes
## the current space is a VIEW onto this object rather than a member of its own —
## the state lives in one place that can be passed to a collaborator, while the
## hundred-odd existing call sites (and the tests) go on reading `world.lattice`,
## `world.mode`, `world.pieces_by_pos` exactly as before.
##
## Migrating those call sites to `space.x` and deleting these properties is a
## mechanical follow-up; having the object at all is what unblocks anything else.
var space := Space.new()

var region_id: String:
	get: return space.region_id
	set(v): space.region_id = v
## Doors: id -> {"region", "cell", "bid", "bp", "pair"}. Points, not tiles.
var doors: Dictionary = {}
var _door_latch: Dictionary = {}
## Lights: region id -> Array[LightSource], bound to their base tiles.
var region_lights: Dictionary = {}

# --- Current region working state (views into regions[region_id]) ---
var base: BaseGrid:
	get: return space.base
	set(v): space.base = v
var folds: Array[Fold] = []
var seam_segs: Dictionary = {}
## fold_id -> Array[Fold]: a fold's inner folds, persistent while it lives.
var inner_folds: Dictionary = {}
## Loose hands lying in THIS region (a view into `hand_pickups`).
var loose_hands: Array = []
var _spawn: Vector2:
	get: return space.spawn
	set(v): space.spawn = v

## Loose hands, region id -> Array[HandPickup]. Authored loose hands and hands that popped
## out of a burst are the SAME list and the same object — to the player they are the
## same thing, a hand on the ground — and only `_reset` reads `authored` to tell them
## apart. Lives outside `regions` so a region rebuild cannot silently drop them.
var hand_pickups: Dictionary = {}

var next_fold_id := 0
## Base tile the player last fired a trigger check against — triggers are edge-fired
## on entering a tile, not re-fired every frame you stand on it.
var _trigger_latch := -1
## Kept as the enum the rest of the file and the tests read, backed by the kernel's
## plain bool — `Space` may not name a view type (Decision 9).
var mode: Mode:
	get: return Mode.SUBSPACE if space.in_subspace else Mode.WORLD
	set(v): space.in_subspace = (v == Mode.SUBSPACE)
## Path of entered folds (outermost first). Empty = region world.
var context: Array[Fold] = []

## Every anchor standing anywhere in the world — the hands you have put down AND the
## ones the world drove in. One list, and which two of them are about to fold together
## is DERIVED from where they are. See `AnchorField`.
##
## A pinned anchor is a hand that has LEFT you: out of its slot from the moment you
## place it, back only when you go and release it. A bolted one was never yours.
##
## There is no fixed number of anchors, and — since pairing stopped being an event —
## no fixed number of UNPAIRED ones either. Put a hand down out of everything's reach
## and it simply stands there, which is the whole of what "more than two hands in the
## world" means.
var field := AnchorField.new()

## The hands you are carrying: one entry per slot, a `HandTypes` id or null.
## See `HandStock` — this array is the whole of your possession.
var hands: Array = []

## Hands currently IN FLIGHT: light balls falling, rolling and settling.
##
## Each is `{"kind": int, "pos": Vector2, "vel": Vector2, "resting": bool,
## "region": String, "in_sub": bool, "seed": float}`. Stepped by
## `WorldCore.hand_ball_step`; the moment one comes to rest it leaves this list and
## becomes a `HandPickup` occupant (`_land_ball`).
##
## This is the ONE place in the game where something in the world holds a position of
## its own, and it is deliberately transient. `AGENTS.md` §8 forbids caching a world
## position on a thing that lives in the world, because the piece list is the only
## authority on where anything is — and that rule is what makes a hand ride flaps and
## fold away into subspaces. A ball keeps a position for a second or two of flight and
## nothing persists it, so nothing that outlives the flight has one.
##
## A ball is still transported by folds like everything else: `_carry_balls_through`
## maps each through `BaseFrame` exactly as the player is, so a hand in flight that a
## fold sweeps into a subspace goes on flying INSIDE that subspace with its velocity
## intact. Folds are translations, so its flight is unaffected by the move.
##
## `in_sub` tags which view a ball is flying in, for the same reason anchors carry
## their region: a region and a subspace are different spaces, and a ball
## must only be stepped, drawn and collided against the one it is actually in.
## Hands in the air. `HandField` owns the flight; this object owns what a hand
## becomes when it stops flying. See HandField.
var hand_field := HandField.new()

var hand_balls: Array:
	get: return hand_field.balls

# --- Fold-key hold tracking (tap = place a hand, hold = pull one back) ---
# Both gestures land on the RELEASE; the hold only decides which one it was. There
# is no "already fired" state any more, because nothing fires while the key is down.
var _hold_active := false
var _hold_elapsed := 0.0

## Where the placement cursor is, or null when no hand is up. **Its emptiness IS the
## mode** — there is no second flag that could disagree with it, the same shape as
## `_anim` / `animating()` and `sub_fold` / `mode`.
##
## While it is set, time is stopped: `_physics_process` returns before it moves
## anything and the body is `frozen`, so nothing is saved and nothing is restored. The
## world simply is not stepped, which is why resuming keeps the exact momentum, the
## exact fuses and the exact hands in flight it was left with.
var _aim = null

## Seconds left on the burst ring the overlay draws, and the sphere it is drawing.
##
## Recorded when the burst FIRES rather than read back per frame: a burst belongs to
## the moment it went off, and neither of these is a fact about where the player is now
## — a plate's burst is centred on the plate and reaches as far as the plate says.
var _burst_flash_left := 0.0
var _burst_at := Vector2.ZERO
var _burst_radius := BURST_RADIUS

# --- The fuses live on the pairs, and the pairs are derived; see `AnchorField`. ---

# --- The CURRENT SPACE (derived from `context` by _apply_context) ---
# One set of these, not one per mode. The region world is the space whose context
# is empty; everything below reads these regardless of how deep you are folded in.

## Identity pieces of this space: the region's base at the top, the entered
## fold's strip content at every depth below it.
var space_base: Array:
	get: return space.base_pieces
	set(v): space.base_pieces = v
## ...with this space's folds replayed over it. The geometry on screen.
var current_pieces: Array:
	get: return space.pieces
	set(v): space.pieces = v
var pieces_by_pos: Dictionary:
	get: return space.pieces_by_pos
	set(v): space.pieces_by_pos = v
var wall_polys: Array:
	get: return space.wall_polys
	set(v): space.wall_polys = v
var goal_polys: Array:
	get: return space.goal_polys
	set(v): space.goal_polys = v
var _on_goal := false

## How this space repeats. Flat in a region, a cylinder inside a fold, a torus
## inside two crossing ones. The single source of truth for the wrap — copies,
## colliders, the body's wrap-around, the camera's framing and the lights all
## come off this.
var lattice: FoldLattice:
	get: return space.lattice
	set(v): space.lattice = v
## Where the copies of this space are drawn, nearest first, always including
## ZERO. Handed to every `WrapCanvas` and baked into the terrain batch.
var wrap_offsets: Array:
	get: return space.wrap_offsets
	set(v): space.wrap_offsets = v
## Content extent along the one direction a cylinder does NOT repeat in — the way
## you can run off the end of a strip. Unused when the space is flat or a torus.
var free_extent: Dictionary:
	get: return space.free_extent
	set(v): space.free_extent = v

## The innermost entered fold, or null at region space. Convenience: it is always
## `context.back()`.
var host_fold: Fold:
	get: return space.host_fold
	set(v): space.host_fold = v

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
## The held look, on the rect that composites the render target. Null when the shader
## is missing.
var _held_mat: ShaderMaterial
## How far into the held look the screen is, 0..1. Eased on WALL time, not world time:
## it is the effect that announces the stop, so being stopped by it would leave the
## world frozen behind a screen that never finished saying so.
var _held := 0.0
## Decides what the camera should be showing; drives the body's lens and the
## render target. See WorldCamera.
var camera: WorldCamera
var _atlas: Texture2D
## The window-resolution overlay (background, controls line, status, flash).
## It is told what to say; it does not read this object. See WorldHud.
var hud: WorldHud


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
	# the player could reach. Both are rebuilt whenever the space changes.
	geo = TileBatch.new()
	geo.z_index = 0
	pixel_view.add_child(geo)
	solid = StaticBody2D.new()
	pixel_view.add_child(solid)

	pixel_view.add_child(light_rig)

	player = PlayerBody.new()
	player.z_index = 40
	pixel_view.add_child(player)

	camera = WorldCamera.new(player, pixel_view)

	# A ball stops being a ball in exactly two ways, and both are the world's business
	# rather than the flight's: it comes to rest and becomes an occupant of the sheet,
	# or it leaves the world and has to be put back somewhere findable.
	hand_field.landed.connect(_land_ball)
	hand_field.lost.connect(_recover_lost_hand)

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
	# The whole world composites through here, which makes it the one place that can
	# speak for all of it at once — so the held look lives on this rect rather than on
	# anything in the scene. The HUD is a layer above and is deliberately not covered:
	# the readout describing the stop must not be dimmed by it.
	if ResourceLoader.exists(HELD_SHADER_PATH):
		_held_mat = ShaderMaterial.new()
		_held_mat.shader = load(HELD_SHADER_PATH)
		_held_mat.set_shader_parameter("held", 0.0)
		# Cells are the unit the design thinks in; art pixels are the unit the shader
		# measures in. Converted once, here, rather than in the shader — which has no
		# business knowing how big a cell is.
		var per_cell := CS / PixelArt.WORLD_PER_PIXEL
		_held_mat.set_shader_parameter("clear_radius", HELD_CLEAR_CELLS * per_cell)
		_held_mat.set_shader_parameter("clear_fade", HELD_FADE_CELLS * per_cell)
		view.material = _held_mat
	else:
		# No shader, no effect, and the game is otherwise unchanged — the stop is
		# still legible from the HUD and from nothing moving.
		push_warning("FoldWorld: %s missing — the held look is off." % HELD_SHADER_PATH)
	screen.add_child(view)


func _setup_all() -> void:
	next_fold_id = 0
	regions = {}
	region_lights = {}
	_door_latch = {}
	field.clear()
	hand_pickups = {}
	# A hand in flight is a hand mid-event. A reset ends the event.
	hand_field.clear()

	world_data = _source_world()
	if world_data == null:
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
			# One clip pass, both halves — see FoldReplay.fold_and_capture.
			var cut := FoldReplay.fold_and_capture(pieces, f, CS)
			rsegs[f.fold_id] = WorldCore.seam_segment(f, cut["dropped"], CS)
			rfolds.append(f)
			pieces = cut["pieces"]
		regions[id] = {"base": rbase, "folds": rfolds, "seam_segs": rsegs,
			"inner_folds": {}, "spawn": world_data.spawn_px(id)}

		# Authored loose hands bind exactly as lights do — a hand on the ground has no
		# world position either, only a base identity the configuration is asked about.
		#
		# Then they are SETTLED. A hand is authored by naming a cell, which puts it at
		# that tile's centre — half a cell up in the air. That was invisible when a
		# resting hand was wherever it was stored, but now that a hand can be woken by a
		# fold taking its ground away, "resting" has to mean the same thing for an
		# authored loose hand as for one that fell there: otherwise the first fold anywhere
		# near one drops it, because it was never really on the ground to begin with.
		var region_hands: Array = []
		for pickup in world_data.hands_of(id):
			if pickup.bind(rbase):
				_settle_authored(pickup, pieces)
				region_hands.append(pickup)
			else:
				push_error("FoldWorld: hand pickup in %s sits outside the region" % id)
		hand_pickups[id] = region_hands

		# Anchors the world has driven into its own sheet. They bind exactly as lights
		# and loose hands do — a base identity, no world position — and from here on
		# they are anchors like any other: they ride folds, they pair, and the ones
		# that reach each other light a fuse. What they are not is HANDS
		# (`Anchor.BOLTED`), so a burst does not answer for them and the ledger does
		# not count them.
		var region_anchors: Array = []
		for anchor in world_data.anchors_of(id):
			if anchor.bind(rbase):
				region_anchors.append(field.add(anchor))
			else:
				push_error("FoldWorld: anchor in %s sits outside region %s" % [id, id])
		Anchor.link_pairs(region_anchors)

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

	_load_region(_start_region())
	context.clear()
	_apply_context()
	_apply_spawn_override()
	player.teleport(_spawn, false)
	_cut_camera()


## The authored world this run is of, built fresh every time — including on `R`.
##
## Three doors, tried from the most specific: a document handed over in memory (a
## playtest), a path this instance was pinned to (a test fixture), and then the
## `--world=` flag or the shipped world. See `data_override` for why the document is
## cloned rather than used.
func _source_world() -> WorldData:
	if data_override != null:
		return data_override.clone()
	var path := world_override if not world_override.is_empty() \
		else WorldData.selected_path(WORLD_PATH)
	var loaded := WorldData.load_from(path)
	if loaded == null:
		push_error("FoldWorld: could not load %s" % path)
	return loaded


## Which region this run starts in: the one the spawn override names, else the world's.
func _start_region() -> String:
	var rid := String(spawn_override.get("region", ""))
	if rid.is_empty():
		return world_data.start_region
	if not regions.has(rid):
		push_error("FoldWorld: no region called %s to start in" % rid)
		return world_data.start_region
	return rid


## Move the starting region's spawn onto the cell the override names.
##
## Resolved through the CURRENT pieces rather than used as a world point: a cell in a
## region with a pre-placed fold in it has been carried somewhere by that fold, and
## dropping the player at its base coordinates would put them where that part of the
## sheet used to be. A cell the fold took away entirely resolves nowhere, and the
## region's own spawn is the honest answer — a strip is not a place you can start in.
##
## Nothing is asked about what is IN the cell. Spawning inside a wall is a thing you
## can do by clicking on one, and the depenetration in the frame below pushes you back
## out of it — refusing would make "play from here" a tool that argues with you.
func _apply_spawn_override() -> void:
	if not spawn_override.has("cell"):
		return
	if region_id != String(spawn_override.get("region", "")):
		return
	var cell: Vector2i = spawn_override["cell"]
	var tile := base.tile_at(cell)
	if tile == null:
		push_error("FoldWorld: cell %s is outside region %s" % [cell, region_id])
		return
	var at = BaseFrame.world_point_from_base(current_pieces, tile.base_id, cell_center(cell))
	if at == null:
		_show_flash("That cell is folded away — started at the region's spawn.")
		return
	_spawn = at
	regions[region_id]["spawn"] = at


func _take_fold_id() -> int:
	next_fold_id += 1
	return next_fold_id - 1


func _load_region(id: String) -> void:
	region_id = id
	var r: Dictionary = regions[id]
	base = r["base"]
	folds = r["folds"]
	seam_segs = r["seam_segs"]
	inner_folds = r["inner_folds"]
	_spawn = r["spawn"]
	loose_hands = _ensure_pickups(id)


## Drop an authored hand onto the ground under the cell it was authored in.
##
## An authored hand names a CELL, and the natural reading of that is "a hand lying on the
## ground there" — not "a hand hovering at the exact centre of that tile", which is where
## naming a cell actually puts it. Settling at load makes the two agree, so an authored
## loose hand and a hand that fell where it lies are the same kind of thing in every respect.
##
## Rebinds the pickup to whatever piece it came to rest on, because that is the tile it
## is now lying on and therefore the one whose folds it must ride.
func _settle_authored(pickup: HandPickup, pieces: Array) -> void:
	var wp = pickup.position_in(pieces)
	if wp == null:
		return                  # sealed inside a pre-fold; it settles when it surfaces
	var solids := WorldCore.solid_polys_of(pieces)
	var rest := WorldCore.settle_hand(Vector2(wp), solids)
	var piece = BaseFrame.piece_at(pieces, rest, CS)
	if piece == null:
		return                  # nothing under it; leave it authored as written
	pickup.base_id = piece.base_id
	pickup.bp = rest - piece.src_offset


## The loose hands in a region, creating the list on first ask.
func _ensure_pickups(id: String) -> Array:
	if not hand_pickups.has(id):
		hand_pickups[id] = []
	return hand_pickups[id]


# ---------------------------------------------------------------------------
# The current space: derived state -> visuals + colliders
# ---------------------------------------------------------------------------
# ONE space is on screen at a time — the region world is simply the space whose
# context is empty. There is no second set of anything here: one derivation, one
# batch of geometry, one body of colliders, one lattice saying how it repeats.

## Rebuild the geometry of the current space from its base pieces and fold list.
##
## Everything that draws is either baked here (the sheet, whose copies cost only
## vertices) or a `WrapCanvas` that repeats itself (the body, the hands you carry,
## the markers). Nothing in between, and nothing that has to be taught about folds.
func rebuild() -> void:
	current_pieces = space_base.duplicate()
	for fold in space_folds():
		current_pieces = FoldReplay.apply_one_fold(current_pieces, fold, CS)
	pieces_by_pos = BaseFrame.index_by_pos(current_pieces)
	wall_polys = WorldCore.solid_polys_of(current_pieces)
	goal_polys = WorldCore.polys_of_type(current_pieces, TileTypes.GOAL)
	_build_terrain()
	_build_colliders()
	_refresh_lights()


## Draw the sheet. Every piece of every visible copy goes into one batch, which
## resolves to two Polygon2Ds — one for what stops you, one for what you move
## through. A region is ~800 tiles and a strip is drawn in every copy it repeats
## into; a node per piece per copy was thousands of nodes torn down and rebuilt
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
## so it can never be more than one copy out — three copies down a cylinder, nine
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
## nearest `LightRig.MAX_LIGHTS`, so copying every visible copy would crowd out
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


## The fold list of the CURRENT space: the region's folds, or the entered
## fold's persistent inner folds — at whatever depth that is.
func space_folds() -> Array:
	if context.is_empty():
		return folds
	return _ensure_inner_folds(context.back().fold_id)


func _ensure_inner_folds(fid: int) -> Array:
	if not inner_folds.has(fid):
		var arr: Array[Fold] = []
		inner_folds[fid] = arr
	return inner_folds[fid]


## Derive the state of a space addressed by a fold path (pure, from region
## working state). Returns {"base_pieces", "space_folds", "pieces"}.
##
## Recursive in the path, so it is indifferent to depth: each step captures the
## strip of the next fold out of the prefix of its own space. That is why folding
## yourself deeper needed nothing new here.
func _compute_space(path: Array) -> Dictionary:
	var sp_base: Array = FoldReplay.identity_pieces(base)
	var sp_folds: Array = folds
	for F in path:
		var i: int = sp_folds.find(F)
		var prefix: Array = sp_base.duplicate()
		for k in range(i):
			prefix = FoldReplay.apply_one_fold(prefix, sp_folds[k], CS)
		# A fold takes what is in front of it in the sheet it is cut FROM. Where a
		# strip runs past a glue line it finds the end of that sheet rather than the
		# next copy of it — see `FoldLattice` §"What the strip contains".
		sp_base = WorldCore.capture_strip(prefix, F, CS)
		sp_folds = _ensure_inner_folds(F.fold_id)
	var pieces: Array = sp_base.duplicate()
	for f in sp_folds:
		pieces = FoldReplay.apply_one_fold(pieces, f, CS)
	return {"base_pieces": sp_base, "space_folds": sp_folds, "pieces": pieces}


## Make the view match `context` — at any depth. The region world is the empty
## context and takes the same path as everything else.
func _apply_context() -> void:
	host_fold = null if context.is_empty() else context.back()
	mode = Mode.WORLD if context.is_empty() else Mode.SUBSPACE
	space_base = _compute_space(context)["base_pieces"]
	lattice = FoldLattice.for_path(context, CS)

	# How many copies to draw: enough to fill the WIDEST frame the camera can pull
	# out to, not the current one. The count is fixed when the space is built, and
	# a visible end to the repetition would break the wrap the moment the lens
	# opened.
	var reach := WorldCore.camera_view_radius(get_viewport_rect().size, WorldCore.ZOOM_WIDEST)
	wrap_offsets = lattice.offsets(reach, MAX_WRAP_COPIES)
	for canvas in _wrap_canvases():
		canvas.set_offsets(wrap_offsets)

	# The one direction a cylinder does not repeat in — the way you can run off
	# the end of a strip, and so the only one that needs a turn-back.
	var free := lattice.free_axis()
	free_extent = WorldCore.strip_extent(space_base, free) if free != Vector2.ZERO else {}

	# Deeper reads darker and more lavender; the sheet's tint follows in the rig.
	hud.set_depth(context.size())
	geo.visible = true
	rebuild()
	_update_music()


## The glue lines of the current space: where its copies are identified. Two down
## a cylinder, four around a torus — one pair per axis of the lattice, drawn so
## the wrap reads as a real join rather than a rendering glitch.
func glue_lines() -> Array:
	if lattice.is_flat() or space_base.is_empty():
		return []
	var out: Array = []
	for period in lattice.periods():
		var n: Vector2 = (period as Vector2).normalized()
		var t := Vector2(-n.y, n.x)
		var ext := WorldCore.strip_extent(space_base, t)
		var base_d := lattice.domain_start(n)
		for d in [base_d, base_d + (period as Vector2).length()]:
			out.append(PackedVector2Array([
				n * d + t * ext["min"], n * d + t * ext["max"]]))
	return out


## Every seam with a presence in the space you are standing in: this space's own
## folds, and the folds of the spaces OUTSIDE it whose seams the strip took in with it.
##
## Each mark is `{"fold", "segs", "at", "outer"}` — the line where it lies now, the
## meeting point a burst measures to (null when nothing of it is in here), and whether
## the fold belongs to a space you are not standing in.
##
## Two things make this one walk rather than a query per space:
##
##   - **A seam moves.** The recorded segment is a statement about the configuration it
##     was recorded in, and every fold made afterwards slides the sheet under it. So it
##     is carried down the list, one fold at a time. It can come back as two where a
##     later fold cut it, and as none where one swallowed it whole.
##   - **A seam can be somewhere else entirely.** A fold laid OVER an older seam takes
##     that seam into its subspace along with the sheet it was cut into — the join is
##     still there, under your feet, in the room you are now standing in. It just
##     belongs to a fold in the space outside. Drawn from `space_folds()` alone it was
##     invisible: a hard line in the art with nothing to say what it was.
##
## The walk mirrors `_compute_space` exactly, because it is answering the same question
## about the same derivation — at each level, carry every mark through that space's
## folds up to the one you went INTO, then keep what lies inside that fold's strip. No
## frame changes on the way down: a strip is captured where it stands.
##
## The recorded segments are not computed here. They are the ones `_commit_fold` stored
## for unfold blocking, which IS the meeting line; a seam drawn from its own arithmetic
## would be a second copy of a fact that can drift from the one deciding whether the
## fold can come out at all.
func seam_marks() -> Array:
	var marks: Array = []
	var sp_folds: Array = folds
	for level in range(context.size() + 1):
		var host: Fold = context[level] if level < context.size() else null
		var limit: int = sp_folds.size() if host == null else sp_folds.find(host)
		if limit < 0:
			return marks              # a context fold missing from its parent's list
		for i in range(limit):
			for m in marks:
				m["segs"] = _carry_segments(m["segs"], sp_folds[i])
				if m["at"] != null:
					m["at"] = WorldCore.carry_point(Vector2(m["at"]), sp_folds[i], CS)
			# ...and only then its own, because a fold does not move its own seam.
			marks.append({
				"fold": sp_folds[i],
				"segs": _recorded_seam(sp_folds[i]),
				"at": cell_center(sp_folds[i].meeting_pos),
				"outer": host != null,
			})
		if host != null:
			marks = _taken_into(marks, host)
			sp_folds = _ensure_inner_folds(host.fold_id)
	return marks


## What the strip took in with it. A seam running out through a crease is kept for the
## part that came in and cut at the glue; one left entirely outside is dropped, and so
## is a meeting point that stayed behind — what is not in here cannot be burst from in
## here.
func _taken_into(marks: Array, host: Fold) -> Array:
	var out: Array = []
	for m in marks:
		var segs: Array = []
		for seg in m["segs"]:
			var part := WorldCore.segment_within_strip(seg[0], seg[1], host)
			if part.size() == 2:
				segs.append(part)
		var at = m["at"]
		if at != null and not WorldCore.point_within_strip(Vector2(at), host):
			at = null
		if not segs.is_empty() or at != null:
			out.append({"fold": m["fold"], "segs": segs, "at": at, "outer": true})
	return out


## The seam lines to draw, from every mark that has one.
func seam_lines() -> Array:
	var out: Array = []
	for m in seam_marks():
		out.append_array(m["segs"])
	return out


## A fold that excised nothing leaves a zero-length segment and has no seam to carry or
## draw; it is dropped here rather than at the far end, so nothing undrawable ever
## reaches the view.
func _recorded_seam(fold: Fold) -> Array:
	var seg: PackedVector2Array = seam_segs.get(fold.fold_id, PackedVector2Array())
	if seg.size() != 2 or seg[0].is_equal_approx(seg[1]):
		return []
	return [seg]


func _carry_segments(segs: Array, through: Fold) -> Array:
	var out: Array = []
	for seg in segs:
		out.append_array(WorldCore.carry_segment(seg[0], seg[1], through, CS))
	return out


## Where the fold's meeting point is NOW — the spot its diamond is drawn on, the burst
## measures to, and F unfolds it at. Null when nothing of it is in this space: the
## hands it holds went wherever its seam went, and there is nothing here to burst.
##
## Every reader of this goes through the marks rather than through `meeting_pos`,
## because the marker, the reach and the act have to agree about one place — a diamond
## drawn where a burst does not reach is the bug that rule exists to prevent.
func seam_point(fold: Fold):
	for m in seam_marks():
		if m["fold"] == fold:
			return m["at"]
	return null


## ...and the cell that point is in. Folds shift by whole cells, so a meeting point
## carried through any number of them is still the centre of one.
func seam_cell(fold: Fold):
	var at = seam_point(fold)
	return null if at == null else Vector2i((Vector2(at) / CS).floor())


func animating() -> bool:
	return not _anim.is_empty()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Which way the placement cursor steps for a key. The SAME keys that move the body,
## because while a hand is up they are what moves instead of it — there is no second
## set of controls to learn, and the hand goes where you would have gone.
const AIM_STEPS := {
	KEY_A: Vector2i(-1, 0), KEY_LEFT: Vector2i(-1, 0),
	KEY_D: Vector2i(1, 0), KEY_RIGHT: Vector2i(1, 0),
	KEY_W: Vector2i(0, -1), KEY_UP: Vector2i(0, -1),
	KEY_S: Vector2i(0, 1), KEY_DOWN: Vector2i(0, 1),
}


## One key for the whole verb. TAP pushes an anchor in (raise the hand, then pin it);
## HOLD pulls one back out — everything of yours within reach of where you are
## standing. The two directions of a conserved resource are the two ways to press
## one key.
##
## BOTH GESTURES FIRE ON RELEASE, and that is the whole shape of this. Holding does
## not do anything — it LOADS. The burst is charged while the key is down and pops
## the moment you let go, so the press is a decision you are still holding and the
## release is you making it. Firing at the threshold instead made the burst arrive
## while you were still deciding, and put the one irreversible half of the verb on a
## timer you could not stop.
##
## What you get for it: a loaded burst can be walked. Charge it, step onto the seam,
## let go — the reach is measured where you release, not where you pressed. That
## holds with a hand raised too: the charge accrues in real time while world time is
## stopped, and letting go loaded cancels the placement and pops.
##
## Cursor steps fire on PRESS, and echoes are dropped at the top, so one press is one
## cell. That matters more than it looks: you tap F while already holding the key you
## were running with, and a cursor driven by the HELD key would set off for the edge
## of your reach the moment it appeared. One press, one cell, and the run key you are
## still leaning on does nothing until you press it again.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	if event.physical_keycode == KEY_R:
		if event.pressed:
			_reset()
		return
	# Leaving is not a world event and takes no notice of what the world is doing: mid
	# fold, mid placement, mid fall, Escape gets you out. A run you cannot abandon
	# while it is animating is a run you have to wait out to fix the thing you saw.
	if event.physical_keycode == KEY_ESCAPE:
		if event.pressed:
			left.emit()
		return
	if placing() and event.pressed and AIM_STEPS.has(event.physical_keycode):
		move_aim(AIM_STEPS[event.physical_keycode])
		return
	if event.physical_keycode != KEY_F:
		return
	if event.pressed:
		if animating():
			return
		_hold_active = true
		_hold_elapsed = 0.0
		return
	# A release with no press behind it — the press landed mid-fold and was refused,
	# or a reset cleared it — is not a gesture, and must not fall through to a tap.
	if not _hold_active:
		return
	var loaded := hold_loaded()
	_hold_active = false
	_hold_elapsed = 0.0
	if animating():
		return
	if loaded:
		hold_action()   # the burst is not aimed; where you stand is the whole input
	else:
		tap_action(player.point_dir())


## How far through the hold the key currently is: 0 not holding, 1 LOADED. The body
## wears this as a colour (see `PlayerBody.charge_color`) — the indicator is on the
## thing the burst comes out of, not on the cell you are pointing at, because the
## burst is not aimed there.
func hold_progress() -> float:
	if not _hold_active:
		return 0.0
	return clampf(_hold_elapsed / HOLD_TIME, 0.0, 1.0)


## Is the burst loaded — would letting go RIGHT NOW pop rather than place a hand?
func hold_loaded() -> bool:
	return _hold_active and _hold_elapsed >= HOLD_TIME


## Charge the burst while the key is down. It never fires from here: the release
## does that. Held past the threshold it simply stays loaded, so you can charge it
## somewhere safe and carry it to where you want it to go off.
func _tick_hold(delta: float) -> void:
	if not _hold_active:
		return
	# A fold started under you — a fuse went off, a trigger fired. The gesture is
	# void: what you charged it against is no longer the world in front of you.
	if animating():
		_hold_active = false
		_hold_elapsed = 0.0
		return
	_hold_elapsed = minf(_hold_elapsed + delta, HOLD_TIME)


func player_cell() -> Vector2i:
	return Vector2i((player.global_position / CS).floor())


func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CS


## Where the cursor STARTS when you raise a hand: the cell you are pointing at, so
## the common placement is still "point, tap, tap" and the keys you were already
## holding have put the cursor where you meant before you look at it.
func candidate_anchor(dir: Vector2i = Vector2i.ZERO) -> Vector2i:
	var d := dir if dir != Vector2i.ZERO else Vector2i(player.point_dir())
	return player_cell() + d * ARM_REACH


# ---------------------------------------------------------------------------
# Placing a hand: the cursor, and the stopped clock
# ---------------------------------------------------------------------------
# Placing used to be one tap in one of four directions, sampled off the keys you
# happened to be holding at that instant. Two things were wrong with that, and both
# of them were about a game where you are usually MOVING:
#
#   - Aiming at a particular cell meant arriving at a particular position with a
#     particular key held, which is a demand on your hands rather than a decision
#     about the fold. Missing meant bursting the hand back and running the approach
#     again, which is repetition standing in for precision.
#   - Only four cells could be named at all, so a cell plainly within reach — the one
#     diagonally under the ledge you are standing on — was unpinnable for a reason
#     that lives in the input code and nowhere in the world.
#
# So the hand comes UP first. Raising it stops the clock and turns it into a cursor
# over the nine cells within arm's reach; the movement keys walk it; the next tap pins
# it. Nothing about the world is saved or restored across that — `_physics_process`
# simply does not run — so the moment you resume is the moment you left, momentum,
# fuses and hands in flight and all. What the pause buys is that WHERE to pin is
# decided as a decision, not as a reflex.
#
# A hold is still a hold while the hand is up: it cancels, bursts, and resumes time
# the same way. The pull-back direction of the one key does not stop meaning
# pull-back because a hand happens to be raised.

## Is a hand up, waiting to be placed? While this is true the world is not stepping.
func placing() -> bool:
	return _aim != null


## The cell the hand would go into. Clamped on the way out rather than only on the way
## in, so it stays inside your reach even if something moved the body while the hand
## was up — a reset, a test, a future path that relocates you. Off-mode it answers
## where a raise would start, which is what the aim ring reads.
func aim_cell() -> Vector2i:
	if _aim == null:
		return candidate_anchor()
	return WorldCore.clamp_to_arm_reach(player_cell(), _aim, ARM_REACH)


## Raise the hand you are about to spend. Refused with no hand to raise: the mode
## exists to place one, and standing in it empty-handed would be a pause button.
func begin_aim(dir: Vector2i = Vector2i.ZERO) -> bool:
	if animating() or placing():
		return false
	if not can_place_hand():
		_deny("No hand to place.")
		return false
	_aim = candidate_anchor(dir)
	player.frozen = true
	# The mirror of `hand_place`, because that is exactly what this is: the same
	# gesture running the other way, like `fold`/`unfold` and `pinch`/`surface`.
	AudioManager.play_sfx(Sounds.HAND_RAISE)
	return true


## Walk the cursor one cell. Clamped, so pressing into the edge of your reach is a
## no-op rather than a refusal — there is nothing to say no to.
func move_aim(step: Vector2i) -> void:
	if not placing() or step == Vector2i.ZERO:
		return
	var from := aim_cell()
	var to := WorldCore.clamp_to_arm_reach(player_cell(), from + step, ARM_REACH)
	if to == from:
		return
	_aim = to
	AudioManager.play_sfx(Sounds.UI_MOVE)


## Pin the raised hand where the cursor is, and start the clock again.
##
## A placement that finds no sheet KEEPS the hand up: the mode ends when a hand goes
## down or you cancel it, and ending it on a refusal would spend the whole gesture on
## a cell the player can see is empty. Nudge one cell over and tap again.
func finish_aim() -> void:
	if not placing():
		return
	if not place_hand(aim_cell()):
		return
	_end_aim()


## Put the hand back down without placing it. Time resumes exactly as it would have.
func cancel_aim() -> void:
	if not placing():
		return
	_end_aim()


func _end_aim() -> void:
	_aim = null
	if player != null:
		player.frozen = false


## Where an anchor lies in THIS frame, or null if it is not here — wrong region, or
## its base tile is folded away.
##
## The region check is not belt-and-braces: base ids are per-region and DO overlap
## between regions, so without it a west anchor could quietly resolve onto whatever
## east tile happens to share its id.
func anchor_point(entry: Anchor):
	if entry == null:
		return null
	return entry.point_in(current_pieces, region_id)


func anchor_cell(entry: Anchor):
	var wp = anchor_point(entry)
	if wp == null:
		return null
	return Vector2i((Vector2(wp) / CS).floor())


func anchor_here(entry: Anchor) -> bool:
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


## Every anchor standing in the world, yours and the world's alike.
func all_anchors() -> Array:
	return field.anchors.duplicate()


## Pin a hand in an absolute cell. Takes the CELL rather than a direction because the
## cursor has already answered "which cell" — a direction here would be a second
## opinion about the same question, resolved against wherever the body had drifted to.
##
## Returns whether a hand actually went down.
func place_hand(cell: Vector2i) -> bool:
	if animating():
		return false
	var center := cell_center(cell)
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
		return false
	# A SITE holds one anchor. This is the second thing placement asks, and it is still
	# not a question about the fold: two anchors on one spot are a pair at zero gap,
	# which under proximity pairing is guaranteed to arm and guaranteed to be refused —
	# a hole with no bottom, dug by a rule that used to merely allow a mistake.
	if field.at_point(space, center, CS * 0.5) != null:
		_deny("There is already a hand there.")
		return false
	# Placing puts a HAND down: it leaves your slot now, and its kind travels with
	# the anchor because the fold will need to know what it was pinned with — and now
	# also how far it reaches for a partner.
	var from_slot := HandStock.first_held(hands)
	if from_slot < 0:
		_deny("No hand to place.")
		return false
	var kind := int(hands[from_slot])
	hands[from_slot] = null
	AudioManager.play_sfx(Sounds.HAND_PLACE)
	field.add(Anchor.make(piece.base_id, center - piece.src_offset, region_id, kind))
	return true


## The anchors a hand placed at `at` would immediately pair with, as world points.
##
## What the cursor previews. It is the same question `AnchorField` will ask a frame
## later and it is asked the same way — a hypothetical anchor of the kind you are
## holding, at the cell you are standing the cursor on. A preview computed by a second
## rule is exactly the lie that shows a fold placement would not actually make.
func aim_partners(at: Vector2, kind: int) -> Array:
	var out: Array = []
	if kind < 0:
		return out
	var reach := HandTypes.span(kind) * CS
	for anchor in field.anchors:
		if anchor.partner >= 0 or anchor.arms != Anchor.PROXIMITY:
			continue          # declared or waiting on a channel: not yours to join
		var wp = anchor_point(anchor)
		if wp == null:
			continue
		if gap_to(Vector2(wp), at) <= reach + anchor.span(CS) + AnchorField.SPAN_EPSILON:
			out.append(Vector2(wp))
	return out


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
	var marks: Array = seam_marks()
	var blocked: Fold = null
	for i in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		if m["at"] == null:
			continue
		var cell := Vector2i((Vector2(m["at"]) / CS).floor())
		if cell != cand and cell != here:
			continue
		if not bool(m["outer"]) and can_unfold_fold(m["fold"]):
			return m["fold"]
		if blocked == null:
			blocked = m["fold"]
	return blocked


## TAP: raise a hand, or put the raised one down. That is all it ever does.
##
## Two taps rather than one, and the world does not move between them — see
## §"Placing a hand". `dir` seeds the cursor on the first tap and is ignored by the
## second, which pins wherever the cursor was walked to.
##
## The second hand of a pair lights that pair's fuse and it commits ITSELF; the next
## hand after that starts another pair, which arms alongside the first. There is no
## committing press and no limit but the hands you are carrying.
func tap_action(dir: Vector2i) -> void:
	if animating():
		return
	if placing():
		finish_aim()
		return
	begin_aim(dir)


## HOLD: a BURST around you.
##
## Not an aimed action — a small sphere of influence centred on your body
## (`BURST_RADIUS`, about a tile and a third). Everything of yours inside it comes loose
## at once:
##
##   - hands you have placed as anchors come back — and ONLY the ones inside it, so
##     reaching one half of an armed pair disarms the pair and pops that half while
##     the other stays pinned where you put it;
##   - folds whose seam is in reach come apart, if nothing newer is blocking them;
##   - inside a subspace, the glue anchor in reach is the way out;
##   - and any hand with nowhere to go POPS INTO THE WORLD at your feet.
##
## That last clause is what makes the burst safe to fire blind. Nothing is ever
## refused for want of a slot and nothing is ever destroyed: a hand that cannot be
## caught is simply a hand on the ground, the same object an authored one is.
##
## The first clause is what makes it safe to fire NEAR something: the sphere is the
## whole of what it touches, so nothing you cannot see moves when you press the key.
##
## Folds come apart one at a time and the first to animate takes the burst with it,
## so a stack under one diamond clears over several bursts rather than all at once.
##
## With a hand raised this is also the CANCEL: the hand goes back into its slot, time
## resumes exactly as it would have, and the burst fires around you as it always does.
## One key, two directions — the pull-back direction does not stop meaning pull-back
## because a hand happens to be up, and a player who wants out of the cursor reaches
## for the key that means "undo what I pushed in" without being taught to.
func hold_action(_dir: Vector2i = Vector2i.ZERO) -> void:
	if animating():
		return
	# Putting a raised hand back is something this gesture DID, and it is tracked apart
	# from what the burst freed because it is not something that came loose: the burst
	# sound belongs to hands and folds leaving their places, and no hand left one here.
	# What it does earn is silence instead of "Nothing here to release" — a pop that
	# cancelled a placement in open ground has not done nothing.
	var cancelled := placing()
	cancel_aim()
	if _burst(player.global_position, BURST_RADIUS) == 0 and not cancelled:
		# "Nothing here" has to be true. A seam the strip took in with it is standing
		# right there — drawn, and reached by this very burst — and held by a fold in
		# the space outside, which is a different answer from an empty sphere.
		_deny("Held from outside the fold."
			if _outer_seam_within(player.global_position, BURST_RADIUS)
			else "Nothing here to release.")


## Fire a burst: a sphere of `radius` centred on `origin`, and everything of yours
## inside it comes loose at once. Returns how many things it freed.
##
## Two things fire one — your own release (at the body, at `BURST_RADIUS`) and a burst
## plate (at the tile, at whatever reach it was authored with) — and they share this
## function rather than the rule. **What a burst reaches is one question**, and a plate
## that answered it for itself would be a second answer free to drift from this one:
## it would be the plate, not the burst, that decided whether reaching half an armed
## pair disarms it, or whether a hand with nowhere to go is dropped or destroyed.
##
## The count is what the caller says something happened with. It is not a hand ledger
## — a released fold and a popped hand both count one — and nothing but the messaging
## reads it.
func _burst(origin: Vector2, radius: float) -> int:
	_burst_flash_left = BURST_FLASH
	_burst_at = origin
	_burst_radius = radius
	var freed := 0

	# Your own placed hands first: cheap, and they change no geometry.
	#
	# Every anchor in reach comes back, and NOTHING else moves. Reaching one half of an
	# armed pair used to need its own careful path — disarm the pair, pop this half,
	# put the far half back where it was — and now it is what happens: the anchor
	# leaves the field, the pair it was in stops existing because a pair is derived
	# from the anchors that are there, and the far one has not been touched.
	#
	# A BOLTED anchor is not yours and does not answer. It is authored world state with
	# no way back, and popping one would let a burst quietly delete a puzzle.
	for anchor in field.anchors.duplicate():
		if anchor.is_hand() and _anchor_within(anchor, origin, radius):
			_release_anchor(anchor, true)
			field.remove(anchor)
			freed += 1

	# Inside a fold, the glue anchor in reach is the exit.
	if mode == Mode.SUBSPACE and _glue_within(origin, radius):
		AudioManager.play_sfx(Sounds.BURST)
		# The way out counts as something found: a burst that opens the fold you are
		# standing in has not done nothing, whatever `try_exit` then makes of it.
		try_exit()
		return freed + 1

	# Then the folds — the ones that were unfoldable WHEN THE BURST FIRED, decided up
	# front. A stack under one diamond clears one layer per burst: releasing the newer
	# fold is what unblocks the older, and cascading into it would mean a single press
	# undid work you never asked it to reach. Snapshotting also makes the burst
	# deterministic, rather than depending on which unfolds happen to animate.
	# The burst itself, before the folds it releases: it is the gesture, and the
	# unfold it sets off should sound like a consequence of it. Only when
	# something actually came loose — the flash always fires, but a burst into
	# empty air is exactly the case the caller's refusal is for.
	var releasing: Array = _unfoldable_within(origin, radius)
	if freed > 0 or not releasing.is_empty():
		AudioManager.play_sfx(Sounds.BURST)

	for fold in releasing:
		if animating():
			break
		unfold_space_fold(fold)
		freed += 1
	return freed


## How far apart two points in THIS space are — the short way round.
##
## Every "is that in reach" question in the world goes through here rather than
## through `distance_to`, because inside a fold the space is identified across its
## glue lines: a hand pinned just past the far glue is drawn beside your feet and
## subtracts to a whole period away. See `FoldLattice.shortest_delta`.
func gap_to(a: Vector2, b: Vector2) -> float:
	return lattice.distance(a, b)


## Is a seam belonging to the space OUTSIDE within reach of a burst from here?
func _outer_seam_within(origin: Vector2, radius: float) -> bool:
	for m in seam_marks():
		if bool(m["outer"]) and m["at"] != null \
				and gap_to(Vector2(m["at"]), origin) <= radius:
			return true
	return false


## Is this anchor within `radius` of a point? False when it is unresolvable in the
## frame we are looking at — an anchor you cannot see is not one you can reach.
func _anchor_within(entry, origin: Vector2, radius: float) -> bool:
	var wp = anchor_point(entry)
	return wp != null and gap_to(Vector2(wp), origin) <= radius


func _glue_within(origin: Vector2, radius: float) -> bool:
	if mode != Mode.SUBSPACE or host_fold == null:
		return false
	for c in [host_fold.anchor_a, host_fold.anchor_b]:
		if gap_to((Vector2(c) + Vector2(0.5, 0.5)) * CS, origin) <= radius:
			return true
	return false


## Folds of this space whose seam is in reach AND can come out right now, newest
## first — the older of a stacked pair is exactly the one the newer is blocking, so
## working backwards offers the ones that can actually move.
func _unfoldable_within(origin: Vector2, radius: float) -> Array:
	var marks: Array = seam_marks()
	var out: Array = []
	for i in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		if bool(m["outer"]) or m["at"] == null:
			continue          # a seam this space can see but cannot open
		if gap_to(Vector2(m["at"]), origin) <= radius and can_unfold_fold(m["fold"]):
			out.append(m["fold"])
	return out


## Seams a burst from here would reach, for the overlay to mark. Includes blocked
## ones: the marker should show what is in range, and its own colour says whether it
## will move.
func seams_within_burst() -> Array:
	var out: Array = []
	var origin := player.global_position
	for m in seam_marks():
		if m["at"] != null and gap_to(Vector2(m["at"]), origin) <= BURST_RADIUS:
			out.append(m["fold"])
	return out


## Is the subspace's glue anchor within burst reach? The overlay lights the white
## diamond on this.
func glue_within_burst() -> bool:
	return _glue_within(player.global_position, BURST_RADIUS)


func burst_flash() -> float:
	return clampf(_burst_flash_left / BURST_FLASH, 0.0, 1.0)


## Put an anchor back where it belongs: into a slot if you have one free and can
## reach it, otherwise it is UNPINNED and falls from where it was.
##
## An unpinned hand is a hand nothing is holding up any more, so it drops — the same
## rule as every other way a hand comes loose, because there is only one kind of loose
## hand and it would be strange for the game to have two ideas about how one behaves.
##
## This costs something real, and it is worth naming: a failed fold used to leave its
## two hands exactly on the cells you chose, so the shape of the fold you tried to make
## was still legible in the world. Now the pair falls. What is bought is that a hand is
## always somewhere you can see and walk to — a hand pinned into a wall face used to
## end up drawn buried inside the tile — and that "hands behave like objects" has no
## exceptions to learn.
## Only ever called for a LOOSE anchor: a bolted one is not a hand and has nowhere to
## go back to.
func _release_anchor(entry: Anchor, into_hand: bool) -> void:
	if into_hand and HandStock.first_empty(hands) >= 0:
		hands[HandStock.first_empty(hands)] = entry.hand
		return
	# An anchor is stored in the BASE frame; a ball needs a point in the view it is
	# falling through. A hand whose tile is folded away has no "here" to fall in, so it
	# stays an occupant on the spot it was pinned to and falls whenever that tile
	# surfaces — there is no view in which it could be dropping right now.
	var here = anchor_point(entry)
	if here != null:
		_toss_hand(entry.hand, Vector2(here))
		return
	var p := HandPickup.new()
	p.kind = entry.hand
	p.region = entry.region
	p.authored = false
	p.base_id = entry.base_id
	p.bp = entry.bp
	_ensure_pickups(p.region).append(p)
	AudioManager.play_sfx(Sounds.HAND_DROP)


## A fold that would not go.
##
## Its LOOSE anchors drop where they were pinned — none of them come back to your
## slots, because returning them would make a mistimed fold free, and the hands lying
## on the spots you chose still hold the shape of the fold you tried to make.
##
## Its BOLTED anchors stay exactly where they are. They are not hands and there is
## nothing to drop; the world wanted that fold and goes on wanting it, so the pair
## re-fuses (`AnchorField.refuse`) and tries again in a fuse's time. That is also why
## a refusal with nothing loose in it is SILENT: a plate whose fold is blocked by a pin
## would otherwise announce itself for as long as you stood there.
func _scatter_pair(pair: Dictionary) -> void:
	var dropped := 0
	for entry in [pair["a"], pair["b"]]:
		var anchor: Anchor = entry
		if not anchor.is_hand():
			continue
		field.remove(anchor)
		_release_anchor(anchor, false)
		dropped += 1
	field.refuse(pair["a"], pair["b"])
	# The one place a refused fold is heard. Every refusal in `fire_pair` and
	# `do_fold` funnels through here, so the sound sits where the OUTCOME is
	# rather than being repeated at each of the six ways to reach it — and it
	# lands under the hands hitting the ground, which say the rest.
	if dropped > 0:
		AudioManager.play_sfx(Sounds.FOLD_REFUSED)


## The channel a pair's fold should be tagged with, or "" — what makes a plate's fold
## findable so the plate does not fire a second one on top of it.
func _channel_of(pair: Dictionary) -> String:
	for entry in [pair["a"], pair["b"]]:
		var arms: String = (entry as Anchor).arms
		if arms != Anchor.PROXIMITY and arms != Anchor.NEVER:
			return arms
	return ""


## Fire one armed pair. Called by its fuse, never by a keypress.
##
## `pair` is `{"a": Anchor, "b": Anchor}` as `AnchorField.step` produced it, so both
## ends are known to resolve in this space — the frame it was decided in is the frame
## it fires in.
func fire_pair(pair: Dictionary) -> void:
	if animating():
		return
	var a: Anchor = pair["a"]
	var b: Anchor = pair["b"]
	var ca = anchor_cell(a)
	var cb = anchor_cell(b)
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
	# What the fold takes CUSTODY of is what was actually spent on it: your hands, and
	# not the world's. A fold pinned by two bolted anchors holds nothing and pays
	# nothing back, which is what authored folds have always done — now for a reason
	# rather than by being a different kind of thing.
	var pinned: Array[int] = []
	for anchor in [a, b]:
		if (anchor as Anchor).is_hand():
			pinned.append((anchor as Anchor).hand)
	if do_fold(ca, cb, pinned, _channel_of(pair)):
		# The fold is holding the SAME hands that were pinned — they went from your
		# slots to the anchors to the fold without ever being duplicated. The anchors
		# are spent, so they leave the field and every pair they were in goes with them.
		field.remove(a)
		field.remove(b)
	else:
		# `do_fold` has already said why. The hands falling where they stood is the
		# rest of the answer, and it needs no words.
		_scatter_pair(pair)


# ---------------------------------------------------------------------------
# The hand ledger (see HandStock)
# ---------------------------------------------------------------------------
# Nothing is stored. `held` is summed from the live fold lists and `pending` from
# the two slots, so unfolding refunds without any bookkeeping — the fold leaves the
# list and stops being counted.

## Every live fold list in the world: each region's, plus every fold's inner_folds.
## The working `folds` / `inner_folds` vars are references INTO `regions`, so walking
## the regions counts the current one exactly once.
func _all_fold_lists() -> Array:
	var out: Array = []
	for id in regions:
		var r: Dictionary = regions[id]
		out.append(r["folds"])
		var ints: Dictionary = r["inner_folds"]
		for fid in ints:
			out.append(ints[fid])
	return out


## Hands in your slots right now.
func hands_held() -> int:
	return HandStock.held_count(hands)


## Empty slots — how many hands you could be given, and so whether a fold's two can
## come home.
func hands_free_slots() -> int:
	return HandStock.free_slots(hands)


## Hands committed to standing folds, everywhere in the world.
func hands_in_folds() -> int:
	return HandStock.held_in(_all_fold_lists())


## Hands of yours that are pinned somewhere. Counting the anchors is the whole of it
## now, since one anchor is one hand — and bolted anchors are not hands, so the world
## driving its own into the sheet cannot move this number.
func hands_pending() -> int:
	return field.hands_out()


func can_place_hand() -> bool:
	return HandStock.has_hand(hands)


## The kind of hand the next tap would put down, or -1 if you have none. Drives the
## aim ring's colour: what you are about to spend is visible before you spend it.
func next_hand_type() -> int:
	var i := HandStock.first_held(hands)
	return -1 if i < 0 else int(hands[i])


## Hands lying on the ground, everywhere in the world — INCLUDING the ones still in the
## air on their way there.
##
## A ball counts as loose because "loose" means "not yours and not in a fold", and a hand
## mid-fall is exactly that. Counting it anywhere else, or nowhere, would make a hand
## appear destroyed for the second or two it is falling and then created again when it
## landed — and conservation is the one property of this system that must never wobble,
## including mid-flight. `HandStock.total` is what states it and `test_hand_stock`
## what pins it.
func hands_loose() -> int:
	var n := hand_balls.size()
	for id in hand_pickups:
		n += (hand_pickups[id] as Array).size()
	return n


## Every hand that exists, in all four places. NOTHING in the game changes this:
## placing, committing, unfolding, bursting and picking up all just move one.
func hands_total() -> int:
	return HandStock.total(hands, hands_pending(), _all_fold_lists(), hands_loose())


# ---------------------------------------------------------------------------
# The fuse: a completed pair folds itself
# ---------------------------------------------------------------------------

## The pairs about to fold in this space, `{"a": Anchor, "b": Anchor, "gap": float}`.
## Derived, so it is a question and not a list that has to be kept true.
func armed_pairs() -> Array:
	return field.pairs_in(space)


## Is anything counting down at all?
func fuse_running() -> bool:
	return not armed_pairs().is_empty()


## How far through its fuse a pair is, 0 (just lit) to 1 (folding now). The overlay
## pulses each pair's own anchors on its own number, so two armed folds beat at
## different rates and you can see which is closer to going.
func fuse_progress_of(pair: Dictionary) -> float:
	return field.progress(pair["a"], pair["b"])


## The progress of whichever pair is closest to firing, or 0 if none is armed.
func fuse_progress() -> float:
	return field.nearest_progress(armed_pairs())


## Run the anchor field on: recompute which anchors reach each other and count their
## fuses down. A pair whose anchors are not BOTH resolvable in the frame we are looking
## at is SUSPENDED — walk through a door mid-count and that fold waits for you rather
## than firing somewhere you cannot see (`AnchorField.step` draws that line).
##
## At most ONE fold per frame, because a fold owns the frame it starts in (see the
## guard below this call in `_physics_process`, and AGENTS.md §3). Two pairs coming due
## together is a tie the field has already broken; the loser fires a frame later, which
## at sixty of them a second is not a wait, and it fires against the geometry the first
## one left behind rather than against the one it was decided in.
func _tick_fuse(delta: float) -> void:
	var res := field.step(space, delta)
	# The fuse is the one thing in this game that goes off without you: it is the only
	# warning there is, and it plays over the hand that completed the pair.
	if int(res["lit"]) > 0:
		AudioManager.play_sfx(Sounds.PAIR_ARMED)
	var due: Array = res["due"]
	if not due.is_empty():
		fire_pair(due[0])


# ---------------------------------------------------------------------------
# Folding
# ---------------------------------------------------------------------------

## What a committed fold takes custody of.
##
## `fire_pair` passes the hands that were actually pinned — they left your slots when
## you placed them, so they are already accounted for. That list may be SHORT or EMPTY:
## a fold pinned by the world's own bolted anchors was paid for by nobody, holds
## nothing, and hands nothing back. `null` means something else entirely — a caller
## folding without having placed anything (`do_fold` as a bare primitive: tests, debug)
## — and then the hands come straight out of your slots.
##
## If your hands are empty the fold holds nothing either. Inventing hands instead would
## be the one thing this whole ledger exists to prevent: a fold holding anchors nobody
## paid for, which unfolding would then hand you.
##
## CALL THIS LATE — at the point of no return, after every refusal has been checked.
## It empties slots, and a fold that gets rejected for a pin in its span or nowhere to
## land must not have cost you the hands it never took.
func _hands_for_fold(pinned) -> Array[int]:
	if pinned != null:
		var given: Array[int] = []
		for kind in pinned:
			given.append(int(kind))
		return given
	var out: Array[int] = []
	for _i in range(HandStock.HANDS_PER_FOLD):
		var from_slot := HandStock.first_held(hands)
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
##   - **PINCH.** It does not: you were in the strip being excised, and the fold
##     swallows you. The fold is applied for real and the space it cut out becomes
##     the place you are standing in — pushed onto the context stack, however
##     many folds deep that already is. Folding yourself deeper used to be
##     refused here; there is no longer anything to refuse, because there is no
##     longer a second code path to be missing.
func do_fold(a1: Vector2i, a2: Vector2i, pinned = null, channel := "") -> bool:
	var fold := Fold.create(next_fold_id, a1, a2, CS, channel)
	var pre: Array = current_pieces
	# ONE clip pass for both halves. The flaps become the new piece list and the
	# strip between them becomes the subspace; `CollisionCore.fold_polygons` produces
	# both from the same cut, and asking for them separately clipped the whole world
	# twice. See FoldReplay.fold_and_capture.
	#
	# Cut from the same content `_compute_space` will hand you when it swallows
	# you, so the refusal here and the place you land agree.
	var cut := FoldReplay.fold_and_capture(pre, fold, CS)
	var dropped: Array = cut["dropped"]
	if dropped.is_empty():
		_show_flash("Nothing there to fold.")
		return false
	if WorldCore.fold_blocked_by_tile(pre, fold, CS):
		_show_flash("Something in that span refuses to fold.")
		return false

	var from_piece = BaseFrame.piece_containing(pieces_by_pos, player.global_position, CS)
	var new_pieces: Array = cut["pieces"]
	var dest = null
	if from_piece != null:
		dest = BaseFrame.world_point_from_base(
			new_pieces, from_piece.base_id, player.global_position - from_piece.src_offset)
	else:
		# Over void: no piece to ride, so fall back to crease arithmetic. Only
		# a point in the excised strip has no side at all, and that is the pinch.
		var side := WorldCore.side_of_fold(player.global_position, fold)
		if side != 0:
			dest = player.global_position + WorldCore.fold_shift_for_side(side, fold, CS)

	if dest == null:
		# PINCH. The fold is applied for real, and you are inside what it took.
		_commit_fold(fold, dropped, pinned)
		var p := player.global_position
		# The player is going INTO the strip, so every ball still flying out here goes
		# with them: the fold is closing around all of it at once.
		_carry_balls_through(new_pieces, true)
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
	# Called with the OLD frame still current, because that is what a ball's position is
	# expressed in: it maps through `BaseFrame` from the piece it is over now to the
	# same spot of sheet in the new configuration, exactly as the player does. A ball
	# over ground the fold excised has no home out here and flies on inside the strip.
	_carry_balls_through(new_pieces, false)
	var finalize_ride := func() -> void:
		rebuild()
		player.teleport(landed)
		_wake_unsupported_hands()
	AudioManager.play_sfx(Sounds.FOLD)
	_play_transition(pre, fold, true, true, player.global_position, landed, finalize_ride)
	return true


## Folding inside a fold is the same act as folding outside one. Kept as a name
## because that is how the tests and the design docs say it.
func do_sub_fold(a1: Vector2i, a2: Vector2i, pinned = null) -> bool:
	return do_fold(a1, a2, pinned)


## Take the fold into the world: claim its id, take custody of the hands, record
## its seam and add it to THIS space's list.
##
## Called at the point of no return, after every refusal — `_hands_for_fold`
## empties slots, and a fold rejected for a pin in its span must not have cost you
## the hands it never took.
func _commit_fold(fold: Fold, dropped: Array, pinned) -> void:
	next_fold_id += 1
	fold.held_hands = _hands_for_fold(pinned)
	seam_segs[fold.fold_id] = WorldCore.seam_segment(fold, dropped, CS)
	space_folds().append(fold)


# ---------------------------------------------------------------------------
# Unfolding (uniform blocking rules at every space)
# ---------------------------------------------------------------------------

## Newer folds in the same list whose strip crosses this fold's seam block it.
## Each newer fold is asked about the seam as it stood WHEN THAT FOLD WAS MADE, which
## is why the seam is carried one step at a time down the list rather than tested once
## where it was first recorded. A fold's creases are coordinates in the configuration
## it was laid into, so comparing them against a line from two folds ago is comparing
## two different worlds — right for the fold immediately after, and drifting by a whole
## strip for every one after that.
func can_unfold_fold(fold: Fold) -> bool:
	var list: Array = space_folds()
	var idx := list.find(fold)
	if idx < 0:
		return false
	var segs: Array = _recorded_seam(fold)
	if segs.is_empty():
		return true
	for j in range(idx + 1, list.size()):
		for seg in segs:
			if WorldCore.segment_intersects_strip(seg[0], seg[1], list[j]):
				return false
		# Not crossed, so nothing is lost by the carry — a fold that would have
		# swallowed any of this seam has already answered the question above.
		segs = _carry_segments(segs, list[j])
	return true


## The seam diamonds to draw: meeting cell -> can anything there come out.
## Several folds can meet in one cell, so the marker is one diamond for all of
## them and reads unblocked when F there would DO something — the same choice
## `aimed_fold` makes, so the colour never promises what the act refuses.
##
## Keyed by where each seam is NOW. A fold whose meeting point is not in this space has
## no diamond at all — a diamond left behind where it used to be is an invitation to
## burst at a place where nothing will happen.
##
## A seam belonging to the space OUTSIDE gets its diamond too, and it reads blocked: the
## join is genuinely there under your feet, and the fold holding it is not one this
## space can open. Drawing nothing said the line was not a seam; drawing it open would
## promise a burst this space cannot deliver.
func seam_markers() -> Dictionary:
	var out: Dictionary = {}
	for m in seam_marks():
		if m["at"] == null:
			continue
		var cell := Vector2i((Vector2(m["at"]) / CS).floor())
		var free: bool = not bool(m["outer"]) and can_unfold_fold(m["fold"])
		out[cell] = bool(out.get(cell, false)) or free
	return out


## An inner fold of `fold` whose strip crosses `fold`'s glue blocks
## unfolding it from EITHER side (the outer seam isn't the newest fold
## affecting itself). Returns the blocker or null.
func _inner_glue_blocker(fold: Fold, sp_base: Array, list: Array, idx: int) -> Fold:
	var kids: Array = inner_folds.get(fold.fold_id, [])
	if kids.is_empty():
		return null
	var prefix: Array = sp_base.duplicate()
	for k in range(idx):
		prefix = FoldReplay.apply_one_fold(prefix, list[k], CS)
	var strip := WorldCore.capture_strip(prefix, fold, CS)
	for seg in WorldCore.glue_segments(fold, strip):
		for kf in kids:
			if WorldCore.segment_intersects_strip(seg[0], seg[1], kf):
				return kf
	return null


## Give the player a hand: into a free slot if there is one, otherwise onto the
## GROUND at their feet as a loose pickup.
##
## The overflow case is the whole reason nothing in this file has to refuse a hand.
## A hand you cannot catch is not a hand destroyed and not an action denied — it is a
## hand lying where you were standing, which is exactly the object an authored loose hand
## already is. Conservation holds without anyone having to check for room first.
func _give_hand(kind: int) -> void:
	var into := HandStock.first_empty(hands)
	if into >= 0:
		hands[into] = kind
		return
	_toss_hand(kind, player.global_position)


## Let a hand go at a world point: it becomes a BALL and falls.
##
## Every way a hand reaches the ground comes through here, so there is one answer to
## "what happens when you let go of a hand" and it is the physical one. What lands is
## decided by `WorldCore.hand_ball_step` over the following second or two, not here —
## this only launches it. `_land_ball` is where a ball stops being a ball.
##
## `nudge` is an initial velocity. A burst throws its hands a little, so two hands out of
## one fold visibly separate instead of stacking; the old code did this by displacing the
## drop POINT, which had to be done carefully to avoid putting one hand either side of a
## crease. As a velocity it cannot do that — the ball starts exactly where the hand was
## let go and the physics takes it from there.
func _drop_hand(kind: int, at: Vector2, nudge: Vector2 = Vector2.ZERO) -> void:
	# Seeded from the launch point, which is stable for the whole flight.
	hand_field.launch(kind, at, space, nudge,
		WorldCore.hand_drift_seed(hand_field.size(), at))
	AudioManager.play_sfx(Sounds.HAND_DROP)


## Throw a hand loose with a little sideways kick, so several out of one fold scatter
## rather than stacking. The kick alternates side, which is what makes a pair read as a
## pair.
func _toss_hand(kind: int, at: Vector2) -> void:
	var side := hand_field.next_toss_side()
	_drop_hand(kind, at, Vector2(side * TOSS_SPEED, -TOSS_LIFT))


## Step every ball in flight, and convert the ones that have come to rest.
##
## Only balls in the CURRENT view are stepped: a region and a subspace are
## different spaces with different ground, and a ball must not fall through the other
## one's floor. A ball in the view you are not in simply waits — which is right, because
## the fold it is inside is not a place where time is passing for you either.
func _step_hand_balls(delta: float) -> void:
	hand_field.step(space, delta)


## Wake any resting hand whose ground has gone.
##
## Called after a fold or unfold has rebuilt the view. A hand is an occupant, so a fold
## that MOVES the tile it lies on carries it and it stays put — that is the rule for
## doors and lamps and it is right here too. But a fold that takes the tile out from
## under it leaves a hand hanging in the air, and a hand hanging in the air is the thing
## the physics exists to prevent. So it becomes a ball again and falls.
##
## The cost, worth stating: a hand can now move without you touching it. One you
## remember the position of may be somewhere lower after you fold nearby. That was the
## explicit choice — physical behaviour with no exceptions, over "a hand is where you
## left it".
func _wake_unsupported_hands() -> void:
	if loose_hands.is_empty():
		return
	var solids := wall_polys
	var pieces := current_pieces
	for i in range(loose_hands.size() - 1, -1, -1):
		var pickup: HandPickup = loose_hands[i]
		var wp = pickup.position_in(pieces)
		if wp == null:
			continue                # folded away — not in this view to fall in
		if WorldCore.hand_ball_supported(Vector2(wp), solids):
			continue                # still on something; it rode its flap and is fine
		loose_hands.remove_at(i)
		# Seeded from the base tile it was lying on, so a woken hand keeps a stable
		# drift phase rather than one that depends on how many are already up.
		hand_field.launch(pickup.kind, Vector2(wp), space, Vector2.ZERO,
			WorldCore.hand_drift_seed(pickup.base_id, pickup.bp))


## A hand that fell out of the sheet, put back somewhere it can be found.
##
## It becomes a PICKUP directly rather than another ball, and that is the point: dropping
## it as a ball at the player's position is what caused the bug this exists to prevent.
## A player standing over a pit — on a seam, on the glue, mid-jump across a gap — would
## have the recovered hand fall straight off the world again, be recovered again, and
## loop. The ledger stayed correct the whole time (it was always counted as loose), so
## nothing detected it; the hand simply never came to rest and so could never be found.
##
## Binding it to the piece under the player's feet is what makes it real: if there is
## no sheet there either, `_land_ball`'s outward search finds the nearest that has some.
func _recover_lost_hand(kind: int) -> void:
	var landing := WorldCore.settle_hand(player.global_position, wall_polys)
	_land_ball({
		"kind": kind,
		"pos": landing,
		"region": region_id,
	})
	AudioManager.play_sfx(Sounds.HAND_DROP)


## A ball has stopped: it stops being a ball and becomes an occupant of the sheet again.
##
## This is the boundary that keeps §8 true. From here on the hand has no position of its
## own — where it lies is a question asked of the piece list, so it rides flaps and
## folds away exactly like a door or a lamp. If there is no sheet under where it landed
## (it came to rest over void) we search outward a little, because a hand that bound to
## nothing would vanish from the world.
func _land_ball(ball: Dictionary) -> void:
	var rest: Vector2 = ball["pos"]
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for step in range(1, 5):
		offsets.append(Vector2(0, -0.5 * CS * step))
		offsets.append(Vector2(-0.5 * CS * step, 0))
		offsets.append(Vector2(0.5 * CS * step, 0))
		offsets.append(Vector2(0, 0.5 * CS * step))
	for off in offsets:
		var piece = BaseFrame.piece_containing(pieces_by_pos, rest + off, CS)
		if piece != null:
			_ensure_pickups(String(ball["region"])).append(
				HandPickup.dropped_at(
					int(ball["kind"]), piece, rest + off, String(ball["region"])))
			return
	# No sheet within reach of where it stopped. This used to warn and RETURN, which
	# destroyed the hand — the only place in the game that could, and invisible because a
	# warning is not a failing test. Fall back to the spawn tile, which always exists:
	# a hand waiting somewhere odd is recoverable, a hand deleted is not.
	var fallback = BaseFrame.piece_containing(pieces_by_pos, _spawn, CS)
	if fallback != null:
		_ensure_pickups(String(ball["region"])).append(
			HandPickup.dropped_at(
				int(ball["kind"]), fallback, _spawn, String(ball["region"])))
		push_warning("FoldWorld: a hand came to rest on nothing at %s; returned to spawn"
			% rest)
		return
	# Nothing anywhere — a world with no sheet under its own spawn. Keep the hand in the
	# air rather than deleting it: an orbiting hand is still countable and catchable.
	#
	# `homeless` marks a ball that has already been through here, and it is load-bearing
	# for the LOG rather than for the physics. This state is stable: the ball is put back
	# in flight, comes to rest on the same geometry next step, fails to bind again, and
	# arrives back here — so reporting on every attempt reports the same hand forever. It
	# did: one hand at (864, 1568) produced 1,964 identical ERROR lines in a 16-second
	# suite run, which is not an error message, it is a screen that hides the next real
	# one. Say it once, when the hand ENTERS the state.
	var already: bool = bool(ball.get("homeless", false))
	hand_field.readmit({
		"kind": int(ball["kind"]),
		"pos": rest,
		"vel": Vector2.ZERO,
		"resting": false,
		"region": String(ball["region"]),
		"in_sub": mode == Mode.SUBSPACE,
		"seed": WorldCore.hand_drift_seed(0, rest),
		"homeless": true,
	})
	if not already:
		push_error(("FoldWorld: nowhere at all to land a hand near %s — no sheet under it, "
			+ "and none under the spawn either. Keeping it in flight so it stays "
			+ "countable and catchable.") % rest)


## Carry every in-flight ball through a fold, exactly as the player is carried.
##
## A ball is transported by `BaseFrame` like anything else in the world, so a hand in
## flight that a fold sweeps into a subspace goes on flying INSIDE the subspace. Its
## velocity is untouched: a fold is a translation, so the flight it was on is still the
## flight it is on.
##
## `into_sub` says the fold swallowed this view into a strip, so surviving balls belong
## to the subspace from now on. A ball the fold leaves nowhere — its tile excised while
## the view stays put — is one the strip captured, and it flies on in there.
func _carry_balls_through(new_pieces: Array, into_sub: bool) -> void:
	hand_field.carry_through(space, new_pieces, into_sub)


func _take_back(fold: Fold) -> void:
	for kind in fold.held_hands:
		_give_hand(int(kind))
	fold.held_hands = [] as Array[int]


## Unfold a fold of the CURRENT space. Its inner folds (if any) splice
## into this space at its index — they were made in exactly this frame.
func unfold_space_fold(fold: Fold) -> void:
	var list: Array = space_folds()
	var idx := list.find(fold)
	if idx < 0:
		# A seam the strip took in with it: visible and standing on real sheet, but held
		# by a fold in the space outside, which this space has no way to reach into. It
		# used to fail silently here, and a marker you can press F at that answers
		# nothing is worse than one that says no.
		_deny("Blocked — this seam is held from outside the fold.")
		return
	if not can_unfold_fold(fold):
		_deny("Blocked — a newer fold crosses this seam.")
		return
	var sp_base: Array = space_base
	if _inner_glue_blocker(fold, sp_base, list, idx) != null:
		_deny("Blocked — a fold inside it crosses its seam.")
		return

	var kids: Array = inner_folds.get(fold.fold_id, [])
	list.remove_at(idx)
	for k in range(kids.size()):
		list.insert(idx + k, kids[k])
	inner_folds.erase(fold.fold_id)
	seam_segs.erase(fold.fold_id)

	var new_pieces: Array = sp_base.duplicate()
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
			inner_folds[fold.fold_id] = kids
		_deny("Unfold blocked — nowhere for you to land.")
		return

	var was_newest := idx == list.size() - kids.size()
	var regained: int = fold.held_hands.size()
	# An unfold moves the sheet too, so anything ALREADY flying over it moves with the
	# ground it is over — the same mapping, in the other direction.
	_carry_balls_through(new_pieces, false)
	# Before `_take_back`, which can drop a hand it cannot give you — this
	# should be the sound underneath that, not the other way round.
	AudioManager.play_sfx(Sounds.UNFOLD)
	var finalize := func() -> void:
		rebuild()
		player.teleport(landed)
		# `_take_back` goes HERE, after the rebuild and the teleport, because a hand it
		# cannot hand you is a hand it DROPS — and a hand is dropped at the player's
		# position, in the current geometry. Called before the rebuild (where it used to
		# be) the ball spawned at the player's PRE-unfold position and into the old
		# piece list, so an unfold that moved you left the overflow hand several cells
		# behind, on ground that had since slid away. It was still counted, which is why
		# conservation never caught it; it simply was not where you were.
		#
		# `_carry_balls_through` above cannot fix that: it runs before these balls exist.
		# Creating them after the move is what makes them correct, rather than creating
		# them wrong and then transporting them.
		_take_back(fold)
		_wake_unsupported_hands()
		if regained > 0:
			_show_flash("Released — %d hands." % regained)
	if was_newest and kids.is_empty():
		_play_transition(new_pieces, fold, false, true,
			player.global_position, landed, finalize)
	else:
		finalize.call()


## Inner fold crossing the glue that locks the exit, or null.
##
## The glue asked about is the ENTERED fold's own — the seam you would come out
## through — not every axis the space repeats on. On a torus the other pair of
## glue lines belongs to a fold further out, and crossing those blocks that fold,
## which is a question for when you get there.
func exit_blocker() -> Fold:
	if host_fold == null:
		return null
	for fold in space_folds():
		for seg in WorldCore.glue_segments(host_fold, space_base):
			if WorldCore.segment_intersects_strip(seg[0], seg[1], fold):
				return fold
	return null


## Exit = unfold the entered fold from inside. Inner folds splice into the
## parent space at its index; the strip (and you, and any pinned anchors)
## land exactly where the subspace showed them.
func try_exit() -> void:
	if mode != Mode.SUBSPACE or animating():
		return
	if exit_blocker() != null:
		_deny("Blocked — an inner fold crosses the outer seam.")
		return
	var outer := host_fold
	var parent_path := context.slice(0, context.size() - 1)
	var plvl := _compute_space(parent_path)
	var plist: Array = plvl["space_folds"]
	var idx := plist.find(outer)
	if idx < 0:
		return
	# The parent's newer folds can cross this fold's seam (door-entered
	# mid-list folds): same blocking rule as everywhere.
	var seg: PackedVector2Array = seam_segs.get(outer.fold_id, PackedVector2Array())
	if seg.size() >= 2:
		for j in range(idx + 1, plist.size()):
			if WorldCore.segment_intersects_strip(seg[0], seg[1], plist[j]):
				_deny("Blocked — a newer fold outside crosses this seam.")
				return

	var kids: Array = space_folds()
	plist.remove_at(idx)
	for k in range(kids.size()):
		plist.insert(idx + k, kids[k])
	inner_folds.erase(outer.fold_id)
	seam_segs.erase(outer.fold_id)

	var new_plvl := _compute_space(parent_path)
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
	var kept := not kids.is_empty()
	var surfaced := context.is_empty()
	var finalize := func() -> void:
		_apply_context()
		player.teleport(landed)
		# After the view swap and the teleport, for the same reason as in
		# `unfold_space_fold`: a hand this cannot hand you is DROPPED, and it must be
		# dropped where you are now, in the space you are now in. Called before
		# `_apply_context` it launched the ball into the subspace you were just
		# leaving — tagged `in_sub` in a world that no longer had a subspace, so it could
		# never be stepped, drawn or reached.
		_take_back(outer)
		_wake_unsupported_hands()
		if kept:
			_show_flash("Unfolded — your inner folds came out with you.")
		elif surfaced:
			_show_flash("Unfolded — you emerge where you walked to.")
		else:
			_show_flash("Up one — still %d folds in." % context.size())
	# The reverse transform is exact only for the newest fold of the space being
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

## Resolve a base point inside one space; recurse into whichever fold's strip
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
		r["inner_folds"], d["bid"], d["bp"], [])


## A door's current position in the CURRENT view space, or null (not here /
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
			over = gap_to(player.global_position, Vector2(wp)) < PlayerBody.RADIUS
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
# Pieces of the PRE-state are split by the fold's creases: flaps translate
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

	# Three batches, not a node per piece. The two flaps move by a TRANSLATION,
	# so each is one assignment per frame however many thousand pieces it holds;
	# only the strip, which collapses onto the meeting line, touches vertices at
	# all. A fold used to build (and immediately throw away) one Polygon2D per
	# piece per copy, which is why folding a large region hitched.
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
	# The world's own clock, and the ONE thing that decides whether the world is
	# moving. Everything that drifts, throbs or flickers without being pushed reads
	# `WorldClock`, so stopping it here stops all of them at once — and stops them
	# where they stood, since none of them integrates.
	#
	# The charge, the HUD's flash and the held ease below take `delta` straight from
	# the frame instead: they are not things in the world, and they are what tells you
	# it has stopped.
	if not placing():
		WorldClock.advance(delta)
	_tick_hold(delta)
	_tick_held_look(delta)
	# The body wears the charge. It is handed the number and nothing else — the body
	# knows how to be a colour, not what folding is.
	if player != null:
		player.fold_charge = hold_progress()
		# ...and holds the lens still while the world is held. Told once per frame
		# rather than at the two edges, so a path that ends the mode without going
		# through `_end_aim` cannot leave the camera stuck.
		player.camera_held = placing()
	# The overlay draws a description of the frame, not this object. Building it here
	# is also what makes it a per-FRAME cost: it used to gather itself from inside
	# `paint()`, which WrapCanvas runs once per copy of the space.
	if overlay != null:
		overlay.set_view(_build_overlay_view())
	if hand_orbit != null and player != null:
		# Zero while the world is held: the springs are an integration, so the way to
		# stop them where they are is to hand them no time rather than to skip the
		# call. Skipping it would also skip the slot bookkeeping, and a hand would be
		# left drawn in a slot it had left.
		var orbit_delta := 0.0 if placing() else delta
		hand_orbit.follow(hands, player.global_position, player.velocity, player.facing,
			orbit_delta)
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


## Close the held look over the world, or let it go again.
##
## Eased rather than switched, and eased on the frame's own time: a stop that arrives
## whole in one frame reads as a dropped frame, and this is the one animation that has
## to keep running while everything else is stopped — it is the announcement.
##
## The shader does the rest. It is handed a number between 0 and 1 and decides for
## itself how a half-held world looks (a Bayer dissolve, not a crossfade); nothing
## here knows what the effect is, which is why retuning it is a shader edit.
func _tick_held_look(delta: float) -> void:
	if _held_mat == null:
		return
	var want := 1.0 if placing() else 0.0
	if not is_equal_approx(_held, want):
		_held = move_toward(_held, want, delta / HELD_EASE)
		_held_mat.set_shader_parameter("held", _held)
	if _held > 0.0:
		_held_mat.set_shader_parameter("clear_at", _body_in_target_px())


## Where the body is in the render target, in texels — which are art pixels, which is
## what the shader measures its clear radius in.
##
## The lens never moves (see `PixelArt`), so this is only ever the body's offset from
## the RENDERED centre, scaled by the one constant that says how big an art pixel is.
## The rendered centre is the camera's snapped position rather than its true one: half
## an art pixel of disagreement would put the clear circle half a pixel off the body it
## is drawn around, which at this resolution is a visible slip.
func _body_in_target_px() -> Vector2:
	var eye := PixelArt.snap_round(player.camera_position())
	var from_centre := (player.global_position - eye) / PixelArt.WORLD_PER_PIXEL
	return Vector2(pixel_view.size) * 0.5 + from_centre


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
		# per COPY (see `TileBatch.deform`), because inside a fold every copy
		# collapses onto its own seam rather than all of them onto one.
		var n := fold.crease_normal
		var meet_d := fold.shift_a_px(CS).dot(n)
		var c1 := fold.crease_point1
		(batches["strip"] as TileBatch).deform(func(v: Vector2) -> Vector2:
			return v + n * ((meet_d - (v - c1).dot(n)) * t))
	player.global_position = Vector2(_anim["p_from"]).lerp(Vector2(_anim["p_to"]), eased)


# ---------------------------------------------------------------------------
# What the overlay draws
# ---------------------------------------------------------------------------
# One value per frame describing the markers, previews and rings — see OverlayView.
# The overlay receives it and can do nothing else; it holds no reference back.
#
# Everything expensive is asked exactly once here. That is not an optimisation, it
# is the reason this function exists: when the overlay held this object it asked
# `glue_lines()` and `loose_hand_points()` from inside `paint()`, and WrapCanvas runs
# `paint()` once per copy — 77 copies two folds deep, at 16.3ms of a 16.6ms frame.

func _build_overlay_view() -> OverlayView:
	var v := OverlayView.new()
	if base == null or animating():
		return v                        # mid-fold: the markers describe a configuration in flight

	v.active = true
	v.flat = lattice.is_flat()
	v.cell_size = base.cell_size
	v.world_px = Vector2(base.grid_size) * v.cell_size
	v.domain = lattice.domain_polygon(v.world_px.length())

	# Where this space's folds met, and the diamonds sitting on those lines.
	v.seams = seam_lines()
	v.markers = seam_markers()
	for fold in seams_within_burst():
		# In reach at all means it has a place in this space, so the point resolves.
		v.in_reach.append({
			"at": Vector2(seam_point(fold)),
			"ok": can_unfold_fold(fold),
		})

	for id in doors:
		var wp = door_point_here(id)
		if wp != null:
			v.doors.append(Vector2(wp))

	# Every anchor standing here, its span, and — if something reaches it — the fuse of
	# whichever pair is closest to taking it. Resolved once, and the pairs are computed
	# from that same resolution rather than asked for again.
	var points := field.points_in(space)
	var pairs := field.pairs_from(space, points)
	for anchor in field.anchors:
		if not points.has(anchor.id):
			v.hands_down.append({"at": null, "kind": anchor.hand, "fuse": -1.0,
				"span": 0.0, "bolted": not anchor.is_hand()})
			continue
		v.hands_down.append({
			"at": points[anchor.id],
			"kind": anchor.hand,
			"fuse": field.progress_of(anchor, pairs),
			# Drawn faintly around every placed hand, because putting one down is a
			# PLAN now: what it will reach has to be visible before the thing it
			# reaches is there. See `WorldOverlay._draw_placed_hands`.
			"span": anchor.span(v.cell_size),
			"bolted": not anchor.is_hand(),
		})
	for pair in pairs:
		v.pairs.append({"a": points[(pair["a"] as Anchor).id],
			"b": points[(pair["b"] as Anchor).id]})

	for entry in loose_hand_points():
		var pickup: HandPickup = entry["pickup"]
		v.loose.append({
			"pos": Vector2(entry["pos"]),
			"kind": pickup.kind,
			"seed": WorldCore.hand_drift_seed(pickup.base_id, pickup.bp),
		})
	v.balls = hand_ball_points()

	if not v.flat:
		v.glue = glue_lines()
		if host_fold != null:
			v.exit_at = host_fold.crease_point1
			v.exit_ok = exit_blocker() == null
			v.exit_in_burst = glue_within_burst()

	v.aiming = placing()
	v.aim_at = cell_center(aim_cell())
	v.aim_hand = next_hand_type()
	# ...and no hold ring. A charging burst is worn by the BODY, which is both where
	# it will come from and the one thing on screen you are already watching.
	if v.aiming:
		# The cells the cursor may go to, as a rectangle, because the overlay should be
		# told the shape of the reach and not the arithmetic that produced it.
		var corner := player_cell() - Vector2i.ONE * ARM_REACH
		var side := float(2 * ARM_REACH + 1) * v.cell_size
		v.aim_box = Rect2(Vector2(corner) * v.cell_size, Vector2(side, side))
		# ...and every fold this hand would arm from where the cursor is standing. More
		# than one, now that a hand pairs with whatever it reaches: dropping one
		# between two lone anchors starts both, and the preview has to say so.
		v.aim_pairs = aim_partners(v.aim_at, v.aim_hand)
		# The span it would bring, drawn around the cursor: the reach you are placing
		# is part of choosing where to place it.
		v.aim_span = 0.0 if v.aim_hand < 0 else HandTypes.span(v.aim_hand) * v.cell_size

	# Where the burst WAS, not where you are: the ring is the sphere that went off, and
	# a plate's went off somewhere you may well have been carried away from since.
	v.burst_t = burst_flash()
	v.burst_at = _burst_at
	v.burst_radius = _burst_radius
	return v


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
## The facts the camera needs about this moment. Everything here is world
## knowledge — what must stay on screen, how the space repeats, whether a fold is
## mid-flight — which is exactly the part `WorldCamera` cannot work out for itself.
func _camera_context() -> Dictionary:
	return {
		"focus": _camera_focus(),
		"periods": lattice.periods(),
		"frozen": animating(),
		"viewport": get_viewport_rect().size,
	}


## `center` overrides where the BODY is taken to be.
func _update_camera(center: Vector2 = Vector2.INF) -> void:
	if camera == null:
		return
	camera.frame(_camera_context(), center)


func _size_pixel_view() -> void:
	if camera != null:
		camera.size_render_target(get_viewport_rect().size)


func _cut_camera() -> void:
	if camera != null:
		camera.cut(_camera_context())


## World points that would be a mistake to leave off screen right now.
func _camera_focus() -> PackedVector2Array:
	var pts := PackedVector2Array([player.global_position])
	# The folds that are HAPPENING, not every hand you ever put down.
	#
	# It used to be every placed anchor, which was right when there could only be two
	# of them and they were always a pair you were composing. Under proximity pairing a
	# hand can be left anywhere, indefinitely, as a plan — and framing a plan you walked
	# away from an hour ago would zoom the world out to nothing.
	#
	# An ARMED pair is different: it is a fold about to go off, and where you are
	# standing when it does is the decision the fuse exists to give you. So the lens
	# holds both its ends. That is bounded by construction — a pair cannot be further
	# apart than the two spans that made it — which is the property that lets the
	# camera have a rule here at all rather than a heuristic.
	for pair in armed_pairs():
		for entry in [pair["a"], pair["b"]]:
			var wp = anchor_point(entry)
			if wp != null:
				pts.append(Vector2(wp))
	# The cell being chosen is deliberately NOT here. It was, briefly, on the reasoning
	# that the one thing which must not be cropped while you pick it is the cell you
	# are picking — but the lens is held still for the whole of that (see
	# `PlayerBody.camera_held`), so it could not act on it then, and by the time it
	# could the hand is down and counted above as an anchor like any other. A focus
	# point nothing can move for is a focus point that does nothing.
	#
	# Inside a fold the strip IS the room: frame the fundamental domain, so a wide
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
	# The burst ring is a thing in the world and fades on the world's terms: held, it
	# hangs where it was, like everything else drawn out there. It DOES keep fading
	# through a fold animation — that draws no overlay at all, and a ring resuming
	# afterwards would be a burst announcing itself late.
	if not placing():
		_burst_flash_left = maxf(_burst_flash_left - delta, 0.0)
	# ...and the flash message does not, because it is not in the world. It counts how
	# long a line of text has been readable, which is a fact about your eyes.
	hud.tick(delta)
	_update_status()
	# Only the nearest handful of lights reach the shader; "nearest" is measured
	# from the player, not the origin.
	if light_rig != null:
		light_rig.set_focus(player.global_position)
	if animating():
		return
	# Time is stopped while a hand is up. Everything below this line MOVES THE WORLD ON
	# — the body's wrap, the fuses, the falling hands, doors, triggers — and none of it
	# should happen while you are choosing which cell to pin. Nothing is stored and
	# nothing is put back: the frame is simply not stepped, so the moment you resume is
	# the moment you left, down to the fraction of a fuse.
	#
	# `_process` deliberately keeps running: the camera goes on easing onto the cell you
	# are choosing, and the hold that cancels this has to keep counting.
	if placing():
		return

	_wrap_body()
	if lattice.is_flat() and player.global_position.y > (base.grid_size.y + 6) * CS:
		player.teleport(_spawn, false)
		AudioManager.play_sfx(Sounds.RESPAWN)
		_show_flash("You fell out of the world — respawned.")
	_tick_fuse(delta)
	# A fuse that just fired has started a fold TRANSITION, and the rest of this
	# frame belongs to it. Everything below reads the player's position and the
	# current piece list, and during a transition both are mid-flight: the body
	# is frozen at where it started and the geometry does not rebuild until the
	# animation finalizes. Letting a door fire from that state teleported the player
	# to another region and then finalized the fold's landing — computed in the
	# region they had just left — on top of it, which is how you ended up in a wall.
	if animating():
		return
	# Before the pickup check: a ball that lands this frame should be collectable this
	# frame, and one still in flight is caught in the air by `_check_pickups` itself.
	_step_hand_balls(delta)
	_check_goal()
	_check_pickups()
	_check_triggers()
	# A burst plate can start an unfold TRANSITION, so the same guard follows it as
	# follows the fuse: everything below reads a position and a piece list that are
	# halfway between two states while one is in flight.
	if animating():
		return
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
## How much slack a thing gets before it counts as having left the strip.
const STRIP_SLACK := 4.0 * CS


func _left_the_strip(point: Vector2) -> bool:
	return space.left_the_strip(point, STRIP_SLACK)


func _turn_back_point() -> Vector2:
	return space.turn_back_point()


func _wrap_body() -> void:
	var delta := lattice.wrap_delta(player.global_position)
	if delta != Vector2.ZERO:
		player.global_position += delta
		player.shift_camera(delta)
		# ...and so does anything drawn beside the body that remembers where it was
		# last frame. The hands you carry are the case that exists; the dispatch is
		# over every canvas so the next one does not have to be found the hard way.
		for canvas in _wrap_canvases():
			canvas.carry_through_wrap(delta)

	# Running off the far end of a strip does NOT force an exit (the exit can be
	# blocked by a crossing fold): the fold turns you back into itself. Only a
	# cylinder has such an end — a torus has nowhere to go, and a region has the
	# fall-out-of-the-world respawn instead.
	if _left_the_strip(player.global_position):
		var back := _turn_back_point()
		var landed := WorldCore.depenetrate(back, PlayerBody.RADIUS, wall_polys)
		player.teleport(back if landed == Vector2.INF else landed, false)
		_cut_camera()
		# Same sound as falling out of the world, because it is the same event
		# seen from inside a fold: you left the sheet and were put back.
		AudioManager.play_sfx(Sounds.RESPAWN)
		_show_flash("The fold turns back on itself here.")


## Tiles that react to being stood on.
##
## The tile NAMES its reaction (`TileTypes.on_enter_kind`) and carries that reaction's
## parameters in its own `data`; this is only the dispatch. Adding a reacting tile is a
## row in the registry and a branch here — not a new latch, not a second definition of
## what "entering" means.
##
## Edge-fired on ENTERING: the latch holds the base tile you were last checked against,
## so standing on a plate fires it once and stepping off and back on fires it again.
## The latch is kept in EVERY space, including inside a fold — it is a fact about where
## the body is, and only what a given reaction does with that is space-dependent.
func _check_triggers() -> void:
	if base == null:
		return
	var here = BaseFrame.piece_containing(pieces_by_pos, player.global_position, CS)
	if here == null:
		_trigger_latch = -1
		return
	if here.base_id == _trigger_latch:
		return
	_trigger_latch = here.base_id
	var tile := base.tile_by_id(here.base_id)
	if tile == null:
		return
	match TileTypes.on_enter_kind(tile.type):
		"fold":
			_fire_fold_trigger(tile)
		"burst":
			_fire_burst_plate(tile, here)


## A BURST PLATE: stepping on one fires a burst (§"HOLD") centred on the plate, at the
## reach the tile was authored with. The player's own gesture with two things taken
## away — you do not choose when, and you do not choose where.
##
## Centred on the PLATE and not on the body, because the plate is what goes off: a wide
## one then reaches the same things whichever side you stepped on from, and the ring
## says where the sphere actually was. You are standing on it either way, so a plate can
## only ever reach MORE than you could have from there, never less.
##
## Fires at any depth, unlike a fold plate. A burst takes folds out of the current
## space's list rather than splicing new ones into it, and `_burst` is the same rule
## inside a fold as in a region — including the clause that opens the way out.
##
## A plate authored with no reach at all (zero or less) is inert, on purpose — the same
## latitude a trigger with no anchors gets. A half-authored tile is a thing you are
## allowed to leave on the canvas overnight; the editor's job is to make sure you know.
## A plate you paint and never touch is not that: it takes the registry's default,
## which is your own reach.
func _fire_burst_plate(tile: BaseTile, piece) -> void:
	var radius := float(TileParams.get_value(tile.type, tile.data, "radius")) * CS
	if radius <= 0.0:
		return
	# Where the plate is in THIS frame. `polygon == base_polygon + src_offset` is the
	# invariant the whole game rides on, so the flap the player is standing on carries
	# the plate's own centre with it — no crease arithmetic, and no second lookup that
	# could land on the far half of a tile a crease has cut in two.
	var center: Vector2 = (Vector2(tile.grid_position) + Vector2(0.5, 0.5)) * CS + piece.src_offset
	# The plate answering, under whatever the burst then does. A plate you did not press
	# has to be heard even when it finds nothing — unlike your own burst, you did not
	# already know it was coming.
	AudioManager.play_sfx(Sounds.TRIGGER)
	if _burst(center, radius) > 0:
		_show_flash("The plate lets go — space springs open.")


## Fold-on-enter tiles: a plate does not make a FOLD, it makes a CHANNEL LIVE.
##
## This is where the unification pays for itself. A plate used to run its own cascade
## — resolve the authored cells against the current fold state, build a fold, check
## the pin rule, transport the player, iterate to a fixpoint under a cap — a second
## implementation of folding that had to be kept in step with the real one and could
## only ever work in a region. Now it drives two bolted anchors into the sheet and
## steps back, and everything after that is the path every other fold takes: they
## pair because they were declared, a fuse lights, `fire_pair` applies it with the
## animation and the ride, and the player rides or is pinched exactly as they would
## be by a fold of their own.
##
## Three consequences worth naming, because each was a rule that lived in the
## resolver and now lives nowhere:
##
##   - **A plate's fold takes a fuse.** The ground answering you comes with the same
##     beat of warning every other fold gives, instead of arriving as a teleport.
##   - **A plate's fold may PINCH you**, because `do_fold` swallows whoever is in the
##     strip and there is no longer a second path that could refuse to. Deliberate:
##     with a fuse you can see it coming, which was most of the old objection.
##   - **A plate works at any depth.** The resolver could only splice into a region's
##     fold list; `do_fold` splices into whatever list the space it is called in owns.
##
## Idempotence is the anchors themselves: a site holds one anchor, and a channel whose
## fold is already standing is not fired again. The cascade cap is gone with the
## cascade — firing consumes two anchors and nothing here makes one without the player
## walking onto a plate, so there is nothing left to run away.
func _fire_fold_trigger(tile: BaseTile) -> void:
	var channel := str(tile.data.get("channel", ""))
	if channel != "":
		for f in space_folds():
			if f.channel == channel:
				return              # its fold is already standing
	var cells: Array = tile.data.get("anchors", [])
	if cells.size() < HandStock.HANDS_PER_FOLD:
		return                      # half-configured plate: nothing to pin
	if not _plant_pair(cells, channel):
		return
	AudioManager.play_sfx(Sounds.TRIGGER)
	_show_flash("The ground answers — space folds around you.")


## Drive a declared pair of bolted anchors into the sheet at two BASE cells of this
## region. Returns whether anything went down.
##
## Refused rather than half-done if either site is taken or unresolvable: half a
## declared pair is an anchor that can never fire, and leaving one standing would be
## a permanent mark on the world for a plate that did nothing.
func _plant_pair(cells: Array, channel: String) -> bool:
	var planted: Array = []
	var sites: Array = []
	for raw in cells.slice(0, HandStock.HANDS_PER_FOLD):
		sites.append(Vector2i(int(raw[0]), int(raw[1])))
	if not WorldCore.anchors_valid(sites[0], sites[1]):
		return false                # both cells the same: no crease direction to have
	for cell in sites:
		var anchor := Anchor.new()
		anchor.cell = cell
		anchor.region = region_id
		anchor.bond = Anchor.BOLTED
		anchor.arms = channel if channel != "" else Anchor.PROXIMITY
		if not anchor.bind(base):
			return false
		var wp = anchor.point_in(current_pieces, region_id)
		if wp == null or field.at_point(space, Vector2(wp), CS * 0.5) != null:
			return false            # folded away, or something is already pinned there
		planted.append(anchor)
	for anchor in planted:
		field.add(anchor)
	planted[0].partner = planted[1].id
	planted[1].partner = planted[0].id
	field.light_channel(channel)
	return true


## Loose hands: walk onto one and it is yours, if you have a slot free.
##
## One object covers both the loose hands a world ships and the hands that pop out of a
## burst, because to the player they are one thing. It only takes if a slot is free,
## and a slot is free because you PUT A HAND DOWN — so one is not a stockpile you
## raid on the way past, it is the second half of a fold you have already started.
##
## Works in a region AND inside a subspace: a hand the fold swallowed is lying in
## there with everything else, and taking it in there counts.
func _check_pickups() -> void:
	if HandStock.first_empty(hands) < 0:
		return                      # full hands walk over it, and it waits
	# A hand still in the air is a hand you can catch. It would be strange to be able to
	# collect one the instant it stopped moving but not a moment earlier, when it is
	# right in front of you — and catching one out of a burst is a good feeling.
	for i in range(hand_balls.size() - 1, -1, -1):
		var ball: Dictionary = hand_balls[i]
		if bool(ball["in_sub"]) != (mode == Mode.SUBSPACE) \
				or String(ball["region"]) != region_id:
			continue
		if gap_to(player.global_position, Vector2(ball["pos"])) > PlayerBody.RADIUS + 8.0:
			continue
		hands[HandStock.first_empty(hands)] = int(ball["kind"])
		hand_balls.remove_at(i)
		AudioManager.play_sfx(Sounds.HAND_PICKUP)
		_show_flash("Caught a %s hand." % HandTypes.type_name(int(ball["kind"])))
		return
	if loose_hands.is_empty():
		return
	for i in range(loose_hands.size()):
		var pickup: HandPickup = loose_hands[i]
		var wp = pickup.position_in(current_pieces)
		if wp == null:
			continue                # folded away — not here to be picked up
		if gap_to(player.global_position, Vector2(wp)) > PlayerBody.RADIUS + 8.0:
			continue
		hands[HandStock.first_empty(hands)] = pickup.kind
		loose_hands.remove_at(i)
		AudioManager.play_sfx(Sounds.HAND_PICKUP)
		_show_flash("Picked up a %s hand." % HandTypes.type_name(pickup.kind))
		return


## Where every loose hand in the current view lies right now, as
## `[{"pickup", "pos"}, ...]`. The overlay draws these; a hand folded away resolves
## to nothing and is simply not in the list.
func loose_hand_points() -> Array:
	return HandPickup.resolve_all(current_pieces, loose_hands)


## Hands in flight in the CURRENT view, as `[{"kind", "pos", "seed"}, ...]`.
##
## Separate from `loose_hand_points` because these are the ones that DO have a position
## of their own — that is the whole difference between a ball and a pickup, and the
## overlay draws them from their own position rather than by resolving a base point.
## Balls flying in the other view are not here: they are not in this space.
func hand_ball_points() -> Array:
	return hand_field.points_in(space)


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
## `_setup_all` rebuilds the loose-hand lists from the authored world, so loose hands
## respawn and hands dropped during play are forgotten. That is the coherent reading
## now that the number you can hold does not grow: a pickup is another hand for an
## empty slot, not a permanent upgrade, and hands are exactly what a reset restores —
## leaving loose hands spent would strand you at fewer hands than you started with, which
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
	_hold_elapsed = 0.0
	# A hand up over a world that is about to be replaced is a cursor pointing at cells
	# that will not exist. R unfreezes as well as rebuilding.
	_aim = null
	player.frozen = false
	_burst_flash_left = 0.0
	context.clear()
	_setup_all()
	AudioManager.play_sfx(Sounds.RESET)
	_show_flash("Reset.")


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	hud = WorldHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.build()
	# Read once, at build: like `world_override`, it is set before the node enters the
	# tree, by whoever opened the run.
	hud.set_session_hint(session_hint)


func _update_status() -> void:
	if hud == null:
		return
	var kinds: Array = []
	for h in hands:
		kinds.append("—" if h == null else HandTypes.type_name(int(h)))
	var stock := "Hands: %s   (%d down, %d in folds)" \
		% [" ".join(kinds), hands_pending(), hands_in_folds()]
	var pairs := armed_pairs()
	if not pairs.is_empty():
		stock += "   %d armed" % pairs.size()
	# The one state the world itself cannot show, because the way it shows it is by
	# not moving — and a world that is not moving looks the same as a world you are
	# not moving in.
	if placing():
		stock += "   ⏸ PLACING (time stopped)"
	if context.is_empty():
		hud.set_status("Region: %s   Folds: %d   Mode: WORLD\n%s"
			% [region_id, folds.size(), stock])
	else:
		# How deep, and what shape the space you are in has come out: one period is
		# a cylinder you can run off the ends of, two is a torus with no outside.
		hud.set_status("Region: %s   Folds: %d   Mode: INSIDE FOLD x%d — %s (%d inner)\n%s"
			% [region_id, folds.size(), context.size(), _space_name(),
				space_folds().size(), stock])


## What shape the space you are standing in is, from how many ways it repeats.
func _space_name() -> String:
	match lattice.depth():
		0: return "cut open"
		1: return "cylinder"
		_: return "torus"


func _show_flash(text: String) -> void:
	hud.flash(text)


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
## whether it reads as one. This is the cheapest honest answer: the subspace
## has its own bed, and crossing the boundary crossfades between them.
func _update_music() -> void:
	AudioManager.play_music(Sounds.MUSIC_SUBSPACE if mode == Mode.SUBSPACE
		else Sounds.MUSIC_REGION)
