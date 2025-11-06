## HUD (Heads-Up Display)
##
## In-game UI showing level info, fold counter, and control buttons.

extends CanvasLayer

signal pause_requested
signal restart_requested
signal undo_requested

## UI element references
@onready var level_name_label: Label = $TopBar/HBoxContainer/LevelInfo/LevelName
@onready var fold_counter_label: Label = $TopBar/HBoxContainer/LevelInfo/FoldCounter
@onready var undo_button: Button = $TopBar/HBoxContainer/ControlButtons/UndoButton
@onready var restart_button: Button = $TopBar/HBoxContainer/ControlButtons/RestartButton
@onready var pause_button: Button = $TopBar/HBoxContainer/ControlButtons/PauseButton

## Current level info
var level_name: String = "Test Level"
var fold_count: int = 0
var par_folds: int = -1  # -1 means no par

## Undo availability
var can_undo: bool = false


func _ready() -> void:
	update_display()


## Set the level information
func set_level_info(p_level_name: String, p_par_folds: int = -1) -> void:
	level_name = p_level_name
	par_folds = p_par_folds
	update_display()


## Update the fold counter
func set_fold_count(count: int) -> void:
	fold_count = count
	update_display()


## Update undo button state
func set_can_undo(enabled: bool) -> void:
	can_undo = enabled
	if undo_button:
		undo_button.disabled = not enabled


## Refresh all UI elements
func update_display() -> void:
	if level_name_label:
		level_name_label.text = level_name

	if fold_counter_label:
		if par_folds > 0:
			fold_counter_label.text = "Folds: %d / %d" % [fold_count, par_folds]
			# Color code based on performance
			if fold_count <= par_folds:
				fold_counter_label.add_theme_color_override("font_color", Color.GREEN)
			elif fold_count <= par_folds * 1.5:
				fold_counter_label.add_theme_color_override("font_color", Color.YELLOW)
			else:
				fold_counter_label.add_theme_color_override("font_color", Color.ORANGE)
		else:
			fold_counter_label.text = "Folds: %d" % fold_count
			fold_counter_label.remove_theme_color_override("font_color")


## Handle undo button press
func _on_undo_button_pressed() -> void:
	undo_requested.emit()


## Handle restart button press
func _on_restart_button_pressed() -> void:
	restart_requested.emit()


## Handle pause button press
func _on_pause_button_pressed() -> void:
	pause_requested.emit()


## Handle keyboard shortcuts
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC
		pause_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_text_backspace"):  # U for undo
		if can_undo:
			undo_requested.emit()
			get_viewport().set_input_as_handled()
	elif Input.is_key_pressed(KEY_R):  # R for restart
		restart_requested.emit()
		get_viewport().set_input_as_handled()


## Show or hide the HUD
func set_visible_hud(visible: bool) -> void:
	visible = visible
