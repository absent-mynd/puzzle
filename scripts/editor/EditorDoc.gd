class_name EditorDoc extends RefCounted

## EditorDoc
##
## The level editor's DOCUMENT: a `WorldData` plus the history around it. Every
## change the editor makes to a world goes through a method here, and nothing here
## knows about a mouse, a Node or a draw call.
##
## Three rules shape it:
##
##   - **A mutation is a method, not a poke at a Dictionary.** `WorldData.regions`
##     is a nest of untyped dictionaries; letting the view reach into it would put
##     the shape of the file in five places. Here it is in one, and a headless test
##     can assert every operation.
##   - **Undo is DOCUMENT history, not fold history.** `AGENTS.md` §"the 2026-08-04
##     consolidation" says the game has no undo, and it still does not — that is
##     about a continuous physics world having no discrete move to reverse. An
##     editor is a different thing: it edits a file, and a paint tool without undo
##     is not a paint tool. The two never meet, because this stack holds authored
##     worlds and the game's fold list holds play state.
##   - **Snapshots, for the same reason the kernel derives.** History is a list of
##     `to_dict()` results; undo restores one. No per-operation inverse to get
##     wrong, no partial rollback, and it composes with operations (resize, region
##     delete) that touch six collections at once.
##
## Coalescing: a brush drag is ONE undo step. Mutators take a `tag`, and two
## consecutive mutations with the same non-empty tag share a snapshot. The view
## calls `end_gesture()` when the mouse comes up.

const MAX_HISTORY := 128

## The world being edited. Never replaced in place by a mutator — see `_snapshot`.
var world: WorldData = null

## Where `save()` writes. "" until loaded from or saved to somewhere.
var path: String = ""

## True when there are changes not yet written to `path`.
var dirty: bool = false

var _undo: Array = []
var _redo: Array = []
var _tag: String = ""
var _batch: int = 0


static func create_empty(world_id: String = "world") -> EditorDoc:
	var doc := EditorDoc.new()
	doc.world = WorldData.new()
	doc.world.world_id = world_id
	doc.world.world_name = world_id.capitalize()
	doc.world.cell_size = WorldCore.CELL
	return doc


static func load_from(p_path: String) -> EditorDoc:
	var wd := WorldData.load_from(p_path)
	if wd == null:
		return null
	var doc := EditorDoc.new()
	doc.world = wd
	doc.path = p_path
	return doc


func save() -> bool:
	if path == "":
		return false
	if not world.save_to(path):
		return false
	dirty = false
	return true


func save_as(p_path: String) -> bool:
	path = p_path
	return save()


# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------

## Record the pre-change state, unless this mutation continues a tagged gesture
## that already recorded one. Every mutator calls this FIRST, before touching
## anything, so a snapshot is always the state the operation started from.
func _snapshot(tag: String) -> void:
	dirty = true
	if _batch > 0:
		return
	if tag != "" and tag == _tag:
		return
	_tag = tag
	_undo.append(world.to_dict())
	_redo.clear()
	if _undo.size() > MAX_HISTORY:
		_undo.pop_front()


## A composite operation is ONE undo step. Between `_begin_batch` and `_end_batch`
## the mutators it calls still work, but their snapshots are suppressed — a resize
## that moves doors, lights, hands and the card must not cost four undos to take
## back. The caller snapshots once before opening the batch.
func _begin_batch() -> void:
	_batch += 1


func _end_batch() -> void:
	_batch = maxi(_batch - 1, 0)


## End a coalescing gesture (mouse up). The next mutation starts a new undo step
## even if it carries the same tag.
func end_gesture() -> void:
	_tag = ""


## Forget the history. Called after opening a file: the placement pass that gives
## hand-authored regions a card position is a real mutation, but "undo" back to a
## world where the cards are stacked at the origin is not a state anyone wants.
func clear_history() -> void:
	_undo.clear()
	_redo.clear()
	_tag = ""
	dirty = false


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(world.to_dict())
	_restore(_undo.pop_back())
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(world.to_dict())
	_restore(_redo.pop_back())
	return true


## Reload `world` from a snapshot. Mutates the existing WorldData rather than
## swapping the reference, so anything holding onto `doc.world` stays valid.
func _restore(snap: Dictionary) -> void:
	world.from_dict(snap)
	dirty = true
	_tag = ""


# ---------------------------------------------------------------------------
# Regions — the canvases
# ---------------------------------------------------------------------------

func region_ids() -> Array:
	var out: Array = world.regions.keys()
	out.sort()
	return out


func has_region(id: String) -> bool:
	return world.regions.has(id)


func region(id: String) -> Dictionary:
	return world.regions.get(id, {})


func size_of(id: String) -> Vector2i:
	return world.region_size(id)


## A fresh canvas. Fails on a duplicate or empty id; the first region added also
## becomes the start region, since a world with no start region cannot boot.
func add_region(id: String, size: Vector2i, at: Vector2 = Vector2.INF, tag: String = "") -> bool:
	if id.strip_edges() == "" or world.regions.has(id):
		return false
	size = Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	_snapshot(tag)
	var pos := suggest_position() if at == Vector2.INF else at
	world.regions[id] = {
		"rows": EditorTools.resize_rows([], Vector2i.ZERO, size),
		"spawn": Vector2(size.x * 0.5, size.y * 0.5),
		"tile_data": {},
		"folds": [],
		"lights": [],
		"hands": [],
		"editor": {"pos": {"x": pos.x, "y": pos.y}, "anchors": []},
	}
	if world.start_region == "" or not world.regions.has(world.start_region):
		world.start_region = id
	return true


## Delete a canvas, and with it every door in it. A door's partner is left
## UNPAIRED rather than deleted — the far side is a real door in a region that
## still exists, and silently removing it would delete work in a region the user
## was not looking at. `validate()` then reports it as dangling, which is the
## honest state of the world.
func remove_region(id: String, tag: String = "") -> bool:
	if not world.regions.has(id):
		return false
	_snapshot(tag)
	world.regions.erase(id)
	for door_id in world.doors.keys():
		if world.doors[door_id]["region"] == id:
			_clear_pairing(door_id)
			world.doors.erase(door_id)
	if world.start_region == id:
		var left := region_ids()
		world.start_region = String(left[0]) if not left.is_empty() else ""
	return true


func rename_region(from_id: String, to_id: String, tag: String = "") -> bool:
	to_id = to_id.strip_edges()
	if from_id == to_id or to_id == "" or not world.regions.has(from_id) or world.regions.has(to_id):
		return false
	_snapshot(tag)
	# Rebuild in order so the region list does not reshuffle on a rename.
	var rebuilt: Dictionary = {}
	for id in world.regions:
		rebuilt[to_id if id == from_id else id] = world.regions[id]
	world.regions = rebuilt
	for door_id in world.doors:
		if world.doors[door_id]["region"] == from_id:
			world.doors[door_id]["region"] = to_id
	for r in world.regions.values():
		for light in r.get("lights", []):
			if light.region == from_id:
				light.region = to_id
		for pickup in r.get("hands", []):
			if pickup.region == from_id:
				pickup.region = to_id
	if world.start_region == from_id:
		world.start_region = to_id
	return true


func set_start_region(id: String, tag: String = "") -> bool:
	if not world.regions.has(id) or world.start_region == id:
		return false
	_snapshot(tag)
	world.start_region = id
	return true


## Where a region's card sits on the board. Authoring only, and the reason it can
## be moved freely: regions are separate sheets with no spatial relationship, so
## the board is a place to THINK, not a map. Nothing in the game reads it.
func move_region(id: String, pos: Vector2, tag: String = "") -> bool:
	if not world.regions.has(id):
		return false
	_snapshot(tag)
	_editor_block(id)["pos"] = {"x": pos.x, "y": pos.y}
	return true


## A free spot for a new card: to the right of the rightmost one, on its top line.
## Only a starting point — the whole idea of the board is that you then drag it
## somewhere that means something to you.
func suggest_position() -> Vector2:
	var gap := WorldCore.CELL * 3.0
	var right := -gap
	var top := 0.0
	for id in world.regions:
		var p := world.board_pos(id)
		var s := Vector2(world.region_size(id)) * world.cell_size
		if p.x + s.x > right:
			right = p.x + s.x
			top = p.y
	return Vector2(right + gap, top)


## Reshape a canvas: the old grid's origin lands at `offset` in a new grid of
## `size`. One call is every edge and both directions (see
## `EditorTools.resize_rows`), and everything cell-addressed in the region moves
## with the terrain — otherwise dragging the left edge would slide the walls out
## from under the doors.
##
## The card's board position moves the opposite way, so growing an edge leaves the
## terrain visually where it was and pushes the card's boundary outward instead.
## Content that falls outside the new grid is dropped; the count comes back so the
## caller can say so.
func resize_region(id: String, offset: Vector2i, size: Vector2i, tag: String = "") -> int:
	if not world.regions.has(id):
		return -1
	size = Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	var old := size_of(id)
	if offset == Vector2i.ZERO and size == old:
		return 0
	_snapshot(tag)
	_begin_batch()
	var r: Dictionary = world.regions[id]
	var dropped := 0

	r["rows"] = EditorTools.resize_rows(r.get("rows", []), offset, size)
	var td: Dictionary = r.get("tile_data", {})
	var moved := EditorTools.shift_cell_keys(td, offset, size)
	dropped += td.size() - moved.size()
	r["tile_data"] = moved

	r["spawn"] = (r.get("spawn", Vector2.ZERO) as Vector2) + Vector2(offset)

	var folds: Array = []
	for f in r.get("folds", []):
		var a := _cell_of(f.get("anchor1", {})) + offset
		var b := _cell_of(f.get("anchor2", {})) + offset
		if not (EditorTools.in_bounds(a, size) and EditorTools.in_bounds(b, size)):
			dropped += 1
			continue
		var moved_fold: Dictionary = (f as Dictionary).duplicate(true)
		moved_fold["anchor1"] = {"x": a.x, "y": a.y}
		moved_fold["anchor2"] = {"x": b.x, "y": b.y}
		folds.append(moved_fold)
	r["folds"] = folds

	var anchors: Array = []
	for a in world.loose_anchors(id):
		var dst: Vector2i = a + offset
		if EditorTools.in_bounds(dst, size):
			anchors.append({"x": dst.x, "y": dst.y})
		else:
			dropped += 1
	_editor_block(id)["anchors"] = anchors

	var lights: Array = []
	for light in r.get("lights", []):
		if EditorTools.in_bounds(light.cell + offset, size):
			light.cell += offset
			lights.append(light)
		else:
			dropped += 1
	r["lights"] = lights

	var hands: Array = []
	for pickup in r.get("hands", []):
		if EditorTools.in_bounds(pickup.cell + offset, size):
			pickup.cell += offset
			hands.append(pickup)
		else:
			dropped += 1
	r["hands"] = hands

	for door_id in world.doors.keys():
		var d: Dictionary = world.doors[door_id]
		if d["region"] != id:
			continue
		var dst: Vector2i = (d["cell"] as Vector2i) + offset
		if EditorTools.in_bounds(dst, size):
			d["cell"] = dst
		else:
			_clear_pairing(door_id)
			world.doors.erase(door_id)
			dropped += 1

	move_region(id, world.board_pos(id) - Vector2(offset) * world.cell_size, tag)
	_end_batch()
	return dropped


# ---------------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------------

func char_at(id: String, cell: Vector2i) -> String:
	if not world.regions.has(id):
		return ""
	return EditorTools.char_at(world.regions[id].get("rows", []), cell)


func paint(id: String, cell: Vector2i, ch: String, tag: String = "paint") -> bool:
	return paint_cells(id, [cell], ch, tag)


## Paint a set of cells in one step. Returns false and records nothing when the
## stroke would change nothing — a no-op must not push an undo step, or undo
## after hovering becomes a lottery.
func paint_cells(id: String, cells: Array, ch: String, tag: String = "paint") -> bool:
	if not world.regions.has(id):
		return false
	var rows: Array = world.regions[id].get("rows", [])
	var size := EditorTools.grid_size(rows)
	var changed := false
	for c in cells:
		var cell: Vector2i = c
		if EditorTools.in_bounds(cell, size) and EditorTools.char_at(rows, cell) != ch:
			changed = true
			break
	if not changed:
		return false
	_snapshot(tag)
	world.regions[id]["rows"] = EditorTools.paint_many(rows, cells, ch)
	return true


func fill_rect(id: String, a: Vector2i, b: Vector2i, ch: String, tag: String = "") -> bool:
	return paint_cells(id, EditorTools.rect_cells(a, b), ch, tag)


func set_spawn(id: String, at: Vector2, tag: String = "") -> bool:
	if not world.regions.has(id):
		return false
	_snapshot(tag)
	world.regions[id]["spawn"] = at
	return true


# ---------------------------------------------------------------------------
# Doors
# ---------------------------------------------------------------------------

## The door at a cell, or "" — one door per cell, since a door is a warp POINT at
## a base tile's centre and two of them would resolve to the same place.
func door_at(id: String, cell: Vector2i) -> String:
	for door_id in world.doors:
		var d: Dictionary = world.doors[door_id]
		if d["region"] == id and d["cell"] == cell:
			return String(door_id)
	return ""


## Place an unpaired door. Ids are generated from the region name (`west_1`) so a
## file stays readable, and a door starts life unpaired — pairing is the drag.
func add_door(id: String, cell: Vector2i, tag: String = "") -> String:
	if not world.regions.has(id) or door_at(id, cell) != "":
		return ""
	if not EditorTools.in_bounds(cell, size_of(id)):
		return ""
	_snapshot(tag)
	var door_id := _unique_door_id(id)
	world.doors[door_id] = {"region": id, "cell": cell, "pair": ""}
	return door_id


func remove_door(door_id: String, tag: String = "") -> bool:
	if not world.doors.has(door_id):
		return false
	_snapshot(tag)
	_clear_pairing(door_id)
	world.doors.erase(door_id)
	return true


## Pair two doors, in either order and across regions. Each side's PREVIOUS partner
## is unpaired first, so a door never ends up pointing at a door that points
## somewhere else — `FoldWorld` resolves a door by following `pair`, and a
## one-way link would send the player through a door that cannot send them back.
func link_doors(a: String, b: String, tag: String = "") -> bool:
	if a == b or not world.doors.has(a) or not world.doors.has(b):
		return false
	_snapshot(tag)
	_clear_pairing(a)
	_clear_pairing(b)
	world.doors[a]["pair"] = b
	world.doors[b]["pair"] = a
	return true


func unlink_door(door_id: String, tag: String = "") -> bool:
	if not world.doors.has(door_id) or world.doors[door_id]["pair"] == "":
		return false
	_snapshot(tag)
	_clear_pairing(door_id)
	return true


## Break `door_id`'s pairing from BOTH sides, without recording history — the
## callers above have already snapshotted.
func _clear_pairing(door_id: String) -> void:
	if not world.doors.has(door_id):
		return
	var partner := String(world.doors[door_id]["pair"])
	world.doors[door_id]["pair"] = ""
	if world.doors.has(partner) and world.doors[partner]["pair"] == door_id:
		world.doors[partner]["pair"] = ""


func _unique_door_id(region_id: String) -> String:
	var stem := region_id.strip_edges().to_lower().replace(" ", "_")
	if stem == "":
		stem = "door"
	var n := 1
	while world.doors.has("%s_%d" % [stem, n]):
		n += 1
	return "%s_%d" % [stem, n]


# ---------------------------------------------------------------------------
# Pre-placed folds — anchors, and the drag that connects two of them
# ---------------------------------------------------------------------------

## A fold is authored the way the player makes one: pin an anchor, pin another,
## and the pair becomes a fold. The difference is that an editor anchor waits
## indefinitely — it is saved as a loose anchor in the region's `editor` block, so
## a design left half-finished on Friday is still half-finished on Monday.

func anchors_of(id: String) -> Array:
	return world.loose_anchors(id)


func has_anchor(id: String, cell: Vector2i) -> bool:
	return world.loose_anchors(id).has(cell)


func add_anchor(id: String, cell: Vector2i, tag: String = "") -> bool:
	if not world.regions.has(id) or not EditorTools.in_bounds(cell, size_of(id)):
		return false
	if has_anchor(id, cell):
		return false
	_snapshot(tag)
	var list: Array = _editor_block(id).get("anchors", [])
	list.append({"x": cell.x, "y": cell.y})
	_editor_block(id)["anchors"] = list
	return true


func remove_anchor(id: String, cell: Vector2i, tag: String = "") -> bool:
	if not has_anchor(id, cell):
		return false
	_snapshot(tag)
	var list: Array = []
	for a in world.loose_anchors(id):
		if a != cell:
			list.append({"x": a.x, "y": a.y})
	_editor_block(id)["anchors"] = list
	return true


## The pre-placed folds of a region, as `{"a": Vector2i, "b": Vector2i,
## "in": Array}` in file order. `in` is the nesting path — always empty today; see
## the `folds` note in `WorldData`.
func folds_of(id: String) -> Array:
	var out: Array = []
	if not world.regions.has(id):
		return out
	for f in world.regions[id].get("folds", []):
		out.append({
			"a": _cell_of(f.get("anchor1", {})),
			"b": _cell_of(f.get("anchor2", {})),
			"in": (f.get("in", []) as Array).duplicate(),
		})
	return out


## Connect two placed anchors into a pre-placed fold, consuming both.
##
## The one pair that is never a fold is two anchors on the same cell: it has no
## crease direction at all. Everything else is allowed here on purpose — the
## surface rules the PLAYER's folds answer to are asked at the fuse, of a fold
## being made in a live world, and an author placing a fold in a region is not
## standing in it. `validate()` reports the questionable ones instead of refusing
## them, so a design can be laid down before it is made legal.
func connect_anchors(id: String, a: Vector2i, b: Vector2i, tag: String = "") -> int:
	if not world.regions.has(id) or a == b:
		return -1
	if not (has_anchor(id, a) and has_anchor(id, b)):
		return -1
	_snapshot(tag)
	_begin_batch()
	remove_anchor(id, a, tag)
	remove_anchor(id, b, tag)
	var folds: Array = world.regions[id].get("folds", [])
	folds.append({"anchor1": {"x": a.x, "y": a.y}, "anchor2": {"x": b.x, "y": b.y}})
	world.regions[id]["folds"] = folds
	_end_batch()
	return folds.size() - 1


## Delete a pre-placed fold. `keep_anchors` puts its two anchors back on the board
## as loose ones, which is what "disconnect" means — the fold stops shipping but
## the two places you chose survive to be re-connected.
func remove_fold(id: String, index: int, keep_anchors: bool = true, tag: String = "") -> bool:
	if not world.regions.has(id):
		return false
	var folds: Array = world.regions[id].get("folds", [])
	if index < 0 or index >= folds.size():
		return false
	_snapshot(tag)
	_begin_batch()
	var entry: Dictionary = folds[index]
	folds.remove_at(index)
	world.regions[id]["folds"] = folds
	if keep_anchors:
		add_anchor(id, _cell_of(entry.get("anchor1", {})), tag)
		add_anchor(id, _cell_of(entry.get("anchor2", {})), tag)
	_end_batch()
	return true


## The fold whose anchor sits on `cell`, or -1. Folds are hit-tested by their
## anchors rather than their band: bands overlap, anchors are where you clicked.
func fold_at(id: String, cell: Vector2i) -> int:
	var folds := folds_of(id)
	for i in range(folds.size()):
		if folds[i]["a"] == cell or folds[i]["b"] == cell:
			return i
	return -1


# ---------------------------------------------------------------------------
# Lights and loose hands
# ---------------------------------------------------------------------------

func add_light(id: String, cell: Vector2i, tag: String = "") -> String:
	if not world.regions.has(id) or not EditorTools.in_bounds(cell, size_of(id)):
		return ""
	if light_at(id, cell) != null:
		return ""
	_snapshot(tag)
	var light := LightSource.new()
	light.id = _unique_light_id(id)
	light.region = id
	light.cell = cell
	var list: Array = world.regions[id].get("lights", [])
	list.append(light)
	world.regions[id]["lights"] = list
	return light.id


func light_at(id: String, cell: Vector2i):
	if not world.regions.has(id):
		return null
	for light in world.regions[id].get("lights", []):
		if light.cell == cell:
			return light
	return null


func remove_light(id: String, cell: Vector2i, tag: String = "") -> bool:
	var light = light_at(id, cell)
	if light == null:
		return false
	_snapshot(tag)
	var list: Array = world.regions[id]["lights"]
	list.erase(light)
	return true


## Edit a placed light in place. Keys match `LightSource`'s fields: `color`,
## `radius_cells`, `energy`, `flicker`.
func update_light(id: String, cell: Vector2i, props: Dictionary, tag: String = "") -> bool:
	var light = light_at(id, cell)
	if light == null:
		return false
	_snapshot(tag)
	for key in props:
		if key in light:
			light.set(key, props[key])
	return true


func _unique_light_id(region_id: String) -> String:
	var stem := region_id.substr(0, 1) if region_id != "" else "l"
	var n := 1
	while _light_id_taken("%s_light_%d" % [stem, n]):
		n += 1
	return "%s_light_%d" % [stem, n]


func _light_id_taken(candidate: String) -> bool:
	for r in world.regions.values():
		for light in r.get("lights", []):
			if light.id == candidate:
				return true
	return false


func hand_at(id: String, cell: Vector2i):
	if not world.regions.has(id):
		return null
	for pickup in world.regions[id].get("hands", []):
		if pickup.cell == cell:
			return pickup
	return null


func add_hand(id: String, cell: Vector2i, kind: int = HandTypes.PLAIN, tag: String = "") -> bool:
	if not world.regions.has(id) or not EditorTools.in_bounds(cell, size_of(id)):
		return false
	if hand_at(id, cell) != null:
		return false
	_snapshot(tag)
	var pickup := HandPickup.new()
	pickup.kind = kind
	pickup.region = id
	pickup.cell = cell
	var list: Array = world.regions[id].get("hands", [])
	list.append(pickup)
	world.regions[id]["hands"] = list
	return true


func remove_hand(id: String, cell: Vector2i, tag: String = "") -> bool:
	var pickup = hand_at(id, cell)
	if pickup == null:
		return false
	_snapshot(tag)
	var list: Array = world.regions[id]["hands"]
	list.erase(pickup)
	return true


## The hands the player sets out with, as `HandTypes` ids. A world may start you
## short-handed, so a shorter list than `AnchorStock.SLOTS` is legal.
func set_starting_hands(kinds: Array, tag: String = "") -> bool:
	_snapshot(tag)
	var out: Array = []
	for k in kinds:
		out.append(HandTypes.type_name(int(k)))
	world.starting_hands = out
	return true


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

## Everything wrong with the world, as `{"level": "error"/"warn", "region": String,
## "message": String}`.
##
## The split matters: an ERROR is something `FoldWorld._setup_all` will refuse or
## push_error on, so the world does not boot correctly. A WARNING is a design
## smell the game will happily load — a spawn inside a wall, an anchor on a tile
## that blocks anchors, a fold nobody can reach. The editor must not refuse those
## while they are being drawn, and must not let them ship unnoticed either.
func validate() -> Array:
	var out: Array = []
	if world.regions.is_empty():
		out.append({"level": "error", "region": "", "message": "the world has no regions"})
	if world.start_region == "" or not world.regions.has(world.start_region):
		out.append({"level": "error", "region": "",
			"message": "start region \"%s\" does not exist" % world.start_region})

	for id in world.regions:
		var size := size_of(id)
		if size.x <= 0 or size.y <= 0:
			out.append({"level": "error", "region": id, "message": "region is empty"})
			continue
		var spawn: Vector2 = world.regions[id].get("spawn", Vector2.ZERO)
		var spawn_cell := Vector2i(floori(spawn.x), floori(spawn.y))
		if not EditorTools.in_bounds(spawn_cell, size):
			out.append({"level": "error", "region": id, "message": "spawn is outside the region"})
		elif not TileTypes.is_walkable(EditorTools.type_of_char(char_at(id, spawn_cell))):
			out.append({"level": "warn", "region": id,
				"message": "spawn sits inside a %s" % TileTypes.type_name(
					EditorTools.type_of_char(char_at(id, spawn_cell)))})

		for entry in folds_of(id):
			var a: Vector2i = entry["a"]
			var b: Vector2i = entry["b"]
			if not (EditorTools.in_bounds(a, size) and EditorTools.in_bounds(b, size)):
				out.append({"level": "error", "region": id,
					"message": "pre-placed fold %s-%s reaches outside the region" % [a, b]})
				continue
			if a == b:
				out.append({"level": "error", "region": id,
					"message": "pre-placed fold has both anchors on %s" % a})
			for cell in [a, b]:
				var type := EditorTools.type_of_char(char_at(id, cell))
				if TileTypes.blocks_anchor(type):
					out.append({"level": "warn", "region": id,
						"message": "fold anchor at %s is on an unanchorable tile" % cell})
			if not (entry["in"] as Array).is_empty():
				out.append({"level": "warn", "region": id,
					"message": "nested pre-placed fold at %s is saved but not applied at load" % a})

		for cell in world.loose_anchors(id):
			if not EditorTools.in_bounds(cell, size):
				out.append({"level": "error", "region": id,
					"message": "loose fold anchor %s is outside the region" % cell})
		if not world.loose_anchors(id).is_empty():
			out.append({"level": "warn", "region": id,
				"message": "%d fold anchor(s) placed but not connected" %
					world.loose_anchors(id).size()})

		for light in world.regions[id].get("lights", []):
			if not EditorTools.in_bounds(light.cell, size):
				out.append({"level": "error", "region": id,
					"message": "light %s is outside the region" % light.id})
		for pickup in world.regions[id].get("hands", []):
			if not EditorTools.in_bounds(pickup.cell, size):
				out.append({"level": "error", "region": id, "message": "loose hand is outside the region"})

	for door_id in world.doors:
		var d: Dictionary = world.doors[door_id]
		var rid := String(d["region"])
		if not world.regions.has(rid):
			out.append({"level": "error", "region": rid,
				"message": "door %s is in a region that does not exist" % door_id})
			continue
		if not EditorTools.in_bounds(d["cell"], size_of(rid)):
			out.append({"level": "error", "region": rid,
				"message": "door %s is outside its region" % door_id})
		var pair := String(d["pair"])
		if pair == "":
			out.append({"level": "warn", "region": rid,
				"message": "door %s leads nowhere" % door_id})
		elif not world.doors.has(pair):
			out.append({"level": "error", "region": rid,
				"message": "door %s points at %s, which does not exist" % [door_id, pair]})
		elif String(world.doors[pair]["pair"]) != door_id:
			out.append({"level": "error", "region": rid,
				"message": "door %s -> %s is one-way" % [door_id, pair]})
	return out


func error_count() -> int:
	var n := 0
	for issue in validate():
		if issue["level"] == "error":
			n += 1
	return n


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The region's authoring block, created on first use so a hand-authored file
## without one can still be dragged around the board.
func _editor_block(id: String) -> Dictionary:
	var r: Dictionary = world.regions[id]
	if not (r.get("editor", null) is Dictionary):
		r["editor"] = {}
	return r["editor"]


static func _cell_of(d: Dictionary) -> Vector2i:
	return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
