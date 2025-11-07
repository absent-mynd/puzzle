class_name ProgressManager
extends Node

## ProgressManager
##
## Tracks campaign progress including completed levels, stars earned,
## and best times. Persists data across game sessions.

## Path to save file (can be overridden for testing)
var SAVE_FILE: String = "user://campaign_progress.json"

## Campaign progress data
var campaign_data: Dictionary = {
	"levels_completed": [],
	"levels_unlocked": ["01_introduction"],  # First level unlocked by default
	"total_folds": 0,
	"best_times": {},  # level_id -> best_time
	"stars_earned": {}  # level_id -> stars (0-3)
}


func _ready():
	load_progress()


## Saves campaign progress to disk
func save_progress() -> void:
	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file == null:
		push_warning("ProgressManager: Failed to open save file for writing")
		return

	var json_string = JSON.stringify(campaign_data, "\t")
	file.store_string(json_string)
	file.close()


## Loads campaign progress from disk
func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_FILE):
		# No save file, use defaults
		return

	var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
	if file == null:
		push_warning("ProgressManager: Failed to open save file for reading")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)

	if error != OK:
		push_warning("ProgressManager: Failed to parse save file, using defaults")
		return

	var loaded_data = json.data
	if loaded_data is Dictionary:
		# Merge with defaults to ensure all keys exist
		for key in campaign_data:
			if loaded_data.has(key):
				campaign_data[key] = loaded_data[key]


## Marks a level as complete and updates stats
func mark_level_complete(level_id: String, stats: Dictionary) -> void:
	# Add to completed list if not already there
	if level_id not in campaign_data["levels_completed"]:
		campaign_data["levels_completed"].append(level_id)

	# Update total folds
	if stats.has("fold_count"):
		campaign_data["total_folds"] += stats["fold_count"]

	# Calculate and store stars (only if better than previous)
	var stars = calculate_stars(stats)
	var current_stars = campaign_data["stars_earned"].get(level_id, 0)
	campaign_data["stars_earned"][level_id] = max(stars, current_stars)

	# Update best time (only if better than previous)
	if stats.has("time_elapsed"):
		var current_best = campaign_data["best_times"].get(level_id, INF)
		campaign_data["best_times"][level_id] = min(stats["time_elapsed"], current_best)

	# Unlock next level
	unlock_next_level(level_id)

	# Auto-save
	save_progress()


## Calculates star rating based on performance
## Returns 1-3 stars based on fold efficiency
func calculate_stars(stats: Dictionary) -> int:
	if not stats.has("fold_count") or not stats.has("par_folds"):
		return 1  # Default to 1 star if data missing

	var fold_count = stats["fold_count"]
	var par_folds = stats["par_folds"]

	if par_folds <= 0:
		return 1  # No par set

	# 3 stars: At or under par
	if fold_count <= par_folds:
		return 3

	# 2 stars: Under 1.5x par
	var ratio = float(fold_count) / float(par_folds)
	if ratio < 1.5:
		return 2

	# 1 star: Completed but over 1.5x par
	return 1


## Unlocks the next sequential level
func unlock_next_level(completed_level_id: String) -> void:
	var next_level = get_sequential_next_level(completed_level_id)
	if not next_level.is_empty():
		unlock_level(next_level)


## Gets the next level ID in sequence
## Assumes format like "01_introduction", "02_basic_folding", etc.
func get_sequential_next_level(level_id: String) -> String:
	# Main campaign sequence (3 levels)
	var level_sequence = {
		"01_introduction": "02_basic_folding",
		"02_basic_folding": "03_diagonal_challenge",
		"03_diagonal_challenge": ""  # End of campaign
	}

	return level_sequence.get(level_id, "")


## Unlocks a specific level
func unlock_level(level_id: String) -> void:
	if level_id not in campaign_data["levels_unlocked"]:
		campaign_data["levels_unlocked"].append(level_id)


## Checks if a level is unlocked
func is_level_unlocked(level_id: String) -> bool:
	return level_id in campaign_data["levels_unlocked"]


## Checks if a level is completed
func is_level_completed(level_id: String) -> bool:
	return level_id in campaign_data["levels_completed"]


## Gets the star count for a specific level
func get_stars_for_level(level_id: String) -> int:
	return campaign_data["stars_earned"].get(level_id, 0)


## Gets the best time for a specific level
func get_best_time(level_id: String) -> float:
	return campaign_data["best_times"].get(level_id, INF)


## Gets total stars earned across all levels
func get_total_stars() -> int:
	var total = 0
	for level_id in campaign_data["stars_earned"]:
		total += campaign_data["stars_earned"][level_id]
	return total


## Resets all progress (use with caution!)
func reset_progress() -> void:
	campaign_data = {
		"levels_completed": [],
		"levels_unlocked": ["01_introduction"],
		"total_folds": 0,
		"best_times": {},
		"stars_earned": {}
	}
	save_progress()
