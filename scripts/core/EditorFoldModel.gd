class_name EditorFoldModel extends RefCounted

## EditorFoldModel
##
## Pure helpers for authoring the pre-placed fold list stored in LevelData.folds. Each
## entry is {"anchor1": {"x","y"}, "anchor2": {"x","y"}} — the exact shape LevelData.folds
## / LevelData.fold_pairs() already read and that save/load round-trips deep-copy. Keeping
## this logic pure makes fold authoring unit-testable without the editor scene.


## Build a fold entry from two grid anchors.
static func make(a: Vector2i, b: Vector2i) -> Dictionary:
	return {"anchor1": {"x": a.x, "y": a.y}, "anchor2": {"x": b.x, "y": b.y}}


## Append a fold between two anchors to `folds` (mutates and returns it).
static func add(folds: Array, a: Vector2i, b: Vector2i) -> Array:
	folds.append(make(a, b))
	return folds


## Remove the fold at index `i` (no-op if out of range). Mutates and returns `folds`.
static func remove_at(folds: Array, i: int) -> Array:
	if i >= 0 and i < folds.size():
		folds.remove_at(i)
	return folds


## The two anchors of a fold entry as Vector2i (ZERO for missing coords).
static func anchors_of(fold: Dictionary) -> Array:
	var a = fold.get("anchor1", {})
	var b = fold.get("anchor2", {})
	return [
		Vector2i(int(a.get("x", 0)), int(a.get("y", 0))),
		Vector2i(int(b.get("x", 0)), int(b.get("y", 0))),
	]


## Human-readable label for a fold, e.g. "A(3,1) <-> B(7,1)".
static func describe(fold: Dictionary) -> String:
	var pair := anchors_of(fold)
	var a: Vector2i = pair[0]
	var b: Vector2i = pair[1]
	return "A(%d,%d) ↔ B(%d,%d)" % [a.x, a.y, b.x, b.y]
