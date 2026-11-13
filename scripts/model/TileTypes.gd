class_name TileTypes extends RefCounted

## TileTypes
##
## The single authority for what a tile type IS and DOES. Every per-type fact lives in
## one row of one table here, so a new tile is one row — not a branch in the collider
## loop, another in the merge rule and a third in the editor's palette. Ask it; do not
## switch on a type id (ARCHITECTURE Decision 5).
##
## ## What a row says
##
##   name          what a person calls it — the editor's palette label, and the word a
##                 validation message uses. Here, not in the editor, so that adding a
##                 tile still means editing one file.
##   walkable      can a body be in a cell of this type? (Not "is it floor": air is
##                 walkable. What stops you is everything that is not.)
##   merge_rank    which type wins where a fold lays two pieces in one cell. Strictly
##                 ordered; higher wins.
##   blocks_fold   no fold may cut or excise it (a PIN). Asked of every fold, the
##                 player's and the world's alike — `FoldReplay.blocked_by_tile`.
##   blocks_anchor a hand will not hold in it. Asked at the FUSE, not at placement.
##   swim          a medium the body floats in rather than falls through. Water is the
##                 only one, and it sets `blocks_anchor` with it on purpose: in air your
##                 hands hold and your body falls, in water your body rises and your
##                 hands slip. See `scripts/world/README.md` §"Water".
##   sigil         a thing you find by reaching it, once (`FoldWorld._check_sigils`).
##   on_enter      the reaction it FIRES when the body enters it: "fold" for a trip
##                 plate, "burst" for a burst plate, "" for nothing.
##   on_weight     the reaction it KEEPS UP while something rests on it: "channel" for a
##                 weight plate, "" for nothing. An event and a state are different
##                 questions — one is asked on the frame you arrive, the other every
##                 frame — so they are two columns rather than two values of one.
##   params        the SCHEMA of its per-instance data; see below.
##
## `on_enter` and `on_weight` are strings rather than Callables so the table stays pure
## const data with nothing pointing out of it. `FoldWorld` dispatches on the names.
##
## ## Per-instance parameters
##
## The ASCII grid says what a tile IS; a region's `tile_data` says what this particular
## one DOES. `params` declares the shape of that entry, one dictionary per parameter:
##
##   {"key": String, "type": String, "default": Variant, "label": String, "hint": String,
##    and per-type extras: "count" for cells, "required", "unless"}
##
## `unless` names another key of the same tile: this parameter is not MISSING while that
## one is set. It is how a trip plate says its own anchors are optional once it has a
## channel — a rule between two fields, declared like every other fact about them.
##
## `TileParams` owns what all of that MEANS and is what the editor's inspector is built
## from. So declaring a parameter here is the whole job: it becomes editable, validated,
## drawn and saved without the editor or the loader learning a new name.

## Canonical type ids (shared with BaseTile).
const NULL := -1
const EMPTY := 0
const WALL := 1
const WATER := 2
## The tile a SIGIL is made of. The identifier is older than the word; `name` and
## everything a player reads say sigil.
const GOAL := 3
## A TRIP PLATE: an event. Stepping on it latches its channel, and the world's anchors
## that arm on that channel fold. It may instead carry two cells of its own (`anchors`),
## in which case it drives a pair in there and then. Taking its fold apart puts it back
## to not-yet-stepped-on. The identifier says "trigger"; the prose says trip plate when
## the point is the tense — see `TRIGGER_WEIGHT`.
const TRIGGER_FOLD := 4
## A PIN is a fold-proof obstacle — a nail. It cannot be stood in and no fold may excise
## or cut it, so the space it holds can never be folded away: route around.
const PIN := 5
## An UNANCHORABLE_FLOOR tile is AIR a hand will not hold in: you walk and fall through
## it exactly as through empty space, and a fold pinned in it is refused at the fuse.
##
## The constant says "floor" because that is what it was first used for — a doormat
## that could not be a fold point. What a designer actually needs it for is a VOLUME:
## the air over a pit a player would otherwise leap into to pin from, a shaft that
## must not be pinned up. It is named for that everywhere a person reads it (`name`,
## the tileset); the identifier stays because it is in every world file's history.
const UNANCHORABLE_FLOOR := 6
## An UNANCHORABLE_WALL tile is a wall a hand will not hold in.
const UNANCHORABLE_WALL := 7
## A BURST PLATE fires a BURST when the player enters it — the same sphere the
## player's own hold-and-release makes, centred on the plate instead of on the body,
## at a reach the plate carries in its own `data`. It is the world's half of the
## one-key verb: the tile does the pulling-back, and it can reach further than an arm.
const TRIGGER_BURST := 8
## A WEIGHT PLATE: a state. It keeps a channel live for as long as something is resting
## on it — you, or one of your hands. The world's own anchors arm on the channel, the
## fold they make stands while the plate is down, and it lets go when the weight comes
## off. Where a trip plate asks "did you step here", this asks "is something here now".
## See `Weights`.
const TRIGGER_WEIGHT := 9

## type -> row. `merge_rank` is strictly ordered: pin > void > sigil > wall > water >
## everything else you walk through.
const _REGISTRY := {
	NULL:  {"name": "void",    "walkable": false, "merge_rank": 5, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	EMPTY: {"name": "air",     "walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	WALL:  {"name": "wall",    "walkable": false, "merge_rank": 3, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	WATER: {"name": "water",   "walkable": true,  "merge_rank": 2, "blocks_fold": false, "blocks_anchor": true,  "on_enter": "", "swim": true, "params": []},
	GOAL:  {"name": "sigil",   "walkable": true,  "merge_rank": 4, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "sigil": true, "params": []},
	TRIGGER_FOLD: {"name": "trip plate", "walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "fold",
		"params": [
			{"key": "channel", "type": "string", "default": "", "label": "channel",
			 "hint": "the channel this plate latches when it is stepped on. Two plates on one channel are one fold: whichever is stepped on first makes it, and the other finds it already standing."},
			{"key": "anchors", "type": "cells", "default": [], "count": 2, "required": true, "unless": "channel", "label": "fold anchors",
			 "hint": "the two cells the fired fold is pinned between, in BASE coordinates — they ride earlier folds like anything else. Leave both unset on a plate that has a channel and it only LATCHES the channel, for anchors already standing in the sheet — the form to prefer, because the player can see those before stepping on anything."},
		]},
	TRIGGER_BURST: {"name": "burst plate", "walkable": true, "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "burst",
		"params": [
			{"key": "radius", "type": "float", "default": 1.3, "label": "burst radius",
			 "hint": "how far the burst reaches, IN CELLS. 1.3 is your own reach, so a default plate pops exactly what you could have popped standing on it; wider is the point of a plate — it opens seams you cannot get next to. Zero or less is an inert plate."},
		]},
	TRIGGER_WEIGHT: {"name": "weight plate", "walkable": true, "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "on_weight": "channel",
		"params": [
			{"key": "channel", "type": "string", "default": "", "required": true, "label": "channel",
			 "hint": "the channel this plate keeps live while something rests on it — you, or a hand. Anchors the world has bolted in arm on a channel by name (`arms`), and the fold they make stands only while a plate of that channel is down."},
		]},
	PIN:          {"name": "pin",     "walkable": false, "merge_rank": 6, "blocks_fold": true,  "blocks_anchor": false, "on_enter": "", "params": []},
	UNANCHORABLE_FLOOR: {"name": "unanchorable air", "walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": true, "on_enter": "", "params": []},
	UNANCHORABLE_WALL:  {"name": "unanchorable wall",  "walkable": false, "merge_rank": 3, "blocks_fold": false, "blocks_anchor": true, "on_enter": "", "params": []},
}

## Safe defaults for an unregistered type: not walkable, lowest rank, non-blocking.
## Unknown types should never be silently walkable.
const _DEFAULT := {"name": "unknown", "walkable": false, "merge_rank": 0, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []}


## Full definition for a type (falls back to safe defaults for unknown types).
static func get_def(type: int) -> Dictionary:
	return _REGISTRY.get(type, _DEFAULT)


static func is_registered(type: int) -> bool:
	return _REGISTRY.has(type)


## Every registered type, in id order — for palettes and for tests that assert the
## registry and the authoring characters describe the same set.
static func all_types() -> Array:
	return _REGISTRY.keys()


## The human name of a tile type ("wall", "unanchorable air").
static func type_name(type: int) -> String:
	return get_def(type)["name"]


## The per-instance parameter schema of a tile type — the shape of its `tile_data`
## entry. Empty for most types. `TileParams` is what reads it; see the note on
## `params` in the registry above.
static func params(type: int) -> Array:
	return get_def(type).get("params", [])


## Can the player stand on a complete cell whose dominant type is `type`?
static func is_walkable(type: int) -> bool:
	return get_def(type)["walkable"]


## Co-surface merge priority; higher wins as the dominant type.
static func merge_rank(type: int) -> int:
	return get_def(type)["merge_rank"]


## Does an occupant of this type block a fold that would cut/excise it?
static func blocks_fold(type: int) -> bool:
	return get_def(type)["blocks_fold"]


## Can this tile type be used as a fold anchor? Returns true if anchor placement
## on a cell of this type should be rejected.
static func blocks_anchor(type: int) -> bool:
	return get_def(type)["blocks_anchor"]


## Name of the reaction fired when the player enters a tile of this type ("" = none).
static func on_enter_kind(type: int) -> String:
	return get_def(type).get("on_enter", "")



## Name of the reaction a tile of this type keeps up while something rests on it ("" = none).
static func on_weight_kind(type: int) -> String:
	return get_def(type).get("on_weight", "")


## Does a hand set down here become a WEIGHT rather than an anchor? True exactly when
## the tile has something to press: the hand is pressing, not gripping, so it reaches for
## no partner (`FoldWorld.place_hand`).
static func is_weighable(type: int) -> bool:
	return on_weight_kind(type) != ""


## Is this a tile you find by reaching it?
static func is_sigil(type: int) -> bool:
	return bool(get_def(type).get("sigil", false))


## Is this a medium the body swims in rather than falls through?
static func is_swim(type: int) -> bool:
	return bool(get_def(type).get("swim", false))


## Resolve a stack of co-surface piece types to the dominant one. Returns EMPTY for
## an empty list. Ties keep the earlier-encountered type (strict-greater compare),
## matching the legacy loops in FoldedState.dominant_type_at / Cell.get_dominant_type.
static func dominant_type(types: Array) -> int:
	var best_type := EMPTY
	var best_rank := -1
	var any := false
	for t in types:
		any = true
		var rank := merge_rank(t)
		if rank > best_rank:
			best_rank = rank
			best_type = t
	if not any:
		return EMPTY
	return best_type
