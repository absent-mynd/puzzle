## Main Menu UI
##
## Entry point for the game, provides navigation to different game modes
## and settings.

extends Control


func _ready() -> void:
	# Start menu music
	AudioManager.play_music("menu", true)

	# Set focus to play button for keyboard navigation
	$CenterContainer/VBoxContainer/PlayButton.grab_focus()


## Start the campaign from the first level
func _on_play_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	# Start the first unlocked campaign level
	var unlocked_levels = GameManager.progress_manager.campaign_data["levels_unlocked"]
	if unlocked_levels.size() > 0:
		var first_unlocked = unlocked_levels[0]
		GameManager.start_level(first_unlocked)
	else:
		push_warning("MainMenu: No levels unlocked!")
		# Fallback: start first level anyway
		GameManager.start_level("01_introduction")


## Open level select screen
func _on_level_select_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn")


## Open custom level select screen
func _on_custom_levels_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/CustomLevelSelect.tscn")


## Open level editor
func _on_editor_button_pressed() -> void:
  # Play button click sound
  AudioManager.play_sfx("button_click")

	get_tree().change_scene_to_file("res://scenes/ui/LevelEditor.tscn")


## Open settings menu
func _on_settings_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	var settings_scene = load("res://scenes/ui/Settings.tscn")
	if settings_scene:
		var settings = settings_scene.instantiate()
		add_child(settings)
		settings.show_settings()
		settings.settings_closed.connect(_on_settings_closed.bind(settings))


## Handle settings closed
func _on_settings_closed(settings_node: Node) -> void:
	settings_node.queue_free()
	$CenterContainer/VBoxContainer/PlayButton.grab_focus()


## Quit the game
func _on_quit_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	get_tree().quit()


## Handle keyboard navigation (ESC to quit)
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
