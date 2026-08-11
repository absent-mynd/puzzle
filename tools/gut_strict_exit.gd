extends GutHookScript

## Post-run hook: fail the build on the two ways a GUT run can be green and wrong.
##
## GUT decides its own exit code from the assertion-failure count alone
## (`GutRunner._handle_quit` -> `gut.get_fail_count()`). That is a reasonable
## default and a bad build gate, because a test can score zero failures by never
## running at all. Two cases, both observed in this repository:
##
##   1. RISKY tests. `CollectedTest.is_risky()` is
##      `should_skip or (was_run and !did_something())`, so a test that crashed at
##      runtime before reaching an assert lands here — as does one that asserts
##      nothing, and a skipped script. A GDScript runtime error
##      (`Invalid access of index '0' on Array[Fold]`, a null dereference) aborts
##      the test body silently, and the suite still reports green.
##
##   2. Test scripts that never loaded. A parse error in a test file makes GUT log
##      "Ignoring script ... because it does not extend GutTest" and move on. The
##      file's tests simply cease to exist: measured on this suite, one bad
##      character removed 9 tests and the run still exited 0. A test file you can
##      delete by breaking it is not a test file.
##
## PENDING tests are deliberately NOT counted. `pending()` is a real authoring tool
## for work that is specified but not yet implemented, and GUT tracks it separately.
##
## Wired in via `post_run_script` in .gutconfig.json, which is the supported
## extension point — `GutRunner._handle_quit` lets a post-run hook override the exit
## code.
##
## If this fires on something you consider legitimate, the fix is to make the test
## assert (or mark it `pending()`), not to widen the exemption.

## Read rather than hardcoded, so this cannot drift out of step with the dirs the
## run actually used.
const CONFIG_PATH := "res://.gutconfig.json"
const DEFAULT_DIRS := ["res://scripts/tests/"]
const DEFAULT_PREFIX := "test_"
const DEFAULT_SUFFIX := ".gd"


func run() -> void:
	var problems: Array[String] = []

	var totals: Dictionary = gut.get_summary().get_totals(gut)
	var risky := int(totals.get("risky", 0))
	if risky > 0:
		problems.append(
			"%d risky test(s): ran without asserting, crashed before asserting, or were skipped"
				% risky)

	var missing := _scripts_that_never_loaded()
	if not missing.is_empty():
		problems.append(
			"%d test script(s) on disk never ran — most likely a parse error: %s"
				% [missing.size(), ", ".join(missing)])

	if problems.is_empty():
		return

	for problem in problems:
		gut.logger.error(problem)
	gut.logger.error(
		"Failing the run: a test that cannot fail cannot protect anything. "
		+ "See tools/gut_strict_exit.gd.")
	set_exit_code(1)


## Test files present on disk that GUT did not collect.
##
## Returns nothing for a FILTERED run. `./run_tests.sh world` (which becomes
## `-gselect=world`) deliberately runs a subset, so "these files did not run" is the
## requested outcome rather than a fault — checking it there would make the everyday
## narrow-it-down loop fail every time. The check that matters is on the full run,
## which is what CI and the pre-push hook do.
func _scripts_that_never_loaded() -> Array[String]:
	if String(gut._select_script) != "":
		return []

	var config := _config()
	var prefix := String(config.get("prefix", DEFAULT_PREFIX))
	var suffix := String(config.get("suffix", DEFAULT_SUFFIX))
	var subdirs := bool(config.get("include_subdirs", false))

	var on_disk: Array[String] = []
	for dir in config.get("dirs", DEFAULT_DIRS):
		_collect(String(dir), prefix, suffix, subdirs, on_disk)

	var ran := {}
	for script in gut.get_test_collector().scripts:
		ran[script.path] = true

	var missing: Array[String] = []
	for path in on_disk:
		if not ran.has(path):
			missing.append(path)
	missing.sort()
	return missing


func _config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _collect(dir_path: String, prefix: String, suffix: String,
		subdirs: bool, into: Array[String]) -> void:
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
			if subdirs:
				_collect(full, prefix, suffix, subdirs, into)
		elif name.begins_with(prefix) and name.ends_with(suffix):
			into.append(full)
		name = dir.get_next()
	dir.list_dir_end()
