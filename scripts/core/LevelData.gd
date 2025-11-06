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

## Cell data: Dictionary mapping Vector2i grid positions to CellType integers
## 0 = empty, 1 = wall, 2 = water, 3 = goal
## Only stores non-empty cells for efficiency
@export var cell_data: Dictionary = {}

## Level constraints and goals
@export var difficulty: int = 1  # 1-5 rating
@export var max_folds: int = -1  # -1 = unlimited
@export var par_folds: int = -1  # -1 = not set, otherwise target for "perfect" completion

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
	metadata = dict.get("metadata", {})

	# Parse cell_data - convert string keys back to Vector2i
	cell_data = {}
	if dict.has("cell_data"):
		for key in dict["cell_data"]:
			# Parse "(x, y)" format
			var coords = _parse_vector2i_string(key)
			if coords != null:
				cell_data[coords] = dict["cell_data"][key]


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
	copy.metadata = metadata.duplicate(true)

	return copy


## Helper function to parse "(x, y)" string format to Vector2i
func _parse_vector2i_string(s: String) -> Vector2i:
	# Remove parentheses and split by comma
	s = s.replace("(", "").replace(")", "").replace(" ", "")
	var parts = s.split(",")

	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))

	return Vector2i.ZERO
