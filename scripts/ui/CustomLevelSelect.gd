## Custom Level Select Screen
##
## Displays available custom levels for playing.

extends Control

@onready var level_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/LevelGrid
@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton


func _ready() -> void:
	populate_levels()
	back_button.grab_focus()


## Populate the grid with custom level buttons
func populate_levels() -> void:
	# Clear existing children
	for child in level_grid.get_children():
		child.queue_free()

	# Get all custom levels from res://levels/custom/
	var level_files = GameManager.get_custom_levels()

	if level_files.is_empty():
		# Show "no levels" message
		var label = Label.new()
		label.text = "No custom levels found. Create one in the Level Editor!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 24)
		level_grid.add_child(label)
		return

	for level_path in level_files:
		var level_data = GameManager.level_manager.load_level(level_path)
		if level_data:
			create_level_button(level_data, level_path)


## Creates a button for a custom level
func create_level_button(level_data: LevelData, level_path: String) -> void:
	var button = Button.new()
	button.custom_minimum_size = Vector2(250, 120)

	# Build button text
	var button_text = level_data.level_name + "\n"
	button_text += "ID: " + level_data.level_id + "\n"

	if level_data.description and not level_data.description.is_empty():
		button_text += level_data.description.substr(0, 30)
		if level_data.description.length() > 30:
			button_text += "..."

	button.text = button_text

	# Style
	button.add_theme_color_override("font_color", Color.CYAN)

	# Connect button press
	button.pressed.connect(_on_level_button_pressed.bind(level_data, level_path))

	level_grid.add_child(button)


## Handle level button press
func _on_level_button_pressed(level_data: LevelData, level_path: String) -> void:
	# Load the level data into GameManager
	GameManager.current_level_id = level_data.level_id
	GameManager.current_level_data = level_data.clone()
	GameManager.fold_count = 0
	GameManager.level_start_time = Time.get_ticks_msec() / 1000.0

	# Load the game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Handle back button
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
