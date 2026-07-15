## LevelSelectShared unit tests
##
## Locks the star-string rendering and the status->color mapping that the campaign and
## custom level-select screens both depend on, so the two screens can't drift apart
## again (the original bug was divergent hardcoded colors).

extends GutTest


func test_star_string_partial():
	assert_eq(LevelSelectShared.star_string(0), "☆☆☆", "no stars")
	assert_eq(LevelSelectShared.star_string(1), "★☆☆", "one star")
	assert_eq(LevelSelectShared.star_string(2), "★★☆", "two stars")
	assert_eq(LevelSelectShared.star_string(3), "★★★", "three stars")


func test_star_string_clamped_display():
	# More than MAX_STARS still renders MAX_STARS glyphs (all filled).
	assert_eq(LevelSelectShared.star_string(5).length(), LevelSelectShared.MAX_STARS,
		"never renders more than MAX_STARS glyphs")


func test_campaign_status_color():
	assert_eq(LevelSelectShared.campaign_status_color(true, true), UIPalette.GOLD_STAR, "completed -> gold")
	assert_eq(LevelSelectShared.campaign_status_color(true, false), UIPalette.SUCCESS, "unlocked -> success")
	assert_eq(LevelSelectShared.campaign_status_color(false, false), UIPalette.NEUTRAL, "locked -> neutral")


func test_custom_accent_color_is_palette_accent():
	assert_eq(LevelSelectShared.custom_accent_color(), UIPalette.ACCENT, "custom tiles use the shared accent")
