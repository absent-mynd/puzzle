## Test Runner for GeometryCore Tests
##
## This script runs all geometry tests and displays results
## Attach this to a Node in a scene and run the scene to execute tests

extends Node

func _ready():
	print("===========================================")
	print("Starting GeometryCore Test Suite")
	print("===========================================\n")

	# Create test instance and run all tests
	var test = TestGeometryCore.new()
	test.run_all_tests()

	print("\n===========================================")
	print("Test Suite Complete")
	print("===========================================")

	# Exit after tests complete (for automated testing)
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
