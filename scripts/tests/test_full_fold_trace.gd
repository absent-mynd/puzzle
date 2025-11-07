extends GutTest

# Test actual fold execution to see which cells remain

var grid_manager: GridManager
var fold_system: FoldSystem

func before_each():
	grid_manager = GridManager.new()
	grid_manager.grid_size = Vector2i(5, 5)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)

func after_each():
	if grid_manager:
		grid_manager.queue_free()
	if fold_system:
		fold_system.queue_free()

func print_grid_state(title: String):
	print("\n=== %s ===" % title)
	print("Grid state (row 2):")
	var row_str = "  "
	for x in range(grid_manager.grid_size.x):
		var pos = Vector2i(x, 2)
		var cell = grid_manager.get_cell(pos)
		if cell:
			if cell.is_partial:
				row_str += "[P%d]" % x
			else:
				row_str += "[F%d]" % x  # Full cell
		else:
			row_str += " .. "
	print(row_str)
	print("  Total cells in grid: %d" % grid_manager.cells.size())

## Test full execution with reversed anchors
func test_full_fold_reversed_anchors():
	var anchor1 = Vector2i(3, 2)
	var anchor2 = Vector2i(1, 2)

	print("\n╔════════════════════════════════════════════╗")
	print("║  FULL FOLD TEST: Reversed Anchors         ║")
	print("║  anchor1=(3,2), anchor2=(1,2)             ║")
	print("╚════════════════════════════════════════════╝")

	print_grid_state("BEFORE fold")

	# Execute the fold
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print_grid_state("AFTER fold")

	# Check which cells remain
	print("\nCell inventory (row 2):")
	for x in range(grid_manager.grid_size.x):
		var pos = Vector2i(x, 2)
		var cell = grid_manager.get_cell(pos)
		if cell:
			print("  x=%d: EXISTS (partial=%s, geometry vertices=%d)" % [
				x, cell.is_partial, cell.geometry.size()
			])
			if cell.geometry.size() > 0:
				var min_x = INF
				var max_x = -INF
				for v in cell.geometry:
					min_x = min(min_x, v.x)
					max_x = max(max_x, v.x)
				print("        geometry x-range: [%.1f, %.1f]" % [min_x, max_x])
		else:
			print("  x=%d: MISSING ❌" % x)

	# Expectations (WITH NORMALIZATION FIX)
	print("\n╔════════════════════════════════════════════╗")
	print("║  Expected Results (with normalization):    ║")
	print("╠════════════════════════════════════════════╣")
	print("║  x=0: Should EXIST (left of left anchor)   ║")
	print("║  x=1: Should EXIST (merged at left anchor) ║")
	print("║  x=2: Should EXIST (shifted from x=4)      ║")
	print("║  x=3: Removed/shifted (no longer exists)   ║")
	print("║  x=4: Removed/shifted (no longer exists)   ║")
	print("║  NOTE: With normalization, cells always    ║")
	print("║        shift toward LEFT-MOST anchor       ║")
	print("╚════════════════════════════════════════════╝")

	# Assertions (UPDATED for normalized behavior)
	assert_not_null(grid_manager.get_cell(Vector2i(0, 2)), "Cell at x=0 should exist")
	assert_not_null(grid_manager.get_cell(Vector2i(1, 2)), "Cell at x=1 should exist (merged)")
	assert_not_null(grid_manager.get_cell(Vector2i(2, 2)), "Cell at x=2 should exist (shifted from x=4)")

	# Check if split cells have proper geometry
	var cell_1 = grid_manager.get_cell(Vector2i(1, 2))
	if cell_1:
		assert_true(cell_1.is_partial, "Cell at x=1 should be marked as partial")
		assert_true(cell_1.geometry.size() >= 3, "Cell at x=1 should have valid geometry")

	# Cell at x=3 no longer exists after normalization (shifted away)

## Test full execution with normal anchors for comparison
func test_full_fold_normal_anchors():
	var anchor1 = Vector2i(1, 2)
	var anchor2 = Vector2i(3, 2)

	print("\n╔════════════════════════════════════════════╗")
	print("║  FULL FOLD TEST: Normal Anchors           ║")
	print("║  anchor1=(1,2), anchor2=(3,2)             ║")
	print("╚════════════════════════════════════════════╝")

	print_grid_state("BEFORE fold")

	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print_grid_state("AFTER fold")

	print("\nCell inventory (row 2):")
	for x in range(grid_manager.grid_size.x):
		var pos = Vector2i(x, 2)
		var cell = grid_manager.get_cell(pos)
		if cell:
			print("  x=%d: EXISTS (partial=%s)" % [x, cell.is_partial])
		else:
			print("  x=%d: MISSING" % x)

	# Same assertions as reversed test (normalization makes them identical)
	assert_not_null(grid_manager.get_cell(Vector2i(0, 2)), "Cell at x=0 should exist")
	assert_not_null(grid_manager.get_cell(Vector2i(1, 2)), "Cell at x=1 should exist (merged)")
	assert_not_null(grid_manager.get_cell(Vector2i(2, 2)), "Cell at x=2 should exist (shifted from x=4)")
