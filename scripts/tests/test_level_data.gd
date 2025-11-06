extends GutTest

# Tests for LevelData class
# LevelData is a Resource that stores all information needed to define a level

func test_level_data_initialization():
	var level = LevelData.new()
	assert_not_null(level, "LevelData should be instantiable")
	assert_eq(level.grid_size, Vector2i(10, 10), "Default grid size should be 10x10")
	assert_eq(level.cell_size, 64.0, "Default cell size should be 64.0")
	assert_eq(level.max_folds, -1, "Default max_folds should be -1 (unlimited)")
	assert_eq(level.par_folds, -1, "Default par_folds should be -1 (not set)")

func test_level_data_properties():
	var level = LevelData.new()

	# Test setting basic properties
	level.level_id = "test_001"
	level.level_name = "Test Level"
	level.description = "A test level for validation"
	level.difficulty = 3

	assert_eq(level.level_id, "test_001", "Level ID should be set correctly")
	assert_eq(level.level_name, "Test Level", "Level name should be set correctly")
	assert_eq(level.description, "A test level for validation", "Description should be set correctly")
	assert_eq(level.difficulty, 3, "Difficulty should be set correctly")

func test_level_data_grid_configuration():
	var level = LevelData.new()

	# Test grid size configuration
	level.grid_size = Vector2i(15, 20)
	level.cell_size = 32.0

	assert_eq(level.grid_size, Vector2i(15, 20), "Grid size should be set correctly")
	assert_eq(level.cell_size, 32.0, "Cell size should be set correctly")

func test_level_data_player_start_position():
	var level = LevelData.new()

	# Test player start position
	level.player_start_position = Vector2i(5, 5)

	assert_eq(level.player_start_position, Vector2i(5, 5), "Player start position should be set correctly")

func test_level_data_cell_data():
	var level = LevelData.new()

	# Test cell data dictionary
	level.cell_data[Vector2i(0, 0)] = 1  # Wall
	level.cell_data[Vector2i(1, 1)] = 2  # Water
	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	assert_eq(level.cell_data.size(), 3, "Cell data should have 3 entries")
	assert_eq(level.cell_data[Vector2i(0, 0)], 1, "Cell (0,0) should be a wall")
	assert_eq(level.cell_data[Vector2i(1, 1)], 2, "Cell (1,1) should be water")
	assert_eq(level.cell_data[Vector2i(9, 9)], 3, "Cell (9,9) should be goal")

func test_level_data_fold_constraints():
	var level = LevelData.new()

	# Test fold constraints
	level.max_folds = 5
	level.par_folds = 3

	assert_eq(level.max_folds, 5, "Max folds should be set correctly")
	assert_eq(level.par_folds, 3, "Par folds should be set correctly")

func test_level_data_metadata():
	var level = LevelData.new()

	# Test metadata dictionary
	level.metadata["author"] = "Test Author"
	level.metadata["tags"] = ["tutorial", "easy"]
	level.metadata["version"] = "1.0"

	assert_eq(level.metadata["author"], "Test Author", "Metadata author should be set correctly")
	assert_eq(level.metadata["version"], "1.0", "Metadata version should be set correctly")
	assert_true(level.metadata.has("tags"), "Metadata should have tags key")

func test_level_data_to_dict():
	var level = LevelData.new()
	level.level_id = "test_001"
	level.level_name = "Test Level"
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(0, 0)
	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	var dict = level.to_dict()

	assert_not_null(dict, "to_dict() should return a dictionary")
	assert_eq(dict["level_id"], "test_001", "Dict should contain level_id")
	assert_eq(dict["level_name"], "Test Level", "Dict should contain level_name")
	assert_true(dict.has("grid_size"), "Dict should contain grid_size")
	assert_true(dict.has("player_start_position"), "Dict should contain player_start_position")
	assert_true(dict.has("cell_data"), "Dict should contain cell_data")

func test_level_data_from_dict():
	var source_dict = {
		"level_id": "test_002",
		"level_name": "Test Level 2",
		"grid_size": {"x": 15, "y": 15},
		"cell_size": 48.0,
		"player_start_position": {"x": 1, "y": 1},
		"cell_data": {
			"(5, 5)": 1,  # Wall
			"(10, 10)": 3  # Goal
		},
		"difficulty": 2,
		"max_folds": 10,
		"par_folds": 5,
		"description": "Second test level",
		"metadata": {"author": "Tester"}
	}

	var level = LevelData.new()
	level.from_dict(source_dict)

	assert_eq(level.level_id, "test_002", "Level ID should be loaded from dict")
	assert_eq(level.level_name, "Test Level 2", "Level name should be loaded from dict")
	assert_eq(level.grid_size, Vector2i(15, 15), "Grid size should be loaded from dict")
	assert_eq(level.cell_size, 48.0, "Cell size should be loaded from dict")
	assert_eq(level.player_start_position, Vector2i(1, 1), "Player start should be loaded from dict")
	assert_eq(level.difficulty, 2, "Difficulty should be loaded from dict")
	assert_eq(level.max_folds, 10, "Max folds should be loaded from dict")
	assert_eq(level.par_folds, 5, "Par folds should be loaded from dict")
	assert_eq(level.description, "Second test level", "Description should be loaded from dict")

func test_level_data_clone():
	var original = LevelData.new()
	original.level_id = "original_001"
	original.level_name = "Original Level"
	original.grid_size = Vector2i(12, 12)
	original.player_start_position = Vector2i(3, 3)
	original.cell_data[Vector2i(5, 5)] = 1

	var clone = original.clone()

	assert_not_null(clone, "Clone should not be null")
	assert_eq(clone.level_id, original.level_id, "Cloned level_id should match original")
	assert_eq(clone.level_name, original.level_name, "Cloned level_name should match original")
	assert_eq(clone.grid_size, original.grid_size, "Cloned grid_size should match original")
	assert_eq(clone.player_start_position, original.player_start_position, "Cloned player_start should match original")

	# Verify deep copy (modifying clone shouldn't affect original)
	clone.level_id = "clone_001"
	clone.cell_data[Vector2i(6, 6)] = 2

	assert_eq(original.level_id, "original_001", "Original level_id should remain unchanged")
	assert_false(original.cell_data.has(Vector2i(6, 6)), "Original cell_data should not have clone's additions")
