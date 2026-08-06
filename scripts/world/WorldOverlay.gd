class_name WorldOverlay extends WrapCanvas

## WorldOverlay
##
## Draw-only layer for the fold world: anchor markers, the excised-band preview,
## seam-anchor diamonds (with unfoldability tint), the glue lines and outer seam
## anchor inside a subspace, doors and hands lying on the ground. Reads everything
## from its owning FoldWorld each frame.
##
## It is a `WrapCanvas`, so nothing here loops over copies of the space: `paint`
## draws one band's worth of markers and they appear in every band. What used to
## be a private `_copy_offsets` threaded through nine draw calls — and had to be
## remembered by every new marker — is now the base class's business.
##
## The two things that must NOT repeat go in `paint_once`: the full-extent axis
## guides and the translucent preview band. Repeated, they would tile the screen
## with lines and stack their alpha into a wash, and they read fine drawn once in
## the band you occupy.
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

# --- Gathered once per frame by `prepare`, drawn once per copy by `paint` ---
# Whether a seam can come out is a real question (it walks the newer folds and
# tests their bands), and a torus can be a hundred copies. Ask once.
var _markers: Dictionary = {}
var _in_reach: Array = []
var _exit_ok := true
var _doors: Array = []
var _hands_down: Array = []


func _process(_delta: float) -> void:
	queue_redraw()


func prepare() -> void:
	_markers = {}
	_in_reach = []
	_doors = []
	_hands_down = []
	if world == null or world.animating():
		return
	_markers = world.seam_markers()
	for fold in world.seams_within_burst():
		_in_reach.append({"fold": fold, "ok": world.can_unfold_fold(fold)})
	_exit_ok = world.exit_blocker() == null
	for id in world.doors:
		var wp = world.door_point_here(id)
		if wp != null:
			_doors.append(Vector2(wp))
	for entry in world.unpaired:
		_hands_down.append({"at": world.anchor_point(entry), "kind": int(entry["hand"]),
			"pulse": 0.0})
	for pair in world.primed:
		var pulse: float = _pulse_at(world.fuse_progress_of(pair))
		for entry in [pair["a"], pair["b"]]:
			_hands_down.append({"at": world.anchor_point(entry),
				"kind": int(entry["hand"]), "pulse": pulse})


func paint() -> void:
	if world == null or world.animating():
		return
	if not world.lattice.is_flat():
		_draw_glue()
		_draw_exit_anchor()
	_draw_seam_markers()
	_draw_doors()
	_draw_loose_hands()
	_draw_aim()
	_draw_placed_hands()
	_draw_burst()


## What belongs to the frame rather than to the space: guides that span the whole
## world, and the translucent band an armed pair would excise.
func paint_once() -> void:
	if world == null or world.animating():
		return
	var cs: float = world.base.cell_size
	var world_px := Vector2(world.base.grid_size) * cs
	for entry in _hands_down:
		if entry["at"] != null:
			_draw_guides(Vector2(entry["at"]), world_px)
	for pair in world.primed:
		var ca = world.anchor_point(pair["a"])
		var cb = world.anchor_point(pair["b"])
		if ca == null or cb == null:
			continue          # half of it is elsewhere; there is no band to draw
		_draw_band(Vector2(ca), Vector2(cb), world_px)


## A fuse, as a 0..1 throb. Frequency ramps with how far through that pair is, so it
## beats slowly when just lit and flutters when about to go.
func _pulse_at(p: float) -> float:
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
	for cell in _markers:
		var center: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * cs
		_draw_diamond(center, 12.0,
			Color("59e0d0") if bool(_markers[cell]) else Color("e06a6a", 0.9))


## Doors are warp POINTS riding tile centers: drawn only where the point
## strictly resolves in the current view (a split door draws nowhere — it is
## dormant).
func _draw_doors() -> void:
	for at in _doors:
		draw_arc(at, 12.0, 0, TAU, 20, Color("7ce07c"), STROKE)
		draw_circle(at, HAIR, Color("7ce07c", 0.9))


## Hands lying in the world — caches the world shipped and hands that popped out of a
## burst alike, drawn through `HandOrbit.draw_hand` so a hand on the ground is
## pixel-identical to one riding beside you.
func _draw_loose_hands() -> void:
	for entry in world.loose_hand_points():
		HandOrbit.draw_hand(self, Vector2(entry["pos"]), entry["pickup"].kind)


## The burst: a ring that snaps out to `BURST_RADIUS` and fades. It is the only thing
## that tells you how far the release reached, and it is drawn AFTER the fact, so its
## job is to confirm what just happened rather than to aim anything.
func _draw_burst() -> void:
	var t: float = world.burst_flash()
	if t <= 0.0:
		return
	var grow := 1.0 - t
	var r: float = world.BURST_RADIUS * (0.35 + 0.65 * sqrt(grow))
	draw_arc(world.player.global_position, r, 0, TAU, 40, Color("ffd27f", t * 0.8), STROKE)


## The way out of a fold: the outer fold's anchor point on the glue, where both
## of its original anchors coincide. A burst in reach of the white diamond opens
## the subspace; red means an inner fold is crossing the seam and holding it shut.
func _draw_exit_anchor() -> void:
	var outer: Fold = world.sub_fold
	if outer == null:
		return
	var col := Color(1, 1, 1, 0.95) if _exit_ok else Color("e06a6a", 0.95)
	_draw_diamond(outer.crease_point1, 12.0, col)
	# The ring lights when a burst from here would reach it — the exit is in
	# range, not aimed at.
	if world.glue_within_burst():
		draw_arc(outer.crease_point1, 20.0, 0, TAU, 24, col, STROKE)


## Where a tap would put a hand, what a burst from here would reach, and how far
## through a hold the key is.
func _draw_aim() -> void:
	var cs: float = world.base.cell_size
	var cand_center: Vector2 = (Vector2(world.candidate_anchor()) + Vector2(0.5, 0.5)) * cs

	# The aim ring takes the colour of the hand you would put down, so you can see
	# what kind of fold you are about to start before you start it — and reddens when
	# you have no hand to place at all.
	var next_hand: int = world.next_hand_type()
	var aim_col := Color("e06a6a", 0.55)
	if next_hand >= 0:
		aim_col = HandTypes.color(next_hand)
		aim_col.a = 0.45
	draw_arc(cand_center, 16.0, 0, TAU, 24, aim_col, HAIR)

	# Seams a burst from here would reach. The burst is not aimed, so what the ring
	# marks is REACH, not a target — walk closer and more of them light up.
	for entry in _in_reach:
		var seam: Vector2 = (Vector2(entry["fold"].meeting_pos) + Vector2(0.5, 0.5)) * cs
		draw_arc(seam, 20.0, 0, TAU, 24,
			Color("59e0d0") if bool(entry["ok"]) else Color("e06a6a", 0.7), STROKE)

	# A hold in progress fills a ring: the two gestures are distinguishable while
	# the key is still down, so a hold never lands as a surprise.
	var hold: float = world.hold_progress()
	if hold > 0.0:
		draw_arc(cand_center, 23.0, -PI / 2.0, -PI / 2.0 + TAU * hold, 32,
			Color("ffd27f"), STROKE)


## Every hand you have put down, in its OWN kind's colour, so a mixed pair reads as a
## mixed pair. Armed pairs pulse on that pair's own fuse: a slow breath winding up to
## a flutter as it comes due. Several can be armed at once and they beat at different
## rates, which is how you see which is about to go — no number could say that as
## quickly, and there is nothing to read but the beat.
func _draw_placed_hands() -> void:
	for entry in _hands_down:
		if entry["at"] == null:
			continue          # pinned somewhere this frame cannot show
		var at := Vector2(entry["at"])
		var pulse: float = entry["pulse"]
		var c: Color = HandTypes.color(int(entry["kind"]))
		draw_arc(at, 16.0 + pulse * 5.0, 0, TAU, 24, c, STROKE)
		if pulse > 0.0:
			draw_circle(at, 3.0 + pulse * 2.5, c)


## Soft full-extent guides through a placed hand. Folds may be diagonal; the guides
## just help line up straight ones.
func _draw_guides(at: Vector2, world_px: Vector2) -> void:
	var guide := Color(1, 1, 1, 0.08)
	draw_line(Vector2(0, at.y), Vector2(world_px.x, at.y), guide, HAIR)
	draw_line(Vector2(at.x, 0), Vector2(at.x, world_px.y), guide, HAIR)


## The translucent band an armed pair would excise: a parallelogram spanning well past
## the view, at whatever angle the pair implies.
func _draw_band(a_center: Vector2, b_center: Vector2, world_px: Vector2) -> void:
	if a_center.is_equal_approx(b_center):
		return
	var band := Color(0.95, 0.25, 0.3, 0.22)
	var bn := (b_center - a_center).normalized()
	var bt := Vector2(-bn.y, bn.x)
	var reach := world_px.length()
	draw_colored_polygon(PackedVector2Array([
		a_center + bt * reach, a_center - bt * reach,
		b_center - bt * reach, b_center + bt * reach,
	]), band)


## The identified crease lines — the glue — so the wrap reads as a real join
## rather than a rendering glitch. One pair per axis of the lattice: two lines
## down a cylinder, and all four walls of a torus when you are folded in twice.
func _draw_glue() -> void:
	for seg in world.glue_lines():
		draw_line(seg[0], seg[1], Color("59e0d0", 0.55), HAIR)


## Marker diamonds are snapped to the art-pixel grid: a diamond is only three
## pixels across, and half a pixel of drift is the difference between a shape
## and a smear. Lattice offsets are whole cells, so a copy is snapped too.
func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	var c := PixelArt.snap_round(center)
	var pts := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0),
		c + Vector2(0, r), c + Vector2(-r, 0),
	])
	draw_colored_polygon(pts, col)
