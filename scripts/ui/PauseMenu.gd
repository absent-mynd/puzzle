## Pause Menu
##
## Displayed when the game is paused, allows resuming, restarting,
## accessing settings, or returning to main menu.

extends Control

signal resume_requested
signal restart_requested
signal main_menu_requested


func _ready() -> void:
	# Hide by default and don't pause yet
	hide()

	# Disable mouse filter on background so it doesn't block clicks when hidden
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Show the pause menu
func show_pause_menu() -> void:
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP  # Block input to game when visible
	get_tree().paused = true
	$CenterContainer/Panel/VBoxContainer/ResumeButton.grab_focus()


## Hide the pause menu
func hide_pause_menu() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Allow input to pass through
	get_tree().paused = false


## Resume the game
func _on_resume_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	hide_pause_menu()
	resume_requested.emit()


## Restart the current level
func _on_restart_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	hide_pause_menu()
	restart_requested.emit()


## Open settings (overlay on pause menu)
func _on_settings_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	# TODO: Show settings overlay
	print("Settings not yet implemented")
	# var settings = load("res://scenes/ui/Settings.tscn").instantiate()
	# add_child(settings)


## Return to main menu
func _on_main_menu_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	hide_pause_menu()
	main_menu_requested.emit()
