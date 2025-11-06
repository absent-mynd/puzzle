## Main Menu UI
##
## Entry point for the game, provides navigation to different game modes
## and settings.

extends Control


func _ready() -> void:
	# Set focus to play button for keyboard navigation
	$CenterContainer/VBoxContainer/PlayButton.grab_focus()


## Start the campaign from the first level
func _on_play_button_pressed() -> void:
	# TODO: Load first campaign level when level system is implemented
	# For now, just start the main game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Open level select screen
func _on_level_select_button_pressed() -> void:
	# TODO: Implement level select screen
	print("Level Select not yet implemented")
	# get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn")


## Open level editor
func _on_editor_button_pressed() -> void:
	# TODO: Implement level editor
	print("Level Editor not yet implemented")
	# get_tree().change_scene_to_file("res://scenes/ui/LevelEditor.tscn")


## Open settings menu
func _on_settings_button_pressed() -> void:
	# TODO: Implement settings as overlay or separate scene
	print("Settings not yet implemented")
	# var settings = load("res://scenes/ui/Settings.tscn").instantiate()
	# add_child(settings)


## Quit the game
func _on_quit_button_pressed() -> void:
	get_tree().quit()


## Handle keyboard navigation (ESC to quit)
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
