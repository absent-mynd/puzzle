class_name FoldedState extends RefCounted

## FoldedState
##
## The derived, queryable folded configuration produced by FoldReplay.derive().
## The source of truth for what is where after a fold replay. Holds
## per-plane-position stacks of FoldedPieces and answers gameplay queries.
##
## "Void" = a position with no pieces (is_occupied == false). There is no null type.

# Merge priority (co-surface) and walkability now live in the TileTypes registry
# (goal > wall > water > empty; a goal merged onto a walkable tile stays reachable).
# See TileTypes.gd — adding a type no longer means editing this file.

const TYPE_EMPTY := 0
const TYPE_WALL := 1
const TYPE_WATER := 2
const TYPE_GOAL := 3

## Vector2i plane_pos -> Array[FoldedPiece], ordered surface-first (stack_order asc).
var stacks: Dictionary = {}

## base_id -> FoldedPiece (its largest/primary fragment) for player-riding.
var base_to_piece: Dictionary = {}

## base_id -> Array[FoldedPiece] (ALL its surface fragments). When a fold cuts a
## tile, it produces two fragments with the same base_id; keeping both here is what
## lets the player be SPLIT into multiple bodies (F4) rather than collapsing to the
## largest fragment. base_to_piece is retained as the "primary" for single-body code.
var base_to_pieces: Dictionary = {}


## Add a derived piece to its plane position's stack.
func add_piece(piece: FoldedPiece) -> void:
	if not stacks.has(piece.plane_pos):
		stacks[piece.plane_pos] = []
	stacks[piece.plane_pos].append(piece)

	# Track the primary (largest-area) fragment per base id.
	var existing: FoldedPiece = base_to_piece.get(piece.base_id, null)
	if existing == null or piece.area() > existing.area():
		base_to_piece[piece.base_id] = piece

	# Track EVERY fragment per base id (for multi-body / split player).
	if not base_to_pieces.has(piece.base_id):
		base_to_pieces[piece.base_id] = []
	base_to_pieces[piece.base_id].append(piece)


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


## Surface fragments here whose type is walkable (per TileTypes). A body stands on
## one of these — sub-tile collision (F-sub) uses this instead of a whole-cell test.
func walkable_pieces_at(pos: Vector2i) -> Array:
	var out: Array = []
	for p in surface_pieces_at(pos):
		if TileTypes.is_walkable(p.type):
			out.append(p)
	return out


## Total walkable ground here (sum of walkable fragment areas). A rigid body fits if
## this is >= its size. Sum (not largest single fragment) so a fold's MERGE seam — a
## full cell tiled by two contiguous flap fragments — correctly holds a full body.
## Folds produce contiguous flaps/merges, so summing doesn't admit disjoint slivers.
func walkable_area_at(pos: Vector2i) -> float:
	var total := 0.0
	for p in walkable_pieces_at(pos):
		total += p.area()
	return total


## Total area a base tile's fragment(s) cover at a position — the "size" of a body
## riding that tile there (smaller once a fold has cut it).
func area_of_base_at(base_id: int, pos: Vector2i) -> float:
	var total := 0.0
	for p in surface_pieces_at(pos):
		if p.base_id == base_id:
			total += p.area()
	return total


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


## Walkable (SUB-TILE): a body can stand here if ANY surface fragment is a walkable
## type. Completeness is no longer required — the body occupies the covered walkable
## sub-region even when the rest of the cell is void or wall (a wall fragment in a
## different sub-region doesn't block the floor fragment). `cell_size` is kept for
## signature compatibility. A cell that is only wall/void has no walkable fragment.
func is_walkable(pos: Vector2i, _cell_size: float = 0.0) -> bool:
	return not walkable_pieces_at(pos).is_empty()


## Merge rule over co-surface pieces. Returns the dominant walkable-relevant type,
## or TYPE_EMPTY sentinel if the position is empty (callers gate on is_occupied).
func dominant_type_at(pos: Vector2i) -> int:
	var types: Array = []
	for p in surface_pieces_at(pos):
		types.append(p.type)
	return TileTypes.dominant_type(types)


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


## ALL surface fragments of a base tile (>1 when a fold has split it). [] if excised.
func pieces_of_base(base_id: int) -> Array:
	return base_to_pieces.get(base_id, [])


## The distinct plane positions a base tile currently occupies. One entry normally;
## several when the tile has been split by a fold. [] if the tile is fully excised.
func plane_positions_of_base(base_id: int) -> Array:
	var seen := {}
	for p in pieces_of_base(base_id):
		seen[p.plane_pos] = true
	return seen.keys()


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


## Area-weighted centroid of ONE base tile's fragment(s) at a position — where a body
## riding that tile actually sits (sub-cell). Falls back to the cell center if the
## base has no fragment here. Used to position the player/occupant on its own
## sub-region rather than the averaged cell center.
func center_of_base_at(base_id: int, pos: Vector2i, cell_size: float = 64.0) -> Vector2:
	var total := 0.0
	var weighted := Vector2.ZERO
	for p in surface_pieces_at(pos):
		if p.base_id == base_id:
			var a: float = p.area()
			weighted += p.center() * a
			total += a
	if total > GeometryCore.EPSILON:
		return weighted / total
	return Vector2(pos) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)


## Number of occupied plane positions (for tests / diagnostics).
func occupied_count() -> int:
	var n := 0
	for pos in stacks:
		if is_occupied(pos):
			n += 1
	return n
