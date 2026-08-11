class_name EditorBoard extends Node2D

## EditorBoard
##
## The drawing half of the level editor: the infinite board, the region cards on
## it, and every overlay that shows what an authored world contains.
##
## The board's coordinate space IS a region's local space, scaled 1:1 — a cell is
## `cell_size` board units, exactly as in the game — with each card translated to
## its authored board position. That is what lets fold guides, doors and lights be
## drawn with the same arithmetic the game uses, offset by one vector.
##
## **A card's position means nothing to the game.** Regions are separate sheets
## with no spatial relationship; the board is a place to arrange your thinking,
## like pinning pages to a wall. Everything that reads a board position is in
## `scripts/editor/`.
##
## Two conventions worth knowing before editing this file:
##
##   - **Chrome is measured in SCREEN pixels, content in board units.** A card's
##     title bar, the handles, the labels and the line widths all stay the same
##     size as you zoom, because they are furniture rather than content. That is
##     why so many sizes are divided by `view_scale`.
##   - **Tiles are drawn from a cached texture, not per cell.** A region is
##     blitted into one `ImageTexture` from the tileset and redrawn as a single
##     quad; the cache is keyed on the rows, so it rebuilds exactly when the
##     terrain changes. Painting a 3000-cell region stays one texture upload, and
##     the editor shows the same art the game does.

## Back-reference to the controller, for tool/selection/gesture state. Same shape
## as `WorldOverlay.world` — the overlay is a view OF something.
var editor = null

## Camera scale, cached per frame: screen px = board units * view_scale.
var view_scale: float = 1.0

# --- Chrome, in screen px ---
const HEADER_PX := 22.0
const HANDLE_PX := 12.0
const BORDER_PX := 2.0
const LINE_PX := 1.5
const LABEL_PX := 12

# --- Palette ---
#
# Every colour the editor uses is here, including the three the PANEL reports
# with. That is partly tidiness and partly dependency direction: `WorldEditor`
# and `EditorUI` both need the status colours, and this file references neither
# of them, so keeping the palette here is what stops the two from having to
# reference each other in a circle.
const C_OK := Color(0.55, 0.92, 0.62)
const C_WARN := Color(1.00, 0.82, 0.40)
const C_BAD := Color(1.00, 0.48, 0.45)
const C_DIM := Color(0.62, 0.66, 0.76)

const C_CARD := Color(0.11, 0.12, 0.16)
const C_CARD_EDGE := Color(0.30, 0.33, 0.42)
const C_SELECTED := Color(0.98, 0.78, 0.36)
const C_HEADER := Color(0.17, 0.19, 0.25)
const C_HEADER_SEL := Color(0.30, 0.26, 0.16)
const C_TEXT := Color(0.86, 0.88, 0.94)
const C_GRID := Color(1, 1, 1, 0.055)
const C_SPAWN := Color(0.45, 1.0, 0.62)
const C_DOOR := Color(0.55, 0.80, 1.0)
const C_DOOR_LOOSE := Color(1.0, 0.45, 0.45)
const C_ANCHOR := Color(1.00, 0.62, 0.36)
const C_FOLD := Color(0.72, 0.55, 1.00)
const C_STRIP := Color(0.72, 0.55, 1.00, 0.16)
const C_HOVER := Color(1, 1, 1, 0.22)
const C_PARAM := Color(0.92, 0.55, 0.85)
const C_PARAM_UNSET := Color(0.55, 0.58, 0.68)

var _tile_cache: Dictionary = {}   # region id -> {"tex": ImageTexture, "stamp": int}

## The card-local origin currently in force. `draw_set_transform` has no getter, so
## a label — which has to install its own scale — needs to know what to put back.
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _font() -> Font:
	return ThemeDB.fallback_font


## Screen px -> board units. Every piece of chrome goes through this.
func _px(screen_px: float) -> float:
	return screen_px / maxf(view_scale, 0.0001)


# ---------------------------------------------------------------------------
# The frame
# ---------------------------------------------------------------------------

func _draw() -> void:
	if editor == null or editor.doc == null:
		return
	var doc: EditorDoc = editor.doc
	for id in doc.region_ids():
		_draw_card(doc, String(id))
	_draw_door_links(doc)
	editor.draw_gesture(self)


func _draw_card(doc: EditorDoc, id: String) -> void:
	var cell: float = doc.world.cell_size
	var pos := doc.world.board_pos(id)
	var size := doc.size_of(id)
	if size.x <= 0 or size.y <= 0:
		return
	var rect := Rect2(pos, Vector2(size) * cell)
	var selected: bool = editor.selected_region == id

	draw_rect(Rect2(rect.position + Vector2(_px(5), _px(5)), rect.size), Color(0, 0, 0, 0.28))
	draw_rect(rect, C_CARD)
	var tex := _tiles_for(doc, id)
	if tex != null:
		draw_texture_rect(tex, rect, false)
	_draw_grid(rect, cell)

	# Content overlays, in the region's LOCAL space — the same coordinates the
	# game uses, which is what keeps the fold guides honest.
	_origin = pos
	draw_set_transform(pos, 0.0, Vector2.ONE)
	_draw_folds(doc, id, cell)
	_draw_tile_params(doc, id, cell)
	_draw_spawn(doc, id, cell)
	_draw_lights(doc, id, cell)
	_draw_hands(doc, id, cell)
	_draw_doors(doc, id, cell)
	_draw_hover(doc, id, cell)
	_origin = Vector2.ZERO
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var edge := C_SELECTED if selected else C_CARD_EDGE
	draw_rect(rect, edge, false, _px(BORDER_PX))
	_draw_header(doc, id, rect, selected)
	if selected:
		for handle in editor.resize_handles(id):
			draw_rect(handle["rect"], C_SELECTED, false, _px(BORDER_PX))


## The title bar: name, grid shape, and a star on the start region. Sized in
## screen px so it stays grabbable and readable at every zoom.
func _draw_header(doc: EditorDoc, id: String, rect: Rect2, selected: bool) -> void:
	var h := _px(HEADER_PX)
	var bar := Rect2(rect.position - Vector2(0, h), Vector2(rect.size.x, h))
	draw_rect(bar, C_HEADER_SEL if selected else C_HEADER)
	draw_rect(bar, C_SELECTED if selected else C_CARD_EDGE, false, _px(BORDER_PX))
	var size := doc.size_of(id)
	var star := "★ " if doc.world.start_region == id else ""
	_label(bar.position + Vector2(_px(6), _px(HEADER_PX * 0.74)),
		"%s%s   %d×%d" % [star, id, size.x, size.y], C_TEXT)


## The cell lattice, and a heavier line every 8 cells so you can count without
## squinting. Dropped entirely once a cell is under a few screen px, where it
## would be noise rather than information.
func _draw_grid(rect: Rect2, cell: float) -> void:
	if cell * view_scale < 6.0:
		return
	var w := _px(1.0)
	var cols := int(round(rect.size.x / cell))
	var rows := int(round(rect.size.y / cell))
	for x in range(1, cols):
		var c := C_GRID if x % 8 != 0 else Color(1, 1, 1, 0.12)
		draw_line(rect.position + Vector2(x * cell, 0),
			rect.position + Vector2(x * cell, rect.size.y), c, w)
	for y in range(1, rows):
		var c := C_GRID if y % 8 != 0 else Color(1, 1, 1, 0.12)
		draw_line(rect.position + Vector2(0, y * cell),
			rect.position + Vector2(rect.size.x, y * cell), c, w)


# ---------------------------------------------------------------------------
# Tiles
# ---------------------------------------------------------------------------

## The cached tile texture for a region, rebuilt when its rows change.
func _tiles_for(doc: EditorDoc, id: String) -> Texture2D:
	var rows: Array = doc.region(id).get("rows", [])
	var stamp := hash(rows)
	var entry: Dictionary = _tile_cache.get(id, {})
	if entry.get("stamp", -1) == stamp:
		return entry.get("tex", null)
	var tex := _build_tiles(rows)
	_tile_cache[id] = {"tex": tex, "stamp": stamp}
	return tex


func drop_tile_cache(id: String = "") -> void:
	if id == "":
		_tile_cache.clear()
	else:
		_tile_cache.erase(id)


## Blit a region's terrain out of the tileset, one atlas tile per cell.
##
## Kind and variant come from the same functions the game uses, so a wall in the
## editor is the same wall on screen — including the `open_above` cap, which is a
## BASE-space fact (`TileAtlas`) and therefore just as true of an unfolded region
## as of a folded one.
func _build_tiles(rows: Array) -> Texture2D:
	var size := EditorTools.grid_size(rows)
	if size.x <= 0 or size.y <= 0:
		return null
	var atlas := TileAtlas.texture()
	if atlas == null:
		return null
	var src := atlas.get_image()
	var tp := PixelArt.TILE_PX
	var img := Image.create(size.x * tp, size.y * tp, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var type := EditorTools.type_of_char(EditorTools.char_at(rows, Vector2i(x, y)))
			var open_above := true
			if y > 0:
				open_above = EditorTools.type_of_char(
					EditorTools.char_at(rows, Vector2i(x, y - 1))) == TileTypes.EMPTY
			var kind := TileAtlas.kind_for(type, open_above)
			var variant := TileAtlas.variant_for(y * size.x + x)
			img.blit_rect(src, Rect2i(variant * tp, kind * tp, tp, tp), Vector2i(x * tp, y * tp))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Overlays
# ---------------------------------------------------------------------------

## Pre-placed folds: where they cut, and what they will take.
##
## They are drawn, not applied. The point of a pre-placed fold in the editor is to
## see the space you are about to seal — a card that shipped already folded would
## show you a hole and no way to reason about what is in it. So the strip is shaded
## rather than removed, the creases are drawn as the hard lines they will be, and
## the meeting line shows where the two halves will come to rest.
func _draw_folds(doc: EditorDoc, id: String, cell: float) -> void:
	var size := doc.size_of(id)
	for entry in doc.folds_of(id):
		var guides := EditorTools.fold_guides(entry["a"], entry["b"], size, cell)
		for poly in guides["strip"]:
			draw_colored_polygon(poly, C_STRIP)
		for key in ["crease1", "crease2"]:
			var seg: PackedVector2Array = guides[key]
			if seg.size() == 2:
				draw_line(seg[0], seg[1], C_FOLD, _px(LINE_PX * 1.4))
		# The line the two halves come to rest along. Drawn bright, not faint: it
		# is where the ground will be after the fold, which is the thing you are
		# actually placing when you place a pre-placed fold.
		var meet: PackedVector2Array = guides["meeting"]
		if meet.size() == 2:
			_dashed(meet[0], meet[1], Color(1, 1, 1, 0.85), _px(LINE_PX * 1.2), _px(9.0))
		var pa := _center(entry["a"], cell)
		var pb := _center(entry["b"], cell)
		_dashed(pa, pb, Color(C_FOLD, 0.7), _px(LINE_PX), _px(6.0))
		_anchor_dot(pa, cell, C_FOLD, true)
		_anchor_dot(pb, cell, C_FOLD, true)

	# Anchors waiting for a partner: hollow, because they are not a fold yet.
	for cell_pos in doc.anchors_of(id):
		_anchor_dot(_center(cell_pos, cell), cell, C_ANCHOR, false)


func _anchor_dot(at: Vector2, cell: float, color: Color, filled: bool) -> void:
	var r := cell * 0.26
	if filled:
		draw_circle(at, r, color)
		draw_arc(at, r, 0, TAU, 24, Color(0, 0, 0, 0.6), _px(LINE_PX))
	else:
		draw_arc(at, r, 0, TAU, 24, color, _px(LINE_PX * 1.6))
		draw_circle(at, r * 0.30, color)


## What a configured tile POINTS AT.
##
## Any parameter of type `cells` is drawn as a line from the tile to each cell it
## names, with a numbered marker on each. Nothing here knows what a trigger is:
## it walks the schema, so a parameter added to any tile type shows up on the
## board the day it is declared. That is the whole reason the coordinates in a
## tile's data are worth having a board at all — a pair of numbers in a JSON file
## tells you nothing about where the fold will land.
##
## The tile being INSPECTED additionally gets the full fold preview, when its
## type reacts by folding. Drawing that for every configured plate at once would
## be a wall of overlapping strips; drawing it for the one you are editing is the
## answer to "what will this actually do".
func _draw_tile_params(doc: EditorDoc, id: String, cell: float) -> void:
	var focus: Dictionary = editor.inspected()
	for tile_cell in doc.tiles_with_data(id):
		var type := doc.type_at(id, tile_cell)
		if not TileParams.has_params(type):
			continue
		var data := doc.tile_data(id, tile_cell)
		var from := _center(tile_cell, cell)
		var focused: bool = not focus.is_empty() \
			and String(focus["region"]) == id and focus["cell"] == tile_cell
		for spec in TileParams.specs_for(type):
			if String(spec.get("type", "")) != TileParams.CELLS:
				continue
			var cells: Array = data.get(String(spec["key"]), [])
			for i in range(cells.size()):
				var target: Vector2i = cells[i]
				if target == TileParams.UNSET:
					continue
				var to := _center(target, cell)
				_dashed(from, to, Color(C_PARAM, 0.75 if focused else 0.4),
					_px(LINE_PX), _px(6.0))
				draw_arc(to, cell * 0.30, 0, TAU, 22, C_PARAM, _px(LINE_PX * 1.5))
				_label(to + Vector2(cell * 0.34, -cell * 0.12), str(i + 1), C_PARAM, 11)
			if focused and TileTypes.on_enter_kind(type) == "fold" and cells.size() >= 2:
				_draw_reaction_preview(doc, id, cells[0], cells[1], cell)
		draw_rect(Rect2(Vector2(tile_cell) * cell, Vector2(cell, cell)),
			C_PARAM, false, _px(BORDER_PX if focused else LINE_PX))

	# The tile the inspector is on, even when it has nothing stored — selecting a
	# wall must look like selecting something.
	if not focus.is_empty() and String(focus["region"]) == id:
		var sel: Vector2i = focus["cell"]
		draw_rect(Rect2(Vector2(sel) * cell, Vector2(cell, cell)),
			C_SELECTED, false, _px(BORDER_PX))
		if not editor.picking.is_empty():
			draw_rect(Rect2(Vector2(sel) * cell, Vector2(cell, cell)), Color(C_SELECTED, 0.18))


## The fold a reacting tile will make, drawn exactly as a pre-placed fold is —
## same guides, dimmer. It is the same question ("where will this cut?") asked of
## a fold that has not happened yet rather than one that ships already made.
func _draw_reaction_preview(doc: EditorDoc, id: String, a: Vector2i, b: Vector2i, cell: float) -> void:
	if a == TileParams.UNSET or b == TileParams.UNSET or a == b:
		return
	var guides := EditorTools.fold_guides(a, b, doc.size_of(id), cell)
	for poly in guides["strip"]:
		draw_colored_polygon(poly, Color(C_PARAM, 0.10))
	for key in ["crease1", "crease2"]:
		var seg: PackedVector2Array = guides[key]
		if seg.size() == 2:
			_dashed(seg[0], seg[1], Color(C_PARAM, 0.7), _px(LINE_PX), _px(7.0))


func _draw_spawn(doc: EditorDoc, id: String, cell: float) -> void:
	var at: Vector2 = (doc.region(id).get("spawn", Vector2.ZERO) as Vector2) * cell
	var r := cell * 0.34
	draw_arc(at, r, 0, TAU, 28, C_SPAWN, _px(LINE_PX * 1.6))
	draw_line(at - Vector2(r, 0), at + Vector2(r, 0), C_SPAWN, _px(LINE_PX))
	draw_line(at - Vector2(0, r), at + Vector2(0, r), C_SPAWN, _px(LINE_PX))


func _draw_lights(doc: EditorDoc, id: String, cell: float) -> void:
	for light in doc.region(id).get("lights", []):
		var at := _center(light.cell, cell)
		draw_arc(at, light.radius_cells * cell, 0, TAU, 48, Color(light.color, 0.22), _px(LINE_PX))
		draw_circle(at, cell * 0.22, light.color)
		draw_arc(at, cell * 0.22, 0, TAU, 20, Color(0, 0, 0, 0.5), _px(LINE_PX))


func _draw_hands(doc: EditorDoc, id: String, cell: float) -> void:
	for pickup in doc.region(id).get("hands", []):
		var at := _center(pickup.cell, cell)
		var col := HandTypes.color(pickup.kind)
		draw_circle(at, cell * 0.20, col)
		draw_arc(at, cell * 0.30, 0, TAU, 20, col, _px(LINE_PX))


func _draw_doors(doc: EditorDoc, id: String, cell: float) -> void:
	for door_id in doc.world.doors:
		var d: Dictionary = doc.world.doors[door_id]
		if d["region"] != id:
			continue
		var linked := String(d["pair"]) != ""
		var col := C_DOOR if linked else C_DOOR_LOOSE
		var r := Rect2(Vector2(d["cell"]) * cell + Vector2(cell * 0.2, cell * 0.08),
			Vector2(cell * 0.6, cell * 0.84))
		draw_rect(r, Color(col, 0.30))
		draw_rect(r, col, false, _px(LINE_PX * 1.4))
		_label(r.position + Vector2(0, -_px(4)), String(door_id), col)


## The door graph, drawn ACROSS cards. This is the one thing on the board that is
## a real relationship rather than an arrangement: two doors are connected in the
## world however far apart their cards sit, so the link is drawn between them
## wherever you have dragged them to.
func _draw_door_links(doc: EditorDoc) -> void:
	var drawn: Dictionary = {}
	for door_id in doc.world.doors:
		var pair := String(doc.world.doors[door_id]["pair"])
		if pair == "" or not doc.world.doors.has(pair) or drawn.has(pair):
			continue
		drawn[door_id] = true
		var a := door_point(doc, String(door_id))
		var b := door_point(doc, pair)
		var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * (a.distance_to(b) * 0.10)
		var prev := a
		for i in range(1, 17):
			var t := float(i) / 16.0
			var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
			draw_line(prev, p, Color(C_DOOR, 0.55), _px(LINE_PX * 1.3))
			prev = p


## The board-space centre of a door's cell.
func door_point(doc: EditorDoc, door_id: String) -> Vector2:
	var d: Dictionary = doc.world.doors.get(door_id, {})
	var rid := String(d.get("region", ""))
	return doc.world.board_pos(rid) + _center(d.get("cell", Vector2i.ZERO), doc.world.cell_size)


func _draw_hover(doc: EditorDoc, id: String, cell: float) -> void:
	if editor.hover_region != id:
		return
	var c: Vector2i = editor.hover_cell
	if not EditorTools.in_bounds(c, doc.size_of(id)):
		return
	draw_rect(Rect2(Vector2(c) * cell, Vector2(cell, cell)), C_HOVER, false, _px(BORDER_PX))


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

static func _center(cell_pos: Vector2i, cell: float) -> Vector2:
	return (Vector2(cell_pos) + Vector2(0.5, 0.5)) * cell


func _dashed(from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var span := from.distance_to(to)
	if span < GeometryCore.EPSILON or dash <= 0.0:
		return
	var dir := (to - from) / span
	var t := 0.0
	while t < span:
		var end := minf(t + dash, span)
		draw_line(from + dir * t, from + dir * end, color, width)
		t = end + dash


## Text at a constant SCREEN size, anchored at a board position. The transform
## trick is what lets a label stay legible while the world under it zooms.
func _label(at: Vector2, text: String, color: Color, size: int = LABEL_PX) -> void:
	draw_set_transform(_origin + at, 0.0, Vector2.ONE / maxf(view_scale, 0.0001))
	draw_string(_font(), Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	draw_set_transform(_origin, 0.0, Vector2.ONE)


## Public wrappers, so the controller can draw its in-flight gesture with the same
## conventions instead of reinventing them.
func gesture_line(from: Vector2, to: Vector2, color: Color) -> void:
	_dashed(from, to, color, _px(LINE_PX * 1.6), _px(7.0))


func gesture_rect(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color(color, 0.20))
	draw_rect(rect, color, false, _px(BORDER_PX))


func px(screen_px: float) -> float:
	return _px(screen_px)
