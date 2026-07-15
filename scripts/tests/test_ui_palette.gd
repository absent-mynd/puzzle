## UIPalette unit tests
##
## The star-tier threshold rule is the highest-value pure logic in the UI overhaul
## (it was previously implemented twice with divergent colors). These lock the tier
## boundaries and the tier->color mapping.

extends GutTest


func test_tier_perfect_at_or_under_par():
	assert_eq(UIPalette.star_tier(3, 5), UIPalette.TIER_PERFECT, "under par is perfect")
	assert_eq(UIPalette.star_tier(5, 5), UIPalette.TIER_PERFECT, "exactly par is perfect")


func test_tier_good_within_one_and_a_half_par():
	# par=4 -> 1.5*par=6; folds 5 and 6 are 'good', 7 is not.
	assert_eq(UIPalette.star_tier(5, 4), UIPalette.TIER_GOOD, "just over par is good")
	assert_eq(UIPalette.star_tier(6, 4), UIPalette.TIER_GOOD, "exactly 1.5x par is good")


func test_tier_complete_over_one_and_a_half_par():
	assert_eq(UIPalette.star_tier(7, 4), UIPalette.TIER_COMPLETE, "over 1.5x par is completion only")


func test_tier_complete_when_par_unset():
	assert_eq(UIPalette.star_tier(2, -1), UIPalette.TIER_COMPLETE, "par=-1 (unset) -> completion")
	assert_eq(UIPalette.star_tier(0, 0), UIPalette.TIER_COMPLETE, "par=0 -> completion")


func test_color_for_tier_mapping():
	assert_eq(UIPalette.color_for_tier(UIPalette.TIER_PERFECT), UIPalette.SUCCESS, "perfect -> success")
	assert_eq(UIPalette.color_for_tier(UIPalette.TIER_GOOD), UIPalette.WARNING, "good -> warning")
	assert_eq(UIPalette.color_for_tier(UIPalette.TIER_COMPLETE), UIPalette.NEUTRAL, "complete -> neutral")
	assert_eq(UIPalette.color_for_tier(999), UIPalette.NEUTRAL, "unknown tier -> neutral fallback")
