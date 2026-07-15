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
##
## Behavior hooks (on_enter / on_fold / on_unfold) are intentionally NOT baked in
## yet; they arrive with the trigger system (F3). `get_def` returns a plain
## Dictionary so those keys can be added without changing call sites.

## Canonical type ids (match the legacy BaseTile / CellPiece ints).
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
## `color` / `display_name` make this registry the single source of truth for tile
## APPEARANCE too, not just behavior. The colors are the exact values previously
## hardcoded in Cell.get_cell_color_for_type (and copy-pasted into FoldController and
## LevelEditor); those consumers now delegate here so a new type is a one-file change.
const _REGISTRY := {
	NULL:  {"walkable": false, "merge_rank": 5, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "color": Color(0.0, 0.0, 0.0, 0.0),   "display_name": "Null"},
	EMPTY: {"walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "color": Color(0.8, 0.8, 0.8),        "display_name": "Empty"},
	WALL:  {"walkable": false, "merge_rank": 3, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "color": Color(0.2, 0.2, 0.2),        "display_name": "Wall"},
	WATER: {"walkable": true,  "merge_rank": 2, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "color": Color(0.2, 0.4, 1.0),        "display_name": "Water"},
	GOAL:  {"walkable": true,  "merge_rank": 4, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "color": Color(0.2, 1.0, 0.2),        "display_name": "Goal"},
	TRIGGER_FOLD: {"walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": false, "on_enter": "fold", "color": Color(1.0, 0.6, 0.1),   "display_name": "Trigger Fold"},
	PIN:          {"walkable": false, "merge_rank": 6, "blocks_fold": true,  "blocks_anchor": false, "on_enter": "",     "color": Color(0.55, 0.1, 0.5),  "display_name": "Pin"},
	UNANCHORABLE_FLOOR: {"walkable": true,  "merge_rank": 1, "blocks_fold": false, "blocks_anchor": true, "on_enter": "", "color": Color(0.75, 0.7, 0.85), "display_name": "Unanchorable Floor"},
	UNANCHORABLE_WALL:  {"walkable": false, "merge_rank": 3, "blocks_fold": false, "blocks_anchor": true, "on_enter": "", "color": Color(0.25, 0.15, 0.3), "display_name": "Unanchorable Wall"},
}

## Safe defaults for an unregistered type: not walkable, lowest rank, non-blocking.
## Unknown types should never be silently walkable. The default color is white, matching
## the legacy `_: return Color(1,1,1)` fallback in Cell.get_cell_color_for_type.
const _DEFAULT := {"walkable": false, "merge_rank": 0, "blocks_fold": false, "blocks_anchor": false, "on_enter": "", "color": Color(1.0, 1.0, 1.0), "display_name": "Unknown"}


## Full definition for a type (falls back to safe defaults for unknown types).
static func get_def(type: int) -> Dictionary:
	return _REGISTRY.get(type, _DEFAULT)


static func is_registered(type: int) -> bool:
	return _REGISTRY.has(type)


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


## Render color for a tile of this type (unknown types fall back to white; NULL is
## transparent). The single source of truth for tile appearance — Cell, FoldController,
## and the level editor palette all delegate here.
static func color_for(type: int) -> Color:
	return get_def(type)["color"]


## Human-readable name for a tile type (used by the editor palette + status readout).
static func display_name(type: int) -> String:
	return get_def(type)["display_name"]


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
