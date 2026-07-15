class_name UIPalette extends RefCounted

## UIPalette
##
## The single source of truth for SEMANTIC UI colors and the star-tier rule. Before
## this, "good / warning / gold / muted" meanings were re-encoded with divergent RGB
## values in HUD.gd, LevelComplete.gd, LevelSelect.gd, and CustomLevelSelect.gd, and
## the star-tier threshold (<=par, <=1.5*par) was implemented twice. Consolidating them
## here means the whole UI reads as one system and the tier rule has exactly one home.
##
## Pure static data + functions (same shape as TileTypes). Tile-APPEARANCE colors live
## in TileTypes.color_for; this file is for UI chrome and performance feedback.

## Semantic feedback colors (tuned for the dark UI background).
const SUCCESS := Color(0.2, 0.8, 0.2)    # perfect / good state
const WARNING := Color(0.85, 0.75, 0.2)  # near the limit
const DANGER := Color(0.9, 0.3, 0.2)     # failure / blocked action
const GOLD_STAR := Color(1.0, 0.84, 0.0) # earned star
const NEUTRAL := Color(0.6, 0.6, 0.6)    # muted / completed-only
const STAR_EMPTY := Color(0.3, 0.3, 0.3) # unearned star

## Backgrounds — unifies the three divergent values that were scattered across scenes.
const BG_MENU := Color(0.1, 0.1, 0.15)      # menu screens
const BG_GAMEPLAY := Color(0.15, 0.15, 0.15) # in-level background
const OVERLAY_DIM := Color(0.0, 0.0, 0.0, 0.7) # dim behind modal overlays

## Star tiers (higher is better).
const TIER_PERFECT := 3
const TIER_GOOD := 2
const TIER_COMPLETE := 1


## Star tier for a completion: 3 if at/under par, 2 if within 1.5x par, else 1.
## A non-positive `par` means "no par set" -> completion only (tier 1). This is the
## single home for the threshold rule (matches the legacy HUD + LevelComplete logic).
static func star_tier(folds: int, par: int) -> int:
	if par <= 0:
		return TIER_COMPLETE
	if folds <= par:
		return TIER_PERFECT
	if folds <= par * 1.5:
		return TIER_GOOD
	return TIER_COMPLETE


## Feedback color for a star tier (perfect=success, good=warning, complete=neutral).
static func color_for_tier(tier: int) -> Color:
	match tier:
		TIER_PERFECT: return SUCCESS
		TIER_GOOD: return WARNING
		_: return NEUTRAL
