class_name LightSource extends RefCounted

## LightSource
##
## A light that is an OCCUPANT of the sheet, not a decoration hung over it.
##
## A light is authored on a base cell and stored the way a door is: as a base
## identity (`base_id`) plus a point inside that tile (`bp`). It has no world
## position of its own. Where it burns is always a question asked of the current
## piece list:
##
##     BaseFrame.world_point_from_base(pieces, base_id, bp)
##
## Everything the design asks for falls out of that one call:
##
##   - Fold the light's tile away and it resolves to null at world space: the
##     lamp is gone from the region and casts nothing there.
##   - Enter that fold's subspace and the same light resolves against the strip
##     content, so it lights the folded-away place from inside.
##   - Fold something else and the light rides its flap, because the piece it
##     belongs to carries the offset.
##
## Unlike a door, a light resolves NON-strictly (`world_point_from_base`, not
## `resolve_base_point`). A door split exactly down the middle is dormant —
## there is no unambiguous side to arrive on. A light split down the middle is
## not ambiguous at all: it burns on whichever half its point ended up in.
##
## Radius is authored in CELLS so a world file reads in the same units as the
## terrain around it; `radius_px` converts.

const DEFAULT_COLOR := Color(1.0, 0.82, 0.52)
const DEFAULT_RADIUS_CELLS := 5.0

## Authored identity.
var id: String = ""
var region: String = ""
var cell: Vector2i = Vector2i.ZERO
## Position within the cell, in cell units. Centre of the tile by default.
var offset: Vector2 = Vector2(0.5, 0.5)

## Authored look.
var color: Color = DEFAULT_COLOR
var radius_cells: float = DEFAULT_RADIUS_CELLS
var energy: float = 1.0
## Amplitude of the idle flicker, 0 = a steady lamp.
var flicker: float = 0.0

## Bound base-frame identity (set by `bind`). -1 until bound.
var base_id: int = -1
## The light's point in BASE space, in px.
var bp: Vector2 = Vector2.ZERO


## Attach the light to its base tile. Returns false if the authored cell lies
## outside the grid, in which case the light stays unbound and is skipped.
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


func radius_px(cell_size: float) -> float:
	return radius_cells * cell_size


## Where this light burns in the given configuration, or null if its tile has no
## surviving piece there (folded away — see the class comment).
func position_in(pieces: Array):
	if not is_bound():
		return null
	return BaseFrame.world_point_from_base(pieces, base_id, bp)


## Resolve a list of lights against one piece list. Returns
## `[{"light": LightSource, "pos": Vector2}, ...]`, skipping any light that does
## not survive into this configuration.
static func resolve_all(pieces: Array, lights: Array) -> Array:
	var out: Array = []
	for light in lights:
		var wp = light.position_in(pieces)
		if wp != null:
			out.append({"light": light, "pos": Vector2(wp)})
	return out


# ---------------------------------------------------------------------------
# Serialization (the authored form; `base_id`/`bp` are bound at load, not stored)
# ---------------------------------------------------------------------------

static func from_dict(d: Dictionary) -> LightSource:
	var light := LightSource.new()
	light.id = String(d.get("id", ""))
	var c: Dictionary = d.get("cell", {})
	light.cell = Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))
	if d.has("offset"):
		var o: Dictionary = d["offset"]
		light.offset = Vector2(float(o.get("x", 0.5)), float(o.get("y", 0.5)))
	if d.has("color"):
		light.color = Color(String(d["color"]))
	light.radius_cells = float(d.get("radius", DEFAULT_RADIUS_CELLS))
	light.energy = float(d.get("energy", 1.0))
	light.flicker = float(d.get("flicker", 0.0))
	return light


func to_dict() -> Dictionary:
	var out := {
		"id": id,
		"cell": {"x": cell.x, "y": cell.y},
		"color": "#" + color.to_html(false),
		"radius": radius_cells,
		"energy": energy,
	}
	if not offset.is_equal_approx(Vector2(0.5, 0.5)):
		out["offset"] = {"x": offset.x, "y": offset.y}
	if absf(flicker) > 0.0:
		out["flicker"] = flicker
	return out


func duplicate_light() -> LightSource:
	var copy := LightSource.from_dict(to_dict())
	copy.region = region
	return copy
