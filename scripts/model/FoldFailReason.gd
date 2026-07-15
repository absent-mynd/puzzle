class_name FoldFailReason extends RefCounted

## FoldFailReason
##
## Turns the engine's terse validation reason strings (returned by
## FoldController.validate_fold / validate_fold_with_player / validate_unfold and
## FoldEngine.player_fold_result) into player-facing copy for an on-screen toast.
## Before this, those reasons were discarded into print() and the player got no
## feedback about WHY a fold was rejected.
##
## Keyed by the exact reason strings the engine emits, so this is the one place that
## canonical set is mapped to human copy — a new engine reason just adds a line here.

const _MESSAGES := {
	# validate_fold
	"engine not initialized": "Something went wrong — try restarting the level.",
	"anchors are the same cell": "Pick two different cells to fold between.",
	"anchor cell does not exist": "You can only anchor a fold on a solid cell.",
	"a pinned tile blocks this fold": "A pinned tile is in the way — it can't be folded.",
	# player_fold_result
	"in_region": "You're standing in the space this fold would remove.",
	"lands_blocked": "You'd be pushed into a wall — there's no room to land.",
	# validate_unfold
	"seam is hidden": "That crease is folded away and can't be unfolded yet.",
	"player would be stranded": "Unfolding here would strand you — move first.",
	"blocked by a newer crossing fold": "A newer fold crosses this crease — undo that one first.",
	# UI-level (not from the engine)
	"needs two anchors": "Select two anchor cells to fold between.",
}

## Generic fallback — also covers the deferred player-position rejection, which fails
## at commit time with an empty reason.
const FALLBACK := "That fold isn't possible here."


## Player-facing message for an engine/UI reason string ("" or unknown -> fallback).
static func message(reason: String) -> String:
	return _MESSAGES.get(reason, FALLBACK)
