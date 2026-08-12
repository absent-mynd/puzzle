## Pause Menu
##
## In-world pause overlay: resume, respawn at the last checkpoint, settings, or quit.
##
## There is no title screen or main menu to return to — the world is continuous, so
## "restart" means respawn, not reload. `respawn_requested` is what the world listens
## for; how far back a respawn goes is the world's business, not the menu's.

extends Control

signal resume_requested
signal respawn_requested


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
	AudioManager.play_sfx(Sounds.UI_CLICK)

	hide_pause_menu()
	resume_requested.emit()


## Respawn at the last checkpoint
func _on_restart_button_pressed() -> void:
	AudioManager.play_sfx(Sounds.UI_CLICK)

	hide_pause_menu()
	respawn_requested.emit()


## Open settings (overlay on the pause menu)
func _on_settings_button_pressed() -> void:
	AudioManager.play_sfx(Sounds.UI_CLICK)

	var scene := load("res://scenes/ui/Settings.tscn")
	if scene == null:
		return
	var settings = scene.instantiate()
	add_child(settings)
	settings.show_settings()
	settings.settings_closed.connect(func() -> void:
		settings.queue_free()
		$CenterContainer/Panel/VBoxContainer/ResumeButton.grab_focus())


## Quit the game
func _on_main_menu_button_pressed() -> void:
	AudioManager.play_sfx(Sounds.UI_CLICK)

	get_tree().quit()
