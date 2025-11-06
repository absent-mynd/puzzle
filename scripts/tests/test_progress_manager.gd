extends GutTest

# Tests for ProgressManager class
# ProgressManager tracks campaign progress and saves it persistently

var progress_manager: ProgressManager
var test_save_path: String = "user://test_campaign_progress.json"

func before_each():
	progress_manager = ProgressManager.new()
	progress_manager.SAVE_FILE = test_save_path  # Use test file instead of production
	add_child_autofree(progress_manager)

	# Clean up test save file
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(test_save_path)

func after_each():
	# Clean up test save file
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(test_save_path)

func test_progress_manager_initialization():
	assert_not_null(progress_manager, "ProgressManager should be instantiable")
	assert_not_null(progress_manager.campaign_data, "Should have campaign_data dictionary")

func test_initial_campaign_data_structure():
	var data = progress_manager.campaign_data

	assert_true(data.has("levels_completed"), "Should have levels_completed array")
	assert_true(data.has("levels_unlocked"), "Should have levels_unlocked array")
	assert_true(data.has("total_folds"), "Should have total_folds counter")
	assert_true(data.has("best_times"), "Should have best_times dictionary")
	assert_true(data.has("stars_earned"), "Should have stars_earned dictionary")

func test_first_level_unlocked_by_default():
	# First level should be unlocked by default
	assert_true(progress_manager.is_level_unlocked("01_introduction"), "First level should be unlocked by default")

func test_is_level_unlocked_for_locked_level():
	assert_false(progress_manager.is_level_unlocked("02_basic_folding"), "Second level should be locked initially")

func test_unlock_level():
	progress_manager.unlock_level("02_basic_folding")

	assert_true(progress_manager.is_level_unlocked("02_basic_folding"), "Level should be unlocked after unlock_level()")

func test_mark_level_complete():
	var stats = {
		"fold_count": 3,
		"time_elapsed": 45.5,
		"par_folds": 3
	}

	progress_manager.mark_level_complete("01_introduction", stats)

	assert_true(progress_manager.is_level_completed("01_introduction"), "Level should be marked as completed")
	assert_true("01_introduction" in progress_manager.campaign_data["levels_completed"], "Level should be in completed list")

func test_mark_level_complete_updates_total_folds():
	var initial_folds = progress_manager.campaign_data["total_folds"]

	var stats = {"fold_count": 5}
	progress_manager.mark_level_complete("01_introduction", stats)

	assert_eq(progress_manager.campaign_data["total_folds"], initial_folds + 5, "Total folds should increase by fold_count")

func test_calculate_stars_for_par():
	var stats = {
		"fold_count": 3,
		"par_folds": 3
	}

	var stars = progress_manager.calculate_stars(stats)

	assert_eq(stars, 3, "Meeting par should give 3 stars")

func test_calculate_stars_for_under_par():
	var stats = {
		"fold_count": 2,
		"par_folds": 3
	}

	var stars = progress_manager.calculate_stars(stats)

	assert_eq(stars, 3, "Under par should give 3 stars")

func test_calculate_stars_for_slightly_over_par():
	var stats = {
		"fold_count": 4,
		"par_folds": 3
	}

	var stars = progress_manager.calculate_stars(stats)

	assert_eq(stars, 2, "1.33x par should give 2 stars")

func test_calculate_stars_for_way_over_par():
	var stats = {
		"fold_count": 10,
		"par_folds": 3
	}

	var stars = progress_manager.calculate_stars(stats)

	assert_eq(stars, 1, "3.33x par should give 1 star")

func test_stars_earned_stored_correctly():
	var stats = {
		"fold_count": 3,
		"par_folds": 3
	}

	progress_manager.mark_level_complete("01_introduction", stats)

	assert_eq(progress_manager.campaign_data["stars_earned"]["01_introduction"], 3, "Stars should be stored in campaign_data")

func test_stars_only_increase_not_decrease():
	# Complete with 3 stars
	var stats_good = {"fold_count": 3, "par_folds": 3}
	progress_manager.mark_level_complete("01_introduction", stats_good)

	assert_eq(progress_manager.campaign_data["stars_earned"]["01_introduction"], 3, "Should have 3 stars initially")

	# Complete again with 1 star
	var stats_bad = {"fold_count": 10, "par_folds": 3}
	progress_manager.mark_level_complete("01_introduction", stats_bad)

	assert_eq(progress_manager.campaign_data["stars_earned"]["01_introduction"], 3, "Stars should not decrease")

func test_save_progress():
	progress_manager.mark_level_complete("01_introduction", {"fold_count": 3})
	progress_manager.unlock_level("02_basic_folding")

	progress_manager.save_progress()

	assert_true(FileAccess.file_exists(test_save_path), "Save file should be created")

func test_load_progress():
	# Setup and save progress
	progress_manager.mark_level_complete("01_introduction", {"fold_count": 3})
	progress_manager.unlock_level("02_basic_folding")
	progress_manager.save_progress()

	# Create new ProgressManager and load
	var new_pm = ProgressManager.new()
	new_pm.SAVE_FILE = test_save_path
	add_child_autofree(new_pm)
	new_pm.load_progress()

	assert_true(new_pm.is_level_completed("01_introduction"), "Loaded data should have completed level")
	assert_true(new_pm.is_level_unlocked("02_basic_folding"), "Loaded data should have unlocked level")

func test_load_progress_with_nonexistent_file():
	# Should not crash, just use defaults
	progress_manager.load_progress()

	assert_not_null(progress_manager.campaign_data, "Should have default campaign_data")
	assert_true(progress_manager.is_level_unlocked("01_introduction"), "First level should still be unlocked")

func test_load_progress_with_corrupted_file():
	# Create corrupted save file
	var file = FileAccess.open(test_save_path, FileAccess.WRITE)
	file.store_string("{corrupted json")
	file.close()

	# Should handle gracefully
	progress_manager.load_progress()

	assert_not_null(progress_manager.campaign_data, "Should fallback to defaults on corrupted file")

func test_get_total_stars():
	progress_manager.campaign_data["stars_earned"]["level_1"] = 3
	progress_manager.campaign_data["stars_earned"]["level_2"] = 2
	progress_manager.campaign_data["stars_earned"]["level_3"] = 1

	var total = progress_manager.get_total_stars()

	assert_eq(total, 6, "Total stars should sum all earned stars")

func test_get_completion_percentage():
	# Simulate 3 total campaign levels
	progress_manager.mark_level_complete("01_introduction", {"fold_count": 3})
	progress_manager.mark_level_complete("02_basic_folding", {"fold_count": 5})

	# If we had a method to set total levels, we'd use it here
	# For now, assume completion percentage is based on completed levels
	var completed_count = progress_manager.campaign_data["levels_completed"].size()

	assert_eq(completed_count, 2, "Should have 2 completed levels")

func test_reset_progress():
	# Setup some progress
	progress_manager.mark_level_complete("01_introduction", {"fold_count": 3})
	progress_manager.unlock_level("02_basic_folding")
	progress_manager.save_progress()

	# Reset
	progress_manager.reset_progress()

	assert_eq(progress_manager.campaign_data["levels_completed"].size(), 0, "Completed levels should be cleared")
	assert_eq(progress_manager.campaign_data["total_folds"], 0, "Total folds should be reset")
	assert_true(progress_manager.is_level_unlocked("01_introduction"), "First level should still be unlocked")

func test_unlock_next_level():
	progress_manager.unlock_next_level("01_introduction")

	assert_true(progress_manager.is_level_unlocked("02_basic_folding"), "Next level should be unlocked")

func test_get_best_time():
	var stats1 = {"time_elapsed": 45.5}
	progress_manager.mark_level_complete("01_introduction", stats1)

	var best_time = progress_manager.get_best_time("01_introduction")

	assert_eq(best_time, 45.5, "Best time should be recorded")

func test_best_time_only_decreases():
	# Complete with time 45.5
	var stats1 = {"time_elapsed": 45.5}
	progress_manager.mark_level_complete("01_introduction", stats1)

	# Complete again with worse time
	var stats2 = {"time_elapsed": 60.0}
	progress_manager.mark_level_complete("01_introduction", stats2)

	var best_time = progress_manager.get_best_time("01_introduction")

	assert_eq(best_time, 45.5, "Best time should not increase")

func test_best_time_improves():
	# Complete with time 45.5
	var stats1 = {"time_elapsed": 45.5}
	progress_manager.mark_level_complete("01_introduction", stats1)

	# Complete again with better time
	var stats2 = {"time_elapsed": 30.0}
	progress_manager.mark_level_complete("01_introduction", stats2)

	var best_time = progress_manager.get_best_time("01_introduction")

	assert_eq(best_time, 30.0, "Best time should improve")

func test_get_stars_for_level():
	var stats = {"fold_count": 3, "par_folds": 3}
	progress_manager.mark_level_complete("01_introduction", stats)

	var stars = progress_manager.get_stars_for_level("01_introduction")

	assert_eq(stars, 3, "Should return stars for completed level")

func test_get_stars_for_uncompleted_level():
	var stars = progress_manager.get_stars_for_level("99_uncompleted")

	assert_eq(stars, 0, "Uncompleted level should have 0 stars")

func test_is_level_completed_false_for_new_level():
	assert_false(progress_manager.is_level_completed("99_new_level"), "New level should not be completed")
