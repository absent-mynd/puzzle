class_name TriggerResolver extends RefCounted

## TriggerResolver
##
## Resolves the reaction cascade that follows a single authored step (F3). It runs
## INSIDE StepReplay.apply_step — i.e. as part of the pure derivation — so triggered
## folds are recomputed on every replay and are therefore deterministic and undoable
## for free (dropping the authored step re-derives the prefix without the cascade).
##
## The only reaction in this slice is "fold-on-enter": when a step lands the player
## on a TRIGGER_FOLD tile, a fold is created between the anchors named in that tile's
## per-instance data, tagged with the tile's channel. The cascade iterates because a
## triggered fold can ride the player onto another trigger.
##
## Determinism & termination:
##   - Each trigger fires at most once per cascade (a `fired` set — the cycle guard).
##   - A fold is created only if no active fold already holds that channel
##     (idempotence: standing on a trigger does not spawn duplicates).
##   - A hard iteration cap (MAX_CASCADE) is the backstop; on hitting it the cascade
##     terminates SILENTLY (per the confirmed decision) rather than looping forever.

## Backstop for pathological cascades. Far above any hand-authored chain.
const MAX_CASCADE := 64

## Triggered folds get ids from a reserved high range so they never collide with the
## engine's player-fold ids (which count up from 0). Deterministic across replays
## because the step/cascade order is deterministic.
const TRIGGER_FOLD_ID_BASE := 1_000_000


## Run `step_fn` on `cp` until it reports done or the cap is hit. `step_fn(cp)` must
## return {"done": bool, "cp": <next>}. Generic and side-effect-free so the cap/loop
## can be unit-tested in isolation from the trigger semantics.
static func run_to_fixpoint(cp, step_fn: Callable):
	var cur = cp
	for _i in range(MAX_CASCADE):
		var res: Dictionary = step_fn.call(cur)
		cur = res["cp"]
		if res["done"]:
			return cur
	# Cap hit: terminate silently with whatever we have so far.
	return cur


## Resolve the full cascade following a step, returning the settled checkpoint.
static func resolve(base: BaseGrid, cp: Dictionary) -> Dictionary:
	var fired := {}  # trigger tile base_id -> true, scoped to THIS cascade
	var step_fn := func(c: Dictionary) -> Dictionary:
		var reaction := _next_reaction(base, c, fired)
		if reaction.is_empty():
			return {"done": true, "cp": c}
		return {"done": false, "cp": _apply_fold_reaction(base, c, reaction, fired)}
	return run_to_fixpoint(cp, step_fn)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The next reaction fireable from ANY player body's tile, or {} if none. A split
## player fires a trigger if any of its bodies rides one.
static func _next_reaction(base: BaseGrid, cp: Dictionary, fired: Dictionary) -> Dictionary:
	for base_id in cp["base_ids"]:
		if base_id < 0 or fired.has(base_id):
			continue
		var tile := base.tile_by_id(base_id)
		if tile == null or TileTypes.on_enter_kind(tile.type) != "fold":
			continue
		var channel: String = str(tile.data.get("channel", ""))
		# Idempotent: don't spawn a second fold for a channel that already has one.
		var channel_taken := false
		for f in cp["folds"]:
			if f.channel == channel and channel != "":
				channel_taken = true
				break
		if channel_taken:
			continue
		var anchors: Array = tile.data.get("anchors", [])
		if anchors.size() < 2:
			continue
		return {"trigger_id": base_id, "channel": channel, "anchors": anchors}
	return {}


## Apply a fold reaction: resolve the anchors through the current fold state (so they
## ride prior folds), create the channel-tagged fold, and extend the checkpoint.
static func _apply_fold_reaction(base: BaseGrid, cp: Dictionary, reaction: Dictionary, fired: Dictionary) -> Dictionary:
	fired[reaction["trigger_id"]] = true  # fire once per cascade regardless of outcome
	var a := _resolve_anchor(base, cp, reaction["anchors"][0])
	var b := _resolve_anchor(base, cp, reaction["anchors"][1])
	# Anchor excised/unresolvable, or degenerate fold -> skip (trigger still "fired").
	if a == _UNRESOLVED or b == _UNRESOLVED or a == b:
		return cp

	var fid: int = cp["next_trigger_fold_id"]
	var f := Fold.create(fid, a, b, base.cell_size, reaction["channel"])
	var folds: Array[Fold] = (cp["folds"] as Array).duplicate()
	folds.append(f)
	var pre_state: FoldedState = cp["state"]
	var pieces := FoldReplay.apply_one_fold(cp["pieces"], f, base.cell_size)
	var state := FoldReplay.state_from_pieces(pieces)
	# A triggered fold splits occupants exactly like a player fold (latents recorded).
	var out: Array = []
	for occ in cp["occupants"]:
		out.append(StepReplay._fold_occupant(occ, f, pre_state, state, base.cell_size))
	return StepReplay._finish(out, cp["plane_pos"], pieces, state, folds, fid + 1)


const _UNRESOLVED := Vector2i(-2147483648, -2147483648)

## Map an author-specified BASE grid position to its CURRENT plane position (so
## triggered-fold anchors follow whatever earlier folds did). Returns _UNRESOLVED if
## the base tile is gone from the surface.
static func _resolve_anchor(base: BaseGrid, cp: Dictionary, raw) -> Vector2i:
	var base_pos := Vector2i(int(raw[0]), int(raw[1]))
	var tile := base.tile_at(base_pos)
	if tile == null:
		return _UNRESOLVED
	var state: FoldedState = cp["state"]
	if not state.has_base(tile.base_id):
		return _UNRESOLVED
	return state.plane_pos_of_base(tile.base_id)
