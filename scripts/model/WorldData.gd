class_name WorldData
extends Resource

## WorldData
##
## The authored definition of a world: a set of REGIONS (each its own sheet of foldable
## space) plus the DOORS that connect them. Serializes to/from JSON.
##
## Replaces the old per-level LevelData. Two things changed with the pivot:
##
##   - A world is not a space. There is no par, no fold budget, no difficulty rating,
##     no win condition to score — the goal is somewhere in the world, and reaching it
##     is the whole game. What used to be "which level" is now "which region".
##   - Tiles are authored as ASCII ROWS, not a sparse position->type dictionary. For a
##     side-view world the shape of the terrain is the content, and a grid of characters
##     shows it directly. `WorldCore.CHARS` owns the character mapping.
##
## Per-tile parameters (trigger channels and anchors, entity declarations) live in
## `tile_data`, keyed "x,y" — the ASCII grid says what a tile IS, `tile_data` says what
## this particular one DOES.
##
## `folds` on a region are PRE-PLACED: applied at load, before the player spawns. A fold
## hides everything between its creases, so a pre-placed fold ships a region already
## folded, with content sealed inside it that unfolding (or a door) reveals.
##
## A fold entry is `{"anchor1": {x,y}, "anchor2": {x,y}, "in": [i, ...]}`. `in` is the
## INDEX PATH of the subspaces this fold lives in — `[]` (or absent) is the region's own
## sheet, `[0]` is inside the subspace of the region's first pre-placed fold, `[0, 1]`
## one step deeper. It is reserved, not yet implemented: `fold_pairs` returns only
## region-level entries, so a nested one is authored, saved and drawn by the editor but
## does NOT ship folded. See `docs/features/WORLD_EDITOR.md` §"Nested pre-placed folds"
## for what implementing it would take. Ignoring it is the deliberate choice — applying
## a nested fold's anchors in a region would fold a stranger part of the region.

## Prefix of the command-line flag that names a world file to open instead of the
## shipped one: `-- --world=res://worlds/testbed.json`.
const WORLD_FLAG := "--world="


@export var world_id: String = ""
@export var world_name: String = ""
@export var cell_size: float = 64.0

## Region id the player spawns in.
@export var start_region: String = ""

## The hands the player starts the world holding, as `HandTypes` authoring keys —
## e.g. `["plain", "plain"]`. One entry per filled slot; fewer than `HandStock.SLOTS`
## entries starts you short-handed, which is a legitimate thing for a world to do.
## Entries beyond `SLOTS` are ignored, since you cannot hold them.
##
## This is not a capacity: the number you can hold is fixed (`HandStock.SLOTS`).
## What a world chooses here is which KINDS you set out with.
@export var starting_hands: Array = ["plain", "plain"]

## region id -> {
##   "rows":      Array[String],  ASCII terrain (see WorldCore.CHARS)
##   "spawn":     Vector2,        spawn point, in CELL units (0.5 = cell center)
##   "tile_data": Dictionary,     "x,y" -> per-tile params
##   "folds":     Array,          pre-placed folds, [{anchor1:{x,y}, anchor2:{x,y}}, ...]
##   "lights":    Array[LightSource], lights placed on base cells (see LightSource)
##   "hands":     Array[HandPickup], loose hands lying on base cells (see HandPickup)
##   "editor":    Dictionary,     AUTHORING ONLY — see below. The game never reads it.
## }
##
## `editor` is the world editor's scratch space, carried through the file so a
## half-finished design survives a save. Nothing in `scripts/world/` may read it:
## a region's PLACE on the editor board is not a fact about the world (regions have
## no spatial relationship to each other — they are separate sheets), and a fold
## anchor waiting for a partner is not a fold. Both are facts about the DESIGN.
##
##   "pos":     {"x": float, "y": float}  where this region's card sits on the board
##   "anchors": [{"x": int, "y": int}]    fold anchors placed but not yet connected
@export var regions: Dictionary = {}

## door id -> {"region": String, "cell": Vector2i, "pair": door id}
@export var doors: Dictionary = {}

@export var metadata: Dictionary = {}


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out_regions: Dictionary = {}
	for id in regions:
		var r: Dictionary = regions[id]
		var out_lights: Array = []
		for light in r.get("lights", []):
			out_lights.append(light.to_dict())
		var out_hands: Array = []
		for pickup in r.get("hands", []):
			out_hands.append(pickup.to_dict())
		out_regions[id] = {
			"rows": (r.get("rows", []) as Array).duplicate(),
			"spawn": {"x": r.get("spawn", Vector2.ZERO).x, "y": r.get("spawn", Vector2.ZERO).y},
			"tile_data": (r.get("tile_data", {}) as Dictionary).duplicate(true),
			"folds": (r.get("folds", []) as Array).duplicate(true),
			"lights": out_lights,
			"hands": out_hands,
			"editor": (r.get("editor", {}) as Dictionary).duplicate(true),
		}
	var out_doors: Dictionary = {}
	for id in doors:
		var d: Dictionary = doors[id]
		var c: Vector2i = d.get("cell", Vector2i.ZERO)
		out_doors[id] = {"region": d.get("region", ""), "cell": {"x": c.x, "y": c.y},
			"pair": d.get("pair", "")}
	return {
		"world_id": world_id,
		"world_name": world_name,
		"cell_size": cell_size,
		"start_region": start_region,
		"starting_hands": starting_hands.duplicate(),
		"regions": out_regions,
		"doors": out_doors,
		"metadata": metadata,
	}


func from_dict(dict: Dictionary) -> void:
	world_id = dict.get("world_id", "")
	world_name = dict.get("world_name", "")
	cell_size = float(dict.get("cell_size", 64.0))
	start_region = dict.get("start_region", "")
	starting_hands = []
	for key in dict.get("starting_hands", ["plain", "plain"]):
		starting_hands.append(String(key))
	metadata = dict.get("metadata", {})

	regions = {}
	for id in dict.get("regions", {}):
		var r: Dictionary = dict["regions"][id]
		var rows: Array = []
		for row in r.get("rows", []):
			rows.append(String(row))
		var sp: Dictionary = r.get("spawn", {})
		var lights: Array = []
		for entry in r.get("lights", []):
			var light := LightSource.from_dict(entry)
			light.region = id
			lights.append(light)
		var hands: Array = []
		for entry in r.get("hands", []):
			var pickup := HandPickup.from_dict(entry)
			pickup.region = id
			hands.append(pickup)
		regions[id] = {
			"rows": rows,
			"spawn": Vector2(float(sp.get("x", 0.0)), float(sp.get("y", 0.0))),
			"tile_data": r.get("tile_data", {}),
			"folds": r.get("folds", []),
			"lights": lights,
			"hands": hands,
			"editor": (r.get("editor", {}) as Dictionary).duplicate(true),
		}

	doors = {}
	for id in dict.get("doors", {}):
		var d: Dictionary = dict["doors"][id]
		var c: Dictionary = d.get("cell", {})
		doors[id] = {
			"region": d.get("region", ""),
			"cell": Vector2i(int(c.get("x", 0)), int(c.get("y", 0))),
			"pair": d.get("pair", ""),
		}


## Which world file this run should open: `--world=...` if the flag was passed after
## `--`, else `fallback`. A flag rather than a menu because the usual case is "the
## world", and the unusual one — a debug world, a world you are editing — is a shell
## away and wants the SAME answer in the game and in the editor. Both call this.
static func selected_path(fallback: String) -> String:
	return path_from_args(OS.get_cmdline_user_args(), fallback)


## The pure half of `selected_path`, so the flag's spelling is testable without a
## process to pass it to. A bare name is taken as `res://worlds/<name>.json`, so
## `--world=testbed` works; anything with a separator or an extension is used as
## written. The LAST flag wins, which is what a shell alias plus an override means.
static func path_from_args(args, fallback: String) -> String:
	var chosen := fallback
	for arg in args:
		var text := String(arg)
		if not text.begins_with(WORLD_FLAG):
			continue
		var value := text.substr(WORLD_FLAG.length()).strip_edges()
		if value.is_empty():
			continue
		chosen = value if (value.contains("/") or value.contains(".")) \
			else "res://worlds/%s.json" % value
	return chosen


## Load a world from a JSON file. Returns null on any read/parse failure.
static func load_from(path: String) -> WorldData:
	if not FileAccess.file_exists(path):
		push_error("WorldData: no such file: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("WorldData: cannot open %s" % path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("WorldData: %s is not a JSON object" % path)
		return null
	var wd := WorldData.new()
	wd.from_dict(parsed)
	return wd


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("WorldData: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true


# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

func has_region(id: String) -> bool:
	return regions.has(id)


## Build the BaseGrid for a region (ASCII rows + per-tile data).
func build_base(id: String) -> BaseGrid:
	if not regions.has(id):
		return null
	var r: Dictionary = regions[id]
	return WorldCore.parse_map(r["rows"], cell_size, r.get("tile_data", {}))


## Spawn point of a region in PIXELS.
func spawn_px(id: String) -> Vector2:
	if not regions.has(id):
		return Vector2.ZERO
	return (regions[id]["spawn"] as Vector2) * cell_size


## A region's OWN pre-placed folds — the ones not nested inside another — as [anchor1, anchor2] Vector2i pairs, in
## order. Entries with a non-empty `in` path are nested inside another fold's subspace
## and are SKIPPED: the world boot applies this list to the region's own sheet, and a
## nested fold's anchors mean nothing there. See the `folds` note in the header.
func fold_pairs(id: String) -> Array:
	var out: Array = []
	if not regions.has(id):
		return out
	for f in regions[id].get("folds", []):
		if not (f.get("in", []) as Array).is_empty():
			continue
		var a: Dictionary = f.get("anchor1", {})
		var b: Dictionary = f.get("anchor2", {})
		out.append([
			Vector2i(int(a.get("x", 0)), int(a.get("y", 0))),
			Vector2i(int(b.get("x", 0)), int(b.get("y", 0))),
		])
	return out


## The board position of a region's card in the editor, in world px. Authoring only —
## see the `editor` note in the header. `Vector2.ZERO` when the region has never been
## placed, which the editor treats as "needs a home" rather than "belongs at the origin".
func board_pos(id: String) -> Vector2:
	if not regions.has(id):
		return Vector2.ZERO
	var e: Dictionary = regions[id].get("editor", {})
	var p: Dictionary = e.get("pos", {})
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))


## Fold anchors placed in a region but not yet connected to a partner, as Vector2i
## cells. Authoring only: an unpaired anchor is a design in progress, not a fold.
func unpaired_anchors(id: String) -> Array:
	var out: Array = []
	if not regions.has(id):
		return out
	var e: Dictionary = regions[id].get("editor", {})
	for a in e.get("anchors", []):
		out.append(Vector2i(int(a.get("x", 0)), int(a.get("y", 0))))
	return out


## The grid shape of a region, in cells, read off its ASCII rows. Rows are padded to
## the widest one when parsed (`WorldCore.parse_map`), so the width is the widest row.
func region_size(id: String) -> Vector2i:
	if not regions.has(id):
		return Vector2i.ZERO
	var rows: Array = regions[id].get("rows", [])
	var w := 0
	for row in rows:
		w = maxi(w, String(row).length())
	return Vector2i(w, rows.size())


## The starting hands as a slot array: `HandTypes` ids, one entry per slot, `null`
## where the world starts you empty-handed. Always exactly `HandStock.SLOTS` long,
## so callers never have to think about a short or over-long authored list.
func starting_hand_slots() -> Array:
	var out: Array = HandStock.empty_slots()
	for i in range(mini(starting_hands.size(), out.size())):
		out[i] = HandTypes.from_name(String(starting_hands[i]))
	return out


## A region's authored loose hands, as fresh unbound copies — same reasoning as
## `lights_of`: binding writes into them, and a reset must re-bind from the authored
## world rather than from whatever the last session did to it.
func hands_of(id: String) -> Array:
	var out: Array = []
	if not regions.has(id):
		return out
	for pickup in regions[id].get("hands", []):
		out.append(pickup.duplicate_pickup())
	return out


## A region's authored lights, as fresh unbound `LightSource` copies. Copies,
## because binding writes `base_id`/`bp` into them and the authored world must
## stay the authored world (a reset re-binds from scratch).
func lights_of(id: String) -> Array:
	var out: Array = []
	if not regions.has(id):
		return out
	for light in regions[id].get("lights", []):
		out.append(light.duplicate_light())
	return out


func clone() -> WorldData:
	var copy := WorldData.new()
	copy.from_dict(to_dict())
	return copy
