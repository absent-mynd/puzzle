class_name WorldOverlay extends Node2D

## WorldOverlay
##
## Draw-only layer for the fold prototype: anchor markers, the excised-band
## preview, seam-anchor diamonds (with unfoldability tint), the glue lines and
## outer seam anchor inside a subspace. Reads everything from its owning
## FoldWorld each frame.

var world  # FoldWorld; untyped to avoid a load-order cycle


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or world.animating():
		return
	var offsets := _copy_offsets()
	if world.mode == world.Mode.SUBSPACE:
		_draw_subspace_glue(offsets)
		_draw_subspace_markers(offsets)
	else:
		_draw_seam_markers()
	_draw_doors(offsets)
	_draw_anchor_and_preview(offsets)


## Where each visible copy of the current view sits. Inside a subspace the
## strip repeats across the glue, so everything that belongs to it — terrain,
## the player, doors, seam anchors, your aim — is drawn once per copy. Outside,
## there is one copy at the origin and every loop over this runs once.
func _copy_offsets() -> Array:
	if world.mode != world.Mode.SUBSPACE or world.sub_fold == null:
		return [Vector2.ZERO]
	var out: Array = []
	var n: Vector2 = world.sub_fold.crease_normal
	var gap: float = world.sub_fold.gap_distance()
	var copies: int = world.sub_copies
	for k in range(-copies, copies + 1):
		out.append(n * (k * gap))
	return out


func _draw_seam_markers() -> void:
	var cs: float = world.base.cell_size
	for fold in world.folds:
		var center: Vector2 = (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * cs
		var ok: bool = world.can_unfold_fold(fold)
		_draw_diamond(center, 10.0, Color("59e0d0") if ok else Color("e06a6a", 0.9))


## Doors are warp POINTS riding tile centers: drawn only where the point
## strictly resolves in the current view (a split door draws nowhere — it is
## dormant). Inside a subspace the glyph repeats across the wrap copies.
func _draw_doors(offsets: Array) -> void:
	for id in world.doors:
		var wp = world.door_point_here(id)
		if wp == null:
			continue
		for off in offsets:
			var p: Vector2 = Vector2(wp) + off
			draw_arc(p, 11.0, 0, TAU, 20, Color("7ce07c"), 3.0)
			draw_circle(p, 4.0, Color("7ce07c", 0.9))


## Inside the subspace: seam anchors of interior folds (every wrap copy), and
## the OUTER fold's anchor point on the glue — both original anchors coincide
## there; F at the white diamond unfolds the subspace.
func _draw_subspace_markers(offsets: Array) -> void:
	var cs: float = world.base.cell_size
	var outer: Fold = world.sub_fold
	if outer == null:
		return
	var exit_ok: bool = world.exit_blocker() == null
	var aimed_glue: bool = world.aiming_at_glue()
	for off in offsets:
		var glue_col := Color(1, 1, 1, 0.95) if exit_ok else Color("e06a6a", 0.95)
		_draw_diamond(outer.crease_point1 + off, 12.0, glue_col)
		if aimed_glue:
			draw_arc(outer.crease_point1 + off, 18.0, 0, TAU, 24, glue_col, 3.0)
		for fold in world.level_folds():
			var center: Vector2 = (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * cs + off
			var ok: bool = world.can_unfold_fold(fold)
			_draw_diamond(center, 10.0, Color("59e0d0") if ok else Color("e06a6a", 0.9))


## Point markers here repeat across the wrap copies, so a player copy is never
## shown standing next to an aim ring that isn't there. The full-extent guides
## and the preview band do NOT: repeated they would tile the screen with lines
## and stack their alpha, and they read fine drawn once in the band you occupy.
func _draw_anchor_and_preview(offsets: Array) -> void:
	var cs: float = world.base.cell_size
	var world_px := Vector2(world.base.grid_size) * cs

	# Where Q/E/F aim right now (follows pointing continuously).
	var cand: Vector2i = world.candidate_anchor()
	var cand_center: Vector2 = (Vector2(cand) + Vector2(0.5, 0.5)) * cs

	# Aimed seam: F here unfolds this fold.
	var aimed = world.aimed_fold()
	var aimed_center := Vector2.ZERO
	if aimed != null:
		aimed_center = (Vector2(aimed.meeting_pos) + Vector2(0.5, 0.5)) * cs

	# The aim ring reddens when you have no anchor left to pin — the limit is
	# visible on the cell you are pointing at, before you press anything.
	var out_of_anchors: bool = not world.can_pin_anchor() and world.pending_b == null
	var aim_col := Color("e06a6a", 0.55) if out_of_anchors else Color(1, 1, 1, 0.30)
	# A hold in progress fills a ring: the two gestures are distinguishable while
	# the key is still down, so a hold never lands as a surprise.
	var hold: float = world.hold_progress()

	for off in offsets:
		draw_arc(cand_center + off, 14.0, 0, TAU, 24, aim_col, 2.0)
		if aimed != null:
			draw_arc(aimed_center + off, 17.0, 0, TAU, 24, Color("59e0d0"), 3.0)
		if hold > 0.0:
			draw_arc(cand_center + off, 20.0, -PI / 2.0, -PI / 2.0 + TAU * hold, 32,
				Color("ffd27f"), 3.0)

	# The two pending anchor slots (Q = orange, E = blue), with soft axis
	# guides — folds may be diagonal; guides just help line up straight ones.
	var colors: Array = [Color("ff9d5c"), Color("5cc8ff")]
	var centers: Array = [null, null]
	for i in range(2):
		var cell = world.pending_cell(i)
		if cell == null:
			continue
		var c: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * cs
		centers[i] = c
		var guide := Color(1, 1, 1, 0.08)
		draw_line(Vector2(0, c.y), Vector2(world_px.x, c.y), guide, 1.0)
		draw_line(Vector2(c.x, 0), Vector2(c.x, world_px.y), guide, 1.0)
		for off in offsets:
			draw_arc(c + off, 14.0, 0, TAU, 24, colors[i], 3.0)

	if centers[0] == null or centers[1] == null:
		return
	if not WorldCore.anchors_valid(world.pending_cell(0), world.pending_cell(1)):
		return
	# Translucent band between the two crease lines: a parallelogram spanning
	# well past the view, at whatever angle the anchor pair implies. F commits.
	var a_center: Vector2 = centers[0]
	var b_center: Vector2 = centers[1]
	var band := Color(0.95, 0.25, 0.3, 0.22)
	var bn := (b_center - a_center).normalized()
	var bt := Vector2(-bn.y, bn.x)
	var reach := world_px.length()
	var quad := PackedVector2Array([
		a_center + bt * reach, a_center - bt * reach,
		b_center - bt * reach, b_center + bt * reach,
	])
	draw_colored_polygon(quad, band)


## Inside the subspace: mark the identified crease lines (the glue) so the
## wrap reads as a real join, not a rendering glitch.
func _draw_subspace_glue(offsets: Array) -> void:
	var fold: Fold = world.sub_fold
	if fold == null:
		return
	var n := fold.crease_normal
	var t := Vector2(-n.y, n.x)
	var c1 := fold.crease_point1.dot(n)
	var lo: float = world.sub_extent["min"] - 2.0 * world.base.cell_size
	var hi: float = world.sub_extent["max"] + 2.0 * world.base.cell_size
	for off in offsets:
		draw_line(n * c1 + t * lo + off, n * c1 + t * hi + off, Color("59e0d0", 0.55), 2.0)


func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0),
	])
	draw_colored_polygon(pts, col)
