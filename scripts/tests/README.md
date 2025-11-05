# GeometryCore Test Suite

## Overview

This directory contains comprehensive unit tests for the `GeometryCore` utility class, which provides all geometric calculations needed for the space-folding puzzle mechanics.

## Test Files

- **test_geometry_core.gd** - Main test suite with all test cases
- **test_runner.gd** - Test execution script
- **test_scene.tscn** - Scene file for running tests (located in `/scenes/`)

## Running Tests

### Option 1: Using Godot Editor (Recommended)

1. Open the project in Godot 4
2. Open the scene: `scenes/test_scene.tscn`
3. Press F6 (or Run Current Scene)
4. Check the Output console for test results

### Option 2: Command Line (Headless)

```bash
# From project root directory
godot --headless --path . scenes/test_scene.tscn
```

### Option 3: Using GUT Framework (Once Issue #3 is complete)

Once the GUT (Godot Unit Test) framework is installed (Issue #3):

```bash
# Run tests using GUT
godot --headless --path . addons/gut/gut_cmdln.gd -gtest=scripts/tests/test_geometry_core.gd
```

## Test Coverage

The test suite covers all functions in `GeometryCore`:

### Core Functions
- ✅ `point_side_of_line()` - Point-line relationship tests
- ✅ `segment_line_intersection()` - Line-segment intersection tests
- ✅ `polygon_area()` - Area calculation tests
- ✅ `polygon_centroid()` - Centroid calculation tests
- ✅ `validate_polygon()` - Polygon validation tests
- ✅ `split_polygon_by_line()` - Polygon splitting tests (Sutherland-Hodgman)

### Helper Functions
- ✅ `segments_intersect()` - Segment intersection tests
- ✅ `create_rect_vertices()` - Rectangle creation tests
- ✅ `point_in_polygon()` - Point containment tests

### Special Test Scenarios
- ✅ **Area Conservation** - Verifies that splitting polygons doesn't lose/gain area
- ✅ **Edge Cases** - Tests epsilon comparisons, parallel lines, degenerate polygons
- ✅ **Multiple Split Angles** - Tests horizontal, vertical, and diagonal cuts
- ✅ **Vertex Cuts** - Tests cuts that go through polygon vertices

## Test Results

The test suite includes:
- **60+ individual test cases**
- **8 test suites** covering different function groups
- **Comprehensive edge case testing**
- **Area conservation validation**

## Expected Output

When all tests pass, you should see:

```
=== GeometryCore Test Suite ===

--- Testing point_side_of_line ---
  ✓ Point on positive side
  ✓ Point on negative side
  ✓ Point exactly on line
  [...]

=== Test Summary ===
Passed: 60
Failed: 0
Total: 60

✓ All tests passed!
```

## Troubleshooting

### Tests won't run
- Ensure you're using Godot 4 (not Godot 3)
- Check that `GeometryCore.gd` is properly loaded as a class
- Verify project.godot is in the root directory

### Assertion failures
- Check the specific test that failed in the output
- Verify EPSILON value is appropriate (0.0001)
- Ensure floating-point comparisons use tolerance

## Integration with CI/CD

These tests can be integrated into automated testing:

```bash
#!/bin/bash
# Run tests in headless mode and capture exit code
godot --headless --path . scenes/test_scene.tscn
exit $?
```

## Next Steps

After completing Issue #3 (Test Framework Setup):
- Migrate to GUT framework for better test reporting
- Add performance benchmarks
- Add visual debugging tools for polygon splitting
- Create stress tests with complex polygons

## Related Issues

- **Issue #1**: Project Structure Setup (Prerequisite) ✅
- **Issue #2**: GeometryCore Implementation (Current) 🔄
- **Issue #3**: Test Framework Setup (Next)

## Documentation

For detailed function documentation, see:
- `scripts/utils/GeometryCore.gd` - Inline documentation
- `spec_files/math_utilities_reference.md` - Mathematical reference
- `IMPLEMENTATION_PLAN.md` - Overall project architecture
