## Tests for AudioManager and the Sounds registry.
##
## The suite is the spec, so what is pinned here is what the audio system
## promises: the user's volume is applied exactly once, the registry and the
## shipped assets are the same set, music loops and effects do not, and a sound
## that cannot be played is never allowed to cost anything.

extends GutTest

var audio_manager: Node

## Volumes to restore between tests — the manager is an autoload, so a test
## that leaves it turned down leaves it turned down for the whole suite.
const V_MASTER := 1.0
const V_MUSIC := 0.7
const V_SFX := 0.8


func before_all():
	audio_manager = AudioManager


func before_each():
	# The retrigger throttle is stateful across calls by design, so tests that
	# play the same sound twice must not inherit another test's timestamps.
	audio_manager._last_played.clear()


func after_each():
	audio_manager.stop_music(false)
	audio_manager.set_master_volume(V_MASTER)
	audio_manager.set_music_volume(V_MUSIC)
	audio_manager.set_sfx_volume(V_SFX)


# ---------------------------------------------------------------------------
# Buses and players
# ---------------------------------------------------------------------------

func test_audio_manager_exists():
	assert_not_null(audio_manager, "AudioManager singleton should exist")
	assert_eq(get_node("/root/AudioManager"), audio_manager,
		"AudioManager should be reachable as an autoload")


func test_audio_buses_exist():
	for bus_name in ["Master", "Music", "SFX"]:
		assert_ne(AudioServer.get_bus_index(bus_name), -1, "%s bus should exist" % bus_name)


func test_music_and_sfx_buses_send_to_master():
	for bus_name in ["Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus_name)
		assert_eq(AudioServer.get_bus_send(idx), "Master",
			"%s should route through Master, or the master volume does nothing" % bus_name)


func test_players_are_created_on_the_right_buses():
	assert_not_null(audio_manager.music_player, "Music player should exist")
	assert_eq(audio_manager.music_player.bus, "Music")
	assert_eq(audio_manager.sfx_players.size(), AudioManager.SFX_PLAYER_POOL_SIZE)
	for player in audio_manager.sfx_players:
		assert_not_null(player)
		assert_eq(player.bus, "SFX")


func test_players_are_children_of_the_manager():
	assert_eq(audio_manager.music_player.get_parent(), audio_manager)
	for player in audio_manager.sfx_players:
		assert_eq(player.get_parent(), audio_manager)


## The pause menu pauses the tree, and Godot pauses an AudioStreamPlayer with
## it. Without this the click that opens the menu is the last thing you hear.
func test_manager_runs_while_the_tree_is_paused():
	assert_eq(audio_manager.process_mode, Node.PROCESS_MODE_ALWAYS,
		"AudioManager must keep processing while paused")


func test_bus_name_constants():
	assert_eq(AudioManager.BUS_MASTER, "Master")
	assert_eq(AudioManager.BUS_MUSIC, "Music")
	assert_eq(AudioManager.BUS_SFX, "SFX")


# ---------------------------------------------------------------------------
# Volume
# ---------------------------------------------------------------------------

func test_volume_getters_report_what_was_set():
	audio_manager.set_master_volume(0.5)
	audio_manager.set_music_volume(0.25)
	audio_manager.set_sfx_volume(0.6)
	assert_almost_eq(audio_manager.get_master_volume(), 0.5, 0.001)
	assert_almost_eq(audio_manager.get_music_volume(), 0.25, 0.001)
	assert_almost_eq(audio_manager.get_sfx_volume(), 0.6, 0.001)


func test_volumes_clamp_to_unit_range():
	for setter in ["set_master_volume", "set_music_volume", "set_sfx_volume"]:
		audio_manager.call(setter, 1.5)
		audio_manager.call(setter, -0.5)
	assert_eq(audio_manager.get_master_volume(), 0.0)
	assert_eq(audio_manager.get_music_volume(), 0.0)
	assert_eq(audio_manager.get_sfx_volume(), 0.0)

	audio_manager.set_master_volume(2.0)
	assert_eq(audio_manager.get_master_volume(), 1.0)


func test_volumes_reach_their_buses():
	audio_manager.set_master_volume(0.5)
	audio_manager.set_music_volume(0.3)
	audio_manager.set_sfx_volume(0.7)
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index("Master"))), 0.5, 0.01)
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index("Music"))), 0.3, 0.01)
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index("SFX"))), 0.7, 0.01)


## The regression this file exists for. The music volume used to be written to
## the bus AND to the player, so it multiplied into itself: half volume played
## at a quarter. The player's volume_db is the FADE, and nothing else.
func test_music_volume_is_applied_once_not_twice():
	audio_manager.play_music(Sounds.MUSIC_OVERWORLD, false)
	audio_manager.set_music_volume(0.5)
	assert_almost_eq(audio_manager.music_player.volume_db, 0.0, 0.001,
		"the music player carries the fade, never the user's volume")
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index("Music"))), 0.5, 0.01,
		"the user's volume belongs on the bus")


func test_zero_volume_mutes_rather_than_scaling():
	audio_manager.set_sfx_volume(0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"silence should be a mute, not a very small number")
	audio_manager.set_sfx_volume(0.8)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))


# ---------------------------------------------------------------------------
# The registry and the assets agree
#
# Both directions, because the two failure modes are different: a name with no
# file is a sound that silently never plays, and a file with no name is a sound
# nobody can reach and a mix trim nobody set.
# ---------------------------------------------------------------------------

func test_every_registered_sound_has_an_asset():
	for id in Sounds.all_sounds():
		assert_true(audio_manager.has_sfx(id),
			"Sounds.%s is registered but assets/audio/sfx/%s.* is missing" % [id, id])


func test_every_shipped_sfx_is_registered():
	for id in audio_manager.get_sfx_list():
		assert_true(Sounds.is_registered(id),
			"assets/audio/sfx/%s.* ships but has no entry in Sounds" % id)


func test_every_registered_track_has_an_asset():
	for id in Sounds.all_music():
		assert_true(audio_manager.has_music_track(id),
			"Sounds lists music '%s' but assets/audio/music/%s.* is missing" % [id, id])


func test_every_shipped_track_is_registered():
	var known := Sounds.all_music()
	for id in audio_manager.get_music_tracks():
		assert_true(known.has(id),
			"assets/audio/music/%s.* ships but Sounds does not list it" % id)


func test_the_fold_vocabulary_is_present():
	# A spot check that the registry is about THIS game, not the deleted
	# top-down build: these are the events folding is made of.
	for id in [Sounds.FOLD, Sounds.UNFOLD, Sounds.PINCH, Sounds.SURFACE,
			Sounds.BURST, Sounds.PAIR_ARMED, Sounds.HAND_PLACE]:
		assert_true(Sounds.is_registered(id), "%s should be registered" % id)
		assert_true(audio_manager.has_sfx(id), "%s should have an asset" % id)


func test_unregistered_names_fall_back_to_defaults():
	assert_false(Sounds.is_registered("no_such_sound"))
	assert_eq(Sounds.get_def("no_such_sound"), Sounds.DEFAULT)
	assert_eq(Sounds.gap("no_such_sound"), 0.0)


func test_registry_entries_are_well_formed():
	for id in Sounds.all_sounds():
		var def := Sounds.get_def(id)
		for field in ["vol", "pitch", "gap"]:
			assert_true(def.has(field), "%s is missing '%s'" % [id, field])
		assert_true(Sounds.volume_db(id) <= 0.0,
			"%s: trims cut, they do not boost — assets are normalized" % id)
		assert_true(Sounds.pitch_jitter(id) >= 0.0 and Sounds.pitch_jitter(id) < 1.0,
			"%s: pitch jitter should be a small fraction" % id)
		assert_true(Sounds.gap(id) >= 0.0, "%s: gap cannot be negative" % id)


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

func test_music_streams_loop():
	for id in Sounds.all_music():
		var stream: AudioStream = audio_manager.music_tracks[id]
		if stream is AudioStreamWAV:
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD,
				"%s must loop — a bed that stops never comes back" % id)
			assert_gt(stream.loop_end, 0, "%s needs a real loop end" % id)
		else:
			assert_true(stream.loop, "%s must loop" % id)


func test_sound_effects_do_not_loop():
	for id in Sounds.all_sounds():
		var stream: AudioStream = audio_manager.sound_effects[id]
		if stream is AudioStreamWAV:
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED,
				"%s must not loop — a looping footstep is a stuck footstep" % id)


func test_reload_is_idempotent():
	var sfx_before: int = audio_manager.get_sfx_list().size()
	var music_before: int = audio_manager.get_music_tracks().size()
	audio_manager.reload_audio_resources()
	assert_eq(audio_manager.get_sfx_list().size(), sfx_before)
	assert_eq(audio_manager.get_music_tracks().size(), music_before)


func test_audio_directories_exist():
	assert_true(DirAccess.dir_exists_absolute("res://assets/audio/music"))
	assert_true(DirAccess.dir_exists_absolute("res://assets/audio/sfx"))


# ---------------------------------------------------------------------------
# Playing effects
# ---------------------------------------------------------------------------

func test_playing_a_real_sound_reports_success():
	assert_true(audio_manager.play_sfx(Sounds.FOLD), "a shipped sound should play")


func test_playing_a_missing_sound_is_survivable_and_warns_once():
	audio_manager._warned.clear()
	assert_false(audio_manager.play_sfx("definitely_not_a_sound"))
	assert_true(audio_manager._warned.has("sfx:definitely_not_a_sound"),
		"a missing sound should warn")
	# Ten more must add nothing: this fires from _physics_process in the real
	# game, and one warning per frame is how a log becomes useless.
	for _i in range(10):
		audio_manager.play_sfx("definitely_not_a_sound")
	assert_eq(audio_manager._warned.size(), 1, "it should warn exactly once")


func test_the_mix_trim_reaches_the_player():
	audio_manager.play_sfx(Sounds.FOOTSTEP)
	var quiet := _last_player_volume()
	audio_manager._last_played.clear()
	audio_manager.play_sfx(Sounds.FOLD)
	var loud := _last_player_volume()
	assert_lt(quiet, loud, "a footstep should sit below a fold in the mix")
	assert_almost_eq(loud, Sounds.volume_db(Sounds.FOLD), 0.001)


func test_pitch_jitter_stays_within_the_registered_bound():
	var jitter := Sounds.pitch_jitter(Sounds.FOOTSTEP)
	for _i in range(20):
		audio_manager._last_played.clear()
		audio_manager.play_sfx(Sounds.FOOTSTEP)
		var scale := _last_player_pitch()
		assert_between(scale, 1.0 - jitter, 1.0 + jitter)


func test_pitch_jitter_can_be_refused_by_the_caller():
	audio_manager.play_sfx(Sounds.FOOTSTEP, false)
	assert_eq(_last_player_pitch(), 1.0)


func test_sounds_with_no_jitter_always_play_at_pitch():
	assert_eq(Sounds.pitch_jitter(Sounds.PAIR_ARMED), 0.0,
		"the fuse is a thing to learn to recognise")
	audio_manager.play_sfx(Sounds.PAIR_ARMED)
	assert_eq(_last_player_pitch(), 1.0)


func test_the_retrigger_gap_swallows_a_repeat():
	assert_gt(Sounds.gap(Sounds.DENY), 0.0, "refusals must be throttled")
	assert_true(audio_manager.play_sfx(Sounds.DENY), "the first should play")
	assert_false(audio_manager.play_sfx(Sounds.DENY), "the second, at once, should not")


func test_the_gap_is_per_sound_not_global():
	assert_true(audio_manager.play_sfx(Sounds.DENY))
	assert_true(audio_manager.play_sfx(Sounds.FOLD),
		"throttling one sound must not throttle another")


func test_ungapped_sounds_repeat_freely():
	assert_eq(Sounds.gap(Sounds.FOLD), 0.0)
	assert_true(audio_manager.play_sfx(Sounds.FOLD))
	assert_true(audio_manager.play_sfx(Sounds.FOLD))


## More simultaneous sounds than the pool has voices: the oldest is taken, and
## nothing is dropped. A dropped sound is a fold you did not hear.
func test_the_pool_steals_rather_than_drops():
	for _i in range(AudioManager.SFX_PLAYER_POOL_SIZE * 2):
		audio_manager._last_played.clear()
		assert_true(audio_manager.play_sfx(Sounds.HAND_PLACE),
			"an exhausted pool should still play")


func test_sfx_played_fires_only_when_something_is_heard():
	var heard: Array = []
	var handler := func(name: String) -> void: heard.append(name)
	audio_manager.sfx_played.connect(handler)

	audio_manager.play_sfx(Sounds.DENY)         # plays
	audio_manager.play_sfx(Sounds.DENY)         # throttled
	audio_manager.play_sfx("not_a_sound")       # missing
	audio_manager.sfx_played.disconnect(handler)

	assert_eq(heard, [Sounds.DENY], "the signal reports what was heard, not what was asked")


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

func test_missing_track_does_not_play():
	audio_manager.play_music("no_such_track", false)
	assert_false(audio_manager.music_player.playing)
	assert_eq(audio_manager.current_music_track, "")


func test_play_and_stop_a_track():
	audio_manager.play_music(Sounds.MUSIC_OVERWORLD, false)
	assert_true(audio_manager.music_player.playing)
	assert_eq(audio_manager.current_music_track, Sounds.MUSIC_OVERWORLD)
	assert_eq(audio_manager.music_player.stream,
		audio_manager.music_tracks[Sounds.MUSIC_OVERWORLD])

	audio_manager.stop_music(false)
	assert_false(audio_manager.music_player.playing)
	assert_eq(audio_manager.current_music_track, "")


func test_replaying_the_same_track_does_not_restart_it():
	audio_manager.play_music(Sounds.MUSIC_OVERWORLD, false)
	var playback_before: float = audio_manager.music_player.get_playback_position()
	audio_manager.play_music(Sounds.MUSIC_OVERWORLD, false)
	assert_eq(audio_manager.music_player.get_playback_position(), playback_before,
		"walking between regions must not restart the bed")


func test_switching_tracks_changes_the_stream():
	audio_manager.play_music(Sounds.MUSIC_OVERWORLD, false)
	audio_manager.play_music(Sounds.MUSIC_SUBSPACE, false)
	assert_eq(audio_manager.current_music_track, Sounds.MUSIC_SUBSPACE)
	assert_eq(audio_manager.music_player.stream,
		audio_manager.music_tracks[Sounds.MUSIC_SUBSPACE])


## A fade is a tween now, not an `await` loop, so it can be cancelled — which is
## what makes a track change during a fade land on the right track instead of
## stopping the music.
func test_a_fade_is_cancellable():
	audio_manager.play_music(Sounds.MUSIC_OVERWORLD, true)
	assert_true(audio_manager.is_fading, "fading in")
	audio_manager.play_music(Sounds.MUSIC_SUBSPACE, false)
	assert_false(audio_manager.is_fading, "the new call should have cancelled it")
	assert_eq(audio_manager.current_music_track, Sounds.MUSIC_SUBSPACE)


func test_stopping_music_that_is_not_playing_is_harmless():
	audio_manager.stop_music(false)
	audio_manager.stop_music(true)
	assert_false(audio_manager.music_player.playing)
	assert_eq(audio_manager.current_music_track, "")


func test_music_signals_exist():
	for sig in ["music_started", "music_stopped", "sfx_played"]:
		assert_true(audio_manager.has_signal(sig), "should have %s" % sig)


func test_music_started_reports_the_track():
	var started: Array = []
	var handler := func(name: String) -> void: started.append(name)
	audio_manager.music_started.connect(handler)
	audio_manager.play_music(Sounds.MUSIC_SUBSPACE, false)
	audio_manager.music_started.disconnect(handler)
	assert_eq(started, [Sounds.MUSIC_SUBSPACE])


func test_fade_duration_constant():
	assert_almost_eq(AudioManager.FADE_DURATION, 1.0, 0.001)


# ---------------------------------------------------------------------------
# Persistence
#
# The bug being pinned: volumes were written to disk by the settings menu and
# only ever read back by the settings menu, so however the player set them,
# every session started at the defaults.
# ---------------------------------------------------------------------------

func test_volumes_survive_a_save_and_load():
	var saved := _read_settings_file()

	audio_manager.set_master_volume(0.42)
	audio_manager.set_music_volume(0.11)
	audio_manager.set_sfx_volume(0.63)
	audio_manager.save_volume_settings()

	audio_manager.set_master_volume(1.0)
	audio_manager.set_music_volume(1.0)
	audio_manager.load_volume_settings()

	assert_almost_eq(audio_manager.get_master_volume(), 0.42, 0.001)
	assert_almost_eq(audio_manager.get_music_volume(), 0.11, 0.001)
	assert_almost_eq(audio_manager.get_sfx_volume(), 0.63, 0.001)

	_restore_settings_file(saved)


func test_saving_volumes_leaves_other_settings_alone():
	var saved := _read_settings_file()

	var file := FileAccess.open(AudioManager.SETTINGS_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"fullscreen": true, "vsync": false}))
	file.close()

	audio_manager.save_volume_settings()
	var data := _read_settings_file()
	assert_true(data.get("fullscreen", false), "graphics keys belong to Settings")
	assert_false(data.get("vsync", true))
	assert_true(data.has("master_volume"))

	_restore_settings_file(saved)


func test_a_missing_settings_file_leaves_the_defaults_standing():
	var saved := _read_settings_file()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioManager.SETTINGS_FILE))

	audio_manager.set_music_volume(0.33)
	audio_manager.load_volume_settings()
	assert_almost_eq(audio_manager.get_music_volume(), 0.33, 0.001,
		"nothing on disk means nothing to apply")

	_restore_settings_file(saved)


func test_loaded_volumes_are_clamped():
	var saved := _read_settings_file()

	var file := FileAccess.open(AudioManager.SETTINGS_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"master_volume": 9.0, "sfx_volume": -3.0}))
	file.close()

	audio_manager.load_volume_settings()
	assert_eq(audio_manager.get_master_volume(), 1.0, "a hand-edited file cannot blow the mix")
	assert_eq(audio_manager.get_sfx_volume(), 0.0)

	_restore_settings_file(saved)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## The pool player the last `play_sfx` used — the one holding the highest play
## number. Unambiguous because `_sfx_order` is a counter and not a clock, which
## is exactly why it is a counter.
func _last_started_player() -> AudioStreamPlayer:
	var best := 0
	for i in range(audio_manager.sfx_players.size()):
		if audio_manager._sfx_order[i] > audio_manager._sfx_order[best]:
			best = i
	return audio_manager.sfx_players[best]


func _last_player_volume() -> float:
	return _last_started_player().volume_db


func _last_player_pitch() -> float:
	return _last_started_player().pitch_scale


func _read_settings_file() -> Dictionary:
	if not FileAccess.file_exists(AudioManager.SETTINGS_FILE):
		return {}
	var file := FileAccess.open(AudioManager.SETTINGS_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _restore_settings_file(data: Dictionary) -> void:
	if data.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioManager.SETTINGS_FILE))
		return
	var file := FileAccess.open(AudioManager.SETTINGS_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
