class_name TileBatch extends Node2D

## TileBatch
##
## Every drawn piece of the sheet, in as few canvas items as the materials
## allow — which is two: what stops you, and what you move through.
##
## A region is ~800 base tiles, a fold cuts pieces out of them, and inside a
## fold the whole strip is drawn again in every visible copy. One `Polygon2D` per
## piece per copy meant thousands of nodes torn down and rebuilt on every
## single fold, which is the most expensive thing the game did. `Polygon2D` can
## hold many sub-polygons over one vertex array (`polygons`), and the tileset is
## one texture, so the ONLY thing that forces a second node is the lit material.
##
## So the wrap is baked into the vertices here rather than repeated through
## `WrapCanvas`: this content is static between rebuilds, and a copy of it costs
## nothing but vertices. The rule for the world at large:
##
##     anything that MOVES repeats through `WrapCanvas`;
##     anything STATIC bakes its copies at rebuild.
##
## Appearance is still per piece and still a base-space fact — kind, variant
## and UVs all come from `TileAtlas` against the piece's `base_id` and
## `src_offset`, so a tile looks the same however it has been folded or cut. The
## batch changes how many draw calls that costs, not what is drawn.
##
## ## What rides in the vertex colour
##
## The sheet is textured, so its vertex colours were spare — and the lit shader needs
## two base-space facts per vertex that the texture cannot carry: WHICH of the tile's
## four neighbours matter, and WHERE in the tile the vertex sits. They travel as
##
##     r   neighbour mask / 15   (UP | RIGHT | DOWN | LEFT)
##     g   how deep in solid mass / MAX_DEPTH
##     b,a position in the base cell, 0..1
##
## and `pixel_lit.gdshader` turns them into a rim on what stops you, a contact shadow
## on what you move through, and rock that darkens away from its surface. "Matters" means the opposite thing for the two
## groups — an OPEN neighbour for a solid, a SOLID one for air — because a rim is
## where something ends and a shadow is where something else begins. Both are read
## off the BASE grid, like the wall's lit cap, so they are cut by a crease exactly as
## the art is and never re-carved by the folded neighbourhood.

## A group's pieces, kept so a fold transition can deform them in place
## without rebuilding the batch: `{"poly": Polygon2D, "local": PackedVector2Array,
## "copy": PackedVector2Array}` — `local` is each vertex before its copy offset,
## `copy` the offset itself.
var _groups: Dictionary = {}

var _atlas: Texture2D = null
var _rig: LightRig = null
var _base: BaseGrid = null


func setup(atlas: Texture2D, rig: LightRig, base: BaseGrid) -> void:
	_atlas = atlas
	_rig = rig
	_base = base


## Draw `frags` — `[{"piece": FoldedPiece, "poly": PackedVector2Array}, ...]` — once
## at every offset in `copies`. Replaces whatever was here before.
##
## `poly` is passed apart from `piece` because a fold transition draws
## SUB-pieces of a piece, cut again by the crease being applied. They share the
## piece's `src_offset`, so their UVs come out of the same base tile and the art
## slides with the geometry instead of swimming across it.
func rebuild(frags: Array, copies: Array) -> void:
	var acc: Dictionary = {}
	var inked := _inked()
	for frag in frags:
		var piece = frag["piece"]
		var poly: PackedVector2Array = frag["poly"]
		if poly.size() < 3:
			continue
		var key := _key_of(piece.type)
		if not acc.has(key):
			acc[key] = {"verts": PackedVector2Array(), "uv": PackedVector2Array(),
				"colors": PackedColorArray(), "polys": [], "local": PackedVector2Array(),
				"copy": PackedVector2Array()}
		var group: Dictionary = acc[key]
		var kind := _kind_of(piece)
		var uv := TileAtlas.uv_for(poly, piece.src_offset, kind,
			TileAtlas.variant_for(piece.base_id), _cell())
		# Three cases for the colour channel. Lit: it is DATA, which the material takes
		# and clears. No tileset: it is the colour, because nothing else says what a
		# tile looks like. A tileset and nothing to light it: white, so the art
		# arrives as painted.
		var data := PackedColorArray()
		if inked:
			data = tile_data(poly, piece)
		var flat := Color.WHITE if _atlas != null else TileAtlas.base_color(piece.type)
		for off in copies:
			var start: int = group["verts"].size()
			var idx := PackedInt32Array()
			for i in range(poly.size()):
				group["verts"].append(poly[i] + off)
				group["local"].append(poly[i])
				group["copy"].append(off)
				group["colors"].append(data[i] if data.size() == poly.size() else flat)
				if uv.size() == poly.size():
					group["uv"].append(uv[i])
				idx.append(start + i)
			group["polys"].append(idx)
	_apply(acc)


## Slide a whole group, copies and all. A flap's shift is a translation, so the
## transition moves the A and B halves with two assignments rather than by
## touching a vertex.
func shift_group(type_key: String, by: Vector2) -> void:
	var group = _groups.get(type_key)
	if group != null:
		(group["poly"] as Polygon2D).position = by


## Move every vertex of this batch, given a function of its position within its
## own copy. The copy offset is taken off before the call and put back after, so
## a deformation that is defined about a crease line applies to each strip about
## its OWN crease — which is what a fold looks like from inside one.
func deform(fn: Callable) -> void:
	for key in _groups:
		var group: Dictionary = _groups[key]
		var local: PackedVector2Array = group["local"]
		var copy: PackedVector2Array = group["copy"]
		var out := PackedVector2Array()
		out.resize(local.size())
		for i in range(local.size()):
			out[i] = fn.call(local[i]) + copy[i]
		(group["poly"] as Polygon2D).polygon = out


## Drop the batch's nodes. Freed outright rather than queued: these are pure
## visuals with nothing in the physics server behind them, and a rebuild that left
## the old sheet standing until the end of the frame would draw both.
func clear() -> void:
	for key in _groups:
		var node: Node = _groups[key]["poly"]
		remove_child(node)
		node.free()
	_groups = {}


## The Polygon2D nodes this batch drew into. For tests and for anything that
## wants to tint or hide the whole sheet at once.
func layers() -> Array:
	var out: Array = []
	for key in _groups:
		out.append(_groups[key]["poly"])
	return out


func _apply(acc: Dictionary) -> void:
	clear()
	for key in acc:
		var group: Dictionary = acc[key]
		var vis := Polygon2D.new()
		vis.polygon = group["verts"]
		vis.polygons = group["polys"]
		vis.vertex_colors = group["colors"]
		if _atlas != null:
			vis.texture = _atlas
			vis.uv = group["uv"]
			vis.color = Color.WHITE
			if _inked():
				vis.material = _rig.material_for_key(key)
		add_child(vis)
		_groups[key] = {"poly": vis, "local": group["local"], "copy": group["copy"]}


## Which material group a piece belongs to. Walkability, not the type list:
## what stops you is foreground, what you move through is background — so a new
## tile type lands in the right group without touching this file.
func _key_of(type: int) -> String:
	return LightRig.BG if TileTypes.is_walkable(type) else LightRig.FG


## Which tileset row a piece draws from. The "open sky above" edge kind is
## decided in BASE space, so a wall keeps its lit cap when a fold slides it under
## something else — material belongs to the sheet, not to the current stacking.
func _kind_of(piece) -> int:
	var open_above := false
	if piece.type == TileTypes.WALL and _base != null:
		var tile := _base.tile_by_id(piece.base_id)
		if tile != null:
			var above := _base.tile_at(tile.grid_position + Vector2i(0, -1))
			open_above = above == null or above.type == TileTypes.EMPTY
	return TileAtlas.kind_for(piece.type, open_above)


## Whether the vertex colours are data. They are exactly when the material that reads
## them will be on the node — the two must never come apart, or the data tints the art.
func _inked() -> bool:
	return _atlas != null and _rig != null and _rig.material_for_key(LightRig.FG) != null


## The shader's facts for every vertex of a piece: its base tile's neighbour mask and
## depth, and where in that tile the vertex sits. See the header.
func tile_data(poly: PackedVector2Array, piece) -> PackedColorArray:
	var out := PackedColorArray()
	var cell := _cell()
	var mask := float(ink_mask(piece)) / 15.0
	var depth := float(ink_depth(piece)) / float(MAX_DEPTH)
	# The base cell comes from the centroid, as it does for the UVs: a vertex can sit
	# exactly on a cell boundary, the interior cannot.
	var base_poly := PackedVector2Array()
	for v in poly:
		base_poly.append(Vector2(v) - piece.src_offset)
	var origin := (GeometryCore.polygon_centroid(base_poly) / cell).floor() * cell
	for v in base_poly:
		var local := ((Vector2(v) - origin) / cell).clamp(Vector2.ZERO, Vector2.ONE)
		out.append(Color(mask, depth, local.x, local.y))
	return out


## Which of a piece's four BASE neighbours matter to how it is inked: the open ones
## for something solid (it gets a rim there), the solid ones for something you move
## through (it gets a shadow there). Off the edge of the grid counts as open.
const UP := 1
const RIGHT := 2
const DOWN := 4
const LEFT := 8
const NEIGHBOURS := [[Vector2i(0, -1), UP], [Vector2i(1, 0), RIGHT], [Vector2i(0, 1), DOWN],
	[Vector2i(-1, 0), LEFT]]


func ink_mask(piece) -> int:
	if _base == null:
		return 0
	var tile := _base.tile_by_id(piece.base_id)
	if tile == null:
		return 0
	var solid := not TileTypes.is_walkable(piece.type)
	var mask := 0
	for entry in NEIGHBOURS:
		var other := _base.tile_at(tile.grid_position + (entry[0] as Vector2i))
		var other_solid := other != null and not TileTypes.is_walkable(other.type)
		if other_solid != solid:
			mask |= int(entry[1])
	return mask


## How many tiles of solid stand between a piece's base tile and the nearest thing you
## can move through, up to `MAX_DEPTH`: 0 for air and for a surface, 1 for the tile
## behind the surface, and so on. It is what lets the shader draw a wall's face as
## authored and let the mass behind it fall away, so a room reads as SHAPES rather
## than as a field of brick.
##
## The edge of the sheet is not open air here, though it is for the rim: a floor
## should run dark into the bottom of its room, and then end on a line.
const MAX_DEPTH := 3


func ink_depth(piece) -> int:
	if _base == null:
		return 0
	return int(_depths().get(piece.base_id, 0))


## Every base tile's depth, flooded outward from the open tiles once per grid. The
## base never changes, so neither does this; it is kept against the grid it was
## computed for and redone only if `setup` hands over another.
var _depth_cache: Dictionary = {}
var _depth_of: BaseGrid = null


func _depths() -> Dictionary:
	if _depth_of == _base:
		return _depth_cache
	_depth_of = _base
	_depth_cache = {}
	var frontier: Array = []
	for tile in _base.tiles:
		if TileTypes.is_walkable(tile.type):
			_depth_cache[tile.base_id] = 0
			frontier.append(tile.grid_position)
	# Breadth-first, so the first time a tile is reached is by its shortest way out.
	# A surface tile is one step from air and reads 0; hence the `- 1`.
	var steps := 0
	while not frontier.is_empty() and steps <= MAX_DEPTH:
		steps += 1
		var next: Array = []
		for pos in frontier:
			for entry in NEIGHBOURS:
				var other := _base.tile_at((pos as Vector2i) + (entry[0] as Vector2i))
				if other == null or _depth_cache.has(other.base_id):
					continue
				_depth_cache[other.base_id] = steps - 1
				next.append(other.grid_position)
		frontier = next
	for tile in _base.tiles:
		if not _depth_cache.has(tile.base_id):
			_depth_cache[tile.base_id] = MAX_DEPTH
	return _depth_cache


func _cell() -> float:
	return _base.cell_size if _base != null else WorldCore.CELL
