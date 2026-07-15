class_name UIConstants extends RefCounted

## UIConstants
##
## Sizing/spacing values that a Godot Theme CANNOT hold — `custom_minimum_size` is a
## Control property, not a theme item, so the theme owns fonts/colors/StyleBoxes and
## this file owns the pixel dimensions. Together they replace the per-screen magic
## numbers (button sizes 120..400, panel sizes 400..700, font sizes 14..64).
##
## Pairs with the theme's type variations: the variation sets font_size + content
## margins; the matching constant here sets `custom_minimum_size`.

## Font scale — replaces the ad-hoc 14/16/18/20/24/28/48/56/64 sprinkled across scenes.
const FONT_SM := 16    # secondary / captions
const FONT_MD := 20    # body / labels
const FONT_LG := 24    # buttons / emphasis
const FONT_XL := 32    # section headings
const FONT_DISPLAY := 56 # screen titles

## Button minimum sizes by role.
const MENU_BUTTON := Vector2(320, 60)   # main-menu / pause / full-width menu actions
const DIALOG_BUTTON := Vector2(200, 60) # Apply / Back / dialog actions
const HUD_BUTTON := Vector2(120, 50)    # compact top-bar buttons
const LEVEL_BUTTON := Vector2(250, 120) # level-select grid tiles

## Panel / overlay sizing.
const PANEL_STANDARD := Vector2(500, 600) # pause / level-complete panels
const PANEL_WIDE := Vector2(600, 700)     # settings

## Spacing + margins.
const SPACING_SM := 10
const SPACING_MD := 20
const SPACING_LG := 30
const MARGIN_SCREEN := 40
