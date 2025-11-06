## Space-Folding Puzzle Game - File Utility Functions
##
## This class provides file and directory utility functions for the game.
## All functions are static and thread-safe.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends Node
class_name FileUtils


## Get list of custom level files from a directory
##
## Scans the specified directory for .json files and returns their names
## (without the .json extension) in sorted order.
##
## @param directory: The directory path to scan (e.g., "user://levels/")
## @return: Array of level file names without .json extension, sorted alphabetically
##
## Example:
##   var levels = FileUtils.get_custom_level_files("user://levels/")
##   # Returns ["level1", "level2", "my_puzzle"] if those .json files exist
static func get_custom_level_files(directory: String) -> Array[String]:
	var files: Array[String] = []

	if not DirAccess.dir_exists_absolute(directory):
		return files

	var dir = DirAccess.open(directory)
	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			files.append(file_name.replace(".json", ""))
		file_name = dir.get_next()

	dir.list_dir_end()
	files.sort()

	return files
