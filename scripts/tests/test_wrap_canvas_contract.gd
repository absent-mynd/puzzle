extends GutTest

## `WrapCanvas` has a contract, and it is a performance contract.
##
## Its own docstring states it: `prepare()` runs once before any copy, "so a question
## that costs something is asked once rather than once per band"; `paint()` runs once
## per copy. A space repeats 7 times inside one fold and 77 two folds deep, and the
## ceiling is `FoldWorld.MAX_WRAP_COPIES` = 121.
##
## `WorldOverlay` broke that contract quietly, and it was expensive. `_draw_glue`
## called `world.glue_lines()` — which scans every base piece for every period — and
## `_draw_loose_hands` called `world.loose_hand_points()`, which resolves every hand
## against every fragment. Both from inside `paint()`. Measured on a torus of 77
## copies, the pair cost **16.3 ms of a 16.6 ms frame**; hoisted into `prepare()` they
## cost 212 µs. The drawing was identical either way.
##
## Nothing detected it, because nothing about it is wrong except *where it happens* —
## and the reason it could happen at all is that the overlay holds the whole world and
## may ask it anything at any point, which is the coupling recorded as finding 08 of
## the August 2026 review.
##
## So this file checks the shape rather than the timing: no query that ALLOCATES a
## fresh container may be reached from a canvas's per-copy path. Cheap reads
## (`world.lattice`, `world.player`, `world.base.cell_size`) are fine and are not
## listed — the rule is about work that scales with the world, done once per band.

## Queries that build a new Array or Dictionary every call. Adding one here is how you
## keep the next `glue_lines()` out of a draw loop.
const ALLOCATING_QUERIES := [
	"glue_lines", "loose_hand_points", "hand_ball_points",
	"seam_markers", "seams_within_burst", "all_anchors", "anchor_cells",
	"lights_here", "level_folds",
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


func test_the_overlay_gathers_the_expensive_answers_once() -> void:
	# The specific regression: these three were in the draw path and are now in
	# prepare(). Asserted by name because they are the ones that were measured.
	var funcs := _functions("res://scripts/world/WorldOverlay.gd")
	assert_true(funcs.has("prepare"), "WorldOverlay overrides prepare()")

	var gathered := "\n".join(funcs.get("prepare", []))
	for query in ["glue_lines", "loose_hand_points", "hand_ball_points"]:
		assert_string_contains(gathered, query,
			"prepare() is where %s() is asked" % query)
