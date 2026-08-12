## AudioManager — the autoload that actually makes noise.
##
## Two responsibilities and no more: own the buses and the players, and play
## what it is asked to play. WHAT each sound is called and how loud it sits is
## `Sounds`; WHEN each one fires is the world's business. Nothing reads back
## from here — audio is a leaf, and no gameplay decision may depend on it.
##
##   AudioManager.play_sfx(Sounds.FOLD)
##   AudioManager.play_music(Sounds.MUSIC_REGION)
##   AudioManager.set_music_volume(0.7)
##
## Three things about this file are load-bearing and easy to undo by accident.
##
## **The user's volume is applied ONCE, on the bus.** A player's `volume_db` is
## never the user's setting — it is the fade envelope for music, and the mix
## trim for an effect. Setting both (as this file used to) multiplies the
## setting into itself, so half volume plays at a quarter.
##
## **This node runs while the tree is paused** (`PROCESS_MODE_ALWAYS`). Godot
## pauses an `AudioStreamPlayer` along with its tree, and the pause menu pauses
## the tree — so without this, the click that opened the menu is the last thing
## you hear, and any fade in flight freezes mid-way.
##
## **Missing audio is a warning, once, and never an error.** The game is fully
## playable silent, and a sound that has no file must not cost a frame or fill
## the log — see `_warned`.
extends Node

## Emitted when music starts playing.
signal music_started(track_name: String)

## Emitted when music stops.
signal music_stopped()

## Emitted when a sound effect actually plays. Not emitted for a sound that was
## missing or throttled — this says "you heard that", not "someone asked".
signal sfx_played(sfx_name: String)

## Audio bus names.
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

## Music fade in/out, seconds.
const FADE_DURATION := 1.0

## The floor the fade runs to. Not -INF: tweening to negative infinity has no
## defined midpoint, and anything below this is inaudible anyway.
const SILENT_DB := -60.0

## What counts as an audio file in the asset directories.
const AUDIO_EXTENSIONS := ["ogg", "wav", "mp3"]

## Where volume settings persist. Shared with `scripts/ui/Settings.gd`, which
## owns the graphics keys in the same file; both sides read-modify-write so
## neither clobbers the other's keys.
const SETTINGS_FILE := "user://settings.json"

## Enough voices for a burst that scatters hands while a fold is landing and the
## player is still running. Beyond this the oldest voice is taken — see
## `_get_sfx_player`.
const SFX_PLAYER_POOL_SIZE := 8

## Audio player for background music.
var music_player: AudioStreamPlayer

## Audio player pool for sound effects, so they can overlap.
var sfx_players: Array[AudioStreamPlayer] = []

## Current music track name ("" when nothing is playing or a fade-out is
## committed to stopping).
var current_music_track: String = ""

## Music tracks by id (basename) -> AudioStream.
var music_tracks: Dictionary = {}

## Sound effects by id (basename) -> AudioStream.
var sound_effects: Dictionary = {}

## Volume settings, 0.0 to 1.0. These are the user's, and they live on the
## buses; see the note at the top about applying them exactly once.
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8

## Is a music fade in flight.
var is_fading: bool = false

## The tween driving the current fade, so a new one can cancel it. The old
## hand-rolled `await` loop could not be cancelled, which is what let a
## track change during a fade stop the music outright.
var _fade: Tween = null

## Play order per sfx player, for oldest-first stealing: a monotonic counter
## rather than a timestamp, because several sounds routinely start in the same
## millisecond (a scattered pair, a burst) and a clock cannot order those. With
## ties, "the oldest voice" is whichever the loop happened to reach first.
var _sfx_order: Array[int] = []

## Source of the above. Only ever increases.
var _sfx_plays: int = 0

## Sound id -> engine ms it last played, for the `Sounds.gap` throttle.
var _last_played: Dictionary = {}

## Names already warned about, so a missing asset costs one line in the log
## rather than one per frame for the rest of the session.
var _warned: Dictionary = {}


func _ready() -> void:
	# See the header: the pause menu pauses the tree, and a paused
	# AudioStreamPlayer is a silent one.
	process_mode = Node.PROCESS_MODE_ALWAYS

	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = BUS_MUSIC
	add_child(music_player)

	for i in range(SFX_PLAYER_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%d" % i
		player.bus = BUS_SFX
		add_child(player)
		sfx_players.append(player)
		_sfx_order.append(0)

	_setup_audio_buses()
	load_volume_settings()
	_apply_volume_settings()
	_load_audio_resources()


## Let the streams go before the engine tears down.
##
## An autoload holding every loaded stream for the life of the process is the
## point — it is what makes a sound cost nothing at the moment it fires — but
## still holding them when Godot clears its resource table makes it report
## resources in use at exit. Dropping the references here keeps a clean run
## clean, so a real leak stays visible.
func _exit_tree() -> void:
	_kill_fade()
	if music_player != null:
		music_player.stream = null
	for player in sfx_players:
		player.stream = null
	music_tracks.clear()
	sound_effects.clear()


# ---------------------------------------------------------------------------
# Buses
# ---------------------------------------------------------------------------

## Create Music and SFX beneath Master if the project has no bus layout.
##
## Indices are re-read after every mutation rather than captured up front:
## adding a bus shifts everything below it, and the stale-index version of this
## routed SFX into whatever bus had taken its place.
func _setup_audio_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var at := AudioServer.bus_count
		AudioServer.add_bus(at)
		AudioServer.set_bus_name(at, bus_name)
		AudioServer.set_bus_send(at, BUS_MASTER)


## Apply the three volumes to their buses. The ONLY place a user volume becomes
## a decibel figure.
func _apply_volume_settings() -> void:
	_set_bus(BUS_MASTER, master_volume)
	_set_bus(BUS_MUSIC, music_volume)
	_set_bus(BUS_SFX, sfx_volume)


func _set_bus(bus_name: String, volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	# Silence is a mute rather than a very small number: linear_to_db(0) is
	# -INF, which some platforms carry into the mixer as a NaN.
	AudioServer.set_bus_mute(idx, volume <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.0001)))


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

func _load_audio_resources() -> void:
	_load_audio_files("res://assets/audio/music/", music_tracks, true)
	_load_audio_files("res://assets/audio/sfx/", sound_effects, false)


## Load every audio file in a directory, keyed by basename.
##
## `loop` is for music only, and it has to be applied here because the loop flag
## lives on the imported resource: the `.import` files are not in version
## control, so nothing on disk can carry it for us.
func _load_audio_files(path: String, dictionary: Dictionary, loop: bool) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("AudioManager: could not open directory: %s" % path)
		return

	dir.list_dir_begin()
	var seen := {}
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# An exported project does not ship the source file — it ships the
			# imported resource behind a `.import` / `.remap` sidecar, and that
			# is what the directory lists. The loadable path is still the
			# original name, so strip the sidecar suffix and de-duplicate.
			var key := file_name
			for suffix in [".import", ".remap"]:
				if key.ends_with(suffix):
					key = key.substr(0, key.length() - suffix.length())
			if AUDIO_EXTENSIONS.has(key.get_extension().to_lower()) and not seen.has(key):
				seen[key] = true
				var full_path := path + key
				if ResourceLoader.exists(full_path):
					var stream = load(full_path)
					if stream is AudioStream:
						if loop:
							_make_looping(stream)
						dictionary[key.get_basename()] = stream
					else:
						push_warning("AudioManager: not an audio stream: %s" % full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Make a stream loop. Every format spells it differently, and a music bed that
## does not loop is a bed that stops thirty seconds in and never comes back.
func _make_looping(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var frames := _wav_frame_count(wav)
		if frames > 0:
			wav.loop_end = frames
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true


## Frames in a WAV, from its byte count and format. Needed because `loop_end` is
## in frames, and the tracks are generated to be sample-exact loops — an end
## even one frame short of the true end puts a tick in the seam.
func _wav_frame_count(wav: AudioStreamWAV) -> int:
	var bytes := wav.data.size()
	if bytes <= 0:
		return 0
	var frames := bytes
	match wav.format:
		AudioStreamWAV.FORMAT_16_BITS:
			frames = bytes / 2
		AudioStreamWAV.FORMAT_IMA_ADPCM:
			frames = bytes * 2
		_:
			frames = bytes
	if wav.stereo:
		frames /= 2
	return frames


## Reload everything from disk. For tooling and tests; the game loads once.
func reload_audio_resources() -> void:
	music_tracks.clear()
	sound_effects.clear()
	_warned.clear()
	_load_audio_resources()


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

## Play a background track, crossfading from whatever is playing.
##
## Deliberately NOT a coroutine. The old version awaited a timer between the
## fade-out and the swap, which meant the caller's `play_music` returned before
## the track had changed and two calls in one frame raced each other. The whole
## sequence is one tween now, so it is cancellable and it composes.
func play_music(track_name: String, fade_in: bool = true) -> void:
	if not music_tracks.has(track_name):
		_warn_once("music:" + track_name, "AudioManager: music track not found: %s" % track_name)
		return
	# Already on this track — playing it, or fading toward it. Walking back and
	# forth across a fold's boundary must not keep restarting the bed.
	if current_music_track == track_name and (music_player.playing or is_fading):
		return

	_kill_fade()
	var stream: AudioStream = music_tracks[track_name]
	# Set at REQUEST time, not when the stream is swapped in. `current_music_track`
	# is the track the system is on, and during a crossfade that is the one
	# arriving — the old one is leaving. Deciding it in the tween callback
	# instead left the field reporting the outgoing track for half a second,
	# which is exactly long enough for the next request to talk itself out of
	# doing anything.
	current_music_track = track_name

	if not fade_in:
		music_player.stream = stream
		music_player.volume_db = 0.0
		music_player.play()
		music_started.emit(track_name)
		return

	var swap := func() -> void:
		music_player.stream = stream
		music_player.play()
		music_started.emit(track_name)

	is_fading = true
	_fade = create_tween()
	if music_player.playing:
		# Out, swap, in. One chain, so a third call simply kills it.
		_fade.tween_property(music_player, "volume_db", SILENT_DB, FADE_DURATION * 0.5)
	_fade.tween_callback(swap)
	_fade.tween_property(music_player, "volume_db", 0.0, FADE_DURATION * 0.5) \
		.from(SILENT_DB)
	_fade.tween_callback(func() -> void: is_fading = false)


## Stop the music, fading out by default.
func stop_music(fade_out: bool = true) -> void:
	_kill_fade()
	if not music_player.playing:
		# Still clear the track: a fade-out cancelled mid-way leaves the player
		# stopped, and reporting the old name would make `play_music` refuse to
		# restart it.
		current_music_track = ""
		return

	# Cleared now for the same reason `play_music` sets it now: a track on its
	# way out is not the track the system is on, and a `play_music` for it
	# during the fade must restart it rather than no-op.
	current_music_track = ""

	if not fade_out:
		music_player.stop()
		music_stopped.emit()
		return

	is_fading = true
	_fade = create_tween()
	_fade.tween_property(music_player, "volume_db", SILENT_DB, FADE_DURATION)
	_fade.tween_callback(func() -> void:
		music_player.stop()
		is_fading = false
		music_stopped.emit())


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	is_fading = false


func is_music_playing() -> bool:
	return music_player != null and music_player.playing


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------

## Play a sound effect by its `Sounds` id.
##
## Mix trim, pitch jitter and the retrigger floor all come from the registry, so
## a call site says only WHAT happened. Returns true if a voice actually
## started — false when the sound is missing or the throttle swallowed it.
## Nothing in the game branches on that; it is for tests.
func play_sfx(sfx_name: String, pitch_var: bool = true) -> bool:
	if not sound_effects.has(sfx_name):
		_warn_once("sfx:" + sfx_name, "AudioManager: sound effect not found: %s" % sfx_name)
		return false

	var now := Time.get_ticks_msec()
	var gap := Sounds.gap(sfx_name)
	if gap > 0.0 and now - int(_last_played.get(sfx_name, -1000000)) < int(gap * 1000.0):
		return false
	_last_played[sfx_name] = now

	var idx := _get_sfx_player()
	var player := sfx_players[idx]
	player.stream = sound_effects[sfx_name]
	player.volume_db = Sounds.volume_db(sfx_name)

	var jitter := Sounds.pitch_jitter(sfx_name) if pitch_var else 0.0
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter) if jitter > 0.0 else 1.0

	player.play()
	_sfx_plays += 1
	_sfx_order[idx] = _sfx_plays
	sfx_played.emit(sfx_name)
	return true


## Index of a free player, or of the longest-running one if all are busy.
##
## Stealing rather than dropping: the pool exists to let sounds overlap, not to
## cap how many events the game may have. A dropped sound is a fold you did not
## hear, and the oldest voice is the one already closest to finishing.
func _get_sfx_player() -> int:
	var oldest := 0
	for i in range(sfx_players.size()):
		if not sfx_players[i].playing:
			return i
		if _sfx_order[i] < _sfx_order[oldest]:
			oldest = i
	return oldest


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)


# ---------------------------------------------------------------------------
# Volume
# ---------------------------------------------------------------------------

func set_master_volume(volume: float) -> void:
	master_volume = clampf(volume, 0.0, 1.0)
	_apply_volume_settings()


func set_music_volume(volume: float) -> void:
	music_volume = clampf(volume, 0.0, 1.0)
	_apply_volume_settings()


func set_sfx_volume(volume: float) -> void:
	sfx_volume = clampf(volume, 0.0, 1.0)
	_apply_volume_settings()


func get_master_volume() -> float:
	return master_volume


func get_music_volume() -> float:
	return music_volume


func get_sfx_volume() -> float:
	return sfx_volume


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
# The volumes are the audio system's own state, so it loads and saves them
# itself rather than waiting to be told by a settings screen that may never be
# opened. That is the bug this replaces: the values were written to disk and
# only ever read back by the menu that wrote them, so every session started at
# the defaults however the player had set them.

## Read the three volumes out of the settings file and apply them. Missing keys
## and a missing (or corrupt) file all mean "keep the defaults".
func load_volume_settings() -> void:
	var data := _read_settings()
	master_volume = clampf(float(data.get("master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(data.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	_apply_volume_settings()


## Write the three volumes back, leaving every other key alone — the graphics
## settings live in this file too and belong to somebody else.
func save_volume_settings() -> void:
	var data := _read_settings()
	data["master_volume"] = master_volume
	data["music_volume"] = music_volume
	data["sfx_volume"] = sfx_volume
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file == null:
		push_warning("AudioManager: could not write %s" % SETTINGS_FILE)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _read_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return {}
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func has_music_track(track_name: String) -> bool:
	return music_tracks.has(track_name)


func has_sfx(sfx_name: String) -> bool:
	return sound_effects.has(sfx_name)


func get_music_tracks() -> Array[String]:
	var tracks: Array[String] = []
	for key in music_tracks.keys():
		tracks.append(String(key))
	return tracks


func get_sfx_list() -> Array[String]:
	var sfx_list: Array[String] = []
	for key in sound_effects.keys():
		sfx_list.append(String(key))
	return sfx_list
