class_name OverlayView extends RefCounted

## Everything the overlay draws, for one frame.
##
## `WorldOverlay` used to hold `FoldWorld` itself — untyped, because naming it would
## have closed a load-order cycle — and reach into two dozen of its members whenever
## it felt like it. That is the coupling recorded as finding 08 of the August 2026
## review, and it was not a tidiness problem.
##
## `WrapCanvas` runs `paint()` once per copy of the space: 7 copies inside one fold,
## 77 two folds deep. Because the overlay could ask the world anything at any point,
## two allocating queries drifted into that per-copy path — `glue_lines()`, which
## scans every base piece per period, and `loose_hand_points()`, which resolves every
## hand against every fragment. Measured on a torus they cost **16.3 ms of a 16.6 ms
## frame**. Nothing about the drawing was wrong; only where the question was asked.
## With no boundary between the two objects, there was no wrong side to be on.
##
## So this is the boundary. It is a plain value: points, colours' worth of state,
## flags. No behaviour, no back-reference, nothing to ask. `FoldWorld` fills one in
## per frame and hands it over; the overlay draws it and can do nothing else.
##
## The rule that keeps it honest: **if the overlay needs a new fact, it goes here.**
## Adding a field is a decision made once, in the light, in a file whose whole
## purpose is to list what a frame contains. Adding a reach-through was a decision
## made silently, inside a draw call, at whatever cost the query happened to have.

# --- The frame as a whole ---

## False while a fold is animating: the overlay draws nothing at all, because the
## markers describe a configuration that is mid-flight.
var active := false

## The space does not repeat. Suppresses the glue lines and the exit anchor, which
## only mean anything inside a fold.
var flat := true

var cell_size := 64.0
## The region's full extent in pixels — how far the alignment guides run.
var world_px := Vector2.ZERO
## One copy of a repeating space, for clipping the preview and guides. Fewer than
## three points means the space does not repeat and nothing is clipped.
var domain := PackedVector2Array()

# --- Markers ---

## Seam cell -> whether anything there can actually come out. One entry per meeting
## CELL rather than per fold: folds can share a cell, and a buried fold's refusal
## must not paint over a free fold's invitation.
var markers: Dictionary = {}

## Seams a burst from where you stand would reach: `{"at": Vector2, "ok": bool}`.
var in_reach: Array = []

## Door points that strictly resolve in this view. A door split down the middle by a
## cut is dormant and appears nowhere.
var doors: Array = []

## Hands you have put down: `{"at": Vector2 or null, "kind": int, "fuse": float}`.
## `at` is null for a hand pinned somewhere this frame cannot show. `fuse` is that
## pair's progress 0..1, or negative for a hand that is not part of an armed pair —
## the overlay turns it into a throb.
var hands_down: Array = []

## Armed pairs, as the two points a preview band spans: `{"a": Vector2, "b": Vector2}`.
## Only pairs with both halves in this frame; half a pair has no band to draw.
var pairs: Array = []

## Hands lying in the world, and hands still in the air. Same shape and the same
## glyph, because they are the same object — one of them is just still moving.
var loose: Array = []
var balls: Array = []

## The identified crease lines of a repeating space.
var glue: Array = []

# --- The way out of a fold ---

## Where the outer fold's anchors coincide on the glue, or null at region level.
var exit_at = null
## False when an inner fold crosses the seam and is holding the subspace shut.
var exit_ok := true
## A burst from where you stand would reach the exit.
var exit_in_burst := false

# --- The one-key verb ---

## Where a tap would put a hand.
var aim_at := Vector2.ZERO
## Which kind it would be, or -1 when you have none to place.
var aim_hand := -1
## How far through a hold the key is, 0 when not held.
var hold := 0.0

# --- The release burst ---

## Time left on the burst ring, 0 when none is showing.
var burst_t := 0.0
var burst_at := Vector2.ZERO
var burst_radius := 0.0
