extends RefCounted

## WorldProbe
##
## A coarse model of where the body can GET TO in the space a `FoldWorld` is showing,
## for tests that have to say "you can walk there" or "you cannot" about a designed
## world rather than about one mechanic.
##
## It exists because a world's beats are claims about reachability — this sigil needs a
## fold, that ledge is a jump — and until something checks them they are claims about
## the author's arithmetic. One of the first world's four beats shipped unreachable for
## exactly that reason.
##
## ## What it models
##
## The space is sampled on a HALF-CELL lattice (axis-aligned folds cut tiles through
## their centres, so a half cell is the finest thing they make). The body is a 2x2
## block of half cells: it fits a one-cell corridor and does not fit a half-cell slot,
## which is what a 40-unit circle does. From a block that is standing — or swimming —
## it may walk, drop, or jump, and a jump is a rise of up to `max_rise` half cells, a
## run of up to `_run_for(rise)` and a fall to the first thing that catches it.
##
## ## Two readings, on purpose
##
## The real arc has a few pixels of grace at each end (coyote time, a corner the circle
## rolls onto) and this model has none, so a single threshold would be wrong one way or
## the other. Instead it is asked twice:
##
##   - **STRICT** under-states the body. Use it for a path a solution DEPENDS on: if
##     the strict model can do it, a player can do it without a perfect input.
##   - **GENEROUS** over-states the body. Use it for a path that must NOT exist: if the
##     generous model cannot do it, no input can.
##
## Jumps between the two readings are deliberately not designed around — a gap that is
## strict-impossible and generous-possible is one the world should not contain where it
## matters, and the solution tests fail in both directions if it does.
##
## The numbers come from `PlayerBody`'s own constants (the peak, and how far a full run
## carries the centre before the arc comes back down through each height), so retuning
## the jump moves this with it: see `_build_run_table`.

const CS := 64.0
const HALF := 32.0

## How many half cells beyond the sheet the model keeps sampling. Over void there is
## nothing to stand on, so this only has to be wide enough for an arc to leave and
## come back.
const MARGIN := 6

var world
var strict := true

var _w := 0
var _h := 0
## 1 where a half cell is solid.
var _solid := PackedByteArray()
## 1 where a half cell is water.
var _water := PackedByteArray()
## Per BLOCK position, worked out once per sampling so the search is table lookups:
## 1 where the body's block fits; 1 where it rests (stands or swims); and the row a
## block dropped there comes to rest in, or -1 if it leaves the sheet.
var _fit := PackedByteArray()
var _rest := PackedByteArray()
var _fall_to := PackedInt32Array()
## rise (half cells, may be negative) -> farthest run (half cells) for this reading.
var _run: Dictionary = {}
var max_rise := 4


## The run table for each reading, built once: it is a function of `PlayerBody`'s
## constants and nothing about the world.
static var _tables: Dictionary = {}


func _init(world_, strict_ := true) -> void:
	world = world_
	strict = strict_
	if not _tables.has(strict):
		_build_run_table()
		_tables[strict] = {"run": _run, "max_rise": max_rise}
	_run = _tables[strict]["run"]
	max_rise = int(_tables[strict]["max_rise"])
	resample()


# ---------------------------------------------------------------------------
# The jump, from the body's own numbers
# ---------------------------------------------------------------------------

## Integrate the real arc once and read off, for each height, the last moment the
## centre is still at or above it. That moment times the run speed is how far a jump
## can carry you and still land that high.
func _build_run_table() -> void:
	var dt := 1.0 / 120.0
	var vy := PlayerBody.JUMP_VELOCITY
	var y := 0.0
	var t := 0.0
	var peak := 0.0
	# height (half cells above takeoff, negative below) -> last time at or above it
	var last_at: Dictionary = {}
	while y < 40.0 * HALF:
		vy = PlayerBody.step_fall(vy, true, dt)
		y += vy * dt
		t += dt
		peak = minf(peak, y)
		var level := int(floor(-y / HALF))
		for k in range(level, -41, -1):
			if last_at.has(k) and float(last_at[k]) >= t:
				break
			last_at[k] = t
	# The peak, with a few units of clearance held back in the strict reading: a ledge
	# the centre clears by a hair is a ledge the circle's rim catches.
	var rise_units := -peak
	max_rise = int(floor((rise_units - (10.0 if strict else 0.0)) / HALF))
	if not strict:
		max_rise = int(floor((rise_units + 4.0) / HALF))
	var grace := PlayerBody.COYOTE_TIME * PlayerBody.RUN_SPEED + PlayerBody.RADIUS * 0.5
	for k in last_at:
		var reach: float = float(last_at[k]) * PlayerBody.RUN_SPEED
		if strict:
			# Take off a full half cell: the model stands the centre exactly on a lattice
			# line, and a real takeoff happens somewhere short of the lip.
			_run[int(k)] = int(floor((reach - HALF) / HALF))
		else:
			_run[int(k)] = int(ceil((reach + grace) / HALF))


func _run_for(rise: int) -> int:
	if rise > max_rise:
		return -1
	return int(_run.get(clampi(rise, -40, max_rise), 0))


# ---------------------------------------------------------------------------
# Sampling the space
# ---------------------------------------------------------------------------

## Read the current space off the world again. Call after anything that changes the
## geometry — a fold, an unfold, a door.
func resample() -> void:
	var grid: Vector2i = world.base.grid_size
	_w = grid.x * 2 + MARGIN * 2
	_h = grid.y * 2 + MARGIN * 2
	_solid = PackedByteArray()
	_solid.resize(_w * _h)
	_water = PackedByteArray()
	_water.resize(_w * _h)
	for hy in range(_h):
		for hx in range(_w):
			var p := Vector2((hx - MARGIN) + 0.5, (hy - MARGIN) + 0.5) * HALF
			var piece = BaseFrame.piece_containing(world.pieces_by_pos, p, CS)
			if piece == null:
				continue
			if not TileTypes.is_walkable(piece.type):
				_solid[hy * _w + hx] = 1
			elif TileTypes.is_swim(piece.type):
				_water[hy * _w + hx] = 1
	_build_tables()


## Fold the half-cell samples into per-block answers. Bottom-up, because where a block
## falls to is where the block below it falls to unless it is already resting.
func _build_tables() -> void:
	_fit = PackedByteArray()
	_fit.resize(_w * _h)
	_rest = PackedByteArray()
	_rest.resize(_w * _h)
	_fall_to = PackedInt32Array()
	_fall_to.resize(_w * _h)
	for hy in range(_h - 1, -1, -1):
		for hx in range(_w):
			var i := hy * _w + hx
			var fits := not (_is_solid(hx, hy) or _is_solid(hx + 1, hy)
				or _is_solid(hx, hy + 1) or _is_solid(hx + 1, hy + 1))
			_fit[i] = 1 if fits else 0
			var rests := false
			if fits:
				var left := _is_solid(hx, hy + 2)
				var right := _is_solid(hx + 1, hy + 2)
				rests = ((left and right) if strict else (left or right)) \
					or _is_water(hx, hy + 1) or _is_water(hx + 1, hy + 1) \
					or _is_water(hx, hy) or _is_water(hx + 1, hy)
			_rest[i] = 1 if rests else 0
			if not fits:
				_fall_to[i] = -1
			elif rests:
				_fall_to[i] = hy
			elif hy + 1 >= _h:
				_fall_to[i] = -1
			else:
				_fall_to[i] = _fall_to[(hy + 1) * _w + hx]


func _is_solid(hx: int, hy: int) -> bool:
	if hx < 0 or hy < 0 or hx >= _w or hy >= _h:
		return false
	return _solid[hy * _w + hx] == 1


func _is_water(hx: int, hy: int) -> bool:
	if hx < 0 or hy < 0 or hx >= _w or hy >= _h:
		return false
	return _water[hy * _w + hx] == 1


## Can the body's 2x2 block sit with its top-left half cell at (hx, hy)?
func _fits(hx: int, hy: int) -> bool:
	if hx < 0 or hy < 0 or hx >= _w or hy >= _h:
		return false
	return _fit[hy * _w + hx] == 1


func _swimming(hx: int, hy: int) -> bool:
	return _is_water(hx, hy + 1) or _is_water(hx + 1, hy + 1) \
		or _is_water(hx, hy) or _is_water(hx + 1, hy)


func _rests(hx: int, hy: int) -> bool:
	if hx < 0 or hy < 0 or hx >= _w or hy >= _h:
		return false
	return _rest[hy * _w + hx] == 1


## Fall from (hx, hy) to the first place the block rests. -1 if it leaves the sheet.
func _land(hx: int, hy: int) -> int:
	if hx < 0 or hy < 0 or hx >= _w or hy >= _h:
		return -1
	return _fall_to[hy * _w + hx]


# ---------------------------------------------------------------------------
# Reachability
# ---------------------------------------------------------------------------

func _block_of(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * 2 + MARGIN, cell.y * 2 + MARGIN)


## Every block position the body can come to rest in, starting from `from` (a CELL the
## body stands or swims in). Keys are Vector2i block positions.
func reachable_from(from: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	var start := _block_of(from)
	if not _fits(start.x, start.y):
		return seen
	var sy := _land(start.x, start.y)
	if sy < 0:
		return seen
	var queue: Array = [Vector2i(start.x, sy)]
	seen[queue[0]] = true
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for next in _moves(at):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


func _moves(at: Vector2i) -> Array:
	var out: Array = []
	var in_water := _swimming(at.x, at.y)
	if in_water:
		# Water is free movement: a half cell any way that fits.
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = at + step
			if _fits(n.x, n.y) and _swimming(n.x, n.y):
				out.append(n)
	# Walk, drop or jump: rise `u`, run `k`, fall to whatever catches you.
	var rise_cap := max_rise
	if in_water and strict:
		rise_cap = max_rise - 1     # the surface is a little lower than a floor would be
	for u in range(0, rise_cap + 1):
		if u > 0 and not _fits(at.x, at.y - u):
			break                   # a ceiling: no higher apex is available either
		var top := at.y - u
		for dir: int in [-1, 1]:
			var k := 1
			while k <= 40:
				var x := at.x + dir * k
				if x < 0 or x >= _w or not _fits(x, top):
					break
				var ly := _land(x, top)
				if ly >= 0:
					var rise := at.y - ly
					if k <= _run_for(rise) or (k == 1 and rise <= 0):
						out.append(Vector2i(x, ly))
				if k > _run_for(-40):
					break
				k += 1
	return out


## Can the body get from one cell to another by walking, jumping, dropping and
## swimming alone — no folds?
func can_reach(from: Vector2i, to: Vector2i) -> bool:
	return touches(reachable_from(from), to)


## Does a reachable set put the body in `cell`? "In" is generous by a half cell either
## way, because a sigil is collected by touching it and a door by overlapping it.
func touches(reached: Dictionary, cell: Vector2i) -> bool:
	var b := _block_of(cell)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if reached.has(Vector2i(b.x + dx, b.y + dy)):
				return true
	return false


## Could a hand be pinned in `cell` from somewhere in a reachable set — standing, or at
## any height of a jump straight up from a place the body rests? Arm's reach is the
## nine cells around the body's own (`WorldCore.within_arm_reach`).
##
## Straight up only: pinning from the middle of a running leap is a thing the game
## allows and this does not model, so a "yes" here is a pin you can make at leisure.
func can_pin(reached: Dictionary, cell: Vector2i, arm: int = 1) -> bool:
	for at in reached:
		var p: Vector2i = at
		for u in range(0, max_rise + 1):
			if u > 0 and not _fits(p.x, p.y - u):
				break
			for body in _cells_of(p.x, p.y - u):
				if WorldCore.within_arm_reach(body, cell, arm):
					return true
	return false


## The same question asked of ONE spot: standing in `stand`, jumping straight up if
## need be, can a hand be pinned in `cell`?
func can_pin_from(stand: Vector2i, cell: Vector2i, arm: int = 1) -> bool:
	var b := _block_of(stand)
	if not _fits(b.x, b.y):
		return false
	var y := _land(b.x, b.y)
	if y < 0:
		return false
	return can_pin({Vector2i(b.x, y): true}, cell, arm)


## The cell (or, for a block straddling a lattice line, the cells) the body's centre is
## in when its block sits at (hx, hy).
func _cells_of(hx: int, hy: int) -> Array:
	var xs: Array = [floori(float(hx - MARGIN) / 2.0)]
	if posmod(hx - MARGIN, 2) == 1:
		xs.append(int(xs[0]) + 1)
	var ys: Array = [floori(float(hy - MARGIN) / 2.0)]
	if posmod(hy - MARGIN, 2) == 1:
		ys.append(int(ys[0]) + 1)
	var out: Array = []
	for x in xs:
		for y in ys:
			out.append(Vector2i(int(x), int(y)))
	return out


# ---------------------------------------------------------------------------
# Looking at it
# ---------------------------------------------------------------------------

## The space as text, two characters to a cell each way, for a failing test to print.
## `marks` maps a CELL to a character to draw over it.
func dump(marks: Dictionary = {}) -> String:
	var lines: PackedStringArray = []
	for hy in range(MARGIN, _h - MARGIN):
		var line := ""
		for hx in range(MARGIN, _w - MARGIN):
			var cell := Vector2i((hx - MARGIN) / 2, (hy - MARGIN) / 2)
			if marks.has(cell):
				line += String(marks[cell])
				continue
			var p := Vector2((hx - MARGIN) + 0.5, (hy - MARGIN) + 0.5) * HALF
			var piece = BaseFrame.piece_containing(world.pieces_by_pos, p, CS)
			line += _glyph(piece)
		lines.append(line)
	return "\n".join(lines)


func _glyph(piece) -> String:
	if piece == null:
		return " "
	for ch in WorldCore.CHARS:
		if WorldCore.CHARS[ch] == piece.type:
			return ch
	return "."
