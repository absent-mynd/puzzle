class_name BaseGrid extends Resource

## BaseGrid
##
## The immutable base (unfolded) level: a set of BaseTiles plus grid metrics.
## Created once at level load and never mutated. Together with an ordered list of
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


## Unit square polygon (LOCAL coords, relative to GridManager) for the base tile
## with the given id. Matches Cell._init's square construction so downstream
## geometry is identical.
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


## Build a BaseGrid by snapshotting a GridManager's CURRENT cells. Used at fold-
## engine init time: the live grid (already populated with the level's types, no
## folds yet) becomes the immutable base. Dominant type of an unfolded cell is its
## single piece's type (0-3; no null in an unfolded level).
static func from_grid_manager(gm) -> BaseGrid:
	var bg := BaseGrid.new(gm.grid_size, gm.cell_size)
	var tiles_arr: Array[BaseTile] = []
	var next_id := 0
	for y in range(gm.grid_size.y):
		for x in range(gm.grid_size.x):
			var pos := Vector2i(x, y)
			var cell = gm.get_cell(pos)
			var type := BaseTile.TYPE_EMPTY
			var data := {}
			if cell:
				type = cell.get_dominant_type()
				if type == CellPiece.CELL_TYPE_NULL:
					type = BaseTile.TYPE_EMPTY
				data = cell.tile_data
			tiles_arr.append(BaseTile.new(next_id, pos, type, data))
			next_id += 1
	bg.tiles = tiles_arr
	bg._rebuild_index()
	return bg


## Build a BaseGrid from a LevelData. Every in-bounds position becomes a BaseTile;
## cell_data (which only stores non-empty cells) supplies non-default types.
static func from_level_data(ld: LevelData) -> BaseGrid:
	var bg := BaseGrid.new(ld.grid_size, ld.cell_size)
	var tiles_arr: Array[BaseTile] = []
	var next_id := 0
	for y in range(ld.grid_size.y):
		for x in range(ld.grid_size.x):
			var pos := Vector2i(x, y)
			tiles_arr.append(BaseTile.new(next_id, pos, ld.type_at(pos), ld.data_at(pos)))
			next_id += 1
	bg.tiles = tiles_arr
	bg._rebuild_index()
	return bg
