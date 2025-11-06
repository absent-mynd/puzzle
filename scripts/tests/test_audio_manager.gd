## Tests for AudioManager
##
## Tests audio system functionality including music playback,
## sound effects, volume controls, and audio bus management.

extends GutTest

## AudioManager singleton reference
var audio_manager: Node


func before_all():
	# AudioManager is an autoload singleton
	audio_manager = AudioManager


func after_each():
	# Stop any playing music and reset state
	if audio_manager:
		audio_manager.stop_music(false)
		audio_manager.set_master_volume(1.0)
		audio_manager.set_music_volume(0.7)
		audio_manager.set_sfx_volume(0.8)


## Test 1: AudioManager singleton exists
func test_audio_manager_exists():
	assert_not_null(audio_manager, "AudioManager singleton should exist")


## Test 2: Audio buses are set up correctly
func test_audio_buses_setup():
	var master_idx = AudioServer.get_bus_index("Master")
	var music_idx = AudioServer.get_bus_index("Music")
	var sfx_idx = AudioServer.get_bus_index("SFX")

	assert_ne(master_idx, -1, "Master bus should exist")
	assert_ne(music_idx, -1, "Music bus should exist")
	assert_ne(sfx_idx, -1, "SFX bus should exist")


## Test 3: Music player is created
func test_music_player_created():
	assert_not_null(audio_manager.music_player, "Music player should be created")
	assert_eq(audio_manager.music_player.bus, "Music", "Music player should use Music bus")


## Test 4: SFX player pool is created
func test_sfx_player_pool_created():
	assert_eq(audio_manager.sfx_players.size(), 8, "Should have 8 SFX players in pool")

	for player in audio_manager.sfx_players:
		assert_not_null(player, "SFX player should not be null")
		assert_eq(player.bus, "SFX", "SFX player should use SFX bus")


## Test 5: Volume getters return correct values
func test_volume_getters():
	assert_almost_eq(audio_manager.get_master_volume(), 1.0, 0.01, "Master volume should be 1.0")
	assert_almost_eq(audio_manager.get_music_volume(), 0.7, 0.01, "Music volume should be 0.7")
	assert_almost_eq(audio_manager.get_sfx_volume(), 0.8, 0.01, "SFX volume should be 0.8")


## Test 6: Set master volume
func test_set_master_volume():
	audio_manager.set_master_volume(0.5)
	assert_almost_eq(audio_manager.get_master_volume(), 0.5, 0.01, "Master volume should be 0.5")

	# Test clamping to 0.0-1.0 range
	audio_manager.set_master_volume(1.5)
	assert_almost_eq(audio_manager.get_master_volume(), 1.0, 0.01, "Master volume should clamp to 1.0")

	audio_manager.set_master_volume(-0.5)
	assert_almost_eq(audio_manager.get_master_volume(), 0.0, 0.01, "Master volume should clamp to 0.0")


## Test 7: Set music volume
func test_set_music_volume():
	audio_manager.set_music_volume(0.3)
	assert_almost_eq(audio_manager.get_music_volume(), 0.3, 0.01, "Music volume should be 0.3")

	# Test clamping
	audio_manager.set_music_volume(2.0)
	assert_almost_eq(audio_manager.get_music_volume(), 1.0, 0.01, "Music volume should clamp to 1.0")


## Test 8: Set SFX volume
func test_set_sfx_volume():
	audio_manager.set_sfx_volume(0.6)
	assert_almost_eq(audio_manager.get_sfx_volume(), 0.6, 0.01, "SFX volume should be 0.6")

	# Test clamping
	audio_manager.set_sfx_volume(-1.0)
	assert_almost_eq(audio_manager.get_sfx_volume(), 0.0, 0.01, "SFX volume should clamp to 0.0")


## Test 9: Play music with non-existent track (should warn, not crash)
func test_play_nonexistent_music():
	# This should generate a warning but not crash
	audio_manager.play_music("nonexistent_track", false)
	assert_false(audio_manager.music_player.playing, "Music should not be playing")


## Test 10: Play SFX with non-existent sound (should warn, not crash)
func test_play_nonexistent_sfx():
	# This should generate a warning but not crash
	audio_manager.play_sfx("nonexistent_sound")
	# Verify it completes without crashing
	assert_true(true, "Playing non-existent SFX should not crash")


## Test 11: Check music track exists
func test_has_music_track():
	# Since we don't have actual audio files, this should return false
	assert_false(audio_manager.has_music_track("gameplay"), "Gameplay music track should not exist (no audio files)")
	assert_false(audio_manager.has_music_track("menu"), "Menu music track should not exist (no audio files)")


## Test 12: Check SFX exists
func test_has_sfx():
	# Since we don't have actual audio files, this should return false
	assert_false(audio_manager.has_sfx("fold"), "Fold SFX should not exist (no audio files)")
	assert_false(audio_manager.has_sfx("footstep"), "Footstep SFX should not exist (no audio files)")


## Test 13: Get music tracks list
func test_get_music_tracks():
	var tracks = audio_manager.get_music_tracks()
	assert_not_null(tracks, "Music tracks list should not be null")
	# Should be empty since no audio files are loaded
	assert_eq(tracks.size(), 0, "Music tracks list should be empty (no audio files)")


## Test 14: Get SFX list
func test_get_sfx_list():
	var sfx_list = audio_manager.get_sfx_list()
	assert_not_null(sfx_list, "SFX list should not be null")
	# Should be empty since no audio files are loaded
	assert_eq(sfx_list.size(), 0, "SFX list should be empty (no audio files)")


## Test 15: Stop music when not playing (should not crash)
func test_stop_music_when_not_playing():
	audio_manager.stop_music(false)
	assert_false(audio_manager.music_player.playing, "Music should not be playing")


## Test 16: Volume changes apply to audio buses
func test_volume_changes_apply_to_buses():
	# Set volumes
	audio_manager.set_master_volume(0.5)
	audio_manager.set_music_volume(0.3)
	audio_manager.set_sfx_volume(0.7)

	# Get bus volumes
	var master_idx = AudioServer.get_bus_index("Master")
	var music_idx = AudioServer.get_bus_index("Music")
	var sfx_idx = AudioServer.get_bus_index("SFX")

	var master_vol = db_to_linear(AudioServer.get_bus_volume_db(master_idx))
	var music_vol = db_to_linear(AudioServer.get_bus_volume_db(music_idx))
	var sfx_vol = db_to_linear(AudioServer.get_bus_volume_db(sfx_idx))

	# Check if volumes are applied (with some tolerance)
	assert_almost_eq(master_vol, 0.5, 0.1, "Master bus volume should be 0.5")
	assert_almost_eq(music_vol, 0.3, 0.1, "Music bus volume should be 0.3")
	assert_almost_eq(sfx_vol, 0.7, 0.1, "SFX bus volume should be 0.7")


## Test 17: Pitch variation setting
func test_pitch_variation():
	# Default pitch variation should be 0.1
	assert_almost_eq(audio_manager.pitch_variation, 0.1, 0.01, "Default pitch variation should be 0.1")

	# Test changing it
	audio_manager.pitch_variation = 0.2
	assert_almost_eq(audio_manager.pitch_variation, 0.2, 0.01, "Pitch variation should be 0.2")


## Test 18: Fade duration setting
func test_fade_duration():
	# Default fade duration should be 1.0 second
	assert_almost_eq(audio_manager.FADE_DURATION, 1.0, 0.01, "Fade duration should be 1.0 second")


## Test 19: Current music track tracking
func test_current_music_track_tracking():
	# Initially should be empty
	assert_eq(audio_manager.current_music_track, "", "Current music track should be empty initially")


## Test 20: Is fading flag
func test_is_fading_flag():
	# Initially should not be fading
	assert_false(audio_manager.is_fading, "Should not be fading initially")


## Test 21: Signals exist
func test_signals_exist():
	# Check if AudioManager has the expected signals
	assert_true(audio_manager.has_signal("music_started"), "Should have music_started signal")
	assert_true(audio_manager.has_signal("music_stopped"), "Should have music_stopped signal")
	assert_true(audio_manager.has_signal("sfx_played"), "Should have sfx_played signal")


## Test 22: Audio bus names constants
func test_audio_bus_constants():
	assert_eq(audio_manager.BUS_MASTER, "Master", "Master bus name should be 'Master'")
	assert_eq(audio_manager.BUS_MUSIC, "Music", "Music bus name should be 'Music'")
	assert_eq(audio_manager.BUS_SFX, "SFX", "SFX bus name should be 'SFX'")


## Test 23: SFX player pool size constant
func test_sfx_player_pool_size():
	assert_eq(audio_manager.SFX_PLAYER_POOL_SIZE, 8, "SFX player pool size should be 8")


## Test 24: Reload audio resources (should not crash)
func test_reload_audio_resources():
	audio_manager.reload_audio_resources()
	# Should complete without crashing
	assert_true(true, "Reload audio resources should complete")


## Test 25: Multiple simultaneous SFX playback
func test_multiple_sfx_playback():
	# Even though sounds don't exist, calling play_sfx multiple times should not crash
	for i in range(10):
		audio_manager.play_sfx("test_sound")

	# Should complete without crashing
	assert_true(true, "Multiple SFX playback calls should not crash")


## Test 26: Music volume affects music player
func test_music_volume_affects_player():
	audio_manager.set_music_volume(0.5)

	# Volume should be applied to the bus
	var music_idx = AudioServer.get_bus_index("Music")
	var music_vol = db_to_linear(AudioServer.get_bus_volume_db(music_idx))

	assert_almost_eq(music_vol, 0.5, 0.1, "Music bus volume should match set volume")


## Test 27: All audio players are children of AudioManager
func test_audio_players_are_children():
	assert_true(audio_manager.music_player.get_parent() == audio_manager,
		"Music player should be child of AudioManager")

	for player in audio_manager.sfx_players:
		assert_true(player.get_parent() == audio_manager,
			"SFX player should be child of AudioManager")


## Test 28: Audio directories exist
func test_audio_directories_exist():
	# Check if audio directories were created
	assert_true(DirAccess.dir_exists_absolute("res://assets/audio/music"),
		"Music directory should exist")
	assert_true(DirAccess.dir_exists_absolute("res://assets/audio/sfx"),
		"SFX directory should exist")


## Test 29: AudioManager is a singleton (autoload)
func test_audio_manager_is_singleton():
	# AudioManager should be accessible from anywhere
	var audio_mgr = get_node("/root/AudioManager")
	assert_not_null(audio_mgr, "AudioManager should be accessible as singleton")
	assert_eq(audio_mgr, audio_manager, "Should be the same instance")


## Test 30: Default volume values are set correctly
func test_default_volume_values():
	# After reset, volumes should be at defaults
	audio_manager.set_master_volume(1.0)
	audio_manager.set_music_volume(0.7)
	audio_manager.set_sfx_volume(0.8)

	assert_almost_eq(audio_manager.master_volume, 1.0, 0.01, "Default master volume should be 1.0")
	assert_almost_eq(audio_manager.music_volume, 0.7, 0.01, "Default music volume should be 0.7")
	assert_almost_eq(audio_manager.sfx_volume, 0.8, 0.01, "Default SFX volume should be 0.8")
