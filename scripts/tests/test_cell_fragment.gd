## Unit tests for CellFragment class
##
## Tests the lightweight RefCounted fragment class that stores
## geometry and metadata for cell pieces.

extends GutTest


## ============================================================================
## BASIC CREATION AND PROPERTIES
## ============================================================================

func test_create_fragment():
	# Create a square fragment
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)

	assert_not_null(frag, "Fragment should be created")
	assert_eq(frag.geometry.size(), 4, "Geometry should have 4 vertices")
	assert_eq(frag.fold_created, -1, "Fold ID should be -1 for original")
	assert_gt(frag.get_area(), 0, "Area should be positive")


func test_fragment_caches_area():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)

	# Area should be cached (64 * 64 = 4096)
	assert_almost_eq(frag.area, 4096.0, 0.1, "Cached area should be 64x64")
	assert_almost_eq(frag.get_area(), 4096.0, 0.1, "get_area() should return cached value")


func test_fragment_caches_centroid():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)

	# Centroid should be at (32, 32)
	assert_almost_eq(frag.centroid.x, 32.0, 0.1, "Cached centroid X should be 32")
	assert_almost_eq(frag.centroid.y, 32.0, 0.1, "Cached centroid Y should be 32")


## ============================================================================
## GEOMETRY METHODS
## ============================================================================

func test_fragment_get_centroid():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)
	var centroid = frag.get_centroid()

	assert_almost_eq(centroid.x, 32.0, 0.1, "Centroid X should be 32")
	assert_almost_eq(centroid.y, 32.0, 0.1, "Centroid Y should be 32")


func test_fragment_translate_geometry():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)

	# Translate by (100, 50)
	frag.translate_geometry(Vector2(100, 50))

	assert_almost_eq(frag.geometry[0].x, 100.0, 0.1, "First vertex X should be shifted to 100")
	assert_almost_eq(frag.geometry[0].y, 50.0, 0.1, "First vertex Y should be shifted to 50")
	assert_almost_eq(frag.geometry[1].x, 164.0, 0.1, "Second vertex X should be shifted to 164")
	assert_almost_eq(frag.geometry[1].y, 50.0, 0.1, "Second vertex Y should be shifted to 50")

	# Cached values should be updated
	assert_almost_eq(frag.get_centroid().x, 132.0, 0.1, "Centroid should be updated after translation")


func test_fragment_set_geometry():
	var initial_geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(initial_geometry, -1)

	# Change to triangle
	var new_geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(32, 64)
	])
	frag.set_geometry(new_geometry)

	assert_eq(frag.geometry.size(), 3, "Should have 3 vertices after update")
	assert_lt(frag.get_area(), 4096.0, "Triangle should have smaller area than square")


func test_fragment_is_degenerate_with_few_vertices():
	# Create fragment with only 2 vertices (invalid polygon)
	var geometry = PackedVector2Array([Vector2(0, 0), Vector2(64, 0)])
	var frag = CellFragment.new(geometry, -1)

	assert_true(frag.is_degenerate(), "Fragment with < 3 vertices should be degenerate")


func test_fragment_is_degenerate_with_zero_area():
	# Create collinear points (zero area)
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(32, 0), Vector2(64, 0)
	])
	var frag = CellFragment.new(geometry, -1)

	# Zero area polygon should be degenerate
	assert_true(frag.is_degenerate(), "Zero area polygon should be degenerate")


func test_fragment_is_not_degenerate_with_valid_polygon():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)

	assert_false(frag.is_degenerate(), "Valid square should not be degenerate")


## ============================================================================
## SEAM MANAGEMENT
## ============================================================================

func test_fragment_add_seam():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)
	])
	var frag = CellFragment.new(geometry, -1)

	var seam = {
		"fold_id": 5,
		"line_point": Vector2(32, 32),
		"line_normal": Vector2(1, 0),
		"intersection_points": PackedVector2Array([Vector2(32, 0), Vector2(32, 64)]),
		"timestamp": 1234567890
	}
	frag.add_seam(seam)

	assert_eq(frag.seam_data.size(), 1, "Should have 1 seam")
	assert_eq(frag.seam_data[0].fold_id, 5, "Seam fold_id should be 5")


func test_fragment_get_seams():
	var frag = CellFragment.new(PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)
	]), -1)

	var seam1 = {"fold_id": 1, "line_point": Vector2(10, 10), "line_normal": Vector2(1, 0)}
	var seam2 = {"fold_id": 2, "line_point": Vector2(20, 20), "line_normal": Vector2(0, 1)}

	frag.add_seam(seam1)
	frag.add_seam(seam2)

	var seams = frag.get_seams()
	assert_eq(seams.size(), 2, "Should return 2 seams")


func test_fragment_has_seam_from_fold():
	var frag = CellFragment.new(PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)
	]), -1)

	var seam = {"fold_id": 7, "line_point": Vector2(32, 32), "line_normal": Vector2(1, 0)}
	frag.add_seam(seam)

	assert_true(frag.has_seam_from_fold(7), "Should have seam from fold 7")
	assert_false(frag.has_seam_from_fold(99), "Should not have seam from fold 99")


## ============================================================================
## DUPLICATION
## ============================================================================

func test_fragment_duplicate():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, 5)

	var seam = {"fold_id": 3, "line_point": Vector2(32, 32), "line_normal": Vector2(1, 0)}
	frag.add_seam(seam)

	var duplicate = frag.duplicate_fragment()

	assert_not_null(duplicate, "Duplicate should be created")
	assert_eq(duplicate.geometry.size(), 4, "Duplicate should have same geometry")
	assert_eq(duplicate.fold_created, 5, "Duplicate should have same fold_created")
	assert_eq(duplicate.seam_data.size(), 1, "Duplicate should have same seam data")
	assert_almost_eq(duplicate.get_area(), frag.get_area(), 0.1, "Duplicate should have same area")


func test_fragment_duplicate_is_independent():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)
	var duplicate = frag.duplicate_fragment()

	# Modify duplicate
	duplicate.translate_geometry(Vector2(100, 100))

	# Original should be unchanged
	assert_almost_eq(frag.geometry[0].x, 0.0, 0.1, "Original should be unchanged")
	assert_almost_eq(duplicate.geometry[0].x, 100.0, 0.1, "Duplicate should be modified")


## ============================================================================
## DEBUG & UTILITIES
## ============================================================================

func test_fragment_to_string():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, 5)

	# Use str() to trigger _to_string() conversion
	var str_repr = str(frag)

	assert_string_contains(str_repr, "CellFragment", "String should contain class name")
	assert_string_contains(str_repr, "4", "String should contain vertex count")
	assert_string_contains(str_repr, "5", "String should contain fold ID")


## ============================================================================
## ERROR HANDLING
## ============================================================================

func test_fragment_add_seam_with_invalid_data():
	var frag = CellFragment.new(PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)
	]), -1)

	# Add seam without required fields - should not crash
	var invalid_seam = {"some_field": 123}
	frag.add_seam(invalid_seam)

	# Should still be in seam_data (validation happens, but we allow it for now)
	# In implementation, we can choose to reject or accept with warning
	assert_eq(frag.seam_data.size(), 0, "Invalid seam should be rejected")


## ============================================================================
## EDGE CASES
## ============================================================================

func test_fragment_with_empty_geometry():
	var empty_geometry = PackedVector2Array([])
	var frag = CellFragment.new(empty_geometry, -1)

	assert_true(frag.is_degenerate(), "Empty geometry should be degenerate")
	assert_eq(frag.get_area(), 0.0, "Empty geometry should have zero area")
	assert_eq(frag.get_centroid(), Vector2.ZERO, "Empty geometry centroid should be zero")


func test_fragment_with_large_coordinates():
	# Test with large coordinate values
	var geometry = PackedVector2Array([
		Vector2(10000, 10000),
		Vector2(10064, 10000),
		Vector2(10064, 10064),
		Vector2(10000, 10064)
	])
	var frag = CellFragment.new(geometry, -1)

	assert_false(frag.is_degenerate(), "Large coordinates should work")
	assert_almost_eq(frag.get_area(), 4096.0, 1.0, "Area calculation should work with large coords")
