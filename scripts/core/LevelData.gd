class_name LevelData
extends Resource

## LevelData Resource
##
## Stores all information needed to define a level in the Space Folding Puzzle Game.
## Can be serialized to/from JSON for saving and loading.

## Basic level identification
@export var level_id: String = ""
@export var level_name: String = ""
@export var description: String = ""

## Grid configuration
@export var grid_size: Vector2i = Vector2i(10, 10)
@export var cell_size: float = 64.0

## Gameplay elements
@export var player_start_position: Vector2i = Vector2i(0, 0)

## Cell data: Dictionary mapping Vector2i grid positions to cell contents.
## A value is EITHER an int type (0=empty, 1=wall, 2=water, 3=goal, 4=trigger-fold)
## for a plain tile, OR a Dictionary {"type": N, ...params} for a behavioral tile
## (F3), e.g. {"type": 4, "channel": "A", "anchors": [[1,1],[4,1]]}. Only non-empty
## cells are stored. Use type_at()/data_at() to read either form uniformly.
@export var cell_data: Dictionary = {}

## Level constraints and goals
@export var difficulty: int = 1  # 1-5 rating
@export var max_folds: int = -1  # -1 = unlimited
@export var par_folds: int = -1  # -1 = not set, otherwise target for "perfect" completion

## Pre-placed folds (F7): an ordered list applied at load, BEFORE the player is
## placed. Each entry is {"anchor1": {x,y}, "anchor2": {x,y}} in base-grid coords.
## Because a fold hides the region between its creases, pre-placed folds ship a level
## already folded — the player can unfold them to REVEAL hidden areas ("nested"
## content is just the excised region of one base grid; no recursive sub-grids).
@export var folds: Array = []

## Additional metadata (author, tags, version, etc.)
@export var metadata: Dictionary = {}


## Converts this LevelData to a Dictionary for JSON serialization
func to_dict() -> Dictionary:
	var dict = {
		"level_id": level_id,
		"level_name": level_name,
		"description": description,
		"grid_size": {"x": grid_size.x, "y": grid_size.y},
		"cell_size": cell_size,
		"player_start_position": {"x": player_start_position.x, "y": player_start_position.y},
		"cell_data": {},
		"folds": folds.duplicate(true),
		"difficulty": difficulty,
		"max_folds": max_folds,
		"par_folds": par_folds,
		"metadata": metadata
	}

	# Convert Vector2i keys to strings for JSON compatibility
	for pos in cell_data:
		var key = "(%d, %d)" % [pos.x, pos.y]
		dict["cell_data"][key] = cell_data[pos]

	return dict


## Loads data from a Dictionary (deserialized from JSON)
func from_dict(dict: Dictionary) -> void:
	level_id = dict.get("level_id", "")
	level_name = dict.get("level_name", "")
	description = dict.get("description", "")

	# Parse grid_size
	if dict.has("grid_size"):
		var gs = dict["grid_size"]
		grid_size = Vector2i(gs.get("x", 10), gs.get("y", 10))

	cell_size = dict.get("cell_size", 64.0)

	# Parse player_start_position
	if dict.has("player_start_position"):
		var psp = dict["player_start_position"]
		player_start_position = Vector2i(psp.get("x", 0), psp.get("y", 0))

	difficulty = dict.get("difficulty", 1)
	max_folds = dict.get("max_folds", -1)
	par_folds = dict.get("par_folds", -1)
	folds = dict.get("folds", [])
	metadata = dict.get("metadata", {})

	# Parse cell_data - convert string keys back to Vector2i
	cell_data = {}
	if dict.has("cell_data"):
		for key in dict["cell_data"]:
			# Parse "(x, y)" format
			var coords = _parse_vector2i_string(key)
			if coords != null:
				cell_data[coords] = dict["cell_data"][key]


## Cell type at a position, reading either the int shorthand or a {"type": N} dict.
func type_at(pos: Vector2i) -> int:
	var v = cell_data.get(pos, 0)
	if v is Dictionary:
		return int(v.get("type", 0))
	return int(v)


## Per-instance parameters at a position ({} for plain int tiles).
func data_at(pos: Vector2i) -> Dictionary:
	var v = cell_data.get(pos, null)
	if v is Dictionary:
		var d: Dictionary = (v as Dictionary).duplicate(true)
		d.erase("type")  # `type` is read via type_at(); keep only behavior params
		return d
	return {}


## Creates a deep copy of this LevelData
func clone() -> LevelData:
	var copy = LevelData.new()
	copy.level_id = level_id
	copy.level_name = level_name
	copy.description = description
	copy.grid_size = grid_size
	copy.cell_size = cell_size
	copy.player_start_position = player_start_position
	copy.difficulty = difficulty
	copy.max_folds = max_folds
	copy.par_folds = par_folds

	# Deep copy dictionaries
	copy.cell_data = cell_data.duplicate(true)
	copy.folds = folds.duplicate(true)
	copy.metadata = metadata.duplicate(true)

	return copy


## Pre-placed folds as [anchor1, anchor2] Vector2i pairs, in order.
func fold_pairs() -> Array:
	var out: Array = []
	for f in folds:
		var a = f.get("anchor1", {})
		var b = f.get("anchor2", {})
		out.append([
			Vector2i(int(a.get("x", 0)), int(a.get("y", 0))),
			Vector2i(int(b.get("x", 0)), int(b.get("y", 0))),
		])
	return out


## Helper function to parse "(x, y)" string format to Vector2i
func _parse_vector2i_string(s: String) -> Vector2i:
	# Remove parentheses and split by comma
	s = s.replace("(", "").replace(")", "").replace(" ", "")
	var parts = s.split(",")

	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))

	return Vector2i.ZERO
