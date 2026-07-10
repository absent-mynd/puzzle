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
## fragments; the between fragment is dropped, the target fragment stays, the
## source fragment translates. Fragments keep their base_id, so identity — and the
## player riding it — survives every fold.

const _MIN_AREA := 0.01  # drop sub-pixel slivers from clipping


## Pure derivation: (BaseGrid, ordered folds) -> FoldedState.
static func derive(base: BaseGrid, folds: Array) -> FoldedState:
	# 1. Identity state: one piece per base tile.
	var pieces: Array[FoldedPiece] = []
	for t in base.tiles:
		pieces.append(FoldedPiece.new(
			t.base_id, t.type, base.unit_square_local(t.base_id), t.grid_position, -1))

	# 2. Apply each fold in order (folds compose over prior fragments).
	for fold in folds:
		pieces = _apply_fold(pieces, fold, base.cell_size)

	# 3. Assemble the queryable state.
	var state := FoldedState.new()
	for p in pieces:
		state.add_piece(p)
	state.finalize()
	return state


## Apply one fold to the current fragment list, returning the new fragment list.
## MEET-IN-THE-MIDDLE: A-side and B-side both translate inward; between is excised.
static func _apply_fold(pieces: Array, fold: Fold, cell_size: float) -> Array[FoldedPiece]:
	var out: Array[FoldedPiece] = []
	var normal := fold.crease_normal
	var p1 := fold.crease_point1
	var p2 := fold.crease_point2
	var shift_a := fold.shift_a_px(cell_size)
	var shift_b := fold.shift_b_px(cell_size)

	for piece in pieces:
		# Clip by crease1: left1 = A-side (d<=0), right1 = d>0 (between + B-side).
		var s1 := GeometryCore.split_polygon_by_line(piece.polygon, p1, normal)
		var a_frag: PackedVector2Array = s1["left"]
		var rest: PackedVector2Array = s1["right"]

		# A-side fragment slides toward B by shift_a.
		if _valid(a_frag):
			var pa := FoldedPiece.new(
				piece.base_id, piece.type, _translate(a_frag, shift_a),
				piece.plane_pos + fold.shift_a_grid, fold.fold_id)
			pa.src_offset = piece.src_offset + shift_a
			out.append(pa)

		if not _valid(rest):
			continue

		# Clip the remainder by crease2: left2 = between (drop), right2 = B-side.
		var s2 := GeometryCore.split_polygon_by_line(rest, p2, normal)
		# left2 (between) is intentionally discarded (excised / hidden until unfold).
		var b_frag: PackedVector2Array = s2["right"]
		if _valid(b_frag):
			var pb := FoldedPiece.new(
				piece.base_id, piece.type, _translate(b_frag, shift_b),
				piece.plane_pos + fold.shift_b_grid, fold.fold_id)
			pb.src_offset = piece.src_offset + shift_b
			out.append(pb)

	return out


static func _valid(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and GeometryCore.polygon_area(poly) > _MIN_AREA


static func _translate(poly: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(v + offset)
	return out


## Convenience: build a Fold and append it (used by FoldEngine in later stages).
static func make_fold(fold_id: int, anchor1: Vector2i, anchor2: Vector2i, cell_size: float) -> Fold:
	return Fold.create(fold_id, anchor1, anchor2, cell_size)
