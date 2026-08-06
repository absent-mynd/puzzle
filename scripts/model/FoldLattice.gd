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
##   - A period `P` of L survives iff `P · n_F == 0`: the excised band
##     `{0 < (p - c)·n_F < gap}` maps to itself under a translation exactly when
##     that translation runs ALONG the band. Otherwise the band cuts across the
##     parent's glue, the strip is captured from one fundamental domain only, and
##     the parent's periodicity does not descend. (That is the same configuration
##     the exit rules already single out — an interior fold crossing the glue.)
##
## Two consequences worth knowing:
##
##   - **The axes are always orthogonal.** A surviving `P` is perpendicular to
##     `n_F`, and F's own period is parallel to it. So there are at most two axes,
##     they are at right angles, and each wraps independently — which is what
##     makes `wrap_delta` a per-axis `floor` rather than a lattice reduction.
##   - **Every period is a whole number of cells.** `n * gap` is exactly
##     `(anchor_b - anchor_a) * cell_size`, so periods land on the art-pixel grid
##     and a wrapped copy is never half a pixel out.
##
## ## What this does NOT model
##
## The lattice is a fact about the space a fold CUT OUT, taken at the moment you
## entered it. Fold *within* that space along a band that crosses its own glue and
## the result is no longer periodic with the period it is drawn at — the fold has
## cut the cylinder open. The game already singles that configuration out (it is
## exactly what blocks the exit, and the glue diamond turns red for it), and it
## has always been drawn this way; stating it here so nobody reads the lattice as
## a stronger guarantee than it is. Making the copies honest in that case would
## mean re-deriving the wrap from the interior fold list, which is a design
## conversation about what "inside" means, not a rendering fix.
##
## Pure kernel: geometry in, geometry out, no view types.

## Axes of the lattice, outermost inherited first. Each is
## `{"period": Vector2, "dir": Vector2 (unit), "len": float, "base": float}`
## where `base` is the coordinate along `dir` at which the fundamental domain
## starts — so the domain along that axis is `[base, base + len)`.
var axes: Array = []

## A translation is treated as "along the band" when its component across the
## band is under this. Periods are whole cells, so nothing lands near the line
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
	var period := Vector2(fold.anchor_b - fold.anchor_a) * cell_size
	out.axes.append({
		"period": period,
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
## Inside a fold the band IS the room, so this is what the camera frames: glue to
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
## that needs a turn-back. ZERO when the space is flat (there is no band to leave)
## or a torus (there is nowhere to go).
func free_axis() -> Vector2:
	if axes.size() != 1:
		return Vector2.ZERO
	var dir: Vector2 = axes[0]["dir"]
	return Vector2(-dir.y, dir.x)
