class_name FoldStep extends Resource

## FoldStep
##
## One entry in the engine's authoritative step log. State = base grid + initial
## player tile + an ordered list of these steps; EVERYTHING else (folded geometry,
## player position, and — in later phases — destroyed tiles and triggered folds) is
## derived by replaying the log (see StepReplay). This is the F2 promotion of the
## source of truth from a fold-only list to a full action log, so that mutations
## like destruction become replay-reachable (and therefore undoable) by construction.
##
## Steps are pure value data (ints / Vector2i) — no Fold objects, no derived state —
## so a log can be duplicated, serialized, and replayed deterministically.

enum Kind { FOLD, UNFOLD, MOVE, PLACE_ANCHOR }

@export var kind: int = Kind.FOLD

## FOLD: the two anchors (current plane positions) and the id assigned to the fold.
@export var anchor1: Vector2i = Vector2i.ZERO
@export var anchor2: Vector2i = Vector2i.ZERO
@export var fold_id: int = -1  # FOLD assigns; UNFOLD references.

## MOVE: a DIRECTION applied to every player body (a split player has several).
## Directional rather than absolute so one step moves all bodies uniformly; replay
## is deterministic because the same prefix reproduces the same bodies.
@export var dir: Vector2i = Vector2i.ZERO

## PLACE_ANCHOR: destination plane cell for a new anchor occupant, plus its channel.
@export var to: Vector2i = Vector2i.ZERO
@export var channel: String = ""


static func fold(fold_id: int, anchor1: Vector2i, anchor2: Vector2i) -> FoldStep:
	var s := FoldStep.new()
	s.kind = Kind.FOLD
	s.fold_id = fold_id
	s.anchor1 = anchor1
	s.anchor2 = anchor2
	return s


static func unfold(fold_id: int) -> FoldStep:
	var s := FoldStep.new()
	s.kind = Kind.UNFOLD
	s.fold_id = fold_id
	return s


static func move(dir: Vector2i) -> FoldStep:
	var s := FoldStep.new()
	s.kind = Kind.MOVE
	s.dir = dir
	return s


static func place_anchor(to: Vector2i, channel: String = "") -> FoldStep:
	var s := FoldStep.new()
	s.kind = Kind.PLACE_ANCHOR
	s.to = to
	s.channel = channel
	return s


func duplicate_step() -> FoldStep:
	var s := FoldStep.new()
	s.kind = kind
	s.anchor1 = anchor1
	s.anchor2 = anchor2
	s.fold_id = fold_id
	s.dir = dir
	s.to = to
	s.channel = channel
	return s
