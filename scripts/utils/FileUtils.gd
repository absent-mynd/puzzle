## Space-Folding Puzzle Game - File Utility Functions
##
## This class provides file and directory utility functions for the game.
## All functions are static and thread-safe.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends Node
class_name FileUtils


## The names of the .json files in a directory, without the extension, sorted.
##
## Non-recursive, which is the property `Launcher` relies on: it lists `worlds/` and
## the suite's fixtures in `worlds/fixtures/` stay out of it without anything having
## to know they are there.
##
## Nothing in the GAME discovers a world by scanning — a run is given a path
## (`FoldWorld.WORLD_PATH`, `--world=`, or a document in memory). Only the launcher
## asks what is on disk, because "what worlds do I have" is a question about the tree
## you are working in rather than about the game.
##
## Example:
##   var names = FileUtils.json_names_in("res://worlds/")
static func json_names_in(directory: String) -> Array[String]:
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
