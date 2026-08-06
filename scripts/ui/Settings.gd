## Settings Menu
##
## Audio and display settings, persisted to the user directory.
##
## The three volumes are NOT stored here. They belong to `AudioManager`, which
## loads them at startup and saves them on demand, and this screen only moves
## them — that is why setting the volume now survives a restart whether or not
## anyone ever opens this menu, which is the bug the old arrangement had: the
## values were written by this screen and read back by nothing else.
##
## Both sides share one file and each owns its own keys, read-modify-writing so
## neither clobbers the other's.

extends Control

signal settings_closed

## Shared with AudioManager, which owns the volume keys in it.
const SETTINGS_FILE = AudioManager.SETTINGS_FILE

## UI element references
@onready var master_volume_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioSection/MasterVolume/Slider
@onready var master_volume_value: Label = $CenterContainer/Panel/VBoxContainer/AudioSection/MasterVolume/Value
@onready var music_volume_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioSection/MusicVolume/Slider
@onready var music_volume_value: Label = $CenterContainer/Panel/VBoxContainer/AudioSection/MusicVolume/Value
@onready var sfx_volume_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioSection/SFXVolume/Slider
@onready var sfx_volume_value: Label = $CenterContainer/Panel/VBoxContainer/AudioSection/SFXVolume/Value
@onready var fullscreen_checkbox: CheckBox = $CenterContainer/Panel/VBoxContainer/GraphicsSection/Fullscreen/CheckBox
@onready var vsync_checkbox: CheckBox = $CenterContainer/Panel/VBoxContainer/GraphicsSection/VSync/CheckBox

## Display settings — this screen's own. The volumes live in AudioManager.
var settings: Dictionary = {
	"fullscreen": false,
	"vsync": true,
}


func _ready() -> void:
	load_settings()
	apply_settings()
	update_ui()
	hide()


## Load the display settings. AudioManager has already loaded its own.
func load_settings() -> void:
	var data := _read_file()
	for key in settings:
		if data.has(key):
			settings[key] = data[key]


## Save the display settings, leaving the volume keys to AudioManager.
func save_settings() -> void:
	AudioManager.save_volume_settings()
	var data := _read_file()
	for key in settings:
		data[key] = settings[key]
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: could not write %s" % SETTINGS_FILE)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _read_file() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return {}
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


## Apply the display settings. The volumes are already live — the sliders apply
## them as they move, which is the only way to judge a volume.
func apply_settings() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync
		else DisplayServer.VSYNC_DISABLED)


## Update UI to reflect current settings.
func update_ui() -> void:
	if master_volume_slider:
		master_volume_slider.value = AudioManager.get_master_volume()
		master_volume_value.text = _percent(AudioManager.get_master_volume())

	if music_volume_slider:
		music_volume_slider.value = AudioManager.get_music_volume()
		music_volume_value.text = _percent(AudioManager.get_music_volume())

	if sfx_volume_slider:
		sfx_volume_slider.value = AudioManager.get_sfx_volume()
		sfx_volume_value.text = _percent(AudioManager.get_sfx_volume())

	if fullscreen_checkbox:
		fullscreen_checkbox.button_pressed = settings.fullscreen

	if vsync_checkbox:
		vsync_checkbox.button_pressed = settings.vsync


func _percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))


func _on_master_volume_changed(value: float) -> void:
	AudioManager.set_master_volume(value)
	master_volume_value.text = _percent(value)
	_preview()


func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_music_volume(value)
	music_volume_value.text = _percent(value)
	# No preview tick: the music IS the preview, and a UI blip on the SFX bus
	# would be telling you about the wrong slider.


func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	sfx_volume_value.text = _percent(value)
	_preview()


## A tick on the bus being adjusted, so the number means something. Fires on
## every notch of a drag; `Sounds.UI_MOVE` carries the retrigger floor that
## keeps a fast drag from emptying the voice pool.
func _preview() -> void:
	AudioManager.play_sfx(Sounds.UI_MOVE)


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	settings.fullscreen = toggled_on


func _on_vsync_toggled(toggled_on: bool) -> void:
	settings.vsync = toggled_on


## Apply and save.
func _on_apply_button_pressed() -> void:
	AudioManager.play_sfx(Sounds.UI_CLICK)
	apply_settings()
	save_settings()


## Close without saving: put the volumes back to what is on disk, since the
## sliders have been changing them live all along.
func _on_back_button_pressed() -> void:
	AudioManager.play_sfx(Sounds.UI_CLICK)
	AudioManager.load_volume_settings()
	load_settings()
	apply_settings()
	update_ui()
	settings_closed.emit()
	hide()


## Show the settings menu.
func show_settings() -> void:
	update_ui()
	show()
	$CenterContainer/Panel/VBoxContainer/ButtonsContainer/ApplyButton.grab_focus()
