extends GutTest

## `WrapCanvas` has a contract, and it is a performance contract.
##
## Its own docstring states it: `prepare()` runs once before any copy, "so a question
## that costs something is asked once rather than once per copy"; `paint()` runs once
## per copy. A space repeats 7 times inside one fold and 77 two folds deep, and the
## ceiling is `FoldWorld.MAX_WRAP_COPIES` = 121.
##
## `WorldOverlay` broke that contract quietly, and it was expensive. `_draw_glue`
## called `world.glue_lines()` — which scans every base piece for every period — and
## `_draw_loose_hands` called `world.loose_hand_points()`, which resolves every hand
## against every piece. Both from inside `paint()`. Measured on a torus of 77
## copies, the pair cost most of the frame; gathered once, the whole per-frame
## description costs about 200 µs. The drawing was identical either way.
##
## Nothing detected it, because nothing about it is wrong except *where it happens* —
## and the reason it could happen at all was that the overlay held the whole world and
## could ask it anything at any point. That coupling is now gone: the overlay draws an
## `OverlayView` handed to it by `FoldWorld` and has no way to ask for anything else.
##
## Both halves are checked here. The general rule — no query that ALLOCATES a fresh
## container may be reached from any canvas's per-copy path — because the next
## `WrapCanvas` subclass will not have a view-model. And the specific one, that the
## overlay still holds no reference back, because that is what made the general rule
## breakable in the first place. Cheap reads were never the problem; work that scales
## with the world, done once per copy, was.

## Queries that build a new Array or Dictionary every call. Adding one here is how you
## keep the next `glue_lines()` out of a draw loop.
const ALLOCATING_QUERIES := [
	"glue_lines", "seam_lines", "seam_marks", "loose_hand_points", "hand_ball_points",
	"seam_markers", "seams_within_burst", "all_anchors", "anchor_cells",
	"lights_here", "space_folds",
	# The anchor field resolves every anchor against every piece to answer either of
	# these, and then compares every pair. Cheap for the handful of anchors a frame
	# usually holds, and once per copy of a torus it is the same mistake as the two
	# above it.
	"armed_pairs", "aim_partners",
]

const WORLD_DIR := "res://scripts/world"


func _gd_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(WORLD_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".gd"):
			out.append("%s/%s" % [WORLD_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _strip_comment(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote != "":
			if ch == "\\" and i + 1 < line.length():
				out += line.substr(i, 2)
				i += 2
				continue
			if ch == quote:
				quote = ""
			out += ch
		elif ch == "\"" or ch == "'":
			quote = ch
			out += ch
		elif ch == "#":
			break
		else:
			out += ch
		i += 1
	return out


## `{func_name: [code lines]}` for one script, comments stripped.
func _functions(path: String) -> Dictionary:
	var funcs := {}
	var cur := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var code := _strip_comment(String(raw))
		var m := RegEx.create_from_string("^func\\s+(\\w+)").search(code)
		if m != null:
			cur = m.get_string(1)
			funcs[cur] = []
		elif cur != "":
			funcs[cur].append(code)
	return funcs


## Every function reachable from `paint`, following calls defined in the same script.
func _reachable_from_paint(funcs: Dictionary) -> Array:
	if not funcs.has("paint"):
		return []
	var seen := {"paint": true}
	var queue := ["paint"]
	while not queue.is_empty():
		var name: String = queue.pop_back()
		for line in funcs.get(name, []):
			for other in funcs:
				if seen.has(other):
					continue
				if RegEx.create_from_string("\\b%s\\s*\\(" % other).search(line) != null:
					seen[other] = true
					queue.append(other)
	return seen.keys()


func test_no_allocating_query_runs_once_per_copy() -> void:
	var canvases: Array = []
	var violations: Array[String] = []

	for path in _gd_files():
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("extends WrapCanvas"):
			continue
		canvases.append(path)

		var funcs := _functions(path)
		for name in _reachable_from_paint(funcs):
			for line in funcs[name]:
				for query in ALLOCATING_QUERIES:
					if RegEx.create_from_string("\\.%s\\s*\\(" % query).search(line) != null:
						violations.append(
							"%s: %s() is on the per-copy path and calls %s() — gather it in prepare()\n    %s"
								% [path, name, query, line.strip_edges()])

	assert_gt(canvases.size(), 0,
		"found WrapCanvas subclasses to check (otherwise this test proves nothing)")
	assert_eq(violations, ([] as Array[String]),
		"no allocating query is asked once per copy\n%s" % "\n".join(violations))


func test_the_overlay_holds_no_reference_to_the_world() -> void:
	# The closure condition for finding 08. The overlay used to hold FoldWorld itself
	# — untyped, because naming it would have closed a load-order cycle — and reach
	# into two dozen members whenever it liked. That is how two allocating queries
	# ended up on the per-copy draw path without anyone deciding they should be.
	#
	# It now receives an OverlayView and cannot ask for anything else. Checked by
	# source rather than by behaviour because "cannot" is the property that matters:
	# a test that merely draws correctly would pass with the reference restored.
	var text := FileAccess.get_file_as_string("res://scripts/world/WorldOverlay.gd")
	var code: Array[String] = []
	for raw in text.split("\n"):
		code.append(_strip_comment(String(raw)))
	var body := "\n".join(code)

	assert_false(RegEx.create_from_string("\\bvar\\s+world\\b").search(body) != null,
		"WorldOverlay declares no `world` member")
	assert_false(RegEx.create_from_string("\\bworld\\.\\w+").search(body) != null,
		"...and reaches into no world member")


func test_the_view_is_built_where_it_can_be_built_once() -> void:
	# The other half: FoldWorld owns the gathering, so the expensive queries happen
	# once per frame in a function whose whole purpose is to be called once.
	var text := FileAccess.get_file_as_string("res://scripts/world/FoldWorld.gd")
	assert_string_contains(text, "func _build_overlay_view() -> OverlayView:",
		"FoldWorld builds the view")
	for query in ["glue_lines", "loose_hand_points", "hand_ball_points"]:
		assert_string_contains(text, query,
			"...and %s() is asked there" % query)
