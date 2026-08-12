class_name BaseTile extends Resource

## BaseTile
##
## Immutable identity for one original grid square in the base (unfolded) space.
## Base tiles are created once at world load and NEVER mutate. The folded
## configuration is derived by replaying folds over the base grid (see FoldReplay).
##
## There is NO "null" type here: void = the ABSENCE of any layer at a plane
## position. This eliminates the null-piece workaround of the old mutating engine.
##
## Type convention (see TileTypes, the registry that owns per-type behavior; downstream color/collision
## code is unchanged):
##   0 = empty (walkable, default floor)
##   1 = wall  (unwalkable)
##   2 = water (walkable)
##   3 = goal  (walkable)

const TYPE_EMPTY := 0
const TYPE_WALL := 1
const TYPE_WATER := 2
const TYPE_GOAL := 3

## Stable identity: index into BaseGrid.tiles. Survives all folds/unfolds and is
## what the player "rides" as cells shift.
@export var base_id: int = -1

## Original grid position in the unfolded base grid.
@export var grid_position: Vector2i = Vector2i.ZERO

## Cell type (see convention above).
@export var type: int = TYPE_EMPTY

## Per-instance parameters for behavioral tiles (F3). Empty for plain tiles. A
## trigger tile, for example, carries {"channel": "A", "anchors": [[1,1],[4,1]]}.
## Kept as a plain Dictionary so new behaviors add keys without schema churn.
@export var data: Dictionary = {}


func _init(p_base_id: int = -1, p_grid_position: Vector2i = Vector2i.ZERO, p_type: int = TYPE_EMPTY, p_data: Dictionary = {}):
	base_id = p_base_id
	grid_position = p_grid_position
	type = p_type
	data = p_data
