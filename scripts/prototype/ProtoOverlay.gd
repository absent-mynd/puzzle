class_name ProtoOverlay extends Node2D

## ProtoOverlay
##
## Draw-only layer for the fold prototype: anchor markers, the excised-strip
## preview band, seam (meeting-line) markers, and the glue lines inside a
## subspace. Reads everything from its owning ProtoWorld each frame.

var world  # ProtoWorld; untyped to avoid a load-order cycle


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	if world.mode == world.Mode.SUBSPACE:
		_draw_subspace_glue()
		return
	_draw_seam_markers()
	_draw_anchor_and_preview()


func _draw_seam_markers() -> void:
	var cs: float = world.base.cell_size
	for fold in world.folds:
		var center: Vector2 = (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * cs
		_draw_diamond(center, 10.0, Color("59e0d0"))


func _draw_anchor_and_preview() -> void:
	var cs: float = world.base.cell_size
	var world_px := Vector2(world.base.grid_size) * cs

	# Where E would pin an anchor right now (follows pointing continuously).
	# Where Q/E/F aim right now (follows pointing continuously).
	var cand: Vector2i = world.candidate_anchor()
	var cand_ok: bool = world.base.is_in_bounds(cand)
	if cand_ok:
		var cand_center: Vector2 = (Vector2(cand) + Vector2(0.5, 0.5)) * cs
		draw_arc(cand_center, 14.0, 0, TAU, 24, Color(1, 1, 1, 0.30), 2.0)

	# Aimed seam: F here unfolds this fold.
	var aimed = world.aimed_fold()
	if aimed != null:
		var m: Vector2 = (Vector2(aimed.meeting_pos) + Vector2(0.5, 0.5)) * cs
		draw_arc(m, 17.0, 0, TAU, 24, Color("59e0d0"), 3.0)

	# The two pending anchor slots (Q = orange, E = blue), with soft axis
	# guides — folds may be diagonal; guides just help line up straight ones.
	var slots: Array = [
		{"cell": world.pending_a, "color": Color("ff9d5c")},
		{"cell": world.pending_b, "color": Color("5cc8ff")},
	]
	var centers: Array = []
	for s in slots:
		if s["cell"] == null:
			centers.append(null)
			continue
		var c: Vector2 = (Vector2(s["cell"]) + Vector2(0.5, 0.5)) * cs
		centers.append(c)
		var guide := Color(1, 1, 1, 0.08)
		draw_line(Vector2(0, c.y), Vector2(world_px.x, c.y), guide, 1.0)
		draw_line(Vector2(c.x, 0), Vector2(c.x, world_px.y), guide, 1.0)
		draw_arc(c, 14.0, 0, TAU, 24, s["color"], 3.0)

	if centers[0] == null or centers[1] == null:
		return
	if not ProtoCore.anchors_valid(world.pending_a, world.pending_b):
		return
	# Translucent band between the two crease lines: a parallelogram spanning
	# well past the view, at whatever angle the anchor pair implies. F commits.
	var a_center: Vector2 = centers[0]
	var b_center: Vector2 = centers[1]
	var band := Color(0.95, 0.25, 0.3, 0.22)
	var n := (b_center - a_center).normalized()
	var t := Vector2(-n.y, n.x)
	var reach := world_px.length()
	var quad := PackedVector2Array([
		a_center + t * reach, a_center - t * reach,
		b_center - t * reach, b_center + t * reach,
	])
	draw_colored_polygon(quad, band)


## Inside the subspace: mark the identified crease lines (the glue) so the
## wrap reads as a real join, not a rendering glitch.
func _draw_subspace_glue() -> void:
	var fold: Fold = world.sub_fold
	if fold == null:
		return
	var n := fold.crease_normal
	var t := Vector2(-n.y, n.x)
	var gap := fold.gap_distance()
	var c1 := fold.crease_point1.dot(n)
	var lo: float = world.sub_extent["min"] - 2.0 * world.base.cell_size
	var hi: float = world.sub_extent["max"] + 2.0 * world.base.cell_size
	var copies: int = world.sub_copies
	for k in range(-copies, copies + 1):
		var offset: float = c1 + k * gap
		var from := n * offset + t * lo
		var to := n * offset + t * hi
		draw_line(from, to, Color("59e0d0", 0.55), 2.0)


func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0),
	])
	draw_colored_polygon(pts, col)
