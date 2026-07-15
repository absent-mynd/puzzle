## InputHelp unit tests
##
## The on-screen controls text is generated from the live InputMap so it can't drift
## from the actual bindings. These assert the mapped keys resolve and the summary
## reflects them (the old HUD string was a stale hardcoded literal).

extends GutTest


func test_key_for_reads_mapped_actions():
	assert_eq(InputHelp.key_for("ui_undo"), "U", "ui_undo is bound to U")
	assert_eq(InputHelp.key_for("restart"), "R", "restart is bound to R")


func test_key_for_unknown_action():
	assert_eq(InputHelp.key_for("no_such_action"), "?", "unmapped action -> '?'")


func test_gameplay_summary_reflects_bindings():
	var summary := InputHelp.gameplay_summary()
	assert_string_contains(summary, "U: Undo", "summary shows the live undo key")
	assert_string_contains(summary, "R: Restart", "summary shows the live restart key")
	assert_string_contains(summary, "Move", "summary mentions movement")


func test_control_rows_cover_core_actions():
	var labels := []
	for row in InputHelp.control_rows():
		labels.append(row["label"])
	assert_true(labels.size() >= 5, "help lists the core controls")
