class_name LevelSelectShared extends RefCounted

## LevelSelectShared
##
## Pure helpers shared by LevelSelect (campaign) and CustomLevelSelect. Before this,
## the star string lived only in LevelSelect and the two screens hand-styled their
## buttons with divergent named colors (Color.GOLD/GREEN/DARK_GRAY vs Color.CYAN) that
## matched nothing else in the UI. Centralizing here (and sourcing colors from
## UIPalette) makes the two screens read as one system and makes the logic testable
## without instantiating a scene.

const MAX_STARS := 3


## The ★/☆ star display for a completed level (filled up to `stars`, out of MAX_STARS).
static func star_string(stars: int) -> String:
	var out := ""
	for i in range(MAX_STARS):
		out += "★" if i < stars else "☆"
	return out


## Font color for a campaign level tile by status: completed -> gold, unlocked -> success,
## locked -> muted. (Replaces Color.GOLD / Color.GREEN / Color.DARK_GRAY.)
static func campaign_status_color(is_unlocked: bool, is_completed: bool) -> Color:
	if is_completed:
		return UIPalette.GOLD_STAR
	if is_unlocked:
		return UIPalette.SUCCESS
	return UIPalette.NEUTRAL


## Font color for a custom level tile. (Replaces the lone Color.CYAN.)
static func custom_accent_color() -> Color:
	return UIPalette.ACCENT
