class_name Occupants extends RefCounted

## Occupants
##
## Entities that RIDE base tiles, and therefore survive folding. An occupant is an
## identity — `{kind, base_ids, latents, shapes, fp_latents}` — that owns a set of base
## tiles rather than a world position, so every fold and unfold repositions it for free.
##
## Extracted from the derive/replay engine's step log, which is gone: the world is
## continuous now and the player is a physics body transported by `BaseFrame`, not a
## tile-hopper. What survives is the part that was never about grid movement — how a
## body behaves when a fold cuts through it:
##
## SPLIT-ON-UNFOLD: when a fold removes area a body occupies, the folded-away part is
## remembered as a LATENT `{base_id, fold_id}`, plus an `fp_latent` carrying the excised
## GEOMETRY. The surviving flap (if any) stays active and can move away. UNFOLDing that
## fold re-materializes the latent at its home tile — so if the active part moved, the
## occupant is now in two places: a SPLIT. A body entirely inside the excised strip has
## no surviving flap: it is hidden until unfold, then reappears where it was.
##
## This is the model for world entities — items, save points, enemies, movable blocks.
## The player does not use it: a continuous body has no single ridden tile.

enum { KIND_ENTITY, KIND_ANCHOR }


## Build a fresh occupant with empty carried-shape state.
static func make(kind: int, base_ids: Array, channel := "", collides := true) -> Dictionary:
	var ids: Array[int] = []
	for b in base_ids:
		ids.append(b)
	return {
		"kind": kind, "base_ids": ids, "latents": [], "channel": channel,
		"collides": collides, "shapes": {}, "fp_latents": [],
	}


## Occupants declared in the base grid: a tile with `data.occupant` set. Anchors carry
## an optional channel and never collide — they are pure markers.
static func from_base(base: BaseGrid) -> Array:
	var out: Array = []
	for t in base.tiles:
		var kind_name: String = t.data.get("occupant", "")
		if kind_name == "anchor":
			out.append(make(KIND_ANCHOR, [t.base_id] as Array[int], str(t.data.get("channel", "")), false))
		elif kind_name != "":
			out.append(make(KIND_ENTITY, [t.base_id] as Array[int], str(t.data.get("channel", "")), true))
	return out


## Rebuild an occupant with new base_ids/latents, preserving carried-shape state and
## identity fields.
static func _rebuilt(occ: Dictionary, base_ids: Array, latents: Array) -> Dictionary:
	var ids: Array[int] = []
	for b in base_ids:
		ids.append(b)
	return {
		"kind": occ["kind"], "base_ids": ids, "latents": latents,
		"channel": occ.get("channel", ""), "collides": occ.get("collides", true),
		"shapes": occ.get("shapes", {}), "fp_latents": occ.get("fp_latents", []),
	}


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## The distinct plane cells occupied by the given ridden base ids (one per body; more
## when a body has been split by a fold). Union across all ridden base tiles.
static func positions_of_bases(base_ids: Array, state: FoldedState) -> Array:
	var seen := {}
	for bid in base_ids:
		for pos in state.plane_positions_of_base(bid):
			seen[pos] = true
	return seen.keys()


## Positions occupied by one occupant.
static func positions(occ: Dictionary, state: FoldedState) -> Array:
	return positions_of_bases(occ["base_ids"], state)


## The occupant's current geometry (plane-space polygons). A body normally takes the
## shape of the tile piece it rides; once it has a CARRIED shape (a rigid cut piece)
## it uses that instead, anchored to the base tile's current position so it repositions
## automatically through folds and unfolds. `shapes[bid]` is stored RELATIVE to bid's
## origin (plane_pos * cell_size).
static func footprint(occ: Dictionary, state: FoldedState, cell_size := 64.0) -> Array:
	var out: Array = []
	var shapes: Dictionary = occ.get("shapes", {})
	for bid in occ["base_ids"]:
		if shapes.has(bid):
			out.append(CollisionCore.shift(shapes[bid], _origin(state, bid, cell_size)))
		else:
			for p in state.pieces_of_base(bid):
				out.append(p.polygon)
	return out


## Is this occupant currently hidden entirely (every body folded away)?
static func is_hidden(occ: Dictionary) -> bool:
	return (occ["base_ids"] as Array).is_empty()


static func of_kind(occupants: Array, kind: int) -> Array:
	var out: Array = []
	for occ in occupants:
		if occ["kind"] == kind:
			out.append(occ)
	return out


## Origin (px) of a base tile's current primary cell — carried shapes are relative to it.
static func _origin(state: FoldedState, bid: int, cell_size: float) -> Vector2:
	return Vector2(state.plane_pos_of_base(bid)) * cell_size


## Absolute polygons of ONE body (base id): its carried shape if present, else the tile
## piece(s) it rides.
static func _body_abs(bid: int, shapes: Dictionary, state: FoldedState, cell_size: float) -> Array:
	if shapes.has(bid):
		return [CollisionCore.shift(shapes[bid], _origin(state, bid, cell_size))]
	var out: Array = []
	for p in state.pieces_of_base(bid):
		out.append(p.polygon)
	return out


# ---------------------------------------------------------------------------
# Fold / unfold response
# ---------------------------------------------------------------------------

## Apply a fold to every occupant in a list.
static func fold_all(occupants: Array, f: Fold, pre: FoldedState, post: FoldedState, cell_size: float) -> Array:
	var out: Array = []
	for occ in occupants:
		out.append(on_fold(occ, f, pre, post, cell_size))
	return out


## Apply an unfold to every occupant in a list.
static func unfold_all(occupants: Array, fold_id: int, state: FoldedState, cell_size: float) -> Array:
	var out: Array = []
	for occ in occupants:
		out.append(on_unfold(occ, fold_id, state, cell_size))
	return out


## Split-on-fold: for each ridden tile, if the fold removes area it holds, remember the
## folded-away part (a `latent` for position, plus an `fp_latent` carrying the excised
## GEOMETRY that reappears on unfold). The surviving flap stays active; a carried shape
## is clipped with the fold so a cut body stays cut.
static func on_fold(occ: Dictionary, f: Fold, pre_state: FoldedState, post_state: FoldedState, cell_size: float) -> Dictionary:
	var active: Array[int] = []
	var latents: Array = (occ["latents"] as Array).duplicate()
	var shapes: Dictionary = (occ.get("shapes", {}) as Dictionary).duplicate()
	var fp_latents: Array = (occ.get("fp_latents", []) as Array).duplicate()
	for t in occ["base_ids"]:
		if not tile_loses_area(t, f, pre_state):
			if post_state.has_base(t):
				active.append(t)
			continue
		# The fold cuts this body: split its current shape into kept flap(s) + dropped.
		var res := CollisionCore.fold_polygons(_body_abs(t, shapes, pre_state, cell_size), f, cell_size)
		var pre_o := _origin(pre_state, t, cell_size)
		for d in res["dropped"]:
			fp_latents.append({"base_id": t, "fold_id": f.fold_id, "rel": CollisionCore.shift(d, -pre_o)})
		latents.append({"base_id": t, "fold_id": f.fold_id})
		if post_state.has_base(t):
			active.append(t)
			if shapes.has(t):  # a carried (diverged) body: keep its clipped flap as the shape
				var kept := CollisionCore.union_all(res["a"] + res["b"])
				if kept.size() == 1:
					shapes[t] = CollisionCore.shift(kept[0], -_origin(post_state, t, cell_size))
	var out := _rebuilt(occ, active, latents)
	out["shapes"] = shapes
	out["fp_latents"] = fp_latents
	return out


## Undo a fold's effect on an occupant: latents tagged with this fold materialize as
## active bodies again (their home tile is whole once more). Duplicates dedup — a body
## that never moved simply rejoins itself, with no spurious split.
static func on_unfold(occ: Dictionary, fold_id: int, state: FoldedState, cell_size: float) -> Dictionary:
	var was_active := {}
	for b in occ["base_ids"]:
		was_active[b] = true
	var active := was_active.duplicate()
	var remaining: Array = []
	for lat in occ["latents"]:
		if lat["fold_id"] == fold_id:
			active[lat["base_id"]] = true
		else:
			remaining.append(lat)
	# Re-materialize the excised GEOMETRY for base ids that reappear as NEW bodies (the
	# survivor moved away). A base id that was still active just rejoins to whole.
	var shapes: Dictionary = (occ.get("shapes", {}) as Dictionary).duplicate()
	var remaining_fp: Array = []
	var restore := {}
	for fpl in occ.get("fp_latents", []):
		if fpl["fold_id"] == fold_id:
			if not restore.has(fpl["base_id"]):
				restore[fpl["base_id"]] = []
			restore[fpl["base_id"]].append(fpl["rel"])
		else:
			remaining_fp.append(fpl)
	for bid in restore.keys():
		if was_active.has(bid):
			shapes.erase(bid)  # rejoin: the whole base tile piece covers it again
			continue
		var merged := CollisionCore.union_all(restore[bid])
		if merged.size() >= 1:
			shapes[bid] = merged[0]  # reappears with its missing (cut) geometry
	var out := _rebuilt(occ, _keys_int(active), remaining)
	out["shapes"] = shapes
	out["fp_latents"] = remaining_fp
	return out


## True if any of base tile `t`'s pre-fold surface area lies strictly inside the fold's
## excised strip (i.e. the fold hides part of it).
static func tile_loses_area(t: int, f: Fold, pre_state: FoldedState) -> bool:
	var gap: float = f.gap_distance()
	var eps := GeometryCore.EPSILON
	for p in pre_state.pieces_of_base(t):
		for v in p.polygon:
			var d: float = (v - f.crease_point1).dot(f.crease_normal)
			if d > eps and d < gap - eps:
				return true
	return false


static func _keys_int(d: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for k in d.keys():
		out.append(k)
	return out
