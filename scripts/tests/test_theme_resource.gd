## Theme resource sanity tests
##
## The theme is hand-authored .tres (no GUI in CI), so these guard against a parse
## error or a missing item silently reverting the UI to the stock Godot look. They
## assert the resource loads as a Theme, the Button has the hover/pressed/focus styles
## that are the visible "refresh", and the type variations the screens rely on exist.

extends GutTest

const THEME_PATH := "res://assets/themes/main_theme.tres"


func test_theme_loads_as_theme():
	var theme = load(THEME_PATH)
	assert_not_null(theme, "theme resource loads")
	assert_true(theme is Theme, "resource is a Theme")


func test_button_has_interaction_styles():
	var theme: Theme = load(THEME_PATH)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		assert_true(theme.has_stylebox(state, "Button"),
			"Button has a '%s' StyleBox (the stock theme had none)" % state)


func test_panel_containers_are_styled():
	var theme: Theme = load(THEME_PATH)
	assert_true(theme.has_stylebox("panel", "PanelContainer"), "PanelContainer is styled")


func test_type_variations_registered():
	var theme: Theme = load(THEME_PATH)
	for variation in ["TitleLabel", "HeadingLabel", "StatusLabel", "PrimaryButton", "DangerButton", "HudButton"]:
		assert_true(theme.get_type_variation_base(variation) != &"",
			"type variation '%s' is registered" % variation)


func test_project_wires_theme_globally():
	# The theme is only useful if it's the project default.
	assert_eq(ProjectSettings.get_setting("gui/theme/custom", ""), THEME_PATH,
		"project.godot wires the theme as the global default")
