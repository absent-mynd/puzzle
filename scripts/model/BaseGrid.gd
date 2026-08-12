class_name BaseGrid extends Resource

## BaseGrid
##
## The immutable base (unfolded) space: a set of BaseTiles plus grid metrics.
## Created once at world load and never mutated. Together with an ordered list of
## folds it is the SOLE source of truth; the folded state is a pure function of
## (BaseGrid, folds) computed by FoldReplay.derive().
##
## Design note: every in-bounds position is materialized as a BaseTile (empty
## floor = TYPE_EMPTY), so "occupied & walkable" is the default and "void" is
## expressed as the absence of a layer in the DERIVED state, never here.

@export var grid_size: Vector2i = Vector2i(10, 10)
@export var cell_size: float = 64.0

## All base tiles, indexed by base_id (tiles[i].base_id == i).
@export var tiles: Array[BaseTile] = []

## Lazily-built lookup: Vector2i grid_position -> BaseTile.
var _by_pos: Dictionary = {}


func _init(p_grid_size: Vector2i = Vector2i(10, 10), p_cell_size: float = 64.0):
	grid_size = p_grid_size
	cell_size = p_cell_size


## Build a grid of `grid_size` where every position is materialized, taking non-default
## types (and optional per-tile data) from a sparse map. `types` is keyed by Vector2i and
## holds either a plain type int or a `{"type": N, ...params}` dictionary.
##
## This is the programmatic constructor; `WorldCore.parse_map` is the authoring one
## (ASCII rows). Both produce the same thing.
static func from_types(p_grid_size: Vector2i, p_cell_size: float, types: Dictionary = {}) -> BaseGrid:
	var bg := BaseGrid.new(p_grid_size, p_cell_size)
	var arr: Array[BaseTile] = []
	var next_id := 0
	for y in range(p_grid_size.y):
		for x in range(p_grid_size.x):
			var pos := Vector2i(x, y)
			var v = types.get(pos, TileTypes.EMPTY)
			var type := TileTypes.EMPTY
			var data := {}
			if v is Dictionary:
				type = int(v.get("type", TileTypes.EMPTY))
				data = (v as Dictionary).duplicate(true)
				data.erase("type")
			else:
				type = int(v)
			arr.append(BaseTile.new(next_id, pos, type, data))
			next_id += 1
	bg.tiles = arr
	bg._rebuild_index()
	return bg


## Rebuild the position lookup. Call after populating `tiles`.
func _rebuild_index() -> void:
	_by_pos.clear()
	for t in tiles:
		_by_pos[t.grid_position] = t


## Get the base tile at a grid position, or null if out of bounds / absent.
func tile_at(pos: Vector2i) -> BaseTile:
	if _by_pos.is_empty() and not tiles.is_empty():
		_rebuild_index()
	return _by_pos.get(pos, null)


## Get the base tile by its stable id, or null if out of range.
func tile_by_id(base_id: int) -> BaseTile:
	if base_id < 0 or base_id >= tiles.size():
		return null
	return tiles[base_id]


## Is a grid position within the base grid bounds?
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y


## Unit square polygon (LOCAL, world-space px) for the base tile
## with the given id. Matches Cell._init's square construction so downstream
## geometry is built from this.
func unit_square_local(base_id: int) -> PackedVector2Array:
	var t := tile_by_id(base_id)
	if t == null:
		return PackedVector2Array()
	return square_at(t.grid_position)


## Unit square polygon (LOCAL coords) for an arbitrary grid position.
func square_at(pos: Vector2i) -> PackedVector2Array:
	var local_pos := Vector2(pos) * cell_size
	return PackedVector2Array([
		local_pos,
		local_pos + Vector2(cell_size, 0),
		local_pos + Vector2(cell_size, cell_size),
		local_pos + Vector2(0, cell_size),
	])


