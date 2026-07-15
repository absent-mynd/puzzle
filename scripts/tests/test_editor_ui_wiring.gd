## Smoke tests for the editor-test UI wiring (Part B).
##
## The Back-to-Editor / TEST MODE controls resolve their nodes via @onready paths, so these
## instantiate the real scenes and confirm the nodes exist and the toggle methods work.

extends GutTest


func test_pause_menu_editor_button_toggles() -> void:
	var scene: PackedScene = load("res://scenes/ui/PauseMenu.tscn")
	var menu = scene.instantiate()
	add_child_autofree(menu)
	await wait_frames(1)

	assert_true(menu.has_signal("editor_requested"), "PauseMenu exposes editor_requested")
	assert_not_null(menu.editor_button, "EditorButton node resolved")
	assert_false(menu.editor_button.visible, "hidden by default")

	menu.set_editor_mode(true)
	assert_true(menu.editor_button.visible, "shown in editor test mode")


func test_level_complete_editor_mode_hides_campaign_buttons() -> void:
	var scene: PackedScene = load("res://scenes/ui/LevelComplete.tscn")
	var lc = scene.instantiate()
	add_child_autofree(lc)
	await wait_frames(1)

	assert_true(lc.has_signal("editor_requested"), "LevelComplete exposes editor_requested")
	assert_not_null(lc.editor_button, "EditorButton node resolved")

	lc.set_editor_mode(true)
	assert_true(lc.editor_button.visible, "editor button shown in test mode")
	assert_false(lc.next_button.visible, "Next hidden in test mode")
	assert_false(lc.level_select_button.visible, "Level Select hidden in test mode")

	lc.set_editor_mode(false)
	assert_false(lc.editor_button.visible, "editor button hidden in normal mode")
	assert_true(lc.next_button.visible, "Next shown in normal mode")


func test_hud_test_mode_label_toggles() -> void:
	var scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	var hud = scene.instantiate()
	add_child_autofree(hud)
	await wait_frames(1)

	assert_not_null(hud.test_mode_label, "TestModeLabel node resolved")
	assert_false(hud.test_mode_label.visible, "hidden by default")

	hud.set_test_mode(true)
	assert_true(hud.test_mode_label.visible, "shown when testing from editor")
