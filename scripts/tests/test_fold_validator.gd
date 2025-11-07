class_name FoldTestValidator
extends RefCounted

## Utility class for validating fold operation results
## Implements comprehensive checks to catch bugs like disappearing cells, memory leaks, etc.

## Calculate total area of all cells
static func calculate_total_area(grid_manager: GridManager) -> float:
	var total = 0.0
	for cell in grid_manager.cells.values():
		if is_instance_valid(cell) and cell.geometry.size() > 0:
			total += GeometryCore.polygon_area(cell.geometry)
	return total

## Get grid bounds (min/max x/y coordinates)
static func get_grid_bounds(grid_manager: GridManager) -> Dictionary:
	var min_x = 0
	var max_x = 0
	var min_y = 0
	var max_y = 0
	var first = true

	for pos in grid_manager.cells.keys():
		if first:
			min_x = pos.x
			max_x = pos.x
			min_y = pos.y
			max_y = pos.y
			first = false
		else:
			min_x = min(min_x, pos.x)
			max_x = max(max_x, pos.x)
			min_y = min(min_y, pos.y)
			max_y = max(max_y, pos.y)

	return {
		"min_x": min_x, "max_x": max_x,
		"min_y": min_y, "max_y": max_y,
		"width": max_x - min_x + 1 if not first else 0,
		"height": max_y - min_y + 1 if not first else 0
	}

## Check for freed/invalid cell references in dictionary
static func find_freed_cells(grid_manager: GridManager) -> Array:
	var freed = []
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		if not is_instance_valid(cell):
			freed.append(pos)
	return freed

## Verify cell has valid geometry
static func verify_cell_geometry(cell: Cell, min_area: float = 10.0) -> Dictionary:
	var result = {
		"valid": true,
		"errors": []
	}

	if cell.geometry == null or cell.geometry.size() == 0:
		result.valid = false
		result.errors.append("Cell has null or empty geometry")
		return result

	if cell.geometry.size() < 3:
		result.valid = false
		result.errors.append("Cell geometry has < 3 vertices (%d)" % cell.geometry.size())

	var area = GeometryCore.polygon_area(cell.geometry)
	if area < min_area:
		result.valid = false
		result.errors.append("Cell area %.1f is too small (min: %.1f)" % [area, min_area])

	# Check for degenerate geometry (area near zero)
	if abs(area) < 0.01:
		result.valid = false
		result.errors.append("Cell has degenerate geometry (area ~0)")

	return result

## Mark cells with original positions for identity tracking
static func mark_cells_with_positions(grid_manager: GridManager) -> Dictionary:
	var cell_markers = {}
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.get_cell(pos)
		if cell:
			# Use cell_type as unique marker
			cell.cell_type = pos.x * 1000 + pos.y
			cell_markers[cell] = pos
	return cell_markers

## Comprehensive validation after a fold operation
## Returns: Dictionary with validation results
static func validate_fold_result(
	grid_manager: GridManager,
	cells_before: int,
	area_before: float,
	expected_removed: int,
	allow_negative_coords: bool = false
) -> Dictionary:
	var result = {
		"passed": true,
		"errors": [],
		"warnings": [],
		"stats": {}
	}

	# 1. Cell count validation
	var cells_after = grid_manager.cells.size()
	var expected_after = cells_before - expected_removed
	result.stats["cells_before"] = cells_before
	result.stats["cells_after"] = cells_after
	result.stats["expected_after"] = expected_after

	if cells_after != expected_after:
		result.passed = false
		result.errors.append(
			"Cell count mismatch: expected %d, got %d (lost %d cells)" %
			[expected_after, cells_after, cells_before - cells_after]
		)

	# 2. Check for freed instances
	var freed_cells = find_freed_cells(grid_manager)
	if freed_cells.size() > 0:
		result.passed = false
		result.errors.append(
			"Found %d freed cell references at: %s" %
			[freed_cells.size(), freed_cells]
		)

	# 3. Geometry validation
	var invalid_geometry_count = 0
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.get_cell(pos)
		if cell:
			var geom_result = verify_cell_geometry(cell)
			if not geom_result.valid:
				invalid_geometry_count += 1
				result.errors.append(
					"Cell at %s has invalid geometry: %s" %
					[pos, ", ".join(geom_result.errors)]
				)

	result.stats["invalid_geometry_count"] = invalid_geometry_count

	# 4. Area conservation (within tolerance)
	var area_after = calculate_total_area(grid_manager)
	var expected_area = area_before - (expected_removed * 64 * 64)  # Assuming 64x64 cells
	var area_diff = abs(area_after - expected_area)
	result.stats["area_before"] = area_before
	result.stats["area_after"] = area_after
	result.stats["expected_area"] = expected_area
	result.stats["area_diff"] = area_diff

	if area_diff > 1000.0:  # Allow 1000 sq pixels tolerance
		result.warnings.append(
			"Total area changed significantly: %.1f → %.1f (expected %.1f, diff %.1f)" %
			[area_before, area_after, expected_area, area_diff]
		)

	# 5. Grid bounds validation
	var bounds = get_grid_bounds(grid_manager)
	result.stats["bounds"] = bounds

	if not allow_negative_coords:
		if bounds.min_x < 0:
			result.passed = false
			result.errors.append("Grid has negative X coordinates (min_x=%d)" % bounds.min_x)
		if bounds.min_y < 0:
			result.passed = false
			result.errors.append("Grid has negative Y coordinates (min_y=%d)" % bounds.min_y)

	return result

## Print validation results in human-readable format
static func print_validation_results(result: Dictionary) -> void:
	print("\n=== Fold Validation Results ===")

	if result.passed:
		print("✅ ALL CHECKS PASSED")
	else:
		print("❌ VALIDATION FAILED")

	print("\nStats:")
	for key in result.stats.keys():
		var value = result.stats[key]
		if value is Dictionary:
			print("  %s:" % key)
			for subkey in value.keys():
				print("    %s: %s" % [subkey, value[subkey]])
		else:
			print("  %s: %s" % [key, value])

	if result.errors.size() > 0:
		print("\nErrors:")
		for error in result.errors:
			print("  ❌ %s" % error)

	if result.warnings.size() > 0:
		print("\nWarnings:")
		for warning in result.warnings:
			print("  ⚠️  %s" % warning)

	print("========================================")  # 40 equals signs
