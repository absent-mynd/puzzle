class_name FoldedState extends RefCounted

## FoldedState
##
## The derived, queryable folded configuration produced by FoldReplay.derive().
## Replaces GridManager.cells as the source of truth for what's where. Holds
## per-plane-position stacks of FoldedPieces and answers gameplay queries.
##
## "Void" = a position with no pieces (is_occupied == false). There is no null type.

## Merge priority when several pieces share a plane position (co-surface merge).
## goal > wall > water > empty. Rationale: a goal merged onto a walkable tile is
## reachable (per design), so goal must win over empty/water; wall still blocks
## unless a goal is co-surface. (Tunable — see plan's open detail on wall+goal.)
const _PRIORITY := {3: 4, 1: 3, 2: 2, 0: 1}  # type -> rank (higher wins)

const TYPE_EMPTY := 0
const TYPE_WALL := 1
const TYPE_WATER := 2
const TYPE_GOAL := 3

## Vector2i plane_pos -> Array[FoldedPiece], ordered surface-first (stack_order asc).
var stacks: Dictionary = {}

## base_id -> FoldedPiece (its largest/primary fragment) for player-riding.
var base_to_piece: Dictionary = {}


## Add a derived piece to its plane position's stack.
func add_piece(piece: FoldedPiece) -> void:
	if not stacks.has(piece.plane_pos):
		stacks[piece.plane_pos] = []
	stacks[piece.plane_pos].append(piece)

	# Track the primary (largest-area) fragment per base id.
	var existing: FoldedPiece = base_to_piece.get(piece.base_id, null)
	if existing == null or piece.area() > existing.area():
		base_to_piece[piece.base_id] = piece


## Finalize ordering within each stack. Later folds (higher source_fold_id) sit on
## top; area breaks ties. Assigns stack_order (0 = topmost). Deterministic.
func finalize() -> void:
	for pos in stacks:
		var arr: Array = stacks[pos]
		arr.sort_custom(func(a, b):
			if a.source_fold_id != b.source_fold_id:
				return a.source_fold_id > b.source_fold_id  # later fold on top
			return a.area() > b.area()  # larger first
		)
		for i in range(arr.size()):
			arr[i].stack_order = i


## All pieces at a plane position (surface-first), or [] if empty.
func pieces_at(pos: Vector2i) -> Array:
	return stacks.get(pos, [])


## Non-occluded (co-surface) pieces at a position. Under the current ruleset all
## present pieces are co-surface, but this keeps the seam for future occlusion.
func surface_pieces_at(pos: Vector2i) -> Array:
	var out: Array = []
	for p in pieces_at(pos):
		if not p.occluded:
			out.append(p)
	return out


func is_occupied(pos: Vector2i) -> bool:
	return not surface_pieces_at(pos).is_empty()


## Total surface area covering a plane position (sum of co-surface piece areas).
func surface_area_at(pos: Vector2i) -> float:
	var total := 0.0
	for p in surface_pieces_at(pos):
		total += p.area()
	return total


## Is the cell fully covered (a complete square), vs merged with empty space? An
## incomplete tile (surface area < a full cell) is not walkable — you can't stand on
## half a tile. Tolerance is ~1px² to absorb clipping slivers.
func is_complete(pos: Vector2i, cell_size: float) -> bool:
	return surface_area_at(pos) >= cell_size * cell_size - 1.0


## Walkable = occupied, complete, and not a wall.
func is_walkable(pos: Vector2i, cell_size: float) -> bool:
	return is_occupied(pos) and is_complete(pos, cell_size) and dominant_type_at(pos) != TYPE_WALL


## Merge rule over co-surface pieces. Returns the dominant walkable-relevant type,
## or TYPE_EMPTY sentinel if the position is empty (callers gate on is_occupied).
func dominant_type_at(pos: Vector2i) -> int:
	var best_type := TYPE_EMPTY
	var best_rank := -1
	var any := false
	for p in surface_pieces_at(pos):
		any = true
		var rank: int = _PRIORITY.get(p.type, 0)
		if rank > best_rank:
			best_rank = rank
			best_type = p.type
	if not any:
		return TYPE_EMPTY
	return best_type


func has_type_at(pos: Vector2i, type: int) -> bool:
	for p in surface_pieces_at(pos):
		if p.type == type:
			return true
	return false


## Current plane position of a base tile's primary fragment. Returns a sentinel
## Vector2i(-99999, -99999) if the base has no surviving surface fragment (excised).
func plane_pos_of_base(base_id: int) -> Vector2i:
	var p: FoldedPiece = base_to_piece.get(base_id, null)
	if p == null:
		return Vector2i(-99999, -99999)
	return p.plane_pos


func has_base(base_id: int) -> bool:
	return base_to_piece.has(base_id)


## Area-weighted centroid of the surface pieces at a position (for player/world
## positioning). Falls back to the geometric cell center if empty.
func center_at(pos: Vector2i, cell_size: float = 64.0) -> Vector2:
	var pieces := surface_pieces_at(pos)
	if pieces.is_empty():
		return Vector2(pos) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)
	var total_area := 0.0
	var weighted := Vector2.ZERO
	for p in pieces:
		var a: float = p.area()
		weighted += p.center() * a
		total_area += a
	if total_area > GeometryCore.EPSILON:
		return weighted / total_area
	# Degenerate: average of centroids.
	var avg := Vector2.ZERO
	for p in pieces:
		avg += p.center()
	return avg / pieces.size()


## Number of occupied plane positions (for tests / diagnostics).
func occupied_count() -> int:
	var n := 0
	for pos in stacks:
		if is_occupied(pos):
			n += 1
	return n
