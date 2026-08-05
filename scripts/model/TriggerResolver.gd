class_name TriggerResolver extends RefCounted

## TriggerResolver
##
## Resolves the fold cascade that follows the player entering a trigger tile.
##
## The only reaction is "fold-on-enter": when the player stands on a TRIGGER_FOLD tile,
## a fold is created between the anchors named in that tile's per-instance data, tagged
## with the tile's channel. The cascade iterates because a triggered fold RIDES the
## player — possibly onto another trigger.
##
## Previously this ran inside the step log, which made it undoable for free. The world
## is continuous now, so it runs against a fragment list and a continuous player
## position instead: each reaction applies its fold to the pieces and transports the
## player through `BaseFrame`, exactly as a player-initiated fold does. The determinism
## properties are unchanged and still carried by this file:
##
##   - Each trigger fires at most once per cascade (a `fired` set — the cycle guard).
##   - A fold is created only if no active fold already holds that channel
##     (idempotence: standing on a trigger does not spawn duplicates).
##   - A hard iteration cap (MAX_CASCADE) is the backstop; on hitting it the cascade
##     terminates SILENTLY rather than looping forever.

## Backstop for pathological cascades. Far above any hand-authored chain.
const MAX_CASCADE := 64

## Triggered folds get ids from a reserved high range so they never collide with the
## player-fold ids (which count up from 0).
const TRIGGER_FOLD_ID_BASE := 1_000_000

const _UNRESOLVED := Vector2i(-2147483648, -2147483648)


## Run `step_fn` on `cp` until it reports done or the cap is hit. `step_fn(cp)` must
## return {"done": bool, "cp": <next>}. Generic and side-effect free so the cap/loop can
## be unit-tested in isolation from the trigger semantics.
static func run_to_fixpoint(cp, step_fn: Callable):
	var cur = cp
	for _i in range(MAX_CASCADE):
		var res: Dictionary = step_fn.call(cur)
		cur = res["cp"]
		if res["done"]:
			return cur
	# Cap hit: terminate silently with whatever we have so far.
	return cur


## Resolve the full cascade following the player arriving at `player_pos`.
##
## `ctx` is {"folds": Array[Fold], "pieces": Array, "player_pos": Vector2,
##           "next_trigger_id": int} and a settled copy of the same shape is returned.
## `occupants` (optional) is carried through the same split-on-fold treatment as a
## player fold, so triggered folds cut entities identically.
static func resolve(base: BaseGrid, ctx: Dictionary) -> Dictionary:
	var fired := {}  # trigger tile base_id -> true, scoped to THIS cascade
	var step_fn := func(c: Dictionary) -> Dictionary:
		var reaction := _next_reaction(base, c, fired)
		if reaction.is_empty():
			return {"done": true, "cp": c}
		return {"done": false, "cp": _apply_fold_reaction(base, c, reaction, fired)}
	return run_to_fixpoint(ctx, step_fn)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The reaction fireable from the tile the player currently stands on, or {} if none.
static func _next_reaction(base: BaseGrid, ctx: Dictionary, fired: Dictionary) -> Dictionary:
	var piece = BaseFrame.piece_at(ctx["pieces"], ctx["player_pos"], base.cell_size)
	if piece == null:
		return {}
	var base_id: int = piece.base_id
	if base_id < 0 or fired.has(base_id):
		return {}
	var tile := base.tile_by_id(base_id)
	if tile == null or TileTypes.on_enter_kind(tile.type) != "fold":
		return {}
	var channel: String = str(tile.data.get("channel", ""))
	# Idempotent: don't spawn a second fold for a channel that already has one.
	if channel != "":
		for f in ctx["folds"]:
			if f.channel == channel:
				return {}
	var anchors: Array = tile.data.get("anchors", [])
	if anchors.size() < 2:
		return {}
	return {"trigger_id": base_id, "channel": channel, "anchors": anchors}


## Apply a fold reaction: resolve the anchors through the current fold state (so they
## ride prior folds), create the channel-tagged fold, extend the fragment list, and
## transport the player onto whichever flap carried them.
static func _apply_fold_reaction(base: BaseGrid, ctx: Dictionary, reaction: Dictionary, fired: Dictionary) -> Dictionary:
	fired[reaction["trigger_id"]] = true  # fire once per cascade regardless of outcome
	var pieces: Array = ctx["pieces"]
	var a := _resolve_anchor(base, pieces, reaction["anchors"][0])
	var b := _resolve_anchor(base, pieces, reaction["anchors"][1])
	# Anchor excised/unresolvable, or degenerate fold -> skip (trigger still "fired").
	if a == _UNRESOLVED or b == _UNRESOLVED or a == b:
		return ctx

	var fid: int = ctx["next_trigger_id"]
	var f := Fold.create(fid, a, b, base.cell_size, reaction["channel"])

	# A pin refuses every fold, including one a plate fires. Otherwise a trigger would
	# be a back door around the one tile type that promises it cannot be folded away.
	if FoldReplay.blocked_by_tile(pieces, f, base.cell_size):
		return ctx

	# Build the typed list explicitly: callers may hand us a plain Array.
	var folds: Array[Fold] = []
	for existing in ctx["folds"]:
		folds.append(existing)
	folds.append(f)
	var new_pieces := FoldReplay.apply_one_fold(pieces, f, base.cell_size)

	# Transport the player onto the flap that carried them. A trigger fold that would
	# swallow the player (no surviving destination) is refused: a trap the player cannot
	# see coming should not pinch them into a subspace.
	var dest = BaseFrame.transport(pieces, new_pieces, ctx["player_pos"], base.cell_size)
	if dest == null:
		return ctx

	var out := ctx.duplicate()
	out["folds"] = folds
	out["pieces"] = new_pieces
	out["player_pos"] = dest
	out["next_trigger_id"] = fid + 1
	# A triggered fold splits occupants exactly like a player fold (latents recorded).
	if ctx.has("occupants"):
		out["occupants"] = Occupants.fold_all(
			ctx["occupants"], f,
			FoldReplay.state_from_pieces(pieces),
			FoldReplay.state_from_pieces(new_pieces),
			base.cell_size)
	return out


## Map an author-specified BASE grid position to its CURRENT plane position (so
## triggered-fold anchors follow whatever earlier folds did). Returns _UNRESOLVED if the
## base tile is gone from the surface.
static func _resolve_anchor(base: BaseGrid, pieces: Array, raw) -> Vector2i:
	var base_pos := Vector2i(int(raw[0]), int(raw[1]))
	var tile := base.tile_at(base_pos)
	if tile == null:
		return _UNRESOLVED
	for piece in pieces:
		if piece.base_id == tile.base_id:
			return piece.plane_pos
	return _UNRESOLVED
