class_name HandPickup extends RefCounted

## HandPickup
##
## A hand lying in the world, waiting to be picked up.
##
## There is only ONE kind of loose hand. A cache the world shipped and a hand that
## popped out of a fold you just burst open are the same object, stored the same way
## and drawn the same way — because to the player they are the same thing: a hand on
## the ground. Anything that made them look or behave differently would be inventing a
## distinction the fiction does not have.
##
## Like a door or a light, a pickup is an OCCUPANT of the sheet: a base identity
## (`base_id`) plus a point inside that tile (`bp`), with no world position of its own.
## Where it lies is always a question asked of the current fragment list, so it rides
## flaps, folds away into a subspace with its tile, and is found again in there.
##
## Resolves NON-strictly (`world_point_from_base`): a pickup on a tile split down the
## middle is not ambiguous the way a door is — it is lying on whichever half its point
## ended up in.

## `HandTypes` id — which kind of hand this is.
var kind: int = HandTypes.PLAIN
var region: String = ""

## Authored identity (unused by pickups created at runtime, which bind directly).
var cell: Vector2i = Vector2i.ZERO
## Position within the cell, in cell units. Centre of the tile by default.
var offset: Vector2 = Vector2(0.5, 0.5)

## Bound base-frame identity. -1 until bound.
var base_id: int = -1
## The pickup's point in BASE space, in px.
var bp: Vector2 = Vector2.ZERO

## True for pickups the world authored, false for hands dropped during play. Only
## used to decide what a reset restores — the two are identical in every other way.
var authored: bool = true


## Attach an authored pickup to its base tile. False if the cell lies outside the
## grid, in which case it stays unbound and is skipped.
func bind(base: BaseGrid) -> bool:
	if base == null:
		return false
	var tile := base.tile_at(cell)
	if tile == null:
		base_id = -1
		return false
	base_id = tile.base_id
	bp = (Vector2(cell) + offset) * base.cell_size
	return true


func is_bound() -> bool:
	return base_id >= 0


## A hand dropped at a world point during play. `piece` is the fragment under that
## point, which supplies the base identity the pickup will ride on — subtracting the
## fragment's offset is what turns "here, now" into "this spot on the sheet".
static func dropped_at(kind_id: int, piece, world_pos: Vector2, region_id: String) -> HandPickup:
	var p := HandPickup.new()
	p.kind = kind_id
	p.region = region_id
	p.authored = false
	p.base_id = piece.base_id
	p.bp = world_pos - piece.src_offset
	return p


## Where this hand lies in the given configuration, or null if its tile has no
## surviving fragment there (folded away — look for it inside the fold).
func position_in(pieces: Array):
	if not is_bound():
		return null
	return BaseFrame.world_point_from_base(pieces, base_id, bp)


## Resolve a list against one fragment list. Returns
## `[{"pickup": HandPickup, "pos": Vector2}, ...]`, skipping any that does not
## survive into this configuration.
static func resolve_all(pieces: Array, pickups: Array) -> Array:
	var out: Array = []
	for p in pickups:
		var wp = p.position_in(pieces)
		if wp != null:
			out.append({"pickup": p, "pos": Vector2(wp)})
	return out


# ---------------------------------------------------------------------------
# Serialization (the authored form; `base_id`/`bp` are bound at load, not stored)
# ---------------------------------------------------------------------------

static func from_dict(d: Dictionary) -> HandPickup:
	var p := HandPickup.new()
	p.kind = HandTypes.from_name(String(d.get("kind", "plain")))
	var c: Dictionary = d.get("cell", {})
	p.cell = Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))
	if d.has("offset"):
		var o: Dictionary = d["offset"]
		p.offset = Vector2(float(o.get("x", 0.5)), float(o.get("y", 0.5)))
	return p


func to_dict() -> Dictionary:
	var out := {"kind": HandTypes.type_name(kind), "cell": {"x": cell.x, "y": cell.y}}
	if not offset.is_equal_approx(Vector2(0.5, 0.5)):
		out["offset"] = {"x": offset.x, "y": offset.y}
	return out


func duplicate_pickup() -> HandPickup:
	var copy := HandPickup.from_dict(to_dict())
	copy.region = region
	return copy
