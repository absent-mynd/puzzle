class_name FoldReplay extends RefCounted

## FoldReplay
##
## The derivation engine. `derive(base, folds)` is a PURE function: it replays the
## ordered fold list over the immutable base grid and returns a fresh FoldedState.
## This replaces ~2000 lines of in-place mutation in the old FoldSystem. Because it
## rebuilds from scratch every call, unfold = "drop a fold, re-derive" and undo =
## "restore a fold list, re-derive" — no snapshots, no null pieces, no stale state.
##
## Fold geometry (per Fold):
##   - crease1 at target center, crease2 at source center, shared normal (target->source).
##   - A point's signed distance d = (p - crease1)·normal:
##       d <= 0        : target side  (kept in place)
##       0 < d < gap   : between      (excised / dropped)
##       d >= gap      : source side  (translated by shift onto the target side)
##
## Each existing piece is clipped by the two parallel creases into up to three
## pieces; the between piece is dropped, the target piece stays, the
## source piece translates. Pieces keep their base_id, so identity — and the
## player riding it — survives every fold.

## Pure derivation: (BaseGrid, ordered folds) -> FoldedState.
static func derive(base: BaseGrid, folds: Array) -> FoldedState:
	return state_from_pieces(derive_pieces(base, folds))


## The piece list after replaying `folds` over the base grid. Exposed so the
## step-log engine (StepReplay) can carry the pieces forward incrementally between
## checkpoints instead of rebuilding a FoldedState it would only re-flatten.
static func derive_pieces(base: BaseGrid, folds: Array) -> Array[FoldedPiece]:
	# 1. Identity state: one piece per base tile.
	var pieces: Array[FoldedPiece] = []
	for t in base.tiles:
		pieces.append(FoldedPiece.new(
			t.base_id, t.type, base.unit_square_local(t.base_id), t.grid_position, -1))

	# 2. Apply each fold in order (folds compose over prior pieces).
	for fold in folds:
		pieces = _apply_fold(pieces, fold, base.cell_size, true, false)["pieces"]

	return pieces


## Build the queryable state from a piece list. Kept separate from derive_pieces
## so a MOVE step (which does not change geometry) can reuse an existing state.
static func state_from_pieces(pieces: Array) -> FoldedState:
	var state := FoldedState.new()
	for p in pieces:
		state.add_piece(p)
	state.finalize()
	return state


## Identity piece list (base tiles, no folds). Convenience for StepReplay.
static func identity_pieces(base: BaseGrid) -> Array[FoldedPiece]:
	return derive_pieces(base, [])


## Apply exactly one fold to a piece list (public wrapper over the internal
## clip-and-shift). Lets StepReplay extend a checkpoint by a single fold.
static func apply_one_fold(pieces: Array, fold: Fold, cell_size: float) -> Array[FoldedPiece]:
	return _apply_fold(pieces, fold, cell_size, true, false)["pieces"]


## Just the strip a fold excises, as pieces that keep their PRE-fold frame.
##
## `WorldCore.capture_strip` is this; it delegates here so the clip lives in one
## place.
static func capture_strip(pieces: Array, fold: Fold, cell_size: float) -> Array:
	return _apply_fold(pieces, fold, cell_size, false, true)["dropped"]


## Apply a fold AND capture what it excised, in ONE pass over the pieces.
##
## Both halves of a fold come out of the same clip. `CollisionCore.fold_polygons`
## already returns `{a, b, dropped}` for a piece, and a fold needs all three: the
## flaps become the new piece list, the strip between them becomes the subspace.
## Asking for them separately — `apply_one_fold` then `capture_strip` — clips the
## whole world twice for one answer.
##
## Measured on the shipped region (792 pieces) that was 14.7ms + 12.9ms of a
## 58ms fold. The clip is Sutherland-Hodgman per piece, so it is the single most
## expensive thing a fold does; doing it once is worth more than anything downstream
## of it.
##
## Returns `{"pieces": Array[FoldedPiece], "dropped": Array}`.
static func fold_and_capture(pieces: Array, fold: Fold, cell_size: float) -> Dictionary:
	return _apply_fold(pieces, fold, cell_size, true, true)


## Apply one fold to the current piece list, returning the new piece list.
## MEET-IN-THE-MIDDLE: A-side and B-side both translate inward; between is excised.
## The polygon clip+shift math is shared with occupant footprints via
## CollisionCore.fold_polygons; here we re-wrap each kept piece as a FoldedPiece,
## carrying base_id/type/plane_pos/src_offset.
##
## `want_pieces` / `want_dropped` say which parts of the answer the caller will use.
## The clip runs either way — it is the expensive part — but the FoldedPiece wrapping
## is skipped for a half nobody asked for, so a caller that wants only the strip pays
## nothing for the flaps.
static func _apply_fold(pieces: Array, fold: Fold, cell_size: float,
		want_pieces: bool, want_dropped: bool) -> Dictionary:
	var out: Array[FoldedPiece] = []
	var dropped: Array = []
	var shift_a := fold.shift_a_px(cell_size)
	var shift_b := fold.shift_b_px(cell_size)
	for piece in pieces:
		var res := CollisionCore.fold_polygons([piece.polygon], fold, cell_size)
		if want_pieces:
			for poly in res["a"]:  # A-side (0 or 1 per convex clip): slid by shift_a
				var pa := FoldedPiece.new(
					piece.base_id, piece.type, poly,
					piece.plane_pos + fold.shift_a_grid, fold.fold_id)
				pa.src_offset = piece.src_offset + shift_a
				out.append(pa)
			for poly in res["b"]:  # B-side: slid by shift_b
				var pb := FoldedPiece.new(
					piece.base_id, piece.type, poly,
					piece.plane_pos + fold.shift_b_grid, fold.fold_id)
				pb.src_offset = piece.src_offset + shift_b
				out.append(pb)
		if want_dropped:
			# The between-strip KEEPS its pre-fold frame: it is the same sheet, seen
			# from inside. Tiles excise it; occupant footprints keep it as a latent.
			for poly in res["dropped"]:
				var fp := FoldedPiece.new(
					piece.base_id, piece.type, poly, piece.plane_pos, piece.source_fold_id)
				fp.src_offset = piece.src_offset
				dropped.append(fp)
	return {"pieces": out, "dropped": dropped}


## Convenience: build a Fold from anchors.
static func make_fold(fold_id: int, anchor1: Vector2i, anchor2: Vector2i, cell_size: float) -> Fold:
	return Fold.create(fold_id, anchor1, anchor2, cell_size)


## Would this fold excise or cut a fold-proof tile (`TileTypes.blocks_fold`, e.g. a PIN)?
## Such a fold must be refused: the space a pin holds can never be folded away.
##
## Kernel rather than view, because every path that creates a fold has to honor it —
## the player's own folds AND the ones TriggerResolver fires. A pin that a pressure
## plate could quietly delete would not be a pin.
static func blocked_by_tile(pieces: Array, fold: Fold, cell_size: float) -> bool:
	for piece in pieces:
		if not TileTypes.blocks_fold(piece.type):
			continue
		var res := CollisionCore.fold_polygons([piece.polygon], fold, cell_size)
		if not res["dropped"].is_empty():
			return true
	return false
