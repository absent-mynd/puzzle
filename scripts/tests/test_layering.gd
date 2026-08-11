extends GutTest

## Decision 9, enforced instead of asked for.
##
## `docs/ARCHITECTURE.md` says the kernel never sees the world:
##
##     scripts/model/ + scripts/utils/   <- pure, headless
##             ^
##     scripts/world/ + friends          <- view, physics, input
##
## The kernel is testable precisely because it has no scene tree, and that property
## is worth exactly as much as it is enforced. It held on discipline for a long time
## and then quietly stopped: `WorldData.build_base` called `WorldCore.parse_map()`
## while `WorldCore` still lived in `scripts/world/`. Nobody wrote a careless call —
## the file was simply in the wrong directory, `class_name` resolves globally, and
## nothing complained. The fix was to move `WorldCore` into the kernel where it
## always belonged; this file is what notices next time.
##
## It lives in the suite rather than in a CI script on purpose. This project already
## learned what happens when a check has its own invocation to keep in step with
## everything else's — CI, the pre-push hook and run_tests.sh all disagreed, and the
## automated ones were the ones that lied. A rule that runs wherever the tests run
## cannot drift away from them.
##
## Comments are ignored. A doc comment in the kernel may still point at
## `PlayerBody.motion_intensity` to say what a parameter means: a cross-reference in
## prose is not a dependency, and the rule is about what the code needs to run.

const KERNEL_DIRS := ["res://scripts/model", "res://scripts/utils"]
const UPPER_DIRS := [
	"res://scripts/world", "res://scripts/editor",
	"res://scripts/ui", "res://scripts/systems",
]


func _gd_files(dirs: Array) -> Array:
	var out: Array = []
	for d in dirs:
		_walk(String(d), out)
	out.sort()
	return out


func _walk(dir_path: String, into: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	if not dir_path.ends_with("/"):
		dir_path += "/"
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path + name
		if dir.current_is_dir():
			_walk(full, into)
		elif name.ends_with(".gd"):
			into.append(full)
		name = dir.get_next()
	dir.list_dir_end()


## Drop a trailing comment, respecting quotes — `WorldCore.CHARS` maps the literal
## string "#" to a wall tile, so a naive split on '#' would mangle real code.
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


## class_name -> the file that declares it, for everything above the kernel.
func _upper_class_names() -> Dictionary:
	var names := {}
	for path in _gd_files(UPPER_DIRS):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var text := String(line).strip_edges()
			if text.begins_with("class_name "):
				var rest := text.substr("class_name ".length()).strip_edges()
				var ident := rest.split(" ")[0].strip_edges()
				if ident != "":
					names[ident] = path
				break
	return names


func test_the_kernel_names_nothing_above_it() -> void:
	var upper := _upper_class_names()
	assert_gt(upper.size(), 0,
		"found some view-layer class_names to check against (otherwise this test proves nothing)")

	var kernel := _gd_files(KERNEL_DIRS)
	assert_gt(kernel.size(), 0, "found kernel files to check")

	# Compiled once rather than per line: this walks every kernel file against every
	# view class_name, and RegEx.create_from_string in that inner loop is the
	# difference between a fast test and a slow one.
	var patterns := {}
	for name in upper:
		patterns[name] = RegEx.create_from_string("\\b%s\\b" % name)

	var violations: Array[String] = []
	for path in kernel:
		var n := 0
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var code := _strip_comment(String(raw))
			if code.strip_edges() == "":
				continue
			for name in upper:
				if patterns[name].search(code) != null:
					violations.append("%s:%d uses `%s`, which is view code (%s)\n    %s"
						% [path, n, name, upper[name], code.strip_edges()])

	assert_eq(violations, ([] as Array[String]),
		"the kernel names nothing above it\n%s" % "\n".join(violations))


func test_the_kernel_preloads_nothing_above_it() -> void:
	# The other shape of the same mistake: reaching for the file directly rather
	# than through its global class_name.
	var re := RegEx.create_from_string("(?:preload|load)\\s*\\(\\s*[\"']([^\"']+)[\"']")
	var kernel := _gd_files(KERNEL_DIRS)
	assert_gt(kernel.size(), 0, "found kernel files to check")

	var violations: Array[String] = []
	for path in kernel:
		var n := 0
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var code := _strip_comment(String(raw))
			for m in re.search_all(code):
				var target: String = m.get_string(1)
				for up in UPPER_DIRS:
					if target.begins_with(String(up)):
						violations.append("%s:%d loads `%s`, which is view code\n    %s"
							% [path, n, target, code.strip_edges()])

	assert_eq(violations, ([] as Array[String]),
		"the kernel loads nothing above it\n%s" % "\n".join(violations))


func test_worldcore_is_in_the_kernel_where_it_belongs() -> void:
	# It is pure — RefCounted, every function static, no scene-tree contact — and it
	# is what WorldData needs. Living in scripts/world/ was the whole violation.
	assert_true(FileAccess.file_exists("res://scripts/model/WorldCore.gd"),
		"WorldCore.gd is in scripts/model/")
	assert_false(FileAccess.file_exists("res://scripts/world/WorldCore.gd"),
		"...and no copy was left behind in scripts/world/")
