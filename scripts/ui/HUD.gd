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
@onready var test_mode_label: Label = $TopBar/HBoxContainer/LevelInfo/TestModeLabel
@onready var instructions_label: Label = $Instructions/InstructionsLabel

## Current level info
var level_name: String = "Test Level"
var fold_count: int = 0
var par_folds: int = -1  # -1 means no par

## Undo availability
var can_undo: bool = false

## Transient message ("toast") shown for e.g. why a fold failed.
var _toast_label: Label = null
var _toast_timer: Timer = null


func _ready() -> void:
	update_display()
	_setup_toast()

	# Build the controls footer from the live InputMap so it can't go stale.
	if instructions_label:
		instructions_label.text = InputHelp.gameplay_summary()

	# Prevent HUD buttons from stealing focus
	# Allow focus only when explicitly clicked
	if undo_button:
		undo_button.focus_mode = Control.FOCUS_CLICK
	if restart_button:
		restart_button.focus_mode = Control.FOCUS_CLICK
	if pause_button:
		pause_button.focus_mode = Control.FOCUS_CLICK


## Build the transient toast label (centered under the top bar) + its auto-hide timer.
func _setup_toast() -> void:
	_toast_label = Label.new()
	_toast_label.name = "Toast"
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.theme_type_variation = &"StatusLabel"
	_toast_label.anchor_left = 0.0
	_toast_label.anchor_right = 1.0
	_toast_label.anchor_top = 0.0
	_toast_label.offset_top = 96.0
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.visible = false
	add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): if _toast_label: _toast_label.visible = false)
	add_child(_toast_timer)


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
			# Color code by performance, using the single shared star-tier rule so the
			# HUD, LevelComplete, and level-select screens all agree.
			var tier := UIPalette.star_tier(fold_count, par_folds)
			fold_counter_label.add_theme_color_override("font_color", UIPalette.color_for_tier(tier))
		else:
			fold_counter_label.text = "Folds: %d" % fold_count
			fold_counter_label.remove_theme_color_override("font_color")


## Handle undo button press
func _on_undo_button_pressed() -> void:
	# Play button click sound (or undo sound when undo is implemented)
	AudioManager.play_sfx("button_click")

	undo_requested.emit()


## Handle restart button press
func _on_restart_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	restart_requested.emit()


## Handle pause button press
func _on_pause_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	pause_requested.emit()


## Handle keyboard shortcuts
## Uses _unhandled_input so game input is processed first
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC
		pause_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_undo"):  # U for undo (mapped action)
		if can_undo:
			undo_requested.emit()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):  # R for restart (mapped action)
		get_viewport().set_input_as_handled()
		restart_requested.emit()


## Show or hide the "TEST MODE" indicator (set when the level is launched from the editor)
func set_test_mode(enabled: bool) -> void:
	if test_mode_label:
		test_mode_label.visible = enabled


## Show a transient message (e.g. why a fold was rejected). Auto-hides after `duration`.
func show_toast(text: String, color: Color = Color.WHITE, duration: float = 2.5) -> void:
	if not _toast_label:
		return
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast_label.visible = true
	if _toast_timer:
		_toast_timer.start(duration)


## Show or hide the HUD
func set_visible_hud(is_visible: bool) -> void:
	visible = is_visible
