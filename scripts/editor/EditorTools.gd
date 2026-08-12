class_name EditorTools extends RefCounted

## EditorTools
##
## Pure, headless helpers for the world editor: the tile palette, raster ops on a
## region's ASCII rows, the arithmetic of resizing a canvas, and the guide geometry
## that shows where a pre-placed fold WOULD cut without folding it.
##
## Everything here is static and side-effect free, and none of it touches a Node.
## The split mirrors `WorldCore` / `FoldWorld`: this file is the part you can assert
## about in a headless test, `WorldEditor` is the part with a mouse in it.
##
## Two things it deliberately does not own:
##
##   - **What a tile is.** The palette is DERIVED from `WorldCore.CHARS` and
##     `TileTypes`, so a new tile type shows up in the editor by virtue of being
##     registered. A hand-maintained palette would be a second place to forget.
##   - **The document.** Mutating a world is `EditorDoc`'s job; these are the
##     functions it is written in terms of.

## The character an empty cell is written as. `WorldCore.parse_map` treats every
## unlisted character as air, but a file wants exactly one spelling of it.
const AIR := "."


# ---------------------------------------------------------------------------
# The palette
# ---------------------------------------------------------------------------

## Every paintable tile, as `{"char": String, "type": int, "name": String}`, air
## first and then `WorldCore.CHARS` in registry order.
##
## Derived from the two registries rather than listed, so "the editor can paint it"
## and "the world can load it" cannot drift apart. `test_editor_tools` asserts the
## round trip in both directions.
static func palette() -> Array:
	var out: Array = [{"char": AIR, "type": TileTypes.EMPTY, "name": TileTypes.type_name(TileTypes.EMPTY)}]
	for type in TileTypes.all_types():
		# EMPTY is already the first entry (as air, the eraser), and NULL is a
		# derived-state artifact with no authoring character at all.
		if int(type) == TileTypes.EMPTY or int(type) == TileTypes.NULL:
			continue
		var ch := char_of_type(int(type))
		if ch == "":
			continue
		out.append({"char": ch, "type": int(type), "name": TileTypes.type_name(int(type))})
	return out


## The tile type an authoring character paints. Unknown characters are air, which
## is `parse_map`'s rule — the editor must not disagree with the loader.
static func type_of_char(ch: String) -> int:
	return WorldCore.CHARS.get(ch, TileTypes.EMPTY)


## The authoring character for a type, or "" if the type has no spelling. EMPTY is
## `AIR`; every other type is found by inverting `WorldCore.CHARS`.
static func char_of_type(type: int) -> String:
	if type == TileTypes.EMPTY:
		return AIR
	for ch in WorldCore.CHARS:
		if WorldCore.CHARS[ch] == type:
			return String(ch)
	return ""


# ---------------------------------------------------------------------------
# Raster ops on ASCII rows
# ---------------------------------------------------------------------------

## The grid shape of a row list, in cells. Width is the WIDEST row, matching
## `WorldCore.parse_map`, which pads short rows with air.
static func grid_size(rows: Array) -> Vector2i:
	var w := 0
	for row in rows:
		w = maxi(w, String(row).length())
	return Vector2i(w, rows.size())


static func in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## The character at a cell, or "" out of bounds. Rows shorter than the grid read as
## air, again matching the loader.
static func char_at(rows: Array, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= rows.size() or cell.x < 0:
		return ""
	var row := String(rows[cell.y])
	if cell.x >= grid_size(rows).x:
		return ""
	return row[cell.x] if cell.x < row.length() else AIR


## Write `ch` at `cell`, returning the new rows. Out-of-bounds writes are dropped
## rather than growing the canvas: growing is `resize_rows`, and a stray brush
## stroke past the edge should do nothing, not silently reshape the region.
##
## Short rows are padded to the full width on the way, so a file hand-authored with
## ragged rows becomes rectangular the first time it is painted.
static func paint_rows(rows: Array, cell: Vector2i, ch: String) -> Array:
	var size := grid_size(rows)
	if not in_bounds(cell, size):
		return rows.duplicate()
	var out: Array = []
	for y in range(rows.size()):
		var row := String(rows[y]).rpad(size.x, AIR)
		if y == cell.y:
			row = row.substr(0, cell.x) + ch + row.substr(cell.x + 1)
		out.append(row)
	return out


## Write `ch` at every listed cell in one pass. A drag stroke is one call, so a
## thousand-cell fill does not rebuild the row list a thousand times.
static func paint_many(rows: Array, cells: Array, ch: String) -> Array:
	var size := grid_size(rows)
	var out: Array = []
	for y in range(rows.size()):
		out.append(String(rows[y]).rpad(size.x, AIR))
	for c in cells:
		var cell: Vector2i = c
		if not in_bounds(cell, size):
			continue
		var row: String = out[cell.y]
		out[cell.y] = row.substr(0, cell.x) + ch + row.substr(cell.x + 1)
	return out


## The cells a brush drag covers between two samples (Bresenham, both ends
## included). The mouse moves further than one cell per frame at any useful zoom,
## so painting only the cell under the cursor leaves a dotted line.
static func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var d := Vector2i(absi(b.x - a.x), -absi(b.y - a.y))
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err := d.x + d.y
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= d.y:
			err += d.y
			p.x += s.x
		if e2 <= d.x:
			err += d.x
			p.y += s.y
	return out


## The inclusive cell rectangle spanned by two corners, in either drag direction.
static func rect_of(a: Vector2i, b: Vector2i) -> Rect2i:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Every cell inside an inclusive corner-to-corner rectangle.
static func rect_cells(a: Vector2i, b: Vector2i) -> Array:
	var r := rect_of(a, b)
	var out: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


# ---------------------------------------------------------------------------
# Resizing a canvas
# ---------------------------------------------------------------------------

## Re-lay the rows onto a grid of `size`, with the OLD origin landing at `offset`.
##
## One call covers every edge: dragging the right edge out by 3 is
## `(offset=(0,0), size=(w+3,h))`; dragging the LEFT edge out by 3 is
## `(offset=(3,0), size=(w+3,h))` — the content slides right to stay put on screen.
## Cropping is the same with a negative offset. New space is air; content that
## falls outside is dropped.
##
## Every other cell-addressed thing in the region (tile data, doors, folds, lights,
## hands, spawn) has to move by the same `offset`, which is why `EditorDoc.resize`
## and not this function is the operation — this is only its raster half.
static func resize_rows(rows: Array, offset: Vector2i, size: Vector2i) -> Array:
	var out: Array = []
	for y in range(maxi(size.y, 0)):
		out.append(AIR.repeat(maxi(size.x, 0)))
	var old := grid_size(rows)
	for y in range(old.y):
		for x in range(old.x):
			var dst := Vector2i(x, y) + offset
			if not in_bounds(dst, size):
				continue
			var ch := char_at(rows, Vector2i(x, y))
			if ch == "" or ch == AIR:
				continue
			var row: String = out[dst.y]
			out[dst.y] = row.substr(0, dst.x) + ch + row.substr(dst.x + 1)
	return out


## Move an `"x,y"`-keyed dictionary (a region's `tile_data`) by `offset`, dropping
## entries that leave the grid.
static func shift_cell_keys(data: Dictionary, offset: Vector2i, size: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for key in data:
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		var dst := Vector2i(int(parts[0]), int(parts[1])) + offset
		if not in_bounds(dst, size):
			continue
		out["%d,%d" % [dst.x, dst.y]] = data[key]
	return out


# ---------------------------------------------------------------------------
# Fold guides
# ---------------------------------------------------------------------------

## Where a pre-placed fold would cut, WITHOUT cutting it.
##
## A fold anchored at two cells is fully determined by `Fold.create`, so the editor
## does not model crease geometry — it asks the kernel and draws the answer. That
## is also why the shaded area comes back from `CollisionCore.fold_polygons`: the
## strip this fold would excise is by definition what the real fold drops, so the
## area on the board is the same computation the game runs, not a lookalike.
##
## Returns, all in the region's LOCAL px space:
##   "crease1"/"crease2" : PackedVector2Array of 2 points — the cut lines, clipped
##                         to the region rect (empty if the line misses it)
##   "meeting"           : the line the two halves will come to rest along
##   "strip"              : Array of polygons — the space the fold excises
##   "orientation"       : "horizontal" / "vertical" / "diagonal"
##   "degenerate"        : true when both anchors are the same cell, which has no
##                         crease direction and is the one pair that is never a fold
static func fold_guides(a: Vector2i, b: Vector2i, size: Vector2i, cell: float) -> Dictionary:
	var out := {
		"crease1": PackedVector2Array(), "crease2": PackedVector2Array(),
		"meeting": PackedVector2Array(), "strip": [],
		"orientation": "", "degenerate": a == b,
	}
	if a == b:
		return out
	var fold := Fold.create(0, a, b, cell)
	var rect := Rect2(Vector2.ZERO, Vector2(size) * cell)
	var tangent := Vector2(-fold.crease_normal.y, fold.crease_normal.x)
	out["orientation"] = fold.orientation
	out["crease1"] = clip_line_to_rect(fold.crease_point1, tangent, rect)
	out["crease2"] = clip_line_to_rect(fold.crease_point2, tangent, rect)
	out["meeting"] = clip_line_to_rect(
		fold.crease_point1 + fold.shift_a_px(cell), tangent, rect)
	out["strip"] = CollisionCore.fold_polygons([rect_polygon(rect)], fold, cell)["dropped"]
	return out


static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])


## The segment of an infinite line inside a rectangle, as 2 points, or empty if it
## misses. Liang-Barsky on the parametric form, so a diagonal crease is handled by
## the same code as an axis-aligned one.
static func clip_line_to_rect(point: Vector2, dir: Vector2, rect: Rect2) -> PackedVector2Array:
	if dir.length_squared() < GeometryCore.EPSILON:
		return PackedVector2Array()
	var t0 := -INF
	var t1 := INF
	var p := [-dir.x, dir.x, -dir.y, dir.y]
	var q := [point.x - rect.position.x, rect.end.x - point.x,
		point.y - rect.position.y, rect.end.y - point.y]
	for i in range(4):
		var pi: float = p[i]
		var qi: float = q[i]
		if absf(pi) < GeometryCore.EPSILON:
			if qi < 0.0:
				return PackedVector2Array()   # parallel and outside
			continue
		var t := qi / pi
		if pi < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	if t0 > t1:
		return PackedVector2Array()
	return PackedVector2Array([point + dir * t0, point + dir * t1])
