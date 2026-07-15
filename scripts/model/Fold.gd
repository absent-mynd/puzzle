class_name Fold extends Resource

## Fold
##
## A single, immutable fold in the ordered fold list. Lightweight: stores the anchors
## and the derived crease geometry needed to replay the fold. No grid snapshot.
##
## MEET-IN-THE-MIDDLE model: BOTH sides move toward the center. The two anchors are
## ordered (anchor_a = lexicographically smaller by (y,x)); the region strictly
## between their creases is excised, and each outer flap slides inward by an integer
## share of the gap so the halves meet at a common line (grid-aligned).
##
## Geometry (LOCAL coords relative to GridManager):
##   - crease_point1 = anchor_a center, crease_point2 = anchor_b center.
##   - crease_normal points anchor_a -> anchor_b (unit).
##   - d(p) = (p - crease_point1)·crease_normal; d(A)=0, d(B)=gap.
##       d <= 0     : A-side (moves by shift_a_grid, toward B)
##       0 < d < gap: between (excised)
##       d >= gap   : B-side (moves by shift_b_grid, toward A)
##   - shift_a_grid ≈ (anchor_b-anchor_a)/2 (integer); shift_b_grid = shift_a_grid - (anchor_b-anchor_a).
##     Their difference equals the full gap, so the two sides meet exactly.

@export var fold_id: int = -1
@export var anchor1: Vector2i = Vector2i.ZERO   # original selection order (for records/UI)
@export var anchor2: Vector2i = Vector2i.ZERO
@export var orientation: String = "diagonal"

## Symbolic tag for trigger-created folds (F3); "" for ordinary player folds.
@export var channel: String = ""

@export var anchor_a: Vector2i = Vector2i.ZERO   # ordered: lexicographic min (y,x)
@export var anchor_b: Vector2i = Vector2i.ZERO

@export var crease_point1: Vector2 = Vector2.ZERO  # anchor_a center (LOCAL)
@export var crease_point2: Vector2 = Vector2.ZERO  # anchor_b center (LOCAL)
@export var crease_normal: Vector2 = Vector2.ZERO  # unit, anchor_a -> anchor_b

@export var shift_a_grid: Vector2i = Vector2i.ZERO  # A-side displacement (toward B)
@export var shift_b_grid: Vector2i = Vector2i.ZERO  # B-side displacement (toward A)

## The grid cell where the two halves meet (anchor_a + shift_a_grid). Marks the seam
## / crease-dot site for unfolding.
@export var meeting_pos: Vector2i = Vector2i.ZERO


## Distance (px) between the two crease lines along the normal.
func gap_distance() -> float:
	return (crease_point2 - crease_point1).dot(crease_normal)


func shift_a_px(cell_size: float) -> Vector2:
	return Vector2(shift_a_grid) * cell_size


func shift_b_px(cell_size: float) -> Vector2:
	return Vector2(shift_b_grid) * cell_size


## Order the two anchors deterministically: anchor_a = lexicographically smaller by
## (y, then x). This makes the crease normal (a->b) and the split reproducible.
static func order_anchors(p1: Vector2i, p2: Vector2i) -> Array:
	if p1.y != p2.y:
		return [p1, p2] if p1.y < p2.y else [p2, p1]
	return [p1, p2] if p1.x <= p2.x else [p2, p1]


static func classify_orientation(p1: Vector2i, p2: Vector2i) -> String:
	if p1.y == p2.y:
		return "horizontal"
	if p1.x == p2.x:
		return "vertical"
	return "diagonal"


## Integer half of a grid delta (round half away from zero), per component.
static func _half(d: Vector2i) -> Vector2i:
	return Vector2i(roundi(d.x / 2.0), roundi(d.y / 2.0))


## Build a Fold from two anchors and the grid cell size. `channel` tags folds
## created by a trigger (F3) so other elements can reference them symbolically; it
## is empty for ordinary player folds.
static func create(fold_id: int, anchor1: Vector2i, anchor2: Vector2i, cell_size: float, channel: String = "") -> Fold:
	var f := Fold.new()
	f.fold_id = fold_id
	f.anchor1 = anchor1
	f.anchor2 = anchor2
	f.channel = channel
	f.orientation = classify_orientation(anchor1, anchor2)

	var ordered := order_anchors(anchor1, anchor2)
	var a: Vector2i = ordered[0]
	var b: Vector2i = ordered[1]
	f.anchor_a = a
	f.anchor_b = b

	var half := Vector2(cell_size / 2.0, cell_size / 2.0)
	f.crease_point1 = Vector2(a) * cell_size + half
	f.crease_point2 = Vector2(b) * cell_size + half
	f.crease_normal = (f.crease_point2 - f.crease_point1).normalized()

	var d := b - a
	f.shift_a_grid = _half(d)          # A-side moves ~half of the gap toward B
	f.shift_b_grid = f.shift_a_grid - d  # B-side moves the complementary amount toward A
	f.meeting_pos = a + f.shift_a_grid
	return f
