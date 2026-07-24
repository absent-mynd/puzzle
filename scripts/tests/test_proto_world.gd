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
