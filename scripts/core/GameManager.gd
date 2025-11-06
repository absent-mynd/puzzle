extends Node

## GameManager
##
## Global singleton managing level system, progress tracking, and game state.
## Accessible from any script via GameManager global variable.

## Constants
const CUSTOM_LEVELS_DIR = "user://levels/"

## Level management
var level_manager: LevelManager = null
var progress_manager: ProgressManager = null

## Current game state
var current_level_id: String = ""
var current_level_data: LevelData = null
var fold_count: int = 0
var level_start_time: float = 0.0


func _ready() -> void:
	# Initialize managers
	level_manager = LevelManager.new()
	add_child(level_manager)

	progress_manager = ProgressManager.new()
	add_child(progress_manager)

	# Preload campaign levels for faster access
	level_manager.preload_levels("res://levels/campaign/")


## Starts a level by loading its data and transitioning to the game scene
func start_level(level_id: String) -> void:
	# Load level data
	var level_data = level_manager.load_level_by_id(level_id)

	if level_data == null:
		push_warning("GameManager: Failed to load level: " + level_id)
		return

	# Store current level info
	current_level_id = level_id
	current_level_data = level_data.clone()
	fold_count = 0
	level_start_time = Time.get_ticks_msec() / 1000.0

	# Load the game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Completes the current level and updates progress
func complete_level() -> void:
	if current_level_id.is_empty():
		return

	# Calculate elapsed time
	var elapsed_time = (Time.get_ticks_msec() / 1000.0) - level_start_time

	# Create stats dictionary
	var stats = {
		"fold_count": fold_count,
		"par_folds": current_level_data.par_folds,
		"time_elapsed": elapsed_time
	}

	# Mark level as complete
	progress_manager.mark_level_complete(current_level_id, stats)


## Gets the next level ID in sequence
func get_next_level_id() -> String:
	return progress_manager.get_sequential_next_level(current_level_id)


## Restarts the current level
func restart_level() -> void:
	if not current_level_id.is_empty():
		start_level(current_level_id)


## Returns to the main menu
func return_to_main_menu() -> void:
	current_level_id = ""
	current_level_data = null
	fold_count = 0
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


## Increments the fold counter
func increment_fold_count() -> void:
	fold_count += 1


## Gets campaign level list
func get_campaign_levels() -> Array[String]:
	return level_manager.get_level_list("res://levels/campaign/")


## Checks if a level is unlocked
func is_level_unlocked(level_id: String) -> bool:
	return progress_manager.is_level_unlocked(level_id)


## Checks if a level is completed
func is_level_completed(level_id: String) -> bool:
	return progress_manager.is_level_completed(level_id)


## Gets stars for a level
func get_stars_for_level(level_id: String) -> int:
	return progress_manager.get_stars_for_level(level_id)
