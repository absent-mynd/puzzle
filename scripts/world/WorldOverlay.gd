class_name WorldOverlay extends Node2D

## WorldOverlay
##
## Draw-only layer for the fold prototype: anchor markers, the excised-band
## preview, seam-anchor diamonds (with unfoldability tint), the glue lines and
## outer seam anchor inside a subspace. Reads everything from its owning
## FoldWorld each frame.
##
## The overlay draws INSIDE the pixel render target, so every stroke is measured
## in art pixels: a 1-unit line would be a quarter of a pixel and would flicker
## in and out of existence as it moved. Widths are multiples of `HAIR`, and
## marker centres are snapped, so the markers stay crisp and stationary.
##
## It is also drawn UNLIT, on purpose. Lighting is style; the markers you
## navigate and fold by must read the same in a dark corner as under a lamp.

## One art pixel.
const HAIR := PixelArt.WORLD_PER_PIXEL
## Two art pixels — for anything that has to be found at a glance.
const STROKE := HAIR * 2.0

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
	_draw_loose_hands(offsets)
	_draw_anchor_and_preview(offsets)
	_draw_burst(offsets)


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


## The fuse, as a 0..1 throb. Frequency ramps with how far through the fuse we are,
## so the pair beats slowly when it is just lit and flutters when it is about to go.
## Returns 0 when no fuse is running, which switches the pulse off entirely rather
## than leaving the rings breathing at rest.
func _fuse_pulse() -> float:
	if not world.fuse_running():
		return 0.0
	var p: float = world.fuse_progress()
	var hz: float = lerpf(2.2, 11.0, p * p)
	var wave := 0.5 - 0.5 * cos(Time.get_ticks_msec() / 1000.0 * hz * TAU)
	# Deepen the swing as well as quickening it: late pulses read as urgent, not
	# merely fast.
	return wave * lerpf(0.55, 1.0, p)


## One diamond per meeting CELL, not per fold: folds can share a seam cell, and
## stacking two markers there would draw the buried fold's refusal over the free
## fold's invitation. `world.seam_markers()` resolves the cell the same way a burst
## does — it reports the cell open if anything there can actually come out.
func _draw_seam_markers() -> void:
	var cs: float = world.base.cell_size
	var markers: Dictionary = world.seam_markers()
	for cell in markers:
		var center: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * cs
		_draw_diamond(center, 12.0,
			Color("59e0d0") if bool(markers[cell]) else Color("e06a6a", 0.9))


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
			draw_arc(p, 12.0, 0, TAU, 20, Color("7ce07c"), STROKE)
			draw_circle(p, HAIR, Color("7ce07c", 0.9))


## Hands lying in the world — caches the world shipped and hands that popped out of a
## burst alike, drawn through `HandOrbit.draw_hand` so a hand on the ground is
## pixel-identical to one riding beside you. They repeat across the wrap copies like
## doors do, because a strip is a cylinder and so is everything on it.
func _draw_loose_hands(offsets: Array) -> void:
	for entry in world.loose_hand_points():
		for off in offsets:
			HandOrbit.draw_hand(self, Vector2(entry["pos"]) + off, entry["pickup"].kind)


## The burst: a ring that snaps out to `BURST_RADIUS` and fades. It is the only thing
## that tells you how far the release reached, and it is drawn AFTER the fact, so its
## job is to confirm what just happened rather than to aim anything.
func _draw_burst(offsets: Array) -> void:
	var t: float = world.burst_flash()
	if t <= 0.0:
		return
	var grow := 1.0 - t
	var r: float = world.BURST_RADIUS * (0.35 + 0.65 * sqrt(grow))
	var col := Color("ffd27f", t * 0.8)
	for off in offsets:
		draw_arc(world.player.global_position + off, r, 0, TAU, 40, col, STROKE)


## Inside the subspace: seam anchors of interior folds (every wrap copy), and
## the OUTER fold's anchor point on the glue — both original anchors coincide
## there; F at the white diamond unfolds the subspace.
func _draw_subspace_markers(offsets: Array) -> void:
	var cs: float = world.base.cell_size
	var outer: Fold = world.sub_fold
	if outer == null:
		return
	var exit_ok: bool = world.exit_blocker() == null
	# The glue ring lights when a burst from here would reach it — the exit is in
	# range, not aimed at.
	var glue_in_reach: bool = world.glue_within_burst()
	var markers: Dictionary = world.seam_markers()
	for off in offsets:
		var glue_col := Color(1, 1, 1, 0.95) if exit_ok else Color("e06a6a", 0.95)
		_draw_diamond(outer.crease_point1 + off, 12.0, glue_col)
		if glue_in_reach:
			draw_arc(outer.crease_point1 + off, 20.0, 0, TAU, 24, glue_col, STROKE)
		for cell in markers:
			var center: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * cs + off
			_draw_diamond(center, 12.0,
				Color("59e0d0") if bool(markers[cell]) else Color("e06a6a", 0.9))


## Point markers here repeat across the wrap copies, so a player copy is never
## shown standing next to an aim ring that isn't there. The full-extent guides
## and the preview band do NOT: repeated they would tile the screen with lines
## and stack their alpha, and they read fine drawn once in the band you occupy.
func _draw_anchor_and_preview(offsets: Array) -> void:
	var cs: float = world.base.cell_size
	var world_px := Vector2(world.base.grid_size) * cs

	# Where a tap would put a hand (follows pointing continuously).
	var cand: Vector2i = world.candidate_anchor()
	var cand_center: Vector2 = (Vector2(cand) + Vector2(0.5, 0.5)) * cs

	# Seams a burst from here would reach. The burst is not aimed, so what the ring
	# marks is REACH, not a target — walk closer and more of them light up.
	var in_reach: Array = world.seams_within_burst()

	# The aim ring takes the colour of the hand you would put down, so you can see
	# what kind of fold you are about to start before you start it — and reddens when
	# you have no hand to place at all.
	var next_hand: int = world.next_hand_type()
	var aim_col := Color("e06a6a", 0.55)
	if next_hand >= 0:
		aim_col = HandTypes.color(next_hand)
		aim_col.a = 0.45
	# A hold in progress fills a ring: the two gestures are distinguishable while
	# the key is still down, so a hold never lands as a surprise.
	var hold: float = world.hold_progress()

	for off in offsets:
		draw_arc(cand_center + off, 16.0, 0, TAU, 24, aim_col, HAIR)
		for fold in in_reach:
			var seam: Vector2 = (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * cs
			var ok: bool = world.can_unfold_fold(fold)
			draw_arc(seam + off, 20.0, 0, TAU, 24,
				Color("59e0d0") if ok else Color("e06a6a", 0.7), STROKE)
		if hold > 0.0:
			draw_arc(cand_center + off, 23.0, -PI / 2.0, -PI / 2.0 + TAU * hold, 32,
				Color("ffd27f"), STROKE)

	# The placed hands, each drawn in its OWN kind's colour — a mixed pair is legible
	# as a mixed pair — with soft axis guides (folds may be diagonal; the guides just
	# help line up straight ones).
	#
	# Once both are down they PULSE, and the pulse is the fuse: it starts as a slow
	# breath and winds up to a flutter as the fold comes due. Nothing tells you the
	# number of seconds, because the thing worth reading is "how long have I got",
	# and a quickening beat says that better than a countdown does.
	var centers: Array = [null, null]
	var pulse := _fuse_pulse()
	for i in range(2):
		var cell = world.pending_cell(i)
		if cell == null:
			continue
		var entry = world.pending_slot(i)
		var col: Color = HandTypes.color(int(entry["hand"])) if entry != null else Color.WHITE
		var c: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * cs
		centers[i] = c
		var guide := Color(1, 1, 1, 0.08)
		draw_line(Vector2(0, c.y), Vector2(world_px.x, c.y), guide, HAIR)
		draw_line(Vector2(c.x, 0), Vector2(c.x, world_px.y), guide, HAIR)
		for off in offsets:
			draw_arc(c + off, 16.0 + pulse * 5.0, 0, TAU, 24, col, STROKE)
			if pulse > 0.0:
				draw_circle(c + off, 3.0 + pulse * 2.5, col)

	if centers[0] == null or centers[1] == null:
		return
	if not WorldCore.anchors_valid(world.pending_cell(0), world.pending_cell(1)):
		return
	# Translucent band between the two crease lines: a parallelogram spanning
	# well past the view, at whatever angle the anchor pair implies. It folds itself.
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
		draw_line(n * c1 + t * lo + off, n * c1 + t * hi + off, Color("59e0d0", 0.55), HAIR)


## Marker diamonds are snapped to the art-pixel grid: a diamond is only three
## pixels across, and half a pixel of drift is the difference between a shape
## and a smear.
func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	var c := PixelArt.snap_round(center)
	var pts := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0),
		c + Vector2(0, r), c + Vector2(-r, 0),
	])
	draw_colored_polygon(pts, col)
