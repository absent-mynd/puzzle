## Snapshot History System (Phase 6 Task 9 - Redesigned Undo)
##
## Unified snapshot-based undo system. Stores complete game state snapshots
## after each action (fold, move, unfold, etc.). Undo simply restores the
## previous snapshot, making the system extensible for future action types.
##
## This approach is cleaner than action-specific undo logic because adding
## new action types requires no changes to the undo system.

class_name SnapshotHistory
extends RefCounted

## Maximum number of snapshots to store (prevents memory issues)
const MAX_SNAPSHOTS: int = 100

## Stack of game state snapshots (LIFO - Last In First Out)
var snapshots: Array[Dictionary] = []


## Push a complete game state snapshot onto the stack
##
## @param snapshot: Dictionary containing complete game state
##   Required keys:
##   - "grid_state": Dictionary - Serialized grid cells (from FoldSystem.serialize_grid_state())
##   - "player_position": Vector2i - Player's current grid position
##   - "fold_count": int - Current number of folds
##   - "fold_history": Array[Dictionary] - Complete fold history at this point
##   - "timestamp": int - When snapshot was taken (OS.get_ticks_msec())
##
##   Optional keys (for UI/logging):
##   - "action_type": String - "fold", "move", or "unfold"
##   - "action_summary": String - Human-readable description of action
func push_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("grid_state"):
		push_error("SnapshotHistory: Snapshot must have 'grid_state' key")
		return
	if not snapshot.has("player_position"):
		push_error("SnapshotHistory: Snapshot must have 'player_position' key")
		return
	if not snapshot.has("fold_count"):
		push_error("SnapshotHistory: Snapshot must have 'fold_count' key")
		return
	if not snapshot.has("fold_history"):
		push_error("SnapshotHistory: Snapshot must have 'fold_history' key")
		return

	# Add snapshot to stack
	snapshots.append(snapshot.duplicate())

	# Enforce max snapshots limit (remove oldest)
	if snapshots.size() > MAX_SNAPSHOTS:
		snapshots.remove_at(0)


## Pop the most recent snapshot from the stack
##
## @return: Dictionary containing the game state snapshot, or empty dict if no snapshots
func pop_snapshot() -> Dictionary:
	if snapshots.is_empty():
		return {}

	return snapshots.pop_back()


## Check if there are snapshots available to undo
##
## @return: true if snapshots can be undone
func can_undo() -> bool:
	return not snapshots.is_empty()


## Get the most recent snapshot without removing it
##
## @return: Dictionary containing the snapshot, or empty dict if no snapshots
func peek_snapshot() -> Dictionary:
	if snapshots.is_empty():
		return {}

	return snapshots[snapshots.size() - 1]


## Clear all snapshots from history
func clear() -> void:
	snapshots.clear()


## Get the total number of snapshots in history
##
## @return: Number of snapshots stored
func get_snapshot_count() -> int:
	return snapshots.size()
