class_name StepReplay extends RefCounted

## StepReplay
##
## Replays an ordered FoldStep log over the immutable base grid to produce the full
## derived world. FoldReplay derives geometry from a fold list; StepReplay derives
## geometry AND the world's OCCUPANTS from an action log.
##
## OCCUPANTS (F6) generalize the player: an occupant is an identity that RIDES a set
## of base tiles — `{kind, base_ids, latents}`. The player is one occupant; pushable
## boxes and (later) anchors are others.
##
## SPLIT-ON-UNFOLD: when a fold removes area a body occupies, that folded-away part is
## remembered as a LATENT `{base_id, fold_id}` (the part that "vanished in the seam").
## The surviving flap (if any) stays an active body and can move away freely. UNFOLDing
## that fold re-materializes the latent as an active body at its home tile — so if the
## active part had moved, the occupant is now in two places: a SPLIT. A body fully in
## the excised region has no surviving flap (e.g. a folded-over box): it's hidden until
## unfold, then reappears where it was. Everything rides tiles, so this is uniform
## across player / box / future occupants.
##
## A "checkpoint" is the derived world after some prefix of the log:
##   {
##     pieces:    Array[FoldedPiece],  # fragment list (to extend by the next fold)
##     folds:     Array[Fold],         # active folds (id-stable, ordered)
##     occupants: Array[Dictionary],   # every occupant {kind, base_ids}
##     base_ids:  Array[int],          # PLAYER occupant's bodies — compat/derived
##     base_id:   int,                 # primary player body (largest fragment) — compat
##     plane_pos: Vector2i,            # primary player body's plane position — compat
##     state:     FoldedState,         # queryable state built from `pieces`
##     next_trigger_fold_id: int,      # F3 reserved-id counter
##   }

enum { KIND_PLAYER, KIND_BOX, KIND_ANCHOR }


## Checkpoint for the empty log: identity geometry, occupants on their start tiles.
static func initial(base: BaseGrid, initial_base_id: int) -> Dictionary:
	var pieces := FoldReplay.identity_pieces(base)
	var state := FoldReplay.state_from_pieces(pieces)
	var occupants: Array = []
	var pbids: Array[int] = []
	if initial_base_id >= 0:
		pbids.append(initial_base_id)
	occupants.append(_new_occ(KIND_PLAYER, pbids, "", true))
	# Occupants declared in the base grid: a floor tile with data.occupant "box" or
	# "anchor" (anchors carry an optional channel; they don't collide — pure markers).
	for t in base.tiles:
		var kind_name: String = t.data.get("occupant", "")
		if kind_name == "box":
			occupants.append(_new_occ(KIND_BOX, [t.base_id] as Array[int], "", true))
		elif kind_name == "anchor":
			occupants.append(_new_occ(KIND_ANCHOR, [t.base_id] as Array[int], str(t.data.get("channel", "")), false))
	return _finish(occupants, Vector2i.ZERO, pieces, state, [] as Array[Fold],
		TriggerResolver.TRIGGER_FOLD_ID_BASE)


## Extend a checkpoint by one step, returning a NEW checkpoint (inputs untouched).
## After the authored step is applied, the trigger cascade (F3) is resolved as part
## of the same derivation, so triggered folds are deterministic and undo drops the
## whole cascade with its step.
static func apply_step(base: BaseGrid, cp: Dictionary, step: FoldStep) -> Dictionary:
	var stepped := cp
	match step.kind:
		FoldStep.Kind.FOLD:
			stepped = _apply_fold_step(base, cp, step)
		FoldStep.Kind.UNFOLD:
			stepped = _apply_unfold_step(base, cp, step)
		FoldStep.Kind.MOVE:
			stepped = _apply_move_step(base, cp, step)
		FoldStep.Kind.PLACE_ANCHOR:
			stepped = _apply_place_anchor(cp, step)
	return TriggerResolver.resolve(base, stepped)


## From-scratch pure derivation of the whole log (restore / determinism tests).
static func derive(base: BaseGrid, steps: Array, initial_base_id: int) -> Dictionary:
	var cp := initial(base, initial_base_id)
	for s in steps:
		cp = apply_step(base, cp, s)
	return cp


## The distinct plane cells occupied by the given ridden base ids (one per body; more
## when a body has been split by a fold). Union across all ridden base tiles.
static func player_positions(base_ids: Array, state: FoldedState) -> Array:
	var seen := {}
	for bid in base_ids:
		for pos in state.plane_positions_of_base(bid):
			seen[pos] = true
	return seen.keys()


## Positions occupied by one occupant.
static func occupant_positions(occ: Dictionary, state: FoldedState) -> Array:
	return player_positions(occ["base_ids"], state)


## The occupant's current geometry (plane-LOCAL polygons). A body normally takes the
## shape of the tile fragment it rides, but once it has a CARRIED shape (Stage 4 — a
## rigid cut piece that moved) it uses that instead, anchored to the base tile's current
## position so it repositions automatically through folds/unfolds. `shapes[bid]` is
## stored RELATIVE to bid's origin (plane_pos*cell_size).
static func occupant_footprint(occ: Dictionary, state: FoldedState, cell_size: float = 64.0) -> Array:
	var out: Array = []
	var shapes: Dictionary = occ.get("shapes", {})
	for bid in occ["base_ids"]:
		if shapes.has(bid):
			out.append(CollisionCore.shift(shapes[bid], _origin(state, bid, cell_size)))
		else:
			for p in state.pieces_of_base(bid):
				out.append(p.polygon)
	return out


## Origin (px) of a base tile's current primary cell — carried shapes are relative to it.
static func _origin(state: FoldedState, bid: int, cell_size: float) -> Vector2:
	return Vector2(state.plane_pos_of_base(bid)) * cell_size


## Absolute polygons of ONE body (base id): its carried shape if present, else the
## tile fragment(s) it rides.
static func _body_abs(bid: int, shapes: Dictionary, state: FoldedState, cell_size: float) -> Array:
	if shapes.has(bid):
		return [CollisionCore.shift(shapes[bid], _origin(state, bid, cell_size))]
	var out: Array = []
	for p in state.pieces_of_base(bid):
		out.append(p.polygon)
	return out


## Build a fresh occupant with empty carried-shape state.
static func _new_occ(kind: int, base_ids: Array, channel: String, collides: bool) -> Dictionary:
	var ids: Array[int] = []
	for b in base_ids:
		ids.append(b)
	return {"kind": kind, "base_ids": ids, "latents": [], "channel": channel, "collides": collides, "shapes": {}, "fp_latents": []}


## Rebuild an occupant with new base_ids/latents, preserving carried-shape state
## (shapes / fp_latents) and identity fields.
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
# Per-kind step application
# ---------------------------------------------------------------------------

static func _apply_fold_step(base: BaseGrid, cp: Dictionary, step: FoldStep) -> Dictionary:
	var f := Fold.create(step.fold_id, step.anchor1, step.anchor2, base.cell_size)
	var folds: Array[Fold] = (cp["folds"] as Array).duplicate()
	folds.append(f)
	var pre_state: FoldedState = cp["state"]
	# Incremental: extend the cached fragment list by just this fold.
	var pieces := FoldReplay.apply_one_fold(cp["pieces"], f, base.cell_size)
	var state := FoldReplay.state_from_pieces(pieces)
	# Each occupant tile that loses area to the fold records a latent (its hidden part);
	# tiles with no surviving flap drop out of the active set until the fold is undone.
	var out: Array = []
	for occ in cp["occupants"]:
		out.append(_fold_occupant(occ, f, pre_state, state, base.cell_size))
	return _finish(out, cp["plane_pos"], pieces, state, folds, cp["next_trigger_fold_id"])


static func _apply_unfold_step(base: BaseGrid, cp: Dictionary, step: FoldStep) -> Dictionary:
	var folds: Array[Fold] = []
	for f in cp["folds"]:
		if f.fold_id != step.fold_id:
			folds.append(f)
	# Removing a non-tail fold means the fragment list must be rebuilt from identity.
	var pieces := FoldReplay.derive_pieces(base, folds)
	var state := FoldReplay.state_from_pieces(pieces)
	# Re-materialize any latent bodies that were hidden by the fold being undone.
	var out: Array = []
	for occ in cp["occupants"]:
		out.append(_unfold_occupant(occ, step.fold_id, state, base.cell_size))
	return _finish(out, cp["plane_pos"], pieces, state, folds, cp["next_trigger_fold_id"])


## Split-on-fold: for each ridden tile, if the fold removes area it holds, remember the
## folded-away part (base_id latent for position + fp_latent carrying the excised
## GEOMETRY for the "missing half" that reappears on unfold). Keep the surviving flap
## active; a carried shape is clipped with the fold so a cut body stays cut.
static func _fold_occupant(occ: Dictionary, f: Fold, pre_state: FoldedState, post_state: FoldedState, cell_size: float) -> Dictionary:
	var active: Array[int] = []
	var latents: Array = (occ["latents"] as Array).duplicate()
	var shapes: Dictionary = (occ.get("shapes", {}) as Dictionary).duplicate()
	var fp_latents: Array = (occ.get("fp_latents", []) as Array).duplicate()
	for t in occ["base_ids"]:
		var loses := _tile_loses_area(t, f, pre_state)
		if not loses:
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


## Undo the fold's effect on an occupant: latents tagged with this fold materialize as
## active bodies again (their home tile is whole once more). Duplicates dedup — so a
## body that never moved simply rejoins itself (no spurious split).
static func _unfold_occupant(occ: Dictionary, fold_id: int, state: FoldedState, cell_size: float) -> Dictionary:
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
	# Re-materialize the excised GEOMETRY for base ids that reappear as NEW bodies
	# (the survivor moved away). A base id that was still active just rejoins to whole.
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
			shapes.erase(bid)  # rejoin: the whole base tile fragment covers it again
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
static func _tile_loses_area(t: int, f: Fold, pre_state: FoldedState) -> bool:
	var gap: float = f.gap_distance()
	var eps := GeometryCore.EPSILON
	for p in pre_state.pieces_of_base(t):
		for v in p.polygon:
			var d: float = (v - f.crease_point1).dot(f.crease_normal)
			if d > eps and d < gap - eps:
				return true
	return false


static func _apply_move_step(base: BaseGrid, cp: Dictionary, step: FoldStep) -> Dictionary:
	# Geometry is unchanged: reuse pieces/folds/state BY REFERENCE (structural sharing).
	# Only occupants move. The player's bodies move in `dir` (blocked ones stay, and a
	# body walking into a box PUSHES it if the box's own destination is clear); each
	# body adopts the top tile wherever it lands; coinciding bodies merge.
	var state: FoldedState = cp["state"]
	var cell_size := base.cell_size
	var dir: Vector2i = step.dir
	var offset := Vector2(dir) * cell_size
	var occupants: Array = cp["occupants"]

	# Map every box body -> its occupant index (for push detection).
	var box_at := {}  # plane_pos -> occupant index
	for i in range(occupants.size()):
		if occupants[i]["kind"] == KIND_BOX:
			for pos in occupant_positions(occupants[i], state):
				box_at[pos] = i

	# Resolve pushes: a player body entering a box cell shoves that box one step, if the
	# box's own footprint can SLIDE clear (swept) and the destination holds no other box.
	var pushed := {}  # occupant index -> true
	var player = _player_occ(occupants)
	if player != null:
		for p in occupant_positions(player, state):
			var t: Vector2i = p + dir
			if box_at.has(t):
				var bi: int = box_at[t]
				var bt: Vector2i = t + dir
				if not box_at.has(bt) and _swept_clear(state, occupant_footprint(occupants[bi], state, cell_size), offset, cell_size, []):
					pushed[bi] = true

	# Blockers for the player's slide: every COLLIDING occupant that isn't the player
	# and isn't being pushed out of the way (a pushed box vacates, so it's excluded).
	# collides=false occupants (e.g. anchors) never block. This is the general
	# "occupants can't overlap" rule, geometric.
	var blockers: Array = []
	for i in range(occupants.size()):
		var o: Dictionary = occupants[i]
		if o["kind"] != KIND_PLAYER and o.get("collides", true) and not pushed.has(i):
			blockers.append(occupant_footprint(o, state, cell_size))

	# Build the new occupant list.
	var out: Array = []
	for i in range(occupants.size()):
		var occ: Dictionary = occupants[i]
		if occ["kind"] == KIND_PLAYER:
			out.append(_move_player(occ, dir, state, cell_size, blockers))
		elif occ["kind"] == KIND_BOX:
			out.append(_move_body_set(occ, dir, state, cell_size) if pushed.has(i) else occ)
		else:
			out.append(occ)  # anchors (and other fixed markers) don't move on a step
	return _finish(out, cp["plane_pos"], cp["pieces"], state, cp["folds"], cp["next_trigger_fold_id"])


## Place a new anchor occupant on the tile currently at `to` (geometry unchanged).
static func _apply_place_anchor(cp: Dictionary, step: FoldStep) -> Dictionary:
	var state: FoldedState = cp["state"]
	var surf := state.surface_pieces_at(step.to)
	var out: Array = (cp["occupants"] as Array).duplicate()
	if not surf.is_empty():
		out.append(_new_occ(KIND_ANCHOR, [surf[0].base_id], step.channel, false))
	return _finish(out, cp["plane_pos"], cp["pieces"], state, cp["folds"], cp["next_trigger_fold_id"])


## Move the player occupant with SWEPT GEOMETRIC COLLISION. Each body (one per
## (base_id, cell) fragment — a split player has several) advances only if its actual
## shape can SLIDE one cell without any part of its path or final position leaving
## navigable ground (walls/void block). A body blocked by an unpushable box stays. On
## moving it adopts the walkable fragment it lands on (conform; rigid no-heal is Stage 4).
static func _move_player(occ: Dictionary, dir: Vector2i, state: FoldedState, cell_size: float, blockers: Array) -> Dictionary:
	var offset := Vector2(dir) * cell_size
	var shapes_in: Dictionary = occ.get("shapes", {})
	var new_bases := {}
	var new_shapes := {}
	for bid in occ["base_ids"]:
		var body_abs := _body_abs(bid, shapes_in, state, cell_size)  # carried shape or fragment
		if _swept_clear(state, body_abs, offset, cell_size, blockers):
			var moved := CollisionCore.translate_polys(body_abs, offset)
			var nb := _adopt_base_at(state, CollisionCore.cell_of_point(CollisionCore.footprint_centroid(moved), cell_size))
			if nb >= 0:
				new_bases[nb] = true
				# Freeze the shape RIGIDLY (relative to the new anchor) — no conform/heal.
				var mu := CollisionCore.union_all(moved)
				if mu.size() >= 1:
					new_shapes[nb] = CollisionCore.shift(mu[0], -_origin(state, nb, cell_size))
		else:
			new_bases[bid] = true  # blocked: stays; keep any carried shape
			if shapes_in.has(bid):
				new_shapes[bid] = shapes_in[bid]
	var out := _rebuilt(occ, _keys_int(new_bases), occ["latents"])
	out["shapes"] = new_shapes
	return out


## Translate every body of an occupant one step (used for a pushed box).
static func _move_body_set(occ: Dictionary, dir: Vector2i, state: FoldedState, cell_size: float) -> Dictionary:
	var new_bases := {}
	for p in occupant_positions(occ, state):
		var bid := _adopt_base_at(state, p + dir)
		if bid >= 0:
			new_bases[bid] = true
	return _rebuilt(occ, _keys_int(new_bases), occ["latents"])


## Polygons of base tile `bid`'s fragment(s) at a specific cell — one body's shape.
static func _base_frag_polys_at(state: FoldedState, bid: int, cell: Vector2i) -> Array:
	var out: Array = []
	for pc in state.pieces_of_base(bid):
		if pc.plane_pos == cell:
			out.append(pc.polygon)
	return out


## Walkable tile polygons over the cells the sweep touches (AABB of footprint ∪
## footprint+offset, +1 cell margin). Not unioned — footprint_contained subtracts each.
static func _navigable_near(state: FoldedState, footprint: Array, offset: Vector2, cell_size: float) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly in footprint:
		for v in poly:
			lo = lo.min(v).min(v + offset)
			hi = hi.max(v).max(v + offset)
	var c0 := CollisionCore.cell_of_point(lo, cell_size) - Vector2i.ONE
	var c1 := CollisionCore.cell_of_point(hi, cell_size) + Vector2i.ONE
	var nav: Array = []
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for p in state.walkable_pieces_at(Vector2i(cx, cy)):
				nav.append(p.polygon)
	return nav


## SWEPT COLLISION: is it clear to slide `footprint` by `offset`? Every sample along the
## slide (spaced <= SWEEP_MAX_STEP) must be fully contained in navigable ground and not
## overlap any `blockers` footprint. This is the geometric heart of the move gate:
## shape + path, not area — a full square is refused a partial/offset navigable region
## even when its area would fit.
static func _swept_clear(state: FoldedState, footprint: Array, offset: Vector2, cell_size: float, blockers: Array) -> bool:
	if footprint.is_empty():
		return false
	var nav := _navigable_near(state, footprint, offset, cell_size)
	var n := int(ceil(offset.length() / CollisionCore.SWEEP_MAX_STEP))
	n = max(n, 1)
	for k in range(1, n + 1):
		var sample := CollisionCore.translate_polys(footprint, offset * (float(k) / n))
		if not CollisionCore.footprint_contained(sample, nav):
			return false
		for b in blockers:
			if CollisionCore.footprints_overlap(sample, b):
				return false
	return true


## The base id a body adopts when it lands on a cell: the top WALKABLE fragment if any
## (so it flows onto floor, not a coexisting wall), else the top surface fragment, else
## -1 when the cell is empty.
static func _adopt_base_at(state: FoldedState, pos: Vector2i) -> int:
	var walk := state.walkable_pieces_at(pos)
	if not walk.is_empty():
		return walk[0].base_id
	var surf := state.surface_pieces_at(pos)
	return surf[0].base_id if not surf.is_empty() else -1


## The base id of the LARGEST walkable fragment at a cell (the sub-region a body settles
## into after a size-fit move), or -1 if none.
static func _largest_walkable_base_at(state: FoldedState, pos: Vector2i) -> int:
	var best := -1
	var best_area := -1.0
	for pc in state.walkable_pieces_at(pos):
		if pc.area() > best_area:
			best_area = pc.area()
			best = pc.base_id
	return best


# ---------------------------------------------------------------------------
# Checkpoint assembly
# ---------------------------------------------------------------------------

## Assemble a checkpoint, deriving the PRIMARY player body (the ridden tile with the
## largest surviving fragment) for single-body/compat readers. `prev_plane` is the
## fallback primary position when every ridden tile has been excised.
static func _finish(occupants: Array, prev_plane: Vector2i, pieces: Array, state: FoldedState, folds: Array, next_trigger_fold_id: int) -> Dictionary:
	var player = _player_occ(occupants)
	var pbids: Array[int] = []
	if player != null:
		for b in player["base_ids"]:
			pbids.append(b)
	var primary := -1
	var best_area := -1.0
	for bid in pbids:
		if state.has_base(bid):
			var a: float = state.base_to_piece[bid].area()
			if a > best_area:
				best_area = a
				primary = bid
	var plane := prev_plane
	if primary >= 0:
		plane = state.plane_pos_of_base(primary)
	return {
		"pieces": pieces,
		"folds": folds,
		"occupants": occupants,
		"base_ids": pbids,
		"base_id": primary,
		"plane_pos": plane,
		"state": state,
		"next_trigger_fold_id": next_trigger_fold_id,
	}


static func _player_occ(occupants: Array):
	for occ in occupants:
		if occ["kind"] == KIND_PLAYER:
			return occ
	return null


static func boxes(occupants: Array) -> Array:
	var out: Array = []
	for occ in occupants:
		if occ["kind"] == KIND_BOX:
			out.append(occ)
	return out


static func anchors(occupants: Array) -> Array:
	var out: Array = []
	for occ in occupants:
		if occ["kind"] == KIND_ANCHOR:
			out.append(occ)
	return out


static func _keys_int(d: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for k in d.keys():
		out.append(k)
	return out
