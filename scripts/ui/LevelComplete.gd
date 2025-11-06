## Level Complete Screen
##
## Displayed when the player completes a level, showing stats and options
## to continue, retry, or return to menu.

extends Control

signal next_level_requested
signal retry_requested
signal level_select_requested
signal main_menu_requested

## UI element references
@onready var title_label: Label = $CenterContainer/Panel/VBoxContainer/Title
@onready var star1: Label = $CenterContainer/Panel/VBoxContainer/StarsContainer/Star1
@onready var star2: Label = $CenterContainer/Panel/VBoxContainer/StarsContainer/Star2
@onready var star3: Label = $CenterContainer/Panel/VBoxContainer/StarsContainer/Star3
@onready var folds_used_label: Label = $CenterContainer/Panel/VBoxContainer/Stats/FoldsUsed
@onready var par_folds_label: Label = $CenterContainer/Panel/VBoxContainer/Stats/ParFolds
@onready var performance_label: Label = $CenterContainer/Panel/VBoxContainer/Stats/Performance
@onready var next_button: Button = $CenterContainer/Panel/VBoxContainer/NextButton

## Level stats
var folds_used: int = 0
var par_folds: int = 0
var stars_earned: int = 0


func _ready() -> void:
	hide()


## Show the level complete screen with stats
func show_complete(p_folds_used: int, p_par_folds: int = -1) -> void:
	folds_used = p_folds_used
	par_folds = p_par_folds

	# Calculate stars (3 = par or better, 2 = under 1.5x par, 1 = completed)
	if par_folds > 0:
		if folds_used <= par_folds:
			stars_earned = 3
		elif folds_used <= par_folds * 1.5:
			stars_earned = 2
		else:
			stars_earned = 1
	else:
		stars_earned = 1  # No par, just completion

	update_display()
	show()

	# Set focus to next button
	next_button.grab_focus()


## Update all UI elements with current stats
func update_display() -> void:
	# Update stats labels
	folds_used_label.text = "Folds Used: %d" % folds_used

	if par_folds > 0:
		par_folds_label.text = "Par: %d" % par_folds
		par_folds_label.show()
	else:
		par_folds_label.hide()

	# Update performance text and color
	match stars_earned:
		3:
			performance_label.text = "Perfect!"
			performance_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))  # Green
		2:
			performance_label.text = "Good!"
			performance_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))  # Yellow
		1:
			performance_label.text = "Completed"
			performance_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))  # Gray

	# Update star display
	update_stars()


## Update star visuals based on stars earned
func update_stars() -> void:
	var gold_color = Color(1.0, 0.84, 0.0)  # Gold
	var gray_color = Color(0.3, 0.3, 0.3)  # Gray (unearned)

	star1.add_theme_color_override("font_color", gold_color if stars_earned >= 1 else gray_color)
	star2.add_theme_color_override("font_color", gold_color if stars_earned >= 2 else gray_color)
	star3.add_theme_color_override("font_color", gold_color if stars_earned >= 3 else gray_color)


## Handle next level button
func _on_next_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	next_level_requested.emit()
	hide()


## Handle retry button
func _on_retry_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	retry_requested.emit()
	hide()


## Handle level select button
func _on_level_select_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	level_select_requested.emit()
	hide()


## Handle main menu button
func _on_main_menu_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	main_menu_requested.emit()
	hide()


## Hide the level complete screen
func hide_complete() -> void:
	hide()
