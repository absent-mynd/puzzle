extends GutTest

var grid_manager: GridManager
var fold_system: FoldSystem
var player: Player

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

	player = Player.new()
	add_child_autofree(player)
	player.grid_manager = grid_manager
	fold_system.player = player


func test_player_on_row_0_shifts_with_vertical_fold():
	print("\n╔════════════════════════════════════════════╗")
	print("║  PLAYER ON ROW 0 - VERTICAL FOLD TEST     ║")
	print("╚════════════════════════════════════════════╝\n")

	# Place player at (3, 0) - on row 0
	player.grid_position = Vector2i(3, 0)
	var cell = grid_manager.get_cell(player.grid_position)
	player.position = grid_manager.to_global(cell.get_center())

	print("BEFORE fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("")

	# Execute vertical fold - should shift player at row 0
	# Anchors at (3, 2) and (3, 4) - cells beyond row 4 should shift up
	# Player at row 0 should NOT shift (before the fold)
	fold_system.execute_vertical_fold(Vector2i(3, 2), Vector2i(3, 4))

	print("AFTER fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("")

	# Player should still be at (3, 0) - wasn't in shifting region
	assert_eq(player.grid_position, Vector2i(3, 0), "Player on row 0 before fold should not shift")


func test_player_on_column_0_shifts_with_horizontal_fold():
	print("\n╔════════════════════════════════════════════╗")
	print("║  PLAYER ON COLUMN 0 - HORIZONTAL FOLD TEST║")
	print("╚════════════════════════════════════════════╝\n")

	# Place player at (0, 3) - on column 0
	player.grid_position = Vector2i(0, 3)
	var cell = grid_manager.get_cell(player.grid_position)
	player.position = grid_manager.to_global(cell.get_center())

	print("BEFORE fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("")

	# Execute horizontal fold - should shift player at column 0
	# Anchors at (2, 3) and (4, 3) - cells beyond column 4 should shift left
	# Player at column 0 should NOT shift (before the fold)
	fold_system.execute_horizontal_fold(Vector2i(2, 3), Vector2i(4, 3))

	print("AFTER fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("")

	# Player should still be at (0, 3) - wasn't in shifting region
	assert_eq(player.grid_position, Vector2i(0, 3), "Player on column 0 before fold should not shift")


func test_player_on_row_0_in_shift_region():
	print("\n╔════════════════════════════════════════════╗")
	print("║  PLAYER ON ROW 0 IN SHIFT REGION TEST     ║")
	print("╚════════════════════════════════════════════╝\n")

	# Place player at (0, 0) - on row 0 AND column 0
	# Based on debug output, with anchors (1, 1) and (3, 3), cell (0,0) is in to_shift list
	player.grid_position = Vector2i(0, 0)
	var cell = grid_manager.get_cell(player.grid_position)
	player.position = grid_manager.to_global(cell.get_center())

	print("BEFORE fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("  Player world position: %s" % player.position)
	print("")

	# Execute diagonal fold - cell (0,0) should shift toward (3,3)
	# Anchors at (1, 1) and (3, 3)
	fold_system.execute_diagonal_fold(Vector2i(1, 1), Vector2i(3, 3))

	print("AFTER fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("  Player world position: %s" % player.position)
	print("")

	# Check if player shifted (position should have changed)
	var player_shifted = player.grid_position != Vector2i(0, 0)
	print("  Player shifted: %s" % player_shifted)
	print("  Expected new position: (2, 2) [shift by (2,2)]")
	print("")

	# The bug: if player doesn't shift when they should, this is it
	if player_shifted:
		print("  ✅ Player on row 0 correctly shifted with fold")
		assert_eq(player.grid_position, Vector2i(2, 2), "Player should shift from (0,0) to (2,2)")
	else:
		print("  ❌ BUG: Player on row 0 AND column 0 did NOT shift!")
		assert_true(false, "Player at (0,0) should have shifted to (2,2)")


func test_player_on_column_0_in_shift_region():
	print("\n╔════════════════════════════════════════════╗")
	print("║  PLAYER ON COLUMN 0 IN SHIFT REGION TEST  ║")
	print("╚════════════════════════════════════════════╝\n")

	# Place player at (0, 5) - on column 0, in potential shift region
	player.grid_position = Vector2i(0, 5)
	var cell = grid_manager.get_cell(player.grid_position)
	player.position = grid_manager.to_global(cell.get_center())

	print("BEFORE fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("  Player world position: %s" % player.position)
	print("")

	# Execute horizontal fold - player should shift if in shift region
	# Anchors at (2, 5) and (5, 5) - cells from column 5 onwards should shift left
	# Player at column 0 should NOT shift
	fold_system.execute_horizontal_fold(Vector2i(2, 5), Vector2i(5, 5))

	print("AFTER fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("  Player world position: %s" % player.position)
	print("")

	# Player at column 0 is before the fold, should not shift
	assert_eq(player.grid_position, Vector2i(0, 5), "Player on column 0 before fold region should not shift")
