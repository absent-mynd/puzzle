class_name EditorHistory extends RefCounted

## EditorHistory
##
## Undo/redo for the level editor, modeled on the gameplay HistoryManager but operating
## on LevelData snapshots (deep clones of cell_data + folds + metadata). The editor had
## no undo at all; painting a wrong tile meant repainting by hand. Pure and testable:
## the editor just calls set_baseline() once, push() after each edit, and undo()/redo()
## to get a LevelData to restore.

var _undo_stack: Array = []   # LevelData snapshots, oldest at the bottom
var _redo_stack: Array = []
var _current: LevelData = null


## Seed the history with the starting state (clears any prior history).
func set_baseline(level: LevelData) -> void:
	_current = level.clone()
	_undo_stack.clear()
	_redo_stack.clear()


## Record a committed edit. Call AFTER mutating `level`. Pushes the previous state onto
## the undo stack and truncates the redo branch (a new edit invalidates redo).
func push(level: LevelData) -> void:
	if _current != null:
		_undo_stack.append(_current)
	_current = level.clone()
	_redo_stack.clear()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


## Step back one edit. Returns a fresh clone of the restored state, or null if nothing
## to undo. The caller applies the returned LevelData and rebuilds its view.
func undo() -> LevelData:
	if _undo_stack.is_empty():
		return null
	_redo_stack.append(_current)
	_current = _undo_stack.pop_back()
	return _current.clone()


## Step forward one previously-undone edit. Returns a fresh clone, or null.
func redo() -> LevelData:
	if _redo_stack.is_empty():
		return null
	_undo_stack.append(_current)
	_current = _redo_stack.pop_back()
	return _current.clone()
