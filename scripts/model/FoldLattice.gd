class_name FoldLattice extends RefCounted

## FoldLattice
##
## The periodic structure of a space: the set of translations that carry it onto
## itself. This is what "the strip is a cylinder" means, stated once, so that
## nothing downstream has to know which fold it is inside.
##
##   - The region world is **flat**: no periods, one copy of everything.
##   - Inside a fold, walking through a glue line lands you in the next copy of
##     the strip — which is this one. That identification is a period:
##     `anchor_b - anchor_a` in cells, times the cell size.
##   - Inside a fold INSIDE a fold, you may be on a **torus**: two periods.
##
## ## Descending (`push`)
##
## Entering fold F from a space with lattice L gives the strip's lattice:
##
##   - F's own period is always there — its two creases are glued.
##   - A period `P` of L descends **iff `P · n_F == 0`**, and the reason is worth
##     spelling out, because a plausible-looking generalisation of it is false.
##
## ## Why `P · n_F == 0` and not "a whole number of gaps"
##
## A space is a pair (stored pieces, lattice), and the content it really has is
## the ORBIT of the stored pieces under the lattice. Descending into F stores
## `content ∩ B`, where `B = {0 < (p - c)·n_F < gap}` — which is a fundamental
## domain of `⟨n_F·gap⟩`, so the glue is exact.
##
## For a parent period `P` to be a period of the child too, the child's content has
## to satisfy `C(x + P) == C(x)` for `x` in `B`. It is tempting to argue that
## sliding by a whole gap is the identity inside F, so a `P` sitting `k` gaps
## across the strip should descend sheared to `P - k·(n_F·gap)`. It does map `B` to
## itself. But the content does not follow it: the parent's content is invariant
## under `P`, not under the shear, so `C(x + P - k·n_F·gap) = C(x - k·n_F·gap)`,
## which is the parent's content `k` copies over — a different piece of sheet.
##
## The gluing identifies POSITIONS, not the content those positions carry. Only
## `k == 0` leaves both intact, and then the shear is the identity and `P` descends
## unchanged. (This was implemented the other way for one commit; it was wrong.)
##
## Two consequences worth knowing:
##
##   - **The axes are always orthogonal.** A descending `P` is perpendicular to
##     `n_F`, and F's own period is parallel to it. So there are at most two axes,
##     they are at right angles, and each wraps independently — which is what
##     makes `wrap_delta` a per-axis `floor` rather than a lattice reduction.
##   - **Every period is a whole number of cells.** `n * gap` is exactly
##     `(anchor_b - anchor_a) * cell_size`, so periods land on the art-pixel grid
##     and a wrapped copy is never half a pixel out.
##
## ## What the strip contains, and what it does not
##
## `content ∩ B` is a fundamental domain of the child's content EXACTLY when every
## parent period is perpendicular to `n_F` — then each period preserves `B`, so
## intersecting and orbiting commute. That covers every fold made from the
## overworld (no periods at all) and the perpendicular nesting case (the torus).
##
## When a parent period is NOT perpendicular, `content ∩ B` is a strict SUBSET of
## what the parent's full orbit puts in the strip: a strip running past its own glue
## line finds the end of the stored sheet rather than the next copy of it. That is
## a deliberate limit, not an oversight — **a fold takes what is in front of it in
## the sheet it is cut from; it does not reach around the cylinder.** What it shows
## is always really there; it just does not reach for everything that is.
##
## Pure kernel: geometry in, geometry out, no view types.

## Axes of the lattice, outermost inherited first. Each is
## `{"period": Vector2, "dir": Vector2 (unit), "len": float, "base": float}`
## where `base` is the coordinate along `dir` at which the fundamental domain
## starts — so the domain along that axis is `[base, base + len)`.
var axes: Array = []

## A translation is treated as "along the strip" when its component across the
## strip is under this. Periods are whole cells, so nothing lands near the line
## by accident.
const PARALLEL_EPS := 0.001


## The lattice of a space that does not repeat: the region world.
static func flat() -> FoldLattice:
	return FoldLattice.new()


## The lattice of the space INSIDE `fold`, given the lattice of the space the
## fold was made in. See the class docs for the survival rule.
func push(fold: Fold, cell_size: float) -> FoldLattice:
	var out := FoldLattice.new()
	var n: Vector2 = fold.crease_normal
	for axis in axes:
		if absf((axis["period"] as Vector2).dot(n)) <= PARALLEL_EPS:
			out.axes.append(axis.duplicate())
	# Exact: n * gap_distance() IS (anchor_b - anchor_a) * cell_size, and stating
	# it that way keeps the period on the cell grid however diagonal the crease is.
	out.axes.append({
		"period": Vector2(fold.anchor_b - fold.anchor_a) * cell_size,
		"dir": n,
		"len": fold.gap_distance(),
		"base": fold.crease_point1.dot(n),
	})
	return out


## The lattice for a whole context path (outermost fold first).
static func for_path(path: Array, cell_size: float) -> FoldLattice:
	var lat := FoldLattice.flat()
	for fold in path:
		lat = lat.push(fold, cell_size)
	return lat


func depth() -> int:
	return axes.size()


func is_flat() -> bool:
	return axes.is_empty()


func periods() -> Array:
	var out: Array = []
	for axis in axes:
		out.append(axis["period"])
	return out


# ---------------------------------------------------------------------------
# Wrapping
# ---------------------------------------------------------------------------

## The displacement that carries `p` into the fundamental domain, or ZERO if it
## is already there.
##
## Returned as a DISPLACEMENT rather than a position because the caller has to
## move more than the body: the camera is shifted by the same vector, and that is
## what makes crossing a glue line invisible — the space repeats with exactly this
## period, so the rendered frame does not change at all.
func wrap_delta(p: Vector2) -> Vector2:
	var delta := Vector2.ZERO
	for axis in axes:
		var dir: Vector2 = axis["dir"]
		var span: float = axis["len"]
		if span <= 0.0:
			continue
		var k := floorf(((p + delta).dot(dir) - float(axis["base"])) / span)
		if k != 0.0:
			delta -= (axis["period"] as Vector2) * k
	return delta


## `p` folded into the fundamental domain.
func wrap(p: Vector2) -> Vector2:
	return p + wrap_delta(p)


# ---------------------------------------------------------------------------
# Copies
# ---------------------------------------------------------------------------

## Where to draw the copies of this space, nearest first, ZERO always included.
##
## `radius` is how far from the camera something can sit and still be drawn; the
## count is capped because a one-cell fold repeats every 64 units and a torus
## squares whatever a cylinder costs.
func offsets(radius: float, cap: int = 121) -> Array:
	if axes.is_empty():
		return [Vector2.ZERO]
	var out: Array = [Vector2.ZERO]
	var ranges: Array = []
	for axis in axes:
		var span: float = maxf(float(axis["len"]), 1.0)
		ranges.append(int(ceil(radius / span)))
	if axes.size() == 1:
		var p0: Vector2 = axes[0]["period"]
		for k in range(1, int(ranges[0]) + 1):
			out.append(p0 * k)
			out.append(p0 * -k)
	else:
		var pa: Vector2 = axes[0]["period"]
		var pb: Vector2 = axes[1]["period"]
		var na: int = ranges[0]
		var nb: int = ranges[1]
		for ka in range(-na, na + 1):
			for kb in range(-nb, nb + 1):
				if ka == 0 and kb == 0:
					continue
				out.append(pa * ka + pb * kb)
		out.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	if out.size() > cap:
		out = out.slice(0, cap)
	return out


## The copies immediately around the fundamental domain — one step along each
## axis, in every combination. What the physics needs: the body is wrapped back
## into the domain every frame, so it can never be more than one copy out.
func neighbour_offsets() -> Array:
	var out: Array = [Vector2.ZERO]
	for axis in axes:
		var period: Vector2 = axis["period"]
		var grown: Array = []
		for base in out:
			grown.append(base + period)
			grown.append(base - period)
		out.append_array(grown)
	return out


# ---------------------------------------------------------------------------
# Framing
# ---------------------------------------------------------------------------

## The edges of the fundamental domain through `p`, one pair per axis.
##
## Inside a fold the strip IS the room, so this is what the camera frames: glue to
## glue on a cylinder, and all four walls on a torus. Empty when the space does
## not repeat — there is no domain to hold in view, only a world.
func domain_edges(p: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for axis in axes:
		var dir: Vector2 = axis["dir"]
		var span: float = axis["len"]
		if span <= 0.0:
			continue
		var c := p.dot(dir)
		var lo: float = float(axis["base"]) + floorf((c - float(axis["base"])) / span) * span
		out.append(p + dir * (lo - c))
		out.append(p + dir * (lo + span - c))
	return out


## The fundamental domain as a convex polygon, `reach` wide in any direction the
## space does NOT repeat in.
##
## What it is for: anything drawn once per copy that would otherwise span the
## whole world — the excised-strip preview, the alignment guides. Repeated
## unclipped they tile the screen and stack their alpha into a wash; clipped to
## this, each copy paints its own strip and the tiling is exact. Empty for a space
## that does not repeat, which means "do not clip".
func domain_polygon(reach: float) -> PackedVector2Array:
	if axes.is_empty():
		return PackedVector2Array()
	var a: Dictionary = axes[0]
	var da: Vector2 = a["dir"]
	var lo_a: float = a["base"]
	var hi_a: float = lo_a + float(a["len"])
	var db: Vector2
	var lo_b: float
	var hi_b: float
	if axes.size() > 1:
		var b: Dictionary = axes[1]
		db = b["dir"]
		lo_b = b["base"]
		hi_b = lo_b + float(b["len"])
	else:
		db = Vector2(-da.y, da.x)
		lo_b = -reach
		hi_b = reach
	return PackedVector2Array([
		da * lo_a + db * lo_b, da * hi_a + db * lo_b,
		da * hi_a + db * hi_b, da * lo_a + db * hi_b,
	])


## Where the fundamental domain begins along one of the lattice's own axes — the
## coordinate of the near glue line. Zero for a direction the space does not
## repeat along, which has no domain to begin.
func domain_start(dir: Vector2) -> float:
	for axis in axes:
		if absf((axis["dir"] as Vector2).dot(dir) - 1.0) < PARALLEL_EPS:
			return float(axis["base"])
	return 0.0


## The one direction the space does NOT repeat along, when it repeats along
## exactly one axis — the axis a body can run off the end of, and so the only one
## that needs a turn-back. ZERO when the space is flat (there is no strip to leave)
## or a torus (there is nowhere to go).
func free_axis() -> Vector2:
	if axes.size() != 1:
		return Vector2.ZERO
	var dir: Vector2 = axes[0]["dir"]
	return Vector2(-dir.y, dir.x)
