extends GutTest

## Tests for Phase 6 Task 7: Action History System

var action_history: ActionHistory


func before_each():
	action_history = ActionHistory.new()


## ============================================================================
## BASIC FUNCTIONALITY TESTS
## ============================================================================

func test_action_history_starts_empty():
	assert_eq(action_history.get_action_count(), 0, "Should start with no actions")
	assert_false(action_history.can_undo(), "Should not be able to undo initially")


func test_push_fold_action():
	var fold_action = {
		"action_type": "fold",
		"fold_id": 0
	}

	action_history.push_action(fold_action)

	assert_eq(action_history.get_action_count(), 1, "Should have 1 action")
	assert_true(action_history.can_undo(), "Should be able to undo")


func test_push_move_action():
	var move_action = {
		"action_type": "move",
		"old_position": Vector2i(3, 4),
		"new_position": Vector2i(3, 5)
	}

	action_history.push_action(move_action)

	assert_eq(action_history.get_action_count(), 1, "Should have 1 action")
	assert_true(action_history.can_undo(), "Should be able to undo")


func test_pop_action_returns_correct_action():
	var fold_action = {
		"action_type": "fold",
		"fold_id": 5
	}

	action_history.push_action(fold_action)
	var popped = action_history.pop_action()

	assert_eq(popped["action_type"], "fold", "Should return fold action")
	assert_eq(popped["fold_id"], 5, "Should return correct fold_id")
	assert_eq(action_history.get_action_count(), 0, "Should be empty after pop")


func test_pop_empty_history_returns_empty_dict():
	var result = action_history.pop_action()

	assert_true(result.is_empty(), "Should return empty dictionary")


func test_peek_action_does_not_remove():
	var fold_action = {
		"action_type": "fold",
		"fold_id": 3
	}

	action_history.push_action(fold_action)
	var peeked = action_history.peek_action()

	assert_eq(peeked["action_type"], "fold", "Should return fold action")
	assert_eq(peeked["fold_id"], 3, "Should return correct fold_id")
	assert_eq(action_history.get_action_count(), 1, "Should still have 1 action")


func test_clear_removes_all_actions():
	action_history.push_action({"action_type": "fold", "fold_id": 0})
	action_history.push_action({"action_type": "fold", "fold_id": 1})
	action_history.push_action({"action_type": "fold", "fold_id": 2})

	assert_eq(action_history.get_action_count(), 3, "Should have 3 actions")

	action_history.clear()

	assert_eq(action_history.get_action_count(), 0, "Should have no actions")
	assert_false(action_history.can_undo(), "Should not be able to undo")


## ============================================================================
## LIFO (Stack) BEHAVIOR TESTS
## ============================================================================

func test_actions_follow_lifo_order():
	# Push three actions
	action_history.push_action({"action_type": "fold", "fold_id": 0})
	action_history.push_action({"action_type": "fold", "fold_id": 1})
	action_history.push_action({"action_type": "fold", "fold_id": 2})

	# Pop should return in reverse order (LIFO)
	var popped1 = action_history.pop_action()
	assert_eq(popped1["fold_id"], 2, "Should pop most recent (fold 2)")

	var popped2 = action_history.pop_action()
	assert_eq(popped2["fold_id"], 1, "Should pop second (fold 1)")

	var popped3 = action_history.pop_action()
	assert_eq(popped3["fold_id"], 0, "Should pop first (fold 0)")


func test_mixed_actions_follow_lifo():
	# Push mixed action types
	action_history.push_action({"action_type": "fold", "fold_id": 0})
	action_history.push_action({"action_type": "move", "old_position": Vector2i(1, 1), "new_position": Vector2i(2, 2)})
	action_history.push_action({"action_type": "fold", "fold_id": 1})

	# Should pop in reverse order
	var popped1 = action_history.pop_action()
	assert_eq(popped1["action_type"], "fold", "Should be fold")
	assert_eq(popped1["fold_id"], 1, "Should be fold 1")

	var popped2 = action_history.pop_action()
	assert_eq(popped2["action_type"], "move", "Should be move")

	var popped3 = action_history.pop_action()
	assert_eq(popped3["action_type"], "fold", "Should be fold")
	assert_eq(popped3["fold_id"], 0, "Should be fold 0")


## ============================================================================
## MAX ACTIONS LIMIT TESTS
## ============================================================================

func test_max_actions_limit_enforced():
	# Push more than MAX_ACTIONS
	for i in range(ActionHistory.MAX_ACTIONS + 10):
		action_history.push_action({"action_type": "fold", "fold_id": i})

	# Should be capped at MAX_ACTIONS
	assert_eq(action_history.get_action_count(), ActionHistory.MAX_ACTIONS, "Should cap at MAX_ACTIONS")


func test_oldest_actions_removed_when_limit_exceeded():
	# Push MAX_ACTIONS + 5
	for i in range(ActionHistory.MAX_ACTIONS + 5):
		action_history.push_action({"action_type": "fold", "fold_id": i})

	# Oldest actions (0-4) should be gone, newest retained
	# Pop all and check we get the right range
	var last_action = action_history.pop_action()
	assert_eq(last_action["fold_id"], ActionHistory.MAX_ACTIONS + 4, "Should have newest action")

	# Clear and repush to test first action
	action_history.clear()
	for i in range(ActionHistory.MAX_ACTIONS + 5):
		action_history.push_action({"action_type": "fold", "fold_id": i})

	# The first action in stack should be fold_id 5 (oldest 0-4 removed)
	var all_actions = action_history.actions
	assert_eq(all_actions[0]["fold_id"], 5, "Oldest retained action should be fold_id 5")


## ============================================================================
## DATA INTEGRITY TESTS
## ============================================================================

func test_actions_are_duplicated():
	# Ensure actions are duplicated so original can't be modified
	var original_action = {
		"action_type": "fold",
		"fold_id": 42
	}

	action_history.push_action(original_action)

	# Modify original
	original_action["fold_id"] = 99

	# Popped action should have original value
	var popped = action_history.pop_action()
	assert_eq(popped["fold_id"], 42, "Action should be duplicated, not referenced")


func test_push_action_without_type_shows_error():
	# This should trigger an error but not crash
	var invalid_action = {
		"some_key": "some_value"
	}

	action_history.push_action(invalid_action)

	# Should not add invalid action
	assert_eq(action_history.get_action_count(), 0, "Should not add action without action_type")
