## Space-Folding Puzzle Game - InteractionConfig Resource
##
## PHASE 8: Debug-toggleable interaction-design decisions. Each axis is exposed as an
## exported enum so combinations can be explored from the Godot inspector (and saved as
## named .tres presets). See docs / plan for the gameplay rationale of each axis.
##
## The defaults here are the "shipping" combination; flip any axis to play-test alternatives.

extends Resource
class_name InteractionConfig

## Axis A - What happens when the second anchor is placed via player interaction
enum SecondAnchor {
	AUTO_FOLD,          # Placing the 2nd anchor executes the fold immediately
	PLACE_THEN_CONFIRM, # 2nd anchor is placed/shown; a further interact commits the fold
}

## Axis C - Priority of unfold vs anchor placement when interacting via facing
enum ActionPriority {
	UNFOLD_WHEN_IDLE, # Facing-interact only unfolds when no selection is in progress
	CREASE_DOT_WINS,  # A faced crease dot always unfolds, regardless of selection state
}

## Axis E - When may a fold be unfolded?
enum UnfoldBlocking {
	ALLOW_ANY,             # Unfoldable as long as its crease dot is visible (+ player-safe)
	BLOCK_ON_INTERSECTION, # A newer fold whose seam CROSSES this one blocks its unfold
}

## Axis D - Which cells are disqualified from being fold anchors (applies to both anchors)
enum NullAnchor {
	OFF,             # No restriction (freely anchor null cells for testing)
	CENTROID_IN_NULL, # Disqualified if the cell's centroid falls in a null region
	ANY_NULL_PIECE,  # Disqualified if the cell contains ANY null piece
}

@export var second_anchor: SecondAnchor = SecondAnchor.PLACE_THEN_CONFIRM
## Player movement while anchors are placed is ALWAYS allowed now (Axis B removed):
## anchors persist and ride their tile through geometry changes until commit/cancel.
## Default CREASE_DOT_WINS so the player can release (unfold) a seam mid-selection.
@export var action_priority: ActionPriority = ActionPriority.CREASE_DOT_WINS
@export var unfold_blocking: UnfoldBlocking = UnfoldBlocking.ALLOW_ANY
@export var null_anchor: NullAnchor = NullAnchor.CENTROID_IN_NULL
