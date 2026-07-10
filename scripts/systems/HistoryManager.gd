class_name HistoryManager extends RefCounted

## HistoryManager
##
## Baba-Is-You-style global undo. Each committed player input (move, fold, OR
## unfold) pushes one lightweight snapshot of the engine's mutable state. Undo
## pops the last snapshot and restores it — reversing whatever the last input was,
## uniformly. This is DISTINCT from unfold (a gameplay action); unfold itself is
## an input that gets its own snapshot, so undo can reverse an unfold too.
##
## Snapshots are cheap: a copy of the (immutable) fold list plus player state. No
## grid snapshot — the folded state is re-derived from the restored fold list.
## Future entities add their own fields to capture_state()/restore_state().

var _stack: Array[Dictionary] = []
var max_depth: int = 200


## Push the current engine state as a new undo point. Call BEFORE applying an input
## (move, fold, or unfold); undo() then restores this pre-input state.
func record(engine: FoldEngine) -> void:
	_stack.append(engine.capture_state())
	if _stack.size() > max_depth:
		_stack.remove_at(0)


func can_undo() -> bool:
	return not _stack.is_empty()


## Restore the most recent snapshot into the engine and re-derive. Returns false if
## there is nothing to undo.
func undo(engine: FoldEngine) -> bool:
	if _stack.is_empty():
		return false
	var snap: Dictionary = _stack.pop_back()
	engine.restore_state(snap)
	return true


func clear() -> void:
	_stack.clear()


func depth() -> int:
	return _stack.size()


# ---------------------------------------------------------------------------
# Generic snapshot-stack API (used by FoldController for the live game, where a
# snapshot bundles engine state + anchor selection + view bookkeeping).
# ---------------------------------------------------------------------------

## Push an arbitrary snapshot dict.
func record_snapshot(snap: Dictionary) -> void:
	_stack.append(snap)
	if _stack.size() > max_depth:
		_stack.remove_at(0)


## Pop and return the most recent snapshot, or {} if empty.
func pop_snapshot() -> Dictionary:
	if _stack.is_empty():
		return {}
	return _stack.pop_back()


## Return the most recent snapshot without removing it, or {} if empty.
func peek_snapshot() -> Dictionary:
	if _stack.is_empty():
		return {}
	return _stack[_stack.size() - 1]
