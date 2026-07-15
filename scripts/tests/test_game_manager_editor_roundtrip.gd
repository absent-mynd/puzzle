## GameManager editor-test round-trip tests
##
## Covers the state used to round-trip between the level editor and play mode:
##  - restart_level() no longer no-ops during an editor test (empty id, in-memory data)
##  - return_to_editor() clears gameplay state but PRESERVES the editor session
##  - return_to_main_menu() clears the editor session too
##  - the stashed editor session is an independent clone
##  - LevelData grid_size/par_folds survive serialization (guards resize + metadata)
##
## These exercise the pure `_prepare_*` mutators so no scene change fires under GUT.

extends GutTest


## Snapshot the autoload fields we touch and restore them after each test so we don't
## leak state into other suites.
var _saved := {}


func before_each() -> void:
	_saved = {
		"current_level_id": GameManager.current_level_id,
		"current_level_data": GameManager.current_level_data,
		"fold_count": GameManager.fold_count,
		"is_testing_from_editor": GameManager.is_testing_from_editor,
		"editor_session": GameManager.editor_session,
	}


func after_each() -> void:
	GameManager.current_level_id = _saved["current_level_id"]
	GameManager.current_level_data = _saved["current_level_data"]
	GameManager.fold_count = _saved["fold_count"]
	GameManager.is_testing_from_editor = _saved["is_testing_from_editor"]
	GameManager.editor_session = _saved["editor_session"]


func _make_level() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "custom_test"
	ld.level_name = "Test"
	ld.grid_size = Vector2i(12, 8)
	ld.cell_size = 64.0
	ld.par_folds = 3
	ld.difficulty = 4
	ld.cell_data[Vector2i(2, 3)] = 1
	ld.cell_data[Vector2i(7, 4)] = 3
	return ld


func test_prepare_test_restart_reloads_in_memory_level() -> void:
	var ld := _make_level()
	GameManager.current_level_id = ""
	GameManager.current_level_data = ld
	GameManager.fold_count = 5

	var should_reload := GameManager._prepare_test_restart()

	assert_true(should_reload, "restart should reload when data is present")
	assert_eq(GameManager.fold_count, 0, "fold count reset on restart")
	assert_ne(GameManager.current_level_data, ld, "data is re-cloned (new instance)")
	assert_eq(GameManager.current_level_data.cell_data, ld.cell_data,
		"re-cloned data preserves cell layout")


func test_prepare_test_restart_noop_when_no_data() -> void:
	GameManager.current_level_id = ""
	GameManager.current_level_data = null
	GameManager.fold_count = 4

	var should_reload := GameManager._prepare_test_restart()

	assert_false(should_reload, "no reload without in-memory data")
	assert_eq(GameManager.fold_count, 4, "state untouched when there's nothing to reload")


func test_prepare_return_to_editor_keeps_session() -> void:
	GameManager.is_testing_from_editor = true
	GameManager.current_level_id = ""
	GameManager.current_level_data = _make_level()
	GameManager.fold_count = 2
	GameManager.editor_session = {"level_data": _make_level(), "cursor": Vector2i(1, 1),
		"player_start": Vector2i(1, 1), "filename": "foo"}

	GameManager._prepare_return_to_editor()

	assert_false(GameManager.is_testing_from_editor, "test flag cleared")
	assert_null(GameManager.current_level_data, "gameplay data cleared")
	assert_eq(GameManager.fold_count, 0, "fold count cleared")
	assert_false(GameManager.editor_session.is_empty(),
		"editor session PRESERVED for the editor to consume")


func test_prepare_return_to_main_menu_clears_session() -> void:
	GameManager.is_testing_from_editor = true
	GameManager.editor_session = {"level_data": _make_level(), "cursor": Vector2i.ZERO,
		"player_start": Vector2i.ZERO, "filename": "foo"}
	GameManager.current_level_data = _make_level()

	GameManager._prepare_return_to_main_menu()

	assert_false(GameManager.is_testing_from_editor, "test flag cleared")
	assert_true(GameManager.editor_session.is_empty(), "editor session cleared")
	assert_null(GameManager.current_level_data, "gameplay data cleared")


func test_editor_session_stash_is_independent_clone() -> void:
	var source := _make_level()
	# Mirror how test_level() builds the stash.
	var stash := {"level_data": source.clone(), "cursor": Vector2i(3, 3),
		"player_start": Vector2i(1, 1), "filename": "lvl"}

	# Mutating the stashed copy must not affect the source.
	stash["level_data"].cell_data[Vector2i(9, 9)] = 2
	stash["level_data"].par_folds = 99

	assert_false(source.cell_data.has(Vector2i(9, 9)),
		"stash cell edit does not leak into source")
	assert_eq(source.par_folds, 3, "stash par edit does not leak into source")
	assert_eq(stash.keys().size(), 4, "stash carries the four expected fields")


func test_level_data_grid_and_par_survive_serialization() -> void:
	var ld := _make_level()
	var restored := LevelData.new()
	restored.from_dict(ld.to_dict())

	assert_eq(restored.grid_size, Vector2i(12, 8), "grid size round-trips")
	assert_eq(restored.par_folds, 3, "par folds round-trips")
	assert_eq(restored.difficulty, 4, "difficulty round-trips")
	assert_eq(restored.cell_data.size(), 2, "cell data round-trips")
