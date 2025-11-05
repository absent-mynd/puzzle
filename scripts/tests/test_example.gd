extends GutTest
## Example test script demonstrating basic GUT assertions
##
## This is a simple example test that shows how to write tests
## using the GUT (Godot Unit Test) framework.


func before_all():
	gut.p("Running example test suite")


func before_each():
	gut.p("Setting up individual test")


func after_each():
	gut.p("Cleaning up after test")


func after_all():
	gut.p("Example test suite complete")


## Test basic equality assertion
func test_assert_eq_passes():
	assert_eq(5, 5, "5 should equal 5")
	assert_eq("hello", "hello", "Strings should match")


## Test inequality assertion
func test_assert_ne_passes():
	assert_ne(1, 2, "1 should not equal 2")
	assert_ne("foo", "bar", "Different strings should not match")


## Test greater than assertion
func test_assert_gt_passes():
	assert_gt(10, 5, "10 should be greater than 5")


## Test less than assertion
func test_assert_lt_passes():
	assert_lt(3, 7, "3 should be less than 7")


## Test boolean assertions
func test_assert_true_passes():
	assert_true(true, "true should be true")
	assert_true(1 == 1, "1 equals 1 is true")


func test_assert_false_passes():
	assert_false(false, "false should be false")
	assert_false(1 == 2, "1 equals 2 is false")


## Test null assertions
func test_assert_null_passes():
	var my_var = null
	assert_null(my_var, "Variable should be null")


func test_assert_not_null_passes():
	var my_var = "not null"
	assert_not_null(my_var, "Variable should not be null")


## Test Vector2 assertion with epsilon
func test_assert_almost_eq_passes():
	var vec1 = Vector2(1.0, 2.0)
	var vec2 = Vector2(1.0001, 2.0001)
	assert_almost_eq(vec1.x, vec2.x, 0.001, "Vectors should be almost equal")


## Example of a test that would fail (commented out to keep tests passing)
#func test_this_would_fail():
#	assert_eq(1, 2, "This will fail: 1 does not equal 2")
