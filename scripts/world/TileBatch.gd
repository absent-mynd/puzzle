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
		var tint := Color.WHITE if _atlas != null else TileAtlas.base_color(piece.type)
		for off in copies:
			var start: int = group["verts"].size()
			var idx := PackedInt32Array()
			for i in range(poly.size()):
				group["verts"].append(poly[i] + off)
				group["local"].append(poly[i])
				group["copy"].append(off)
				group["colors"].append(tint)
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
		if _atlas != null:
			vis.texture = _atlas
			vis.uv = group["uv"]
			vis.color = Color.WHITE
		else:
			# No tileset: fall back to flat per-type colour, which has to travel
			# per vertex now that a hundred types share one node.
			vis.vertex_colors = group["colors"]
		if _rig != null:
			var mat := _rig.material_for_key(key)
			if mat != null:
				vis.material = mat
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


func _cell() -> float:
	return _base.cell_size if _base != null else WorldCore.CELL
