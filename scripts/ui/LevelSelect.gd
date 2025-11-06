## Level Select Screen
##
## Displays available campaign levels with completion status and stars.

extends Control

@onready var level_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/LevelGrid
@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton


func _ready() -> void:
	# Start menu music (if not already playing)
	if AudioManager.current_music_track != "menu":
		AudioManager.play_music("menu", true)

	populate_levels()
	back_button.grab_focus()


## Populate the grid with level buttons
func populate_levels() -> void:
	# Clear existing children
	for child in level_grid.get_children():
		child.queue_free()

	# Get all campaign levels
	var level_files = GameManager.get_campaign_levels()

	for level_path in level_files:
		var level_data = GameManager.level_manager.load_level(level_path)
		if level_data:
			create_level_button(level_data)


## Creates a button for a level
func create_level_button(level_data: LevelData) -> void:
	var button = Button.new()
	button.custom_minimum_size = Vector2(250, 120)

	# Check level status
	var is_unlocked = GameManager.is_level_unlocked(level_data.level_id)
	var is_completed = GameManager.is_level_completed(level_data.level_id)
	var stars = GameManager.get_stars_for_level(level_data.level_id)

	# Build button text
	var button_text = level_data.level_name + "\n"
	if not is_unlocked:
		button_text += "🔒 LOCKED"
		button.disabled = true
	elif is_completed:
		button_text += create_star_display(stars) + "\n"
		button_text += "Par: %d" % level_data.par_folds
	else:
		button_text += "✓ UNLOCKED\n"
		button_text += "Par: %d" % level_data.par_folds

	button.text = button_text

	# Style based on status
	if is_completed:
		button.add_theme_color_override("font_color", Color.GOLD)
	elif is_unlocked:
		button.add_theme_color_override("font_color", Color.GREEN)
	else:
		button.add_theme_color_override("font_color", Color.DARK_GRAY)

	# Connect button press
	if is_unlocked:
		button.pressed.connect(_on_level_button_pressed.bind(level_data.level_id))

	level_grid.add_child(button)


## Creates a star display string
func create_star_display(stars: int) -> String:
	var display = ""
	for i in range(3):
		if i < stars:
			display += "★"
		else:
			display += "☆"
	return display


## Handle level button press
func _on_level_button_pressed(level_id: String) -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	GameManager.start_level(level_id)


## Handle back button
func _on_back_button_pressed() -> void:
	# Play button click sound
	AudioManager.play_sfx("button_click")

	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
