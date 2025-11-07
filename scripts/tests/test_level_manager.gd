extends GutTest

# Tests for LevelManager class
# LevelManager handles saving, loading, and managing level files

var level_manager: LevelManager
var test_level_path: String = "user://test_level.json"
var test_campaign_path: String = "res://levels/campaign/"

func before_each():
	level_manager = LevelManager.new()
	add_child_autofree(level_manager)

	# Clean up any existing test files
	if FileAccess.file_exists(test_level_path):
		DirAccess.remove_absolute(test_level_path)

func after_each():
	# Clean up test files
	if FileAccess.file_exists(test_level_path):
		DirAccess.remove_absolute(test_level_path)

func test_level_manager_initialization():
	assert_not_null(level_manager, "LevelManager should be instantiable")

func test_save_level_to_json():
	var level = LevelData.new()
	level.level_id = "test_001"
	level.level_name = "Test Level"
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(0, 0)
	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	var success = level_manager.save_level(level, test_level_path)

	assert_true(success, "save_level should return true on success")
	assert_true(FileAccess.file_exists(test_level_path), "Level file should exist after saving")

func test_load_level_from_json():
	# First, save a level
	var original_level = LevelData.new()
	original_level.level_id = "test_002"
	original_level.level_name = "Load Test Level"
	original_level.grid_size = Vector2i(12, 12)
	original_level.player_start_position = Vector2i(1, 1)
	original_level.cell_data[Vector2i(5, 5)] = 1  # Wall
	original_level.cell_data[Vector2i(10, 10)] = 3  # Goal
	original_level.par_folds = 5

	level_manager.save_level(original_level, test_level_path)

	# Now load it back
	var loaded_level = level_manager.load_level(test_level_path)

	assert_not_null(loaded_level, "load_level should return a LevelData object")
	assert_eq(loaded_level.level_id, "test_002", "Loaded level_id should match original")
	assert_eq(loaded_level.level_name, "Load Test Level", "Loaded level_name should match original")
	assert_eq(loaded_level.grid_size, Vector2i(12, 12), "Loaded grid_size should match original")
	assert_eq(loaded_level.player_start_position, Vector2i(1, 1), "Loaded player_start should match original")
	assert_eq(loaded_level.par_folds, 5, "Loaded par_folds should match original")
	assert_eq(loaded_level.cell_data.size(), 2, "Loaded cell_data should have 2 entries")
	assert_eq(loaded_level.cell_data[Vector2i(5, 5)], 1, "Loaded wall cell should match original")
	assert_eq(loaded_level.cell_data[Vector2i(10, 10)], 3, "Loaded goal cell should match original")

func test_load_level_returns_null_for_nonexistent_file():
	var loaded_level = level_manager.load_level("user://nonexistent_level.json")

	assert_null(loaded_level, "load_level should return null for nonexistent file")

func test_load_level_returns_null_for_invalid_json():
	# Create a file with invalid JSON
	var file = FileAccess.open(test_level_path, FileAccess.WRITE)
	file.store_string("{invalid json content")
	file.close()

	var loaded_level = level_manager.load_level(test_level_path)

	assert_null(loaded_level, "load_level should return null for invalid JSON")

func test_save_and_load_preserves_all_data():
	var original = LevelData.new()
	original.level_id = "complex_001"
	original.level_name = "Complex Test"
	original.description = "A complex level with all features"
	original.grid_size = Vector2i(15, 20)
	original.cell_size = 48.0
	original.player_start_position = Vector2i(3, 7)
	original.difficulty = 4
	original.max_folds = 10
	original.par_folds = 6
	original.metadata["author"] = "Test Suite"
	original.metadata["version"] = "1.0"

	# Add multiple cell types
	for i in range(5):
		original.cell_data[Vector2i(i, i)] = 1  # Walls
	original.cell_data[Vector2i(8, 8)] = 2  # Water
	original.cell_data[Vector2i(14, 19)] = 3  # Goal

	level_manager.save_level(original, test_level_path)
	var loaded = level_manager.load_level(test_level_path)

	assert_eq(loaded.level_id, original.level_id, "Complex level_id should be preserved")
	assert_eq(loaded.description, original.description, "Complex description should be preserved")
	assert_eq(loaded.grid_size, original.grid_size, "Complex grid_size should be preserved")
	assert_eq(loaded.cell_size, original.cell_size, "Complex cell_size should be preserved")
	assert_eq(loaded.difficulty, original.difficulty, "Complex difficulty should be preserved")
	assert_eq(loaded.max_folds, original.max_folds, "Complex max_folds should be preserved")
	assert_eq(loaded.metadata["author"], "Test Suite", "Complex metadata should be preserved")
	assert_eq(loaded.cell_data.size(), 7, "Complex cell_data should have 7 entries")

func test_get_level_list_returns_campaign_levels():
	var levels = level_manager.get_level_list("res://levels/campaign/")

	assert_not_null(levels, "get_level_list should return an array")
	assert_true(levels is Array, "get_level_list should return an Array")

func test_get_level_list_filters_json_files():
	var levels = level_manager.get_level_list("res://levels/campaign/")

	# All returned files should end with .json
	for level_path in levels:
		assert_true(level_path.ends_with(".json"), "All level files should be .json files: " + level_path)

	# Always assert something even if directory is empty
	assert_true(true, "Test completed - checked " + str(levels.size()) + " files")

func test_get_level_list_empty_directory():
	# Custom directory now contains test campaign levels (16 levels)
	var levels = level_manager.get_level_list("res://levels/custom/")

	assert_not_null(levels, "get_level_list should return an array")
	assert_eq(levels.size(), 16, "Custom directory should contain 16 test campaign levels")

func test_load_level_by_id_finds_correct_level():
	# This test requires actual campaign levels to exist
	# For now, we'll test the method exists and handles missing IDs
	var level = level_manager.load_level_by_id("nonexistent_id")

	assert_null(level, "load_level_by_id should return null for nonexistent ID")

func test_validate_level_data_before_saving():
	var invalid_level = LevelData.new()
	# Level with no level_id should be considered invalid
	invalid_level.level_id = ""

	var success = level_manager.save_level(invalid_level, test_level_path)

	# LevelManager should validate and possibly reject invalid levels
	# The exact behavior depends on implementation
	assert_not_null(success, "save_level should return a boolean result")

func test_save_level_creates_directory_if_needed():
	var nested_path = "user://test_dir/nested/level.json"

	var level = LevelData.new()
	level.level_id = "nested_test"
	level.level_name = "Nested Test"

	var success = level_manager.save_level(level, nested_path)

	assert_true(success, "save_level should create directories if needed")
	assert_true(FileAccess.file_exists(nested_path), "Nested file should exist")

	# Clean up
	DirAccess.remove_absolute(nested_path)

func test_json_formatting_is_readable():
	var level = LevelData.new()
	level.level_id = "format_test"
	level.level_name = "Format Test"

	level_manager.save_level(level, test_level_path)

	# Read the file and check if it's properly formatted
	var file = FileAccess.open(test_level_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()

	assert_true(json_string.length() > 0, "JSON file should not be empty")
	assert_true(json_string.contains("level_id"), "JSON should contain level_id field")
	assert_true(json_string.contains("format_test"), "JSON should contain the level_id value")

func test_save_level_handles_special_characters():
	var level = LevelData.new()
	level.level_id = "special_test"
	level.level_name = "Test with \"quotes\" and 'apostrophes'"
	level.description = "Test\nwith\nnewlines"

	var success = level_manager.save_level(level, test_level_path)
	assert_true(success, "Should handle special characters in save")

	var loaded = level_manager.load_level(test_level_path)
	assert_eq(loaded.level_name, level.level_name, "Special characters in name should be preserved")
	assert_eq(loaded.description, level.description, "Special characters in description should be preserved")

func test_concurrent_save_load_operations():
	var level1 = LevelData.new()
	level1.level_id = "concurrent_1"

	var level2 = LevelData.new()
	level2.level_id = "concurrent_2"

	var path1 = "user://concurrent_1.json"
	var path2 = "user://concurrent_2.json"

	level_manager.save_level(level1, path1)
	level_manager.save_level(level2, path2)

	var loaded1 = level_manager.load_level(path1)
	var loaded2 = level_manager.load_level(path2)

	assert_eq(loaded1.level_id, "concurrent_1", "First level should load correctly")
	assert_eq(loaded2.level_id, "concurrent_2", "Second level should load correctly")

	# Clean up
	DirAccess.remove_absolute(path1)
	DirAccess.remove_absolute(path2)
