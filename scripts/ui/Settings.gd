## Settings Menu
##
## Allows players to configure audio, graphics, and other game settings.
## Settings are saved to user directory and persist across sessions.

extends Control

signal settings_closed

## Settings file path
const SETTINGS_FILE = "user://settings.json"

## UI element references
@onready var master_volume_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioSection/MasterVolume/Slider
@onready var master_volume_value: Label = $CenterContainer/Panel/VBoxContainer/AudioSection/MasterVolume/Value
@onready var music_volume_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioSection/MusicVolume/Slider
@onready var music_volume_value: Label = $CenterContainer/Panel/VBoxContainer/AudioSection/MusicVolume/Value
@onready var sfx_volume_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioSection/SFXVolume/Slider
@onready var sfx_volume_value: Label = $CenterContainer/Panel/VBoxContainer/AudioSection/SFXVolume/Value
@onready var fullscreen_checkbox: CheckBox = $CenterContainer/Panel/VBoxContainer/GraphicsSection/Fullscreen/CheckBox
@onready var vsync_checkbox: CheckBox = $CenterContainer/Panel/VBoxContainer/GraphicsSection/VSync/CheckBox

## Current settings
var settings: Dictionary = {
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"fullscreen": false,
	"vsync": true
}


func _ready() -> void:
	load_settings()
	apply_settings()
	update_ui()
	hide()


## Load settings from file
func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_FILE):
		var file = FileAccess.open(SETTINGS_FILE, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			var parsed = JSON.parse_string(json_string)
			if parsed is Dictionary:
				settings = parsed
			file.close()


## Save settings to file
func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()


## Apply current settings to the game
func apply_settings() -> void:
	# Apply audio settings
	var master_bus_index = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus_index, linear_to_db(settings.master_volume))

	# TODO: Apply music and SFX volume when audio buses are configured
	# var music_bus_index = AudioServer.get_bus_index("Music")
	# AudioServer.set_bus_volume_db(music_bus_index, linear_to_db(settings.music_volume))
	# var sfx_bus_index = AudioServer.get_bus_index("SFX")
	# AudioServer.set_bus_volume_db(sfx_bus_index, linear_to_db(settings.sfx_volume))

	# Apply graphics settings
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	if settings.vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


## Update UI to reflect current settings
func update_ui() -> void:
	if master_volume_slider:
		master_volume_slider.value = settings.master_volume
		master_volume_value.text = "%d%%" % int(settings.master_volume * 100)

	if music_volume_slider:
		music_volume_slider.value = settings.music_volume
		music_volume_value.text = "%d%%" % int(settings.music_volume * 100)

	if sfx_volume_slider:
		sfx_volume_slider.value = settings.sfx_volume
		sfx_volume_value.text = "%d%%" % int(settings.sfx_volume * 100)

	if fullscreen_checkbox:
		fullscreen_checkbox.button_pressed = settings.fullscreen

	if vsync_checkbox:
		vsync_checkbox.button_pressed = settings.vsync


## Handle master volume change
func _on_master_volume_changed(value: float) -> void:
	settings.master_volume = value
	master_volume_value.text = "%d%%" % int(value * 100)
	# Apply immediately for preview
	var master_bus_index = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus_index, linear_to_db(value))


## Handle music volume change
func _on_music_volume_changed(value: float) -> void:
	settings.music_volume = value
	music_volume_value.text = "%d%%" % int(value * 100)
	# TODO: Apply to music bus when available


## Handle SFX volume change
func _on_sfx_volume_changed(value: float) -> void:
	settings.sfx_volume = value
	sfx_volume_value.text = "%d%%" % int(value * 100)
	# TODO: Apply to SFX bus when available


## Handle fullscreen toggle
func _on_fullscreen_toggled(toggled_on: bool) -> void:
	settings.fullscreen = toggled_on


## Handle vsync toggle
func _on_vsync_toggled(toggled_on: bool) -> void:
	settings.vsync = toggled_on


## Apply and save settings
func _on_apply_button_pressed() -> void:
	apply_settings()
	save_settings()
	print("Settings applied and saved")


## Close settings without saving
func _on_back_button_pressed() -> void:
	# Reload settings to discard changes
	load_settings()
	apply_settings()
	settings_closed.emit()
	hide()


## Show the settings menu
func show_settings() -> void:
	show()
	$CenterContainer/Panel/VBoxContainer/ButtonsContainer/ApplyButton.grab_focus()
