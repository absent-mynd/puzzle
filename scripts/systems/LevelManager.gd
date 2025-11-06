class_name LevelManager
extends Node

## LevelManager
##
## Handles loading, saving, and managing level files.
## Supports JSON format for level data storage.

## Cache of loaded levels to avoid re-parsing
var _level_cache: Dictionary = {}


## Saves a level to a JSON file
## Returns true on success, false on failure
func save_level(level_data: LevelData, file_path: String) -> bool:
	if level_data == null:
		push_warning("LevelManager: Cannot save null level data")
		return false

	# Validate that level has at least an ID
	if level_data.level_id.is_empty():
		push_warning("LevelManager: Cannot save level without an ID")
		return false

	# Create directory if it doesn't exist
	var dir_path = file_path.get_base_dir()
	if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
		var error = DirAccess.make_dir_recursive_absolute(dir_path)
		if error != OK:
			push_warning("LevelManager: Failed to create directory: " + dir_path)
			return false

	# Convert level data to dictionary
	var dict = level_data.to_dict()

	# Serialize to JSON
	var json_string = JSON.stringify(dict, "\t")  # Use tabs for readability

	# Write to file
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_warning("LevelManager: Failed to open file for writing: " + file_path)
		return false

	file.store_string(json_string)
	file.close()

	# Update cache
	_level_cache[file_path] = level_data.clone()

	return true


## Loads a level from a JSON file
## Returns LevelData on success, null on failure
func load_level(file_path: String) -> LevelData:
	# Check cache first
	if _level_cache.has(file_path):
		return _level_cache[file_path].clone()

	# Check if file exists
	if not FileAccess.file_exists(file_path):
		push_warning("LevelManager: Level file does not exist: " + file_path)
		return null

	# Read file
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("LevelManager: Failed to open file for reading: " + file_path)
		return null

	var json_string = file.get_as_text()
	file.close()

	# Parse JSON
	var json = JSON.new()
	var error = json.parse(json_string)

	if error != OK:
		push_warning("LevelManager: Failed to parse JSON at line " + str(json.get_error_line()) + ": " + json.get_error_message())
		return null

	var dict = json.data
	if not dict is Dictionary:
		push_warning("LevelManager: JSON root is not a dictionary")
		return null

	# Create LevelData from dictionary
	var level_data = LevelData.new()
	level_data.from_dict(dict)

	# Cache the loaded level
	_level_cache[file_path] = level_data.clone()

	return level_data


## Returns a list of level file paths in the specified directory
## Only includes .json files
func get_level_list(directory: String) -> Array[String]:
	var levels: Array[String] = []

	# Check if directory exists
	if not DirAccess.dir_exists_absolute(directory):
		return levels

	var dir = DirAccess.open(directory)
	if dir == null:
		push_warning("LevelManager: Failed to open directory: " + directory)
		return levels

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			levels.append(directory + file_name)
		file_name = dir.get_next()

	dir.list_dir_end()

	# Sort alphabetically for consistent ordering
	levels.sort()

	return levels


## Loads a level by its level_id
## Searches in campaign, custom, and level_packs directories
## Returns LevelData on success, null if not found
func load_level_by_id(level_id: String) -> LevelData:
	var search_directories = [
		"res://levels/campaign/",
		"res://levels/custom/",
		"res://levels/level_packs/"
	]

	for directory in search_directories:
		var level_files = get_level_list(directory)

		for file_path in level_files:
			var level = load_level(file_path)
			if level != null and level.level_id == level_id:
				return level

	push_warning("LevelManager: Level with ID '" + level_id + "' not found")
	return null


## Clears the level cache
## Useful for forcing a reload of all levels
func clear_cache() -> void:
	_level_cache.clear()


## Returns the file path for a level ID if it exists in cache
## Returns empty string if not found
func get_cached_level_path(level_id: String) -> String:
	for path in _level_cache:
		if _level_cache[path].level_id == level_id:
			return path
	return ""


## Pre-loads all levels in a directory into cache
## Useful for reducing load times during gameplay
func preload_levels(directory: String) -> int:
	var level_files = get_level_list(directory)
	var loaded_count = 0

	for file_path in level_files:
		var level = load_level(file_path)
		if level != null:
			loaded_count += 1

	return loaded_count
