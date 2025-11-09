## Action History System (Phase 6 Task 7)
##
## Tracks player actions (folds and optionally moves) for sequential undo functionality.
## Implements a stack-based LIFO system for traditional undo button behavior.

class_name ActionHistory
extends RefCounted

## Maximum number of actions to store (prevents memory issues)
const MAX_ACTIONS: int = 100

## Stack of actions (LIFO - Last In First Out)
var actions: Array[Dictionary] = []


## Push a new action onto the stack
##
## @param action: Dictionary containing action data
##   Required keys:
##   - "action_type": "fold" or "move"
##   For fold actions:
##   - "fold_id": int - ID of the fold in FoldSystem.fold_history
##   For move actions:
##   - "old_position": Vector2i - Player position before move
##   - "new_position": Vector2i - Player position after move
func push_action(action: Dictionary) -> void:
	if not action.has("action_type"):
		push_error("ActionHistory: Action must have 'action_type' key")
		return

	# Add action to stack
	actions.append(action.duplicate())

	# Enforce max actions limit (remove oldest)
	if actions.size() > MAX_ACTIONS:
		actions.remove_at(0)


## Pop the most recent action from the stack
##
## @return: Dictionary containing the action, or empty dict if no actions
func pop_action() -> Dictionary:
	if actions.is_empty():
		return {}

	return actions.pop_back()


## Check if there are actions available to undo
##
## @return: true if actions can be undone
func can_undo() -> bool:
	return not actions.is_empty()


## Get the most recent action without removing it
##
## @return: Dictionary containing the action, or empty dict if no actions
func peek_action() -> Dictionary:
	if actions.is_empty():
		return {}

	return actions[actions.size() - 1]


## Clear all actions from history
func clear() -> void:
	actions.clear()


## Get the total number of actions in history
##
## @return: Number of actions stored
func get_action_count() -> int:
	return actions.size()
