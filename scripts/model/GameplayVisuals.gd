class_name GameplayVisuals extends RefCounted

## GameplayVisuals
##
## One home for the gameplay layer's Z-ORDER and semantic overlay colors. These were
## scattered across GridManager, Cell, Player, and FoldController as bare literals /
## per-file consts that HAD to stay mutually consistent (e.g. the highlight dot at 3
## must sit above pieces at 0) but nothing enforced it. Centralizing lets a test assert
## the layering invariant, and lets the overlay colors read as one system.

## Z-order (higher draws on top). The invariant the four files depended on:
## preview line > preview fill > highlight/crease > occupant/seam > facing/anim > piece.
const Z_PIECE := 0        # cell fill / geometry pieces
const Z_FACING := 1       # player facing indicator + fold-animation overlay
const Z_OCCUPANT := 2     # boxes, split-off bodies, legacy seams
const Z_HIGHLIGHT := 3    # anchor / hover dots + crease-dot unfold handles
const Z_PREVIEW_FILL := 10 # fold-region preview shading (drawn over the map)
const Z_PREVIEW_LINE := 11 # fold preview / cut lines (topmost)

## Semantic overlay colors.
const ANCHOR_FIRST := Color.RED    # first-placed fold anchor
const ANCHOR_SECOND := Color.BLUE  # second-placed fold anchor
const PREVIEW_VALID := Color.GREEN # valid fold preview line/border
const PREVIEW_INVALID := Color.RED # invalid fold preview line/border
const PLAYER_BLOCKED := Color.RED  # player flash when they block a fold
