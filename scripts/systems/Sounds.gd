class_name Sounds extends RefCounted

## Sounds
##
## The registry of everything the game can be HEARD to do — the audio twin of
## `TileTypes` and `HandTypes`. Adding a sound means editing this file and
## dropping a file of the same name in `assets/audio/sfx/`; nothing else in the
## codebase learns a new name.
##
## An id here IS the asset's basename, so there is no mapping table to drift:
## `Sounds.FOLD` is `"fold"` is `assets/audio/sfx/fold.wav`. `AudioManager`
## looks every play up in here, so an unregistered name still plays — it simply
## plays with the defaults below.
##
## `test_audio_manager` asserts this registry and the shipped assets are the
## same set in both directions, so a sound named here with no file (and a file
## with no entry) fails the suite rather than turning into a runtime warning
## nobody reads.
##
## Per-sound definition fields:
##   vol   : dB trim. **This is the mix**, and it lives here rather than in the
##           assets on purpose — `tools/gen_audio.py` normalizes every effect to
##           one peak, so how loud a footstep is beside a fold is a decision you
##           can read, review and change in a diff instead of a binary.
##   pitch : ± fraction of pitch jitter per play. Variety for anything that
##           repeats; zero for anything with a pitch the player might learn.
##   gap   : seconds this sound refuses to retrigger within. The reason this
##           registry exists at all: footsteps, dropped hands and refusals all
##           fire from `_physics_process`, and without a floor on the interval
##           a single frame's worth of events machine-guns the pool. Solved once
##           here rather than at every call site.


# --- Folding: the verb the whole game is made of -----------------------------

## A hand goes down as an anchor.
const HAND_PLACE := "hand_place"
## A pair completes and its fuse lights. The player's only warning.
const PAIR_ARMED := "pair_armed"
## A fold commits.
const FOLD := "fold"
## A fold comes apart.
const UNFOLD := "unfold"
## The fold closed over the player instead of moving them: they are inside it.
const PINCH := "pinch"
## Emerging from a subspace back to the space above.
const SURFACE := "surface"
## The burst.
const BURST := "burst"
## The fuse went off and the fold would not go; the hands scatter.
const FOLD_REFUSED := "fold_refused"
## A trigger tile firing — the world folding itself, not the player folding it.
const TRIGGER := "trigger"

# --- Hands -------------------------------------------------------------------

## Walking over a loose hand and taking it.
const HAND_PICKUP := "hand_pickup"
## A hand with nowhere to go landing on the ground.
const HAND_DROP := "hand_drop"

# --- The body and the world --------------------------------------------------

const JUMP := "jump"
const LAND := "land"
const FOOTSTEP := "footstep"
## Stepping through a door.
const DOOR := "door"
## Put back: fell out of the world, or the fold turned you back.
const RESPAWN := "respawn"
## R — the whole world goes back.
const RESET := "reset"
const GOAL := "goal"
## A refused action with nothing more specific to say.
const DENY := "deny"

# --- UI ----------------------------------------------------------------------

const UI_MOVE := "ui_move"
const UI_CLICK := "ui_click"

# --- Music -------------------------------------------------------------------
# Track ids, resolved against `assets/audio/music/` the same way.

## The bed for ordinary play.
const MUSIC_REGION := "region"
## The bed inside a fold. A different place should sound like one.
const MUSIC_SUBSPACE := "subspace"


## Applied to any name with no entry below, so an unregistered sound is audible
## and unprocessed rather than silent — a missing REGISTRY line should not look
## like a missing asset.
const DEFAULT := {"vol": 0.0, "pitch": 0.06, "gap": 0.0}

const _REGISTRY := {
	# The fold vocabulary sits at the top of the mix: these are the events the
	# game is about, and the two that cost you something (FOLD, PINCH) are the
	# loudest things in it.
	FOLD:         {"vol":  0.0, "pitch": 0.04, "gap": 0.0},
	PINCH:        {"vol":  0.0, "pitch": 0.03, "gap": 0.0},
	UNFOLD:       {"vol": -1.0, "pitch": 0.04, "gap": 0.0},
	SURFACE:      {"vol": -2.0, "pitch": 0.03, "gap": 0.0},
	TRIGGER:      {"vol": -2.0, "pitch": 0.02, "gap": 0.0},
	BURST:        {"vol": -4.0, "pitch": 0.07, "gap": 0.0},
	FOLD_REFUSED: {"vol": -4.0, "pitch": 0.05, "gap": 0.0},
	# No jitter: this is a countdown starting, and a countdown that arrives at a
	# different pitch each time is harder to learn to recognise.
	PAIR_ARMED:   {"vol": -3.0, "pitch": 0.00, "gap": 0.0},
	HAND_PLACE:   {"vol": -6.0, "pitch": 0.09, "gap": 0.0},

	HAND_PICKUP:  {"vol": -3.0, "pitch": 0.03, "gap": 0.0},
	# NOT throttled, deliberately. A failed fold scatters both its hands in one
	# frame, and two hands out of one fold are supposed to read as two — a gap
	# of any size would swallow the second. The wide pitch jitter is what keeps
	# the simultaneous pair sounding like two objects rather than one loud one.
	HAND_DROP:    {"vol": -8.0, "pitch": 0.10, "gap": 0.0},

	# Movement, all well down in the mix: it plays constantly and it is not what
	# the player is listening for.
	JUMP:         {"vol": -9.0,  "pitch": 0.07, "gap": 0.0},
	LAND:         {"vol": -10.0, "pitch": 0.08, "gap": 0.08},
	# The gap is a floor under the stride, not the stride itself — PlayerBody
	# steps by distance travelled. This only catches the degenerate cases
	# (a body shoved along a wall, a fold landing you mid-run).
	FOOTSTEP:     {"vol": -14.0, "pitch": 0.16, "gap": 0.13},

	DOOR:         {"vol": -5.0, "pitch": 0.03, "gap": 0.0},
	RESPAWN:      {"vol": -4.0, "pitch": 0.02, "gap": 0.0},
	RESET:        {"vol": -4.0, "pitch": 0.00, "gap": 0.0},
	GOAL:         {"vol": -2.0, "pitch": 0.00, "gap": 0.0},
	# Refusals are throttled hardest of anything here. Most of them come from
	# per-frame checks that can hold true for many frames running, and a denial
	# that repeats stops reading as information and starts reading as nagging.
	DENY:         {"vol": -10.0, "pitch": 0.05, "gap": 0.30},

	UI_CLICK:     {"vol": -8.0,  "pitch": 0.03, "gap": 0.0},
	# Fires on every notch of a dragged slider.
	UI_MOVE:      {"vol": -14.0, "pitch": 0.04, "gap": 0.05},
}


## Every registered sound id, in declaration order.
static func all_sounds() -> Array:
	return _REGISTRY.keys()


## Every music track id.
static func all_music() -> Array:
	return [MUSIC_REGION, MUSIC_SUBSPACE]


static func is_registered(id: String) -> bool:
	return _REGISTRY.has(id)


## The full definition for a sound — `DEFAULT` for anything unregistered.
static func get_def(id: String) -> Dictionary:
	return _REGISTRY.get(id, DEFAULT)


## dB trim for this sound.
static func volume_db(id: String) -> float:
	return float(get_def(id)["vol"])


## ± pitch jitter fraction for this sound.
static func pitch_jitter(id: String) -> float:
	return float(get_def(id)["pitch"])


## Seconds this sound refuses to retrigger within.
static func gap(id: String) -> float:
	return float(get_def(id)["gap"])
