## AudioManager - Singleton for managing game audio
##
## Handles music playback, sound effects, and volume controls.
## Uses separate audio buses for music, SFX, and master volume.
##
## Usage:
##   AudioManager.play_sfx("fold")
##   AudioManager.play_music("gameplay")
##   AudioManager.set_music_volume(0.7)
extends Node

## Emitted when music starts playing
signal music_started(track_name: String)

## Emitted when music stops
signal music_stopped()

## Emitted when a sound effect plays
signal sfx_played(sfx_name: String)

## Audio bus names
const BUS_MASTER = "Master"
const BUS_MUSIC = "Music"
const BUS_SFX = "SFX"

## Fade duration in seconds
const FADE_DURATION = 1.0

## Audio player for background music
var music_player: AudioStreamPlayer

## Audio players pool for sound effects (to allow overlapping sounds)
var sfx_players: Array[AudioStreamPlayer] = []
const SFX_PLAYER_POOL_SIZE = 8

## Current music track name
var current_music_track: String = ""

## Music tracks dictionary (name -> AudioStream)
var music_tracks: Dictionary = {}

## Sound effects dictionary (name -> AudioStream)
var sound_effects: Dictionary = {}

## Volume settings (0.0 to 1.0)
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8

## Pitch variation range for SFX
var pitch_variation: float = 0.1

## Is music currently fading
var is_fading: bool = false


func _ready() -> void:
	# Create music player
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = BUS_MUSIC
	add_child(music_player)

	# Create SFX player pool
	for i in range(SFX_PLAYER_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.name = "SFXPlayer_%d" % i
		player.bus = BUS_SFX
		add_child(player)
		sfx_players.append(player)

	# Initialize audio buses if they don't exist
	_setup_audio_buses()

	# Apply initial volume settings
	_apply_volume_settings()

	# Load audio resources
	_load_audio_resources()


## Setup audio buses if they don't exist
func _setup_audio_buses() -> void:
	# Get audio bus layout
	var master_idx = AudioServer.get_bus_index(BUS_MASTER)
	var music_idx = AudioServer.get_bus_index(BUS_MUSIC)
	var sfx_idx = AudioServer.get_bus_index(BUS_SFX)

	# Create Music bus if it doesn't exist
	if music_idx == -1:
		AudioServer.add_bus(1)  # Add after Master (index 0)
		AudioServer.set_bus_name(1, BUS_MUSIC)
		AudioServer.set_bus_send(1, BUS_MASTER)

	# Create SFX bus if it doesn't exist
	if sfx_idx == -1:
		var bus_count = AudioServer.bus_count
		AudioServer.add_bus(bus_count)
		AudioServer.set_bus_name(bus_count, BUS_SFX)
		AudioServer.set_bus_send(bus_count, BUS_MASTER)


## Load all audio resources from the assets directory
func _load_audio_resources() -> void:
	# Load music tracks
	_load_audio_files("res://assets/audio/music/", music_tracks)

	# Load sound effects
	_load_audio_files("res://assets/audio/sfx/", sound_effects)


## Helper function to load audio files from a directory
func _load_audio_files(path: String, dictionary: Dictionary) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		push_warning("AudioManager: Could not open directory: %s" % path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".ogg") or file_name.ends_with(".wav") or file_name.ends_with(".mp3")):
			var full_path = path + file_name
			var stream = load(full_path)
			if stream:
				# Use filename without extension as key
				var key = file_name.get_basename()
				dictionary[key] = stream
			else:
				push_warning("AudioManager: Failed to load audio file: %s" % full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


## Play background music with optional fade in
func play_music(track_name: String, fade_in: bool = true) -> void:
	# Check if track exists
	if not music_tracks.has(track_name):
		push_warning("AudioManager: Music track not found: %s" % track_name)
		return

	# If same track is already playing, do nothing
	if current_music_track == track_name and music_player.playing:
		return

	# Stop current music
	if music_player.playing:
		stop_music(fade_in)  # Fade out if fade_in is true
		await get_tree().create_timer(FADE_DURATION if fade_in else 0.0).timeout

	# Set new track
	music_player.stream = music_tracks[track_name]
	current_music_track = track_name

	# Play with fade in
	if fade_in:
		music_player.volume_db = linear_to_db(0.0001) # Use epsilon instead of 0.0 to avoid -INF
		music_player.play()
		_fade_music_to(music_volume, FADE_DURATION)
	else:
		music_player.volume_db = linear_to_db(music_volume)
		music_player.play()

	music_started.emit(track_name)


## Stop background music with optional fade out
func stop_music(fade_out: bool = true) -> void:
	if not music_player.playing:
		return

	if fade_out:
		await _fade_music_to(0.0, FADE_DURATION)

	music_player.stop()
	current_music_track = ""
	music_stopped.emit()


## Fade music volume to target over duration
func _fade_music_to(target_volume: float, duration: float) -> void:
	if is_fading:
		return

	is_fading = true
	var start_volume = db_to_linear(music_player.volume_db)
	var elapsed = 0.0

	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var t = clampf(elapsed / duration, 0.0, 1.0)
		var current_volume = lerpf(start_volume, target_volume, t)
		music_player.volume_db = linear_to_db(max(current_volume, 0.0001))  # Avoid log(0)

	music_player.volume_db = linear_to_db(max(target_volume, 0.0001))
	is_fading = false


## Play a sound effect with optional pitch variation
func play_sfx(sfx_name: String, pitch_var: bool = true) -> void:
	# Check if sound effect exists
	if not sound_effects.has(sfx_name):
		push_warning("AudioManager: Sound effect not found: %s" % sfx_name)
		return

	# Find available player
	var player = _get_available_sfx_player()
	if player == null:
		push_warning("AudioManager: All SFX players are busy")
		return

	# Set stream
	player.stream = sound_effects[sfx_name]

	# Apply pitch variation
	if pitch_var and pitch_variation > 0.0:
		var variation = randf_range(-pitch_variation, pitch_variation)
		player.pitch_scale = 1.0 + variation
	else:
		player.pitch_scale = 1.0

	# Play
	player.play()
	sfx_played.emit(sfx_name)


## Get an available SFX player from the pool
func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	return null


## Set master volume (0.0 to 1.0)
func set_master_volume(volume: float) -> void:
	master_volume = clampf(volume, 0.0, 1.0)
	_apply_volume_settings()


## Set music volume (0.0 to 1.0)
func set_music_volume(volume: float) -> void:
	music_volume = clampf(volume, 0.0, 1.0)
	_apply_volume_settings()


## Set SFX volume (0.0 to 1.0)
func set_sfx_volume(volume: float) -> void:
	sfx_volume = clampf(volume, 0.0, 1.0)
	_apply_volume_settings()


## Apply volume settings to audio buses
func _apply_volume_settings() -> void:
	var master_idx = AudioServer.get_bus_index(BUS_MASTER)
	var music_idx = AudioServer.get_bus_index(BUS_MUSIC)
	var sfx_idx = AudioServer.get_bus_index(BUS_SFX)

	if master_idx != -1:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(max(master_volume, 0.0001)))

	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(max(music_volume, 0.0001)))

	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(max(sfx_volume, 0.0001)))


## Get master volume (0.0 to 1.0)
func get_master_volume() -> float:
	return master_volume


## Get music volume (0.0 to 1.0)
func get_music_volume() -> float:
	return music_volume


## Get SFX volume (0.0 to 1.0)
func get_sfx_volume() -> float:
	return sfx_volume


## Check if a music track is loaded
func has_music_track(track_name: String) -> bool:
	return music_tracks.has(track_name)


## Check if a sound effect is loaded
func has_sfx(sfx_name: String) -> bool:
	return sound_effects.has(sfx_name)


## Get list of available music tracks
func get_music_tracks() -> Array[String]:
	var tracks: Array[String] = []
	for key in music_tracks.keys():
		tracks.append(key)
	return tracks


## Get list of available sound effects
func get_sfx_list() -> Array[String]:
	var sfx_list: Array[String] = []
	for key in sound_effects.keys():
		sfx_list.append(key)
	return sfx_list


## Reload all audio resources
func reload_audio_resources() -> void:
	music_tracks.clear()
	sound_effects.clear()
	_load_audio_resources()
