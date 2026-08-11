extends GutHookScript

## Post-run hook: make a RISKY test fail the build.
##
## GUT decides its own exit code from the assertion-failure count alone
## (`GutRunner._handle_quit` -> `gut.get_fail_count()`). A test that never
## reaches an assertion therefore exits 0, and GUT is right to call that
## "risky" rather than "failing" — but a build gate that lets it through is
## not.
##
## `CollectedTest.is_risky()` is `should_skip or (was_run and !did_something())`,
## so this catches three things, all of which should stop a push:
##
##   - a test that CRASHED at runtime. This is the important one. A GDScript
##     runtime error (`Invalid access of index '0' on Array[Fold]`, a null
##     dereference) aborts the test body before any assert runs, so the test
##     silently scores zero of everything and the suite still reports green.
##     That is exactly the failure that hid behind CI's `-d` flag, and removing
##     `-d` alone does not close it — it only stops the run being truncated.
##   - a test that asserts NOTHING. It is dead weight giving false coverage.
##   - a skipped script, which should be a deliberate, visible decision.
##
## PENDING tests are deliberately NOT counted. `pending()` is a real authoring
## tool for work that is specified but not yet implemented, and GUT tracks it
## in its own total.
##
## Wired in via `post_run_script` in .gutconfig.json, which is the supported
## extension point — `GutRunner._handle_quit` lets a post-run hook override the
## exit code.
##
## If this ever fires on something you consider legitimate, the fix is to make
## the test assert (or mark it `pending()`), not to widen the exemption.

func run() -> void:
	var totals: Dictionary = gut.get_summary().get_totals(gut)
	var risky: int = int(totals.get("risky", 0))

	if risky <= 0:
		return

	gut.logger.error(
		"%d risky test(s): ran without asserting, crashed before asserting, or were skipped. "
		% risky
		+ "Treating as failure — a test that cannot fail cannot protect anything. "
		+ "See tools/gut_strict_exit.gd.")

	set_exit_code(1)
