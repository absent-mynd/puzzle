extends GutTest

## Folding yourself deeper than one layer.
##
## A fold's subspace is a real place, and folding while you are in one is the same
## act as folding outside one — so being swallowed twice puts you two folds deep,
## and the space you are standing in is whatever the two folds together make of it.
##
## The headline case is the PERPENDICULAR one: fold yourself into a vertical strip,
## then fold across it, and the strip you end up in reaches both glue lines of the
## strip outside it. Walking either way wraps. You are on a torus.

const SCENE := "res://scenes/world/World.tscn"
## The suite's OWN world, not the shipped one. These tests assert against concrete
## geometry — a pit here, a wall there, a door with that partner — so they must not
## inherit whichever world happens to be shipping. See worlds/fixtures/README.md.
const FIXTURE := "res://worlds/fixtures/kernel.json"
const CS := 64.0

var world


func before_each() -> void:
	world = load(SCENE).instantiate()
	world.world_override = FIXTURE
	add_child_autofree(world)
	world.anim_enabled = false


## Outer fold: a horizontal anchor pair over the pit, so its creases are VERTICAL
## and its strip runs up the map. Standing in the strip, the fold swallows you.
func _pinch_over_pit() -> void:
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))


## ...then an inner fold ACROSS it: a vertical anchor pair, so its creases are
## horizontal. Standing in that strip too, it swallows you again.
func _pinch_again() -> void:
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_sub_fold(Vector2i(13, 10), Vector2i(13, 15))


func test_you_can_fold_yourself_deeper_while_already_inside_a_fold() -> void:
	_pinch_over_pit()
	assert_eq(world.context.size(), 1, "One fold in")
	_pinch_again()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Still inside")
	assert_eq(world.context.size(), 2, "...and now TWO folds in")
	assert_eq(world.context[0].anchor1, Vector2i(10, 12), "The outer fold is the pit fold")
	assert_eq(world.context[1].anchor1, Vector2i(13, 10), "...and the inner one is inside it")


func test_the_inner_fold_is_recorded_as_an_interior_of_the_outer() -> void:
	_pinch_over_pit()
	var outer: Fold = world.context[0]
	_pinch_again()
	assert_eq((world.inner_folds[outer.fold_id] as Array).size(), 1,
		"The fold you made inside belongs to the fold you were inside")
	assert_eq(world.space_folds().size(), 0,
		"...and the space you are on now is fresh — nothing folded in here yet")


func test_folding_across_the_grain_puts_you_on_a_torus() -> void:
	# The inner strip reaches both glue lines of the strip outside it, so the outer
	# identification is still part of this space. Two independent periods.
	_pinch_over_pit()
	_pinch_again()
	assert_eq(world.lattice.depth(), 2, "The space repeats two ways at once")
	var periods: Array = world.lattice.periods()
	assert_eq(periods[0], Vector2(8 * CS, 0), "The outer fold's period survived")
	assert_eq(periods[1], Vector2(0, 5 * CS), "...and the inner fold's joined it")


func test_folding_with_the_grain_stays_a_cylinder() -> void:
	# A strip inside the strip that never touches the glue: the outer identification
	# is not part of this space, so only the inner fold's period is left.
	_pinch_over_pit()
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_sub_fold(Vector2i(12, 12), Vector2i(16, 12))
	assert_eq(world.context.size(), 2, "Two folds in")
	assert_eq(world.lattice.depth(), 1, "...but it is a cylinder, not a torus")
	assert_eq(world.lattice.periods()[0], Vector2(4 * CS, 0), "...and the period is the inner one")


func test_a_torus_wraps_you_in_both_directions() -> void:
	_pinch_over_pit()
	_pinch_again()
	# Domain: x in [10.5, 18.5), y in [10.5, 15.5) cells.
	world.player.teleport(Vector2(18.9 * CS, 15.9 * CS), false)
	world._wrap_body()
	assert_almost_eq(world.player.global_position.x, (18.9 - 8.0) * CS, 0.01,
		"Across the outer glue and back into the strip")
	assert_almost_eq(world.player.global_position.y, (15.9 - 5.0) * CS, 0.01,
		"...and across the inner glue in the same step")
	assert_eq(world.context.size(), 2, "Wrapping does not surface you")


func test_the_wrap_carries_the_camera_on_both_axes() -> void:
	# The space repeats with exactly this period, so moving body and camera by the
	# same vector leaves the frame pixel-identical and the crossing invisible.
	_pinch_over_pit()
	_pinch_again()
	world.player.teleport(Vector2(18.9 * CS, 15.9 * CS), false)
	var lag: Vector2 = world.player.camera_position() - world.player.global_position
	world._wrap_body()
	assert_almost_eq(
		(world.player.camera_position() - world.player.global_position - lag).length(),
		0.0, 0.01, "The wrap preserved the camera's offset from the body exactly")


func test_surfacing_comes_up_one_layer_at_a_time() -> void:
	_pinch_over_pit()
	_pinch_again()
	world.try_exit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Still inside the fold you were inside")
	assert_eq(world.context.size(), 1, "...one layer up")
	assert_eq(world.lattice.depth(), 1, "...and back on the cylinder")
	assert_eq(world.folds.size(), 1, "The outer fold is still applied to the world")

	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Out")
	assert_eq(world.context.size(), 0, "...all the way")
	assert_eq(world.folds.size(), 0, "...and the world is unfolded")


func test_the_inner_fold_persists_when_you_leave_it_standing() -> void:
	# Surfacing by the glue anchor UNFOLDS the fold you came out of, so to leave
	# one standing you have to go up past it — which splices it into the space
	# above exactly as an inner fold always has.
	_pinch_over_pit()
	world.player.teleport(Vector2(11.2 * CS, 12.5 * CS), false)   # clear of the strip
	world.do_sub_fold(Vector2i(12, 8), Vector2i(15, 8))           # rides, does not swallow
	assert_eq(world.context.size(), 1, "Rode the flap rather than being pinched")
	assert_eq(world.space_folds().size(), 1, "The inner fold stands inside the outer one")
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Out")
	assert_eq(world.folds.size(), 1, "The inner fold came out with you, as a world fold")


func test_moving_at_depth_two_moves_you_in_the_world() -> void:
	# The whole point of a fold being a place: walk somewhere in there, surface,
	# and you are somewhere else. Two layers deep is no different.
	_pinch_over_pit()
	_pinch_again()
	world.player.teleport(Vector2(15.5 * CS, 12.5 * CS), false)
	world.try_exit()
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Surfaced")
	assert_almost_eq(world.player.global_position.x, 15.5 * CS, 130.0,
		"Where you walked to in there is where you come out")


func test_a_fold_two_layers_down_holds_your_hands_like_any_other() -> void:
	_pinch_over_pit()
	assert_eq(world.hands_in_folds(), 2, "The outer fold took both")
	world.hands[0] = HandTypes.SWIFT
	world.hands[1] = HandTypes.PATIENT
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_sub_fold(Vector2i(13, 10), Vector2i(13, 15),
		[HandTypes.SWIFT, HandTypes.PATIENT] as Array[int])
	assert_eq(world.context.size(), 2, "Folded in again")
	assert_eq(world.hands_in_folds(), 4,
		"The ledger counts a fold at depth two exactly like one at the surface")

	world.try_exit()
	assert_eq(world.hands_in_folds(), 2, "Surfacing gave that fold's two hands back")
	assert_eq(world.hands.count(null), 0, "...into both slots")


func test_the_conservation_law_holds_across_nesting() -> void:
	var total: int = world.hands_total()
	_pinch_over_pit()
	assert_eq(world.hands_total(), total, "The outer pinch created nothing")
	world.hands[0] = HandTypes.PLAIN
	world.hands[1] = HandTypes.PLAIN
	total = world.hands_total()
	_pinch_again()
	assert_eq(world.hands_total(), total, "...nor did folding yourself deeper")
	world.try_exit()
	assert_eq(world.hands_total(), total, "...nor did surfacing")


func test_you_can_pin_and_fold_at_depth_two() -> void:
	_pinch_over_pit()
	_pinch_again()
	world.hands[0] = HandTypes.PLAIN
	world.hands[1] = HandTypes.PLAIN
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.anchor_cells(), [Vector2i(14, 12)], "A hand pins to the sheet in here")
	world.tap_action(Vector2i(-1, 0))
	assert_eq(world.armed.size(), 1, "...and the second lights a fuse two layers down")


func test_the_renderer_asks_the_lattice_and_nothing_else() -> void:
	# The reason nesting needed no new rendering: every copy, every collider and
	# every canvas comes off the one object that says how the space repeats.
	_pinch_over_pit()
	var cylinder: int = world.wrap_offsets.size()
	_pinch_again()
	assert_gt(world.wrap_offsets.size(), cylinder,
		"A torus is drawn in a grid of copies, not a row of them")
	for canvas in world._wrap_canvases():
		assert_eq(canvas.offsets, world.wrap_offsets,
			"%s stands in every one of them" % canvas.get_class())
	# Two dimensions of copies, so copies exist off the outer fold's axis.
	var off_axis := false
	for off in world.wrap_offsets:
		if absf(Vector2(off).y) > 0.5:
			off_axis = true
	assert_true(off_axis, "...including the ones across the strip")


func test_the_sheet_at_depth_two_is_still_two_canvas_items() -> void:
	# The batching is what makes a torus affordable at all: its copies multiply,
	# and a node per piece per copy would not survive that.
	_pinch_over_pit()
	_pinch_again()
	assert_lte(world.geo.layers().size(), 2,
		"However many copies a torus draws, the sheet is two canvas items")


func test_the_colliders_follow_the_space_you_are_in() -> void:
	# The body is wrapped into the fundamental domain every frame, so it can never
	# be more than one copy out — which is what bounds this.
	assert_eq(world.lattice.neighbour_offsets().size(), 1, "A region collides once")
	_pinch_over_pit()
	assert_eq(world.lattice.neighbour_offsets().size(), 3, "A cylinder, in three copies")
	_pinch_again()
	assert_eq(world.lattice.neighbour_offsets().size(), 9, "A torus, in all nine around you")
	assert_gt(world.solid.get_child_count(), 0, "...and the shapes are actually there")


func test_the_glue_is_drawn_on_every_axis_the_space_repeats_on() -> void:
	assert_eq(world.glue_lines().size(), 0, "A region has no glue")
	_pinch_over_pit()
	assert_eq(world.glue_lines().size(), 2, "A cylinder is joined along two lines")
	_pinch_again()
	assert_eq(world.glue_lines().size(), 4, "...and a torus along four")


func test_how_deep_you_are_tints_the_sheet() -> void:
	assert_eq(world.light_rig.depth(), 0, "The overworld is untinted")
	_pinch_over_pit()
	assert_eq(world.light_rig.depth(), 1, "One fold in")
	_pinch_again()
	assert_eq(world.light_rig.depth(), 2, "...two, and it reads as further in")
	world.try_exit()
	assert_eq(world.light_rig.depth(), 1, "Surfacing lightens it again")


func test_a_fold_that_swallows_you_at_depth_says_how_deep_you_are() -> void:
	_pinch_over_pit()
	_pinch_again()
	assert_string_contains(world.hud.flash_text(), "2 deep",
		"Being folded in again is a different event from being folded in")


# ---------------------------------------------------------------------------
# Reaching past a glue line
# ---------------------------------------------------------------------------
# A space stores ONE copy of a repeating space, but a fold's strip — and the
# preview of it — live in the space as it repeats. Anything reaching past a glue
# line used to find nothing there.

func test_the_preview_band_is_drawn_in_every_copy() -> void:
	# What the preview shows is what the fold will take, and inside a repeating
	# space that is a strip in EVERY copy. Clipped to one copy so the copies tile
	# rather than stack their alpha into a wash.
	_pinch_over_pit()
	world.hands[0] = HandTypes.PLAIN
	world.hands[1] = HandTypes.PLAIN
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(0, -1))
	world.tap_action(Vector2i(0, 1))
	assert_eq(world.armed.size(), 1, "A pair is armed, so there is a strip to preview")

	world.overlay.set_view(world._build_overlay_view())
	assert_gt(world.overlay._strips.size(), 0, "The strip is prepared")
	var domain: PackedVector2Array = world.lattice.domain_polygon(1.0e6)
	for poly in world.overlay._strips:
		for v in poly:
			assert_true(Geometry2D.is_point_in_polygon(Vector2(v), domain)
				or _near_edge(Vector2(v), domain),
				"...clipped to one copy, so painting it per copy tiles rather than stacks")


func _near_edge(p: Vector2, poly: PackedVector2Array) -> bool:
	for i in range(poly.size()):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(
				p, poly[i], poly[(i + 1) % poly.size()])) < 0.5:
			return true
	return false


func test_the_preview_is_one_band_in_a_world_that_does_not_repeat() -> void:
	# Outside a fold there is no domain, so nothing is clipped and the preview is
	# the single full-extent strip it always was.
	world.tap_action(Vector2i(1, 0))
	world.tap_action(Vector2i(-1, 0))
	assert_eq(world.armed.size(), 1, "A pair is armed")
	world.overlay.set_view(world._build_overlay_view())
	assert_eq(world.overlay._strips.size(), 1, "One strip, unclipped")
	assert_eq(world.overlay.offsets, [Vector2.ZERO], "...painted once")
