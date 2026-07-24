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
	for i in range(world.folds.size()):
		var fold: Fold = world.folds[i]
		var center := (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * cs
		var is_last: bool = i == world.folds.size() - 1
		var col := Color("59e0d0") if is_last else Color("59e0d0", 0.45)
		_draw_diamond(center, 10.0, col)


func _draw_anchor_and_preview() -> void:
	var cs: float = world.base.cell_size
	var world_px := Vector2(world.base.grid_size) * cs

	# Where E would pin an anchor right now (follows pointing continuously).
	var cand: Vector2i = world.candidate_anchor()
	var cand_ok: bool = world.base.is_in_bounds(cand)
	var cand_center := (Vector2(cand) + Vector2(0.5, 0.5)) * cs
	if cand_ok:
		draw_arc(cand_center, 14.0, 0, TAU, 24, Color("ff9d5c", 0.35), 2.0)

	if world.pending_anchor == null:
		return
	var a: Vector2i = world.pending_anchor
	var a_center := (Vector2(a) + Vector2(0.5, 0.5)) * cs
	# Alignment guides: the row/column the second anchor must land on.
	var guide := Color(1, 1, 1, 0.10)
	draw_line(Vector2(0, a_center.y), Vector2(world_px.x, a_center.y), guide, 1.0)
	draw_line(Vector2(a_center.x, 0), Vector2(a_center.x, world_px.y), guide, 1.0)
	draw_arc(a_center, 14.0, 0, TAU, 24, Color("ff9d5c"), 3.0)

	if not cand_ok or not ProtoCore.anchors_valid(a, cand):
		return
	# Translucent band between the two crease lines, spanning the world.
	var band := Color(0.95, 0.25, 0.3, 0.22)
	if a.y == cand.y:
		var x0 := minf(a_center.x, cand_center.x)
		var x1 := maxf(a_center.x, cand_center.x)
		draw_rect(Rect2(x0, 0, x1 - x0, world_px.y), band)
	else:
		var y0 := minf(a_center.y, cand_center.y)
		var y1 := maxf(a_center.y, cand_center.y)
		draw_rect(Rect2(0, y0, world_px.x, y1 - y0), band)
	draw_arc(cand_center, 14.0, 0, TAU, 24, Color("ff9d5c", 0.8), 3.0)


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
