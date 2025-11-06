#!/usr/bin/env -S godot --headless --script
extends SceneTree

## Level Validation Script
##
## Validates all level files in the campaign directory
## Usage: godot --headless --script tools/validate_levels.gd

func _init():
	print("=== Level Validation Script ===\n")

	var LevelManagerScript = load("res://scripts/systems/LevelManager.gd")
	var LevelValidatorScript = load("res://scripts/systems/LevelValidator.gd")

	var level_manager = LevelManagerScript.new()
	var validator = LevelValidatorScript.new()

	var levels_dir = "res://levels/campaign/"
	var level_files = level_manager.get_level_list(levels_dir)

	if level_files.is_empty():
		print("ERROR: No level files found in " + levels_dir)
		quit(1)
		return

	print("Found %d level files\n" % level_files.size())

	var total_levels = 0
	var valid_levels = 0
	var invalid_levels = 0
	var warnings_count = 0

	# Validate each level
	for level_file in level_files:
		total_levels += 1
		var file_name = level_file.get_file()

		print("Validating: %s" % file_name)
		print("------------------------------------------------------------")

		# Load the level
		var level_data = level_manager.load_level(level_file)

		if level_data == null:
			print("  [ERROR] Failed to load level file\n")
			invalid_levels += 1
			continue

		# Validate the level
		var result = validator.validate_level(level_data)

		# Print level info
		print("  ID: %s" % level_data.level_id)
		print("  Name: %s" % level_data.level_name)
		print("  Grid: %dx%d" % [level_data.grid_size.x, level_data.grid_size.y])
		print("  Difficulty: %d" % level_data.difficulty)

		# Print validation results
		if result["valid"]:
			print("  Status: [VALID]")
			valid_levels += 1
		else:
			print("  Status: [INVALID]")
			invalid_levels += 1

		# Print errors
		if result["errors"].size() > 0:
			print("  Errors:")
			for error in result["errors"]:
				print("    - " + error)

		# Print warnings
		if result["warnings"].size() > 0:
			print("  Warnings:")
			for warning in result["warnings"]:
				print("    - " + warning)
			warnings_count += result["warnings"].size()

		print()

	# Summary
	print("============================================================")
	print("VALIDATION SUMMARY")
	print("============================================================")
	print("Total levels: %d" % total_levels)
	print("Valid levels: %d" % valid_levels)
	print("Invalid levels: %d" % invalid_levels)
	print("Total warnings: %d" % warnings_count)
	print()

	if invalid_levels == 0:
		print("✓ All levels are valid!")
		quit(0)
	else:
		print("✗ Some levels have errors")
		quit(1)
