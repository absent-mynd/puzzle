extends GutTest

## Integration tests for the gravity-prototype scene (ProtoWorld): the player
## rides flaps through fold/unfold, and folding around the player pinches them
## into the subspace. Runs the real scene; assertions are synchronous (no
## physics frames advance between calls).

const SCENE := "res://scenes/prototype/FoldPrototype.tscn"
const CS := 64.0

var world


func before_each() -> void:
	world = load(SCENE).instantiate()
	add_child_autofree(world)


func test_player_rides_a_side_flap_and_unfold_returns() -> void:
	var start: Vector2 = world.player.global_position
	# Fold entirely to the player's right: player is on the A-side flap.
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_eq(world.folds.size(), 1, "Fold applied")
	assert_eq(world.mode, world.Mode.WORLD, "Riding a flap stays in the world")
	var ridden: Vector2 = world.player.global_position
	assert_almost_eq(ridden.x, start.x + 4 * CS, 130.0,
		"A-side rides shift_a (4 cells right, +/- depenetration slack)")

	world.pop_fold()
	assert_eq(world.folds.size(), 0, "Unfold removes the fold")
	assert_almost_eq(world.player.global_position.x, start.x, 130.0,
		"Unfold carries the player back")


func test_fold_around_player_pinches_into_subspace_and_exit_restores() -> void:
	# Stand the player over the pit (air column), then fold across them.
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	assert_eq(world.mode, world.Mode.SUBSPACE, "Player in the strip is folded IN")
	assert_eq(world.folds.size(), 0,
		"v1: a pinch fold is not applied to the (invisible) outside world")
	assert_gt(world.sub_geo.get_child_count(), 0, "Subspace geometry exists")
	assert_false(world.world_geo.visible, "Outside world is hidden")

	# Walk inside the fold, then exit: position carries into the world.
	world.player.teleport(Vector2(15.5 * CS, 12.5 * CS), false)
	world.exit_subspace("test exit")
	assert_eq(world.mode, world.Mode.WORLD, "Exit returns to the world")
	assert_true(world.world_geo.visible, "World visible again")
	assert_almost_eq(world.player.global_position.x, 15.5 * CS, 130.0,
		"Moving inside the fold moved you in the world (dive-traversal v1)")


func test_directional_anchor_placement_and_pinch() -> void:
	# Player spawns in cell (4,12); reach is the adjacent cell, facing right.
	world.place_anchor(Vector2i(1, 0))
	assert_eq(world.pending_anchor, Vector2i(5, 12), "First anchor pins the cell in front")
	world.place_anchor(Vector2i(1, 0))
	assert_eq(world.pending_anchor, null, "Pointing at the pending anchor cancels it")

	world.place_anchor(Vector2i(1, 0))              # pin (5,12) again
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.place_anchor(Vector2i(1, 0))              # (9,12): gap 4
	assert_eq(world.mode, world.Mode.SUBSPACE,
		"Player stood between the anchors: folded in")


func test_too_close_second_anchor_keeps_pending() -> void:
	world.place_anchor(Vector2i(1, 0))              # (5,12)
	world.place_anchor(Vector2i(0, 1))              # (4,13): dist sqrt(2), too close
	assert_eq(world.pending_anchor, Vector2i(5, 12),
		"Too-close second anchor is rejected, pending kept")
	assert_eq(world.folds.size(), 0, "No fold committed")


func test_off_axis_anchor_pair_makes_a_diagonal_fold() -> void:
	world.place_anchor(Vector2i(1, 0))              # (5,12)
	world.player.teleport(Vector2(7.5 * CS, 10.5 * CS), false)
	world.place_anchor(Vector2i(1, 0))              # (8,10): off-axis, dist ~3.6
	assert_eq(world.mode, world.Mode.SUBSPACE, "Off-axis pinch folds the player in")
	assert_eq(world.sub_fold.orientation, "diagonal", "The committed fold is diagonal")


func test_no_hud_control_swallows_mouse_input() -> void:
	# Anchor placement relies on _unhandled_input receiving mouse clicks; any
	# Control with MOUSE_FILTER_STOP covering the screen consumes them first
	# (this bit us: the background ColorRect blocked all anchor clicks).
	var stack: Array = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			assert_ne(node.mouse_filter, Control.MOUSE_FILTER_STOP,
				"%s must not stop mouse events" % node.get_path())
		stack.append_array(node.get_children())


func test_subspace_wrap_teleports_across_the_glue() -> void:
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	assert_eq(world.mode, world.Mode.SUBSPACE, "Pinched in")
	# Band along x is (10.5, 18.5) cells. Step past the far crease and wrap.
	world.player.teleport(Vector2(18.9 * CS, 12.5 * CS), false)
	world._subspace_wrap_and_eject()
	assert_almost_eq(world.player.global_position.x, (18.9 - 8.0) * CS, 0.01,
		"Crossing the glue wraps one band width back")
	assert_eq(world.mode, world.Mode.SUBSPACE, "Wrap does not eject")
