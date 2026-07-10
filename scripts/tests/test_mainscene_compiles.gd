## Compile smoke test (Stage 5)
##
## MainScene.gd has no class_name, so it isn't auto-compiled during test runs.
## Loading its GDScript resource forces compilation (with autoloads present),
## catching wiring/parse errors from the FoldSystem -> FoldController swap.

extends GutTest


func test_mainscene_script_compiles():
	var s = load("res://scenes/MainScene.gd")
	assert_not_null(s, "MainScene.gd should compile without errors")


func test_swapped_scripts_compile():
	for path in [
		"res://scripts/systems/FoldController.gd",
		"res://scripts/systems/FoldEngine.gd",
		"res://scripts/systems/HistoryManager.gd",
		"res://scripts/core/GridManager.gd",
		"res://scripts/core/Cell.gd",
		"res://scripts/systems/InteractionController.gd",
		"res://scripts/model/FoldReplay.gd",
	]:
		assert_not_null(load(path), "%s should compile" % path)
