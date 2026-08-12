class_name TileTypes extends RefCounted

## TileTypes
##
## The single authority for what a tile type IS and DOES. Before this, the type
## int (0=empty, 1=wall, 2=water, 3=goal, -1=null) was switched on in ~6 places
## (FoldedState merge priority, Cell.get_dominant_type, Player.can_move_to, ...),
## so adding a type meant editing every site. This registry centralizes the
## per-type facts and — as the game grows — the per-type behavior hooks, so a new
## tile ("destroys pieces", "triggers an unfold", "blocks folding") can be added in
## ONE place without touching the engine.
##
## Per-type definition fields:
##   walkable    : can the player stand on a complete cell of this type?
##   merge_rank  : co-surface merge priority (higher wins as the dominant type when
##                 several pieces share a plane position). null > goal > wall >
##                 water > empty reproduces the two legacy orderings exactly.
##   blocks_fold : does an occupant of this type block a fold that would cut/excise
##                 it? (Consumed by the general fold-block predicate — F5.)
## Behavior hooks (on_enter / on_fold / on_unfold) are intentionally NOT baked in
## yet; they arrive with the trigger system (F3). `get_def` returns a plain
## Dictionary so those keys can be added without changing call sites.

## Canonical type ids (shared with BaseTile).
const NULL := -1
const EMPTY := 0
const WALL := 1
const WATER := 2
const GOAL := 3
## Behavioral tiles (F3). TRIGGER_FOLD fires a fold when the player enters it; its
## parameters (channel, anchors) live in the tile's per-instance `data`.
const TRIGGER_FOLD := 4
## A PIN (F5) is a fold-proof obstacle: it cannot be stood on and no fold may excise
## or cut it, so the space it holds can never be folded away — you must route around.
const PIN := 5
## An UNANCHORABLE_FLOOR tile is walkable but cannot be used as a fold anchor.
## Useful for decorative or structural floor areas that should never be a fold point.
const UNANCHORABLE_FLOOR := 6
## An UNANCHORABLE_WALL tile is not walkable (like a wall) and also cannot be used
## as a fold anchor. Useful for walls that must never become fold reference points.
const UNANCHORABLE_WALL := 7

## type -> definition. Keep merge_rank strictly ordered: null(5) > goal(4) >
## wall(3) > water(2) > empty(1). FoldedState never produces null pieces, so its
## ordering (goal > wall > water > empty) falls out of the same ranks; Cell view
## code that can still see legacy null pieces gets null-on-top for free.
## `on_enter` names the reaction a tile fires when the player enters it (""=none).
## The reaction's parameters come from the tile's per-instance `data`; the resolver
## (TriggerResolver) interprets the name. Kept as a string, not a Callable, so the
## registry stays a pure const data table.
##
## `name` is what a human calls this tile — the label the world editor's palette
## shows. It lives here rather than in the editor because a new tile type must
## still mean editing ONE file; a palette that kept its own name table would be a
## second place to forget.
##
## `params` DECLARES the per-instance parameters a tile of this type takes — the
## shape of its entry in a region's `tile_data`. The ASCII grid says what a tile
## IS; `tile_data` says what this particular one DOES, and this is the schema of
## that "does". Each entry is:
##
##   {"key": String, "type": String, "default": Variant, "label": String,
##    "hint": String, and per-type extras}
##
## `type` is a plain string, not a constant from elsewhere, for the same reason
## `on_enter` is — the registry stays a pure const data table with no outbound
## references. `TileParams` owns what those names MEAN, validates against them,
## and is what the editor generates its inspector from. So a new parameter on a
## new tile type becomes editable, validated and saved without the editor
## learning anything: it is still ONE file to touch.
const _REGISTRY := {
	NULL:  {"name": "void",    "walkable": false, "merge_rank": 5, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	EMPTY: {"name": "air",     "walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	WALL:  {"name": "wall",    "walkable": false, "merge_rank": 3, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	WATER: {"name": "water",   "walkable": true,  "merge_rank": 2, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	GOAL:  {"name": "goal",    "walkable": true,  "merge_rank": 4, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "params": []},
	TRIGGER_FOLD: {"name": "trigger", "walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "fold",
		"params": [
			{"key": "channel", "type": "string", "default": "", "label": "channel",
			 "hint": "names the fold this plate makes. Two plates on one channel are one fold: whichever fires first makes it, and the other finds it already standing."},
			{"key": "anchors", "type": "cells", "default": [], "count": 2, "required": true, "label": "fold anchors",
			 "hint": "the two cells the fired fold is pinned between, in BASE coordinates — they ride earlier folds like anything else."},
		]},
	PIN:          {"name": "pin",     "walkable": false, "merge_rank": 6, "blocks_fold": true,  "blocks_anchor": false, "on_enter": "", "params": []},
	UNANCHORABLE_FLOOR: {"name": "unanchorable floor", "walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": true, "on_enter": "", "params": []},
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


## The human name of a tile type ("wall", "unanchorable floor").
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
