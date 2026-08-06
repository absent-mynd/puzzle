class_name WorldEditor extends Node2D

## WorldEditor
##
## The level editor: an MS-Paint canvas for terrain, on a Mural-style board of
## canvases you can arrange, resize and connect.
##
## It is called a WORLD editor and not a level editor because there are no levels
## — one world, many regions (see `AGENTS.md` §"the 2026-08-04 consolidation";
## the `LevelEditor` named there is the deleted top-down one, and this is not it).
## A CANVAS on the board is a REGION in the file: its own sheet of foldable space,
## with its own terrain, spawn, lights, hands and pre-placed folds.
##
## **A card's position on the board is not a fact about the world.** Regions have
## no spatial relationship to each other — they are connected by doors, not by
## adjacency — so where you put a card is a note to yourself about how you are
## thinking, and it lives in the file's authoring-only `editor` block. This is why
## dragging cards around is safe: there is nothing to break.
##
## Layering, in the same spirit as `WorldCore` / `FoldWorld`:
##
##     EditorTools   pure raster + guide geometry, headless-testable
##     EditorDoc     the document: every mutation, plus undo
##     EditorBoard   the drawing
##     WorldEditor   the mouse, the camera, the tools  ← you are here
##     EditorUI      the panel
##
## This file owns exactly one thing the others do not: what an input EVENT means.

const WORLD_PATH := "res://worlds/overworld.json"
const MIN_ZOOM := 0.04
const MAX_ZOOM := 4.0
const ZOOM_STEP := 1.15

## A canvas smaller than this has no room for anything; a larger one is almost
## certainly a typo in the size box.
const MIN_CELLS := 2
const MAX_CELLS := 512

enum Tool { PAINT, RECT, PICK, SPAWN, DOOR, FOLD, LIGHT, HAND }

## Tool -> the one-line hint the status bar shows. Kept beside the enum so adding a
## tool means adding a row, not hunting for the place that describes it.
const TOOL_HINT := {
	Tool.PAINT: "drag to paint · right-drag to erase",
	Tool.RECT: "drag a rectangle to fill · right-drag to clear it",
	Tool.PICK: "click a tile to load it into the brush",
	Tool.SPAWN: "click to move this region's spawn point",
	Tool.DOOR: "click to place a door · drag door→door to connect · right-click to remove",
	Tool.FOLD: "click to place an anchor · drag anchor→anchor to make a pre-placed fold · right-click to remove",
	Tool.LIGHT: "click to place a light · right-click to remove",
	Tool.HAND: "click to leave a hand on the ground · right-click to remove",
}

var doc: EditorDoc = null
var board: EditorBoard = null
var ui = null
var cam: Camera2D = null

# --- Tool state ---
var tool: int = Tool.PAINT
var brush: String = "#"
var hand_kind: int = HandTypes.PLAIN

# --- Selection and hover ---
var selected_region: String = ""
var hover_region: String = ""
var hover_cell: Vector2i = Vector2i.ZERO

## The in-flight gesture: `{}` when idle, otherwise `{"kind": String, ...}`. One
## dictionary rather than a flag per gesture, because exactly one can be running
## and a set of booleans would let two be.
var _gesture: Dictionary = {}
var _space_held: bool = false


## The board, the panel and the camera are nodes of `WorldEditor.tscn`, not
## objects made here. That is not only tidiness: `EditorUI` needs this file's
## tool enum and limits, so if this file also named `EditorUI` the two would
## reference each other in a circle. The scene owns the tree; the dependencies
## between the scripts run one way.
func _ready() -> void:
	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.055, 0.06, 0.08)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)

	cam = $Camera2D
	board = $Board
	board.editor = self
	ui = $UI
	ui.editor = self

	_open(_startup_path())
	# The panel has not been laid out yet, so it cannot say how wide it is until
	# a frame has passed — and the opening view is framed AROUND it.
	await get_tree().process_frame
	frame_all()


## The world to open: `--world=res://...` if given, else the shipped one. A flag
## rather than a file dialog because the usual case is "edit the world I am
## playing", and the unusual one is a shell away.
func _startup_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--world="):
			return String(arg).substr(8)
	return WORLD_PATH


func _open(path: String) -> void:
	var loaded := EditorDoc.load_from(path)
	if loaded == null:
		doc = EditorDoc.create_empty("world")
		doc.path = path
		doc.add_region("start", Vector2i(32, 18), Vector2.ZERO)
		toast("could not read %s — started an empty world" % path, EditorBoard.C_WARN)
	else:
		doc = loaded
		toast("opened %s" % path, EditorBoard.C_OK)
	_place_unplaced()
	selected_region = doc.world.start_region
	if not doc.has_region(selected_region):
		var ids := doc.region_ids()
		selected_region = String(ids[0]) if not ids.is_empty() else ""
	doc.clear_history()
	board.drop_tile_cache()
	refresh()


## Give a card a home if the file has never been through the editor. A world
## authored by hand has no board positions, and stacking every region at the
## origin would look like one region.
func _place_unplaced() -> void:
	for id in doc.region_ids():
		var rid := String(id)
		if not (doc.region(rid).get("editor", {}) as Dictionary).has("pos"):
			doc.move_region(rid, doc.suggest_position())
	doc.end_gesture()


func refresh() -> void:
	if ui != null:
		ui.refresh()
	board.queue_redraw()


func toast(text: String, color: Color = Color.WHITE) -> void:
	if ui != null:
		ui.toast(text, color)


# ---------------------------------------------------------------------------
# Geometry: board <-> cards <-> cells
# ---------------------------------------------------------------------------

func view_scale() -> float:
	return cam.zoom.x


## Screen px expressed in board units, for anything that must stay a constant
## size on screen (chrome, handles, grab tolerances).
func px(screen_px: float) -> float:
	return screen_px / maxf(view_scale(), 0.0001)


func card_rect(id: String) -> Rect2:
	return Rect2(doc.world.board_pos(id), Vector2(doc.size_of(id)) * doc.world.cell_size)


func header_rect(id: String) -> Rect2:
	var r := card_rect(id)
	var h := px(EditorBoard.HEADER_PX)
	return Rect2(r.position - Vector2(0, h), Vector2(r.size.x, h))


## The eight resize grips of a card, each a constant size on screen. `dir` says
## which edges a grip moves: (-1,0) is the left edge, (1,1) the bottom-right
## corner. `EditorDoc.resize_region` turns that plus a cell delta into a reshape.
func resize_handles(id: String) -> Array:
	if not doc.has_region(id):
		return []
	var r := card_rect(id)
	var s := px(EditorBoard.HANDLE_PX)
	var out: Array = []
	for dir in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
			Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]:
		var at := r.position + Vector2(
			r.size.x * (0.5 + 0.5 * dir.x), r.size.y * (0.5 + 0.5 * dir.y))
		out.append({"dir": dir, "rect": Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s))})
	return out


## The topmost card under a board point, counting its title bar. Iterates in the
## reverse of `EditorBoard`'s draw order, so the card you can SEE in an overlap is
## the card you hit — cards may freely be dragged on top of one another.
func region_at(p: Vector2) -> String:
	var ids := doc.region_ids()
	ids.reverse()
	for id in ids:
		var rid := String(id)
		if card_rect(rid).has_point(p) or header_rect(rid).has_point(p):
			return rid
	return ""


func cell_at(id: String, p: Vector2) -> Vector2i:
	var local := (p - doc.world.board_pos(id)) / doc.world.cell_size
	return Vector2i(floori(local.x), floori(local.y))


func cell_in_region(id: String, p: Vector2) -> bool:
	return EditorTools.in_bounds(cell_at(id, p), doc.size_of(id))


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		_key(event as InputEventKey)


func _mouse_button(event: InputEventMouseButton) -> void:
	var at := get_global_mouse_position()
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_at(at, ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_at(at, 1.0 / ZOOM_STEP)
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_gesture = {"kind": "pan"}
			else:
				_end_gesture()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(at, false)
			else:
				_release(at)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_press(at, true)
			else:
				_release(at)


func _mouse_motion(event: InputEventMouseMotion) -> void:
	var at := get_global_mouse_position()
	var was := [hover_region, hover_cell]
	hover_region = region_at(at)
	if hover_region != "":
		hover_cell = cell_at(hover_region, at)
	if _gesture.is_empty():
		if was != [hover_region, hover_cell]:
			board.queue_redraw()
		return
	_drag(at, event.relative)


## Zoom about a board point, so the thing under the cursor stays under it. This is
## the one interaction that has to be exactly right — a zoom that drifts makes a
## large board unnavigable.
func zoom_at(anchor: Vector2, factor: float) -> void:
	var before := cam.zoom.x
	var after := clampf(before * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(before, after):
		return
	cam.zoom = Vector2.ONE * after
	cam.position = anchor + (cam.position - anchor) * (before / after)
	board.view_scale = after
	board.queue_redraw()


## The part of the window the board actually gets: everything the panel is not
## covering. Framing into the whole viewport would centre a world neatly and then
## hide its left-hand card behind the tools.
func free_rect() -> Rect2:
	var view := get_viewport_rect().size
	var left := 0.0
	if ui != null:
		left = ui.panel_width()
	return Rect2(left, 0.0, maxf(view.x - left, 1.0), view.y)


## Fit every card into the free area. The default view of a world you have just
## opened, and the way back when you have lost yourself in a corner.
func frame_all() -> void:
	_frame(board_bounds(), 1.12)


func focus_region(id: String) -> void:
	if doc.has_region(id):
		_frame(card_rect(id).merge(header_rect(id)), 1.25)


## Put `bounds` in the middle of the free area at the largest zoom that fits.
##
## `Camera2D.position` is the world point under the VIEWPORT's centre, not the
## free area's, so the offset between the two has to be subtracted — otherwise
## every frame lands half a panel to the left.
func _frame(bounds: Rect2, margin: float) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		cam.position = Vector2.ZERO
		cam.zoom = Vector2.ONE * 0.5
		board.view_scale = cam.zoom.x
		board.queue_redraw()
		return
	var free := free_rect()
	var fit := minf(free.size.x / (bounds.size.x * margin), free.size.y / (bounds.size.y * margin))
	var zoom := clampf(fit, MIN_ZOOM, MAX_ZOOM)
	cam.zoom = Vector2.ONE * zoom
	cam.position = bounds.get_center() - (free.get_center() - get_viewport_rect().size * 0.5) / zoom
	board.view_scale = zoom
	board.queue_redraw()


## The bounding box of every card, title bars included.
func board_bounds() -> Rect2:
	var ids := doc.region_ids()
	if ids.is_empty():
		return Rect2()
	var out := card_rect(String(ids[0])).merge(header_rect(String(ids[0])))
	for id in ids:
		out = out.merge(card_rect(String(id))).merge(header_rect(String(id)))
	return out


# ---------------------------------------------------------------------------
# Gestures
# ---------------------------------------------------------------------------

## What a press MEANS, resolved in priority order: chrome first (a grip and a
## title bar are always what they look like, whatever tool is selected), then the
## tool, then the empty board. Putting chrome first is what makes the board
## navigable without a modal "select" tool.
func _press(at: Vector2, alt: bool) -> void:
	if _space_held:
		_gesture = {"kind": "pan"}
		return
	var id := region_at(at)

	if not alt and selected_region != "" and doc.has_region(selected_region):
		for handle in resize_handles(selected_region):
			if (handle["rect"] as Rect2).has_point(at):
				_gesture = {"kind": "resize", "id": selected_region,
					"dir": handle["dir"], "from": at, "delta": Vector2i.ZERO}
				return

	if id == "":
		if not alt:
			selected_region = ""
			_gesture = {"kind": "pan"}
			refresh()
		return

	if not alt and header_rect(id).has_point(at):
		selected_region = id
		_gesture = {"kind": "card", "id": id, "grab": at - doc.world.board_pos(id)}
		refresh()
		return

	selected_region = id
	var cell := cell_at(id, at)
	if not EditorTools.in_bounds(cell, doc.size_of(id)):
		return
	_tool_press(id, cell, at, alt)
	refresh()


## The tool half of a press. Each branch either does something outright or opens a
## drag; nothing here reads the mouse again.
func _tool_press(id: String, cell: Vector2i, at: Vector2, alt: bool) -> void:
	match tool:
		Tool.PAINT:
			var ch := EditorTools.AIR if alt else brush
			doc.paint(id, cell, ch, "paint")
			board.drop_tile_cache(id)
			_gesture = {"kind": "paint", "id": id, "last": cell, "char": ch}
		Tool.RECT:
			_gesture = {"kind": "rect", "id": id, "from": cell, "to": cell,
				"char": EditorTools.AIR if alt else brush}
		Tool.PICK:
			brush = doc.char_at(id, cell)
			toast("brush: %s" % _brush_name(), EditorBoard.C_OK)
		Tool.SPAWN:
			if not alt:
				doc.set_spawn(id, Vector2(cell) + Vector2(0.5, 0.5))
		Tool.DOOR:
			_door_press(id, cell, at, alt)
		Tool.FOLD:
			_fold_press(id, cell, at, alt)
		Tool.LIGHT:
			if alt:
				doc.remove_light(id, cell)
			elif doc.add_light(id, cell) == "":
				toast("a light is already on that cell", EditorBoard.C_WARN)
		Tool.HAND:
			if alt:
				doc.remove_hand(id, cell)
			elif not doc.add_hand(id, cell, hand_kind):
				toast("a hand is already on that cell", EditorBoard.C_WARN)


func _door_press(id: String, cell: Vector2i, at: Vector2, alt: bool) -> void:
	var existing := doc.door_at(id, cell)
	if alt:
		if existing != "":
			doc.remove_door(existing)
		return
	if existing != "":
		# Dragging FROM a door is how it gets connected — the same gesture as the
		# fold tool's, because "these two things are the same thing" is one idea.
		_gesture = {"kind": "link_door", "from": existing, "at": at}
		return
	var made := doc.add_door(id, cell)
	if made != "":
		_gesture = {"kind": "link_door", "from": made, "at": at}


func _fold_press(id: String, cell: Vector2i, at: Vector2, alt: bool) -> void:
	if alt:
		var fold_idx := doc.fold_at(id, cell)
		if fold_idx >= 0:
			doc.remove_fold(id, fold_idx, true)
			toast("fold disconnected — its anchors are back on the board", EditorBoard.C_OK)
		else:
			doc.remove_anchor(id, cell)
		return
	if doc.fold_at(id, cell) >= 0:
		toast("that anchor belongs to a fold — right-click to disconnect it", EditorBoard.C_WARN)
		return
	if not doc.has_anchor(id, cell):
		doc.add_anchor(id, cell)
	_gesture = {"kind": "link_fold", "id": id, "from": cell, "at": at}


func _drag(at: Vector2, relative: Vector2) -> void:
	match _gesture.get("kind", ""):
		"pan":
			cam.position -= relative / view_scale()
		"card":
			var pos := at - (_gesture["grab"] as Vector2)
			doc.move_region(String(_gesture["id"]), _snap(pos), "move")
		"resize":
			_gesture["delta"] = _cells_of(at - (_gesture["from"] as Vector2))
		"paint":
			var id := String(_gesture["id"])
			var cell := cell_at(id, at)
			doc.paint_cells(id, EditorTools.line_cells(_gesture["last"], cell),
				String(_gesture["char"]), "paint")
			_gesture["last"] = cell
			board.drop_tile_cache(id)
		"rect":
			_gesture["to"] = cell_at(String(_gesture["id"]), at)
		"link_door", "link_fold":
			_gesture["at"] = at
	board.queue_redraw()


func _release(at: Vector2) -> void:
	match _gesture.get("kind", ""):
		"resize":
			_commit_resize()
		"rect":
			var id := String(_gesture["id"])
			doc.fill_rect(id, _gesture["from"], _gesture["to"], String(_gesture["char"]))
			board.drop_tile_cache(id)
		"link_door":
			_finish_door_link(at)
		"link_fold":
			_finish_fold_link(at)
	_end_gesture()
	refresh()


func _end_gesture() -> void:
	_gesture = {}
	if doc != null:
		doc.end_gesture()
	board.queue_redraw()


## Turn the accumulated grip drag into a reshape. Committed on RELEASE rather than
## live: a resize moves doors, lights, hands and the card itself, and doing that
## every mouse-move would fill the undo stack with frames of a drag.
func _commit_resize() -> void:
	var id := String(_gesture["id"])
	var dir: Vector2i = _gesture["dir"]
	var d: Vector2i = _gesture["delta"]
	var old := doc.size_of(id)
	var offset := Vector2i(-d.x if dir.x < 0 else 0, -d.y if dir.y < 0 else 0)
	var size := old + Vector2i(
		(d.x if dir.x > 0 else (-d.x if dir.x < 0 else 0)),
		(d.y if dir.y > 0 else (-d.y if dir.y < 0 else 0)))
	size = Vector2i(clampi(size.x, MIN_CELLS, MAX_CELLS), clampi(size.y, MIN_CELLS, MAX_CELLS))
	if offset == Vector2i.ZERO and size == old:
		return
	var dropped := doc.resize_region(id, offset, size)
	board.drop_tile_cache(id)
	if dropped > 0:
		toast("resized to %d×%d — %d thing(s) fell outside and were dropped"
			% [size.x, size.y, dropped], EditorBoard.C_WARN)
	else:
		toast("resized to %d×%d" % [size.x, size.y], EditorBoard.C_OK)


func _finish_door_link(at: Vector2) -> void:
	var from := String(_gesture["from"])
	var id := region_at(at)
	if id == "":
		return
	var target := doc.door_at(id, cell_at(id, at))
	if target == "" or target == from:
		return
	if doc.link_doors(from, target):
		toast("%s ↔ %s" % [from, target], EditorBoard.C_OK)


func _finish_fold_link(at: Vector2) -> void:
	var id := String(_gesture["id"])
	var from: Vector2i = _gesture["from"]
	if region_at(at) != id:
		toast("a fold's two anchors must be in the same region", EditorBoard.C_WARN)
		return
	var target := cell_at(id, at)
	if target == from or not doc.has_anchor(id, target):
		return
	if doc.connect_anchors(id, from, target) >= 0:
		toast("pre-placed fold %s → %s" % [from, target], EditorBoard.C_OK)


## Draw whatever gesture is in flight. Called from `EditorBoard._draw` so the
## preview sits over the cards, and written here because the gesture's shape is
## this file's business.
func draw_gesture(target: EditorBoard) -> void:
	match _gesture.get("kind", ""):
		"rect":
			var id := String(_gesture["id"])
			var r := EditorTools.rect_of(_gesture["from"], _gesture["to"])
			var cell: float = doc.world.cell_size
			target.gesture_rect(Rect2(
				doc.world.board_pos(id) + Vector2(r.position) * cell,
				Vector2(r.size) * cell), EditorBoard.C_SELECTED)
		"resize":
			target.gesture_rect(_resize_preview(), EditorBoard.C_SELECTED)
		"link_door":
			target.gesture_line(target.door_point(doc, String(_gesture["from"])),
				_gesture["at"], EditorBoard.C_DOOR)
		"link_fold":
			var id := String(_gesture["id"])
			var from: Vector2i = _gesture["from"]
			target.gesture_line(
				doc.world.board_pos(id) + (Vector2(from) + Vector2(0.5, 0.5)) * doc.world.cell_size,
				_gesture["at"], EditorBoard.C_ANCHOR)


func _resize_preview() -> Rect2:
	var id := String(_gesture["id"])
	var dir: Vector2i = _gesture["dir"]
	var d: Vector2i = _gesture["delta"]
	var r := card_rect(id)
	var cell: float = doc.world.cell_size
	if dir.x < 0:
		r.position.x += d.x * cell
		r.size.x -= d.x * cell
	elif dir.x > 0:
		r.size.x += d.x * cell
	if dir.y < 0:
		r.position.y += d.y * cell
		r.size.y -= d.y * cell
	elif dir.y > 0:
		r.size.y += d.y * cell
	return r.abs()


func _snap(pos: Vector2) -> Vector2:
	var cell: float = doc.world.cell_size
	return (pos / cell).round() * cell


func _cells_of(delta: Vector2) -> Vector2i:
	var cell: float = doc.world.cell_size
	return Vector2i(roundi(delta.x / cell), roundi(delta.y / cell))


# ---------------------------------------------------------------------------
# Keyboard
# ---------------------------------------------------------------------------

func _key(event: InputEventKey) -> void:
	if event.keycode == KEY_SPACE:
		_space_held = event.pressed
		return
	if not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_S: save()
			KEY_Z:
				if event.shift_pressed:
					_history(doc.redo(), "redo")
				else:
					_history(doc.undo(), "undo")
			KEY_Y: _history(doc.redo(), "redo")
		return
	match event.keycode:
		KEY_B: set_tool(Tool.PAINT)
		KEY_E: set_tool(Tool.RECT)
		KEY_I: set_tool(Tool.PICK)
		KEY_P: set_tool(Tool.SPAWN)
		KEY_D: set_tool(Tool.DOOR)
		KEY_A: set_tool(Tool.FOLD)
		KEY_L: set_tool(Tool.LIGHT)
		KEY_H: set_tool(Tool.HAND)
		KEY_HOME: frame_all()
		KEY_ESCAPE: _end_gesture()
		_:
			var index := event.keycode - KEY_1
			if index >= 0 and index < 9:
				var pal := EditorTools.palette()
				if index < pal.size():
					brush = String(pal[index]["char"])
					set_tool(Tool.PAINT)


## Undo and redo drop every cached tile texture rather than guessing which region
## changed: a snapshot restore can reshape any of them, and a stale card is a
## worse bug than a rebuild nobody notices.
func _history(ok: bool, what: String) -> void:
	if not ok:
		toast("nothing to %s" % what, EditorBoard.C_WARN)
		return
	board.drop_tile_cache()
	if not doc.has_region(selected_region):
		selected_region = ""
	toast(what, EditorBoard.C_OK)
	refresh()


# ---------------------------------------------------------------------------
# Commands the panel calls
# ---------------------------------------------------------------------------

func set_tool(next: int) -> void:
	tool = next
	refresh()


func set_brush(ch: String) -> void:
	brush = ch
	tool = Tool.PAINT
	refresh()


func _brush_name() -> String:
	return TileTypes.type_name(EditorTools.type_of_char(brush))


func save() -> void:
	var errors := doc.error_count()
	if not doc.save():
		toast("could not write %s" % doc.path, EditorBoard.C_BAD)
		return
	if errors > 0:
		toast("saved %s — %d error(s) still to fix" % [doc.path, errors], EditorBoard.C_WARN)
	else:
		toast("saved %s" % doc.path, EditorBoard.C_OK)
	refresh()


func reload() -> void:
	_open(doc.path)
	frame_all()


func new_region(id: String, size: Vector2i) -> void:
	size = Vector2i(clampi(size.x, MIN_CELLS, MAX_CELLS), clampi(size.y, MIN_CELLS, MAX_CELLS))
	if not doc.add_region(id, size):
		toast("a canvas called \"%s\" already exists" % id, EditorBoard.C_WARN)
		return
	doc.end_gesture()
	selected_region = id
	toast("new canvas \"%s\" (%d×%d)" % [id, size.x, size.y], EditorBoard.C_OK)
	focus_region(id)
	refresh()


func delete_region(id: String) -> void:
	if not doc.remove_region(id):
		return
	doc.end_gesture()
	board.drop_tile_cache(id)
	if selected_region == id:
		selected_region = doc.world.start_region
	toast("deleted \"%s\"" % id, EditorBoard.C_OK)
	refresh()


func rename_region(from_id: String, to_id: String) -> void:
	if not doc.rename_region(from_id, to_id):
		toast("cannot rename to \"%s\"" % to_id, EditorBoard.C_WARN)
		return
	doc.end_gesture()
	board.drop_tile_cache(from_id)
	if selected_region == from_id:
		selected_region = to_id
	refresh()


func resize_selected(size: Vector2i) -> void:
	if selected_region == "":
		return
	size = Vector2i(clampi(size.x, MIN_CELLS, MAX_CELLS), clampi(size.y, MIN_CELLS, MAX_CELLS))
	var dropped := doc.resize_region(selected_region, Vector2i.ZERO, size)
	doc.end_gesture()
	board.drop_tile_cache(selected_region)
	if dropped > 0:
		toast("%d thing(s) fell outside and were dropped" % dropped, EditorBoard.C_WARN)
	refresh()


func set_start_region(id: String) -> void:
	if doc.set_start_region(id):
		doc.end_gesture()
		toast("\"%s\" is where the world starts" % id, EditorBoard.C_OK)
	refresh()


func select_region(id: String) -> void:
	selected_region = id
	refresh()
