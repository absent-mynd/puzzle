## Pause Menu
##
## Displayed when the game is paused, allows resuming, restarting,
## accessing settings, or returning to main menu.

extends Control

signal resume_requested
signal restart_requested
signal main_menu_requested


func _ready() -> void:
	# Pause the game when this menu is shown
	get_tree().paused = true

	# Set focus to resume button
	$CenterContainer/Panel/VBoxContainer/ResumeButton.grab_focus()

	# Hide by default
	hide()


## Show the pause menu
func show_pause_menu() -> void:
	show()
	get_tree().paused = true
	$CenterContainer/Panel/VBoxContainer/ResumeButton.grab_focus()


## Hide the pause menu
func hide_pause_menu() -> void:
	hide()
	get_tree().paused = false


## Resume the game
func _on_resume_button_pressed() -> void:
	hide_pause_menu()
	resume_requested.emit()


## Restart the current level
func _on_restart_button_pressed() -> void:
	hide_pause_menu()
	restart_requested.emit()


## Open settings (overlay on pause menu)
func _on_settings_button_pressed() -> void:
	# TODO: Show settings overlay
	print("Settings not yet implemented")
	# var settings = load("res://scenes/ui/Settings.tscn").instantiate()
	# add_child(settings)


## Return to main menu
func _on_main_menu_button_pressed() -> void:
	hide_pause_menu()
	main_menu_requested.emit()


## Handle ESC key to toggle pause
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			_on_resume_button_pressed()
		else:
			show_pause_menu()
		get_viewport().set_input_as_handled()
