class_name WorldOverlay extends WrapCanvas

## WorldOverlay
##
## Draw-only layer for the fold world: anchor markers, the excised-strip preview,
## seam-anchor diamonds (with unfoldability tint), the glue lines and outer seam
## anchor inside a subspace, doors and hands lying on the ground.
##
## It draws an `OverlayView` and knows nothing else. It does not hold `FoldWorld`,
## cannot ask it anything, and has no way to find it — which is the point. It used
## to hold the world untyped (naming it would have closed a load-order cycle) and
## reach into two dozen members at will; two of those reaches were allocating
## queries that had drifted into the per-copy draw path, where on a torus they cost
## 16.3 ms of a 16.6 ms frame. See `OverlayView`.
##
## It is a `WrapCanvas`, so nothing here loops over copies of the space: `paint`
## draws one copy's worth of markers and they appear in every copy. What used to
## be a private `_copy_offsets` threaded through nine draw calls — and had to be
## remembered by every new marker — is now the base class's business.
##
## The excised-strip preview and the alignment guides repeat like everything else,
## but they are the one thing that has to be CLIPPED first: both span the whole
## world, so unclipped copies would lie on top of each other and stack their alpha
## into a wash. Clipped to the fundamental domain each copy paints its own strip and
## the tiling is exact. In a space that does not repeat there is no domain, nothing
## is clipped, and this is the single strip it always was.
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

var _view := OverlayView.new()

## The preview strip and the guides, clipped to one copy of the space. Built when the
## view arrives — once per frame — rather than per copy, which is the whole lesson of
## `OverlayView`: `Geometry2D.intersect_polygons` is not free.
var _strips: Array = []
var _guides: Array = []
## ...and the strip the raised hand WOULD excise, kept apart from `_strips` because it is
## a proposal rather than a fact and must not be drawn as one.
var _aim_strip: Array = []


## Take the frame's description and redraw. The only way anything gets in here.
func set_view(view: OverlayView) -> void:
	_view = view if view != null else OverlayView.new()
	_rebuild_preview()
	queue_redraw()


## The strip an armed pair would excise, and the guides through every placed hand.
func _rebuild_preview() -> void:
	_strips = []
	_guides = []
	_aim_strip = []
	if not _view.active:
		return
	if _view.aiming and _view.aim_pair != null:
		_aim_strip = _clip(_strip_polygon(
			_view.aim_at, Vector2(_view.aim_pair), _view.world_px))
	var world_px := _view.world_px
	for entry in _view.hands_down:
		if entry["at"] == null:
			continue
		var at := Vector2(entry["at"])
		_guides.append_array(_clip(PackedVector2Array([
			Vector2(0, at.y - HAIR * 0.5), Vector2(world_px.x, at.y - HAIR * 0.5),
			Vector2(world_px.x, at.y + HAIR * 0.5), Vector2(0, at.y + HAIR * 0.5),
		])))
		_guides.append_array(_clip(PackedVector2Array([
			Vector2(at.x - HAIR * 0.5, 0), Vector2(at.x + HAIR * 0.5, 0),
			Vector2(at.x + HAIR * 0.5, world_px.y), Vector2(at.x - HAIR * 0.5, world_px.y),
		])))
	for pair in _view.pairs:
		_strips.append_array(
			_clip(_strip_polygon(Vector2(pair["a"]), Vector2(pair["b"]), world_px)))


## `poly` cut down to one copy of the space. A domain of fewer than three points
## means the space does not repeat, and then there is nothing to cut it down to.
##
## Nothing undrawable comes out of here. Fewer than three points is not a polygon
## and `draw_colored_polygon` refuses one — once per copy of the space, every frame,
## for as long as it sits in the view. The clipping branch dropped a degenerate
## polygon for free, since `intersect_polygons` returns nothing for one; the branch
## that does NOT clip passed it straight through. So two anchors pinned to a single
## cell errored for the whole length of their fuse in a region, and not at all
## inside a fold. Both branches answer alike now: no polygon in, no polygons out.
func _clip(poly: PackedVector2Array) -> Array:
	if poly.size() < 3:
		return []
	if _view.domain.size() < 3:
		return [poly]
	return Geometry2D.intersect_polygons(poly, _view.domain)


func paint() -> void:
	if not _view.active:
		return
	if not _view.flat:
		_draw_glue()
		_draw_exit_anchor()
	_draw_seam_markers()
	_draw_doors()
	_draw_loose_hands()
	_draw_aim()
	_draw_placed_hands()
	_draw_preview()
	_draw_burst()


## A fuse, as a 0..1 throb. Frequency ramps with how far through that pair is, so it
## beats slowly when just lit and flutters when about to go.
##
## On `WorldClock`, so a fuse that has stopped burning has also stopped beating. A
## pulse is a countdown drawn as a rhythm, and one still fluttering over a stopped
## fuse would be counting down to nothing.
func _pulse_at(p: float) -> float:
	if p <= 0.0:
		return 0.0
	var hz: float = lerpf(2.2, 11.0, p * p)
	var wave := 0.5 - 0.5 * cos(WorldClock.now() * hz * TAU)
	# Deepen the swing as well as quickening it: late pulses read as urgent, not
	# merely fast.
	return wave * lerpf(0.55, 1.0, p)


## One diamond per meeting CELL, not per fold: folds can share a seam cell, and
## stacking two markers there would draw the buried fold's refusal over the free
## fold's invitation. The view resolves the cell the same way a burst does — it
## reports the cell open if anything there can actually come out.
func _draw_seam_markers() -> void:
	var cs := _view.cell_size
	for cell in _view.markers:
		var center: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * cs
		_draw_diamond(center, 12.0,
			Color("59e0d0") if bool(_view.markers[cell]) else Color("e06a6a", 0.9))


## Doors are warp POINTS riding tile centers: drawn only where the point
## strictly resolves in the current view (a split door draws nowhere — it is
## dormant).
func _draw_doors() -> void:
	for at in _view.doors:
		draw_arc(at, 12.0, 0, TAU, 20, Color("7ce07c"), STROKE)
		draw_circle(at, HAIR, Color("7ce07c", 0.9))


## Hands lying in the world — loose hands the world shipped and hands that popped out of a
## burst alike, drawn through `HandOrbit.draw_hand` so a hand on the ground is
## pixel-identical to one riding beside you, idle float and all.
##
## Every copy of one hand takes that hand's own drift seed, so the copies float in step:
## they are one object seen several times, and copies bobbing out of phase would say
## otherwise. The seed comes from the hand's base identity rather than its place in the
## list — see `WorldCore.hand_drift_seed`. (The copies themselves are `WrapCanvas`'s
## business: this draws one copy's worth and they appear in every copy.)
##
## The float does NOT move the hand. `_check_pickups` measures from `position_in`, so a
## hand is picked up where it lies; the drift is only ever how it is drawn, which is why
## its radius is a fraction of the pickup range.
##
## Hands still in the air are drawn from their own live position — the one kind of
## thing in the world that has one. Same glyph, because it is the same hand: what is
## different is that it is still moving.
func _draw_loose_hands() -> void:
	for entry in _view.loose:
		HandOrbit.draw_hand(self, Vector2(entry["pos"]), int(entry["kind"]),
			float(entry["seed"]))
	for ball in _view.balls:
		HandOrbit.draw_hand(self, Vector2(ball["pos"]), int(ball["kind"]),
			float(ball["seed"]))


## The burst: a ring that snaps out and fades. It is the only thing that tells you
## how far the release reached, and it is drawn AFTER the fact, so its job is to
## confirm what just happened rather than to aim anything.
func _draw_burst() -> void:
	var t := _view.burst_t
	if t <= 0.0:
		return
	var grow := 1.0 - t
	var r: float = _view.burst_radius * (0.35 + 0.65 * sqrt(grow))
	draw_arc(_view.burst_at, r, 0, TAU, 40, Color("ffd27f", t * 0.8), STROKE)


## The way out of a fold: the outer fold's anchor point on the glue, where both
## of its original anchors coincide. A burst in reach of the white diamond opens
## the subspace; red means an inner fold is crossing the seam and holding it shut.
func _draw_exit_anchor() -> void:
	if _view.exit_at == null:
		return
	var at := Vector2(_view.exit_at)
	var col := Color(1, 1, 1, 0.95) if _view.exit_ok else Color("e06a6a", 0.95)
	_draw_diamond(at, 12.0, col)
	# The ring lights when a burst from here would reach it — the exit is in
	# range, not aimed at.
	if _view.exit_in_burst:
		draw_arc(at, 20.0, 0, TAU, 24, col, STROKE)


## The colour of the hand a tap would put down: that kind's own, and RED when you have
## none to put down at all. Both the ring and the cursor are drawn in it, so "what am I
## about to spend" is one answer wearing two shapes.
func _aim_colour() -> Color:
	return Color("e06a6a") if _view.aim_hand < 0 else HandTypes.color(_view.aim_hand)


## Where a tap would put a hand, and what a burst from here would reach.
##
## A burst being CHARGED is drawn nowhere near here: it is a tint on the body. This
## used to fill a ring at `aim_at`, which said the wrong thing twice over — the
## burst is not aimed at that cell, and a ring is not subtle enough to be the thing
## you look at through every tap.
func _draw_aim() -> void:
	if _view.aiming:
		_draw_cursor()
	else:
		# A ring on the cell a raise would START from, so you can see what kind of fold
		# you would be starting before you start it.
		var col := _aim_colour()
		col.a = 0.55 if _view.aim_hand < 0 else 0.45
		draw_arc(_view.aim_at, 16.0, 0, TAU, 24, col, HAIR)

	# Seams a burst from here would reach. The burst is not aimed, so what the ring
	# marks is REACH, not a target — walk closer and more of them light up.
	for entry in _view.in_reach:
		draw_arc(Vector2(entry["at"]), 20.0, 0, TAU, 24,
			Color("59e0d0") if bool(entry["ok"]) else Color("e06a6a", 0.7), STROKE)


## The raised hand, as a cursor over the cells it may go into.
##
## Three things, and each answers a question the old aim ring could not:
##
##   - **The reach.** A box around the cell you are standing in, so how far your arm
##     goes is drawn rather than discovered by pushing at it.
##   - **The cell.** Filled, because the cursor picks a CELL and a ring floating at a
##     centre point never quite said which one — least of all on a diagonal.
##   - **The hand itself**, drawn through `HandOrbit.draw_hand` like every other hand
##     in the game, so what you are moving is legibly the thing you are about to
##     spend. It is the ONE hand drawn without its idle float: this one is a tool
##     being aimed, and a tool that wobbles is a tool you cannot aim.
##
## Everything is in the hand's own colour, so the cursor already says which kind is
## about to go down — the aim ring's one job, kept.
func _draw_cursor() -> void:
	var col := _aim_colour()
	var cs := _view.cell_size
	if _view.aim_box.size != Vector2.ZERO:
		draw_rect(_view.aim_box, Color(col, 0.30), false, HAIR)
	var cell := Rect2(_view.aim_at - Vector2(cs, cs) * 0.5, Vector2(cs, cs))
	draw_rect(cell, Color(col, 0.12), true)
	draw_rect(cell, Color(col, 0.75), false, HAIR)
	if _view.aim_hand >= 0:
		HandOrbit.draw_hand(self, _view.aim_at, _view.aim_hand, 0.0, 1.0, 0.0)


## Every hand you have put down, in its OWN kind's colour, so a mixed pair reads as a
## mixed pair. Armed pairs pulse on that pair's own fuse: a slow breath winding up to
## a flutter as it comes due. Several can be armed at once and they beat at different
## rates, which is how you see which is about to go — no number could say that as
## quickly, and there is nothing to read but the beat.
func _draw_placed_hands() -> void:
	for entry in _view.hands_down:
		if entry["at"] == null:
			continue          # pinned somewhere this frame cannot show
		var at := Vector2(entry["at"])
		var pulse := _pulse_at(float(entry["fuse"]))
		var c: Color = HandTypes.color(int(entry["kind"]))
		draw_arc(at, 16.0 + pulse * 5.0, 0, TAU, 24, c, STROKE)
		if pulse > 0.0:
			draw_circle(at, 3.0 + pulse * 2.5, c)


## The strip an armed pair would excise, and the alignment guides — in every copy
## of the space, because the fold reaches into every copy. What the preview shows
## is what the fold will take, and inside a repeating space that is a strip in each
## strip. Folds may be diagonal; the guides just help line up straight ones.
func _draw_preview() -> void:
	for poly in _guides:
		draw_colored_polygon(poly, Color(1, 1, 1, 0.08))
	# The fold the raised hand would arm, under the ones already armed and fainter than
	# them: a proposal you can still walk the cursor out of, not a strip that is coming.
	# Drawn at all because "which cells does this pair take" is the question the whole
	# placement is about, and answering it after the fuse is lit is answering it late.
	for poly in _aim_strip:
		draw_colored_polygon(poly, Color(0.95, 0.25, 0.3, 0.10))
	for poly in _strips:
		draw_colored_polygon(poly, Color(0.95, 0.25, 0.3, 0.22))


## The parallelogram an armed pair would excise: spanning well past the view, at
## whatever angle the pair implies.
##
## Two anchors on ONE cell imply no angle, so there is no strip and this returns no
## polygon. That pair is legal right up to the fuse — placement asks only whether
## there is sheet to pin to, and `fire_pair` is what refuses it — so the preview has
## to hold a frame it cannot draw, rather than assume it never sees one.
func _strip_polygon(a_center: Vector2, b_center: Vector2,
		world_px: Vector2) -> PackedVector2Array:
	if a_center.is_equal_approx(b_center):
		return PackedVector2Array()
	var bn := (b_center - a_center).normalized()
	var bt := Vector2(-bn.y, bn.x)
	var reach := world_px.length()
	return PackedVector2Array([
		a_center + bt * reach, a_center - bt * reach,
		b_center - bt * reach, b_center + bt * reach,
	])


## The identified crease lines — the glue — so the wrap reads as a real join
## rather than a rendering glitch. One pair per axis of the lattice: two lines
## down a cylinder, and all four walls of a torus when you are folded in twice.
func _draw_glue() -> void:
	for seg in _view.glue:
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
