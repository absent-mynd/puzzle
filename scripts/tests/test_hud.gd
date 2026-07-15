## HUD behavior tests
##
## Covers the two Phase-2 HUD fixes: set_visible_hud actually toggles visibility (it
## was a `visible = visible` no-op), and the fold-counter performance color comes from
## the shared UIPalette star-tier rule (so it matches LevelComplete / level-select).

extends GutTest


func _make_hud():
	var hud = load("res://scenes/ui/HUD.tscn").instantiate()
	add_child_autofree(hud)
	await wait_frames(1)
	return hud


func test_set_visible_hud_hides_and_shows():
	var hud = await _make_hud()
	hud.set_visible_hud(false)
	assert_false(hud.visible, "set_visible_hud(false) hides the HUD")
	hud.set_visible_hud(true)
	assert_true(hud.visible, "set_visible_hud(true) shows the HUD")


func test_fold_counter_color_uses_shared_tier_rule():
	var hud = await _make_hud()
	hud.set_level_info("Test", 5)  # par = 5

	hud.set_fold_count(4)  # under par -> perfect
	assert_eq(hud.fold_counter_label.get_theme_color("font_color"),
		UIPalette.color_for_tier(UIPalette.TIER_PERFECT), "under par uses perfect color")

	hud.set_fold_count(7)  # <=1.5*par -> good
	assert_eq(hud.fold_counter_label.get_theme_color("font_color"),
		UIPalette.color_for_tier(UIPalette.TIER_GOOD), "within 1.5x par uses good color")

	hud.set_fold_count(9)  # >1.5*par -> completion/neutral
	assert_eq(hud.fold_counter_label.get_theme_color("font_color"),
		UIPalette.color_for_tier(UIPalette.TIER_COMPLETE), "over 1.5x par uses neutral color")


func test_fold_counter_no_color_override_without_par():
	var hud = await _make_hud()
	hud.set_level_info("Test", -1)  # no par
	hud.set_fold_count(3)
	assert_false(hud.fold_counter_label.has_theme_color_override("font_color"),
		"no performance color when par is unset")
