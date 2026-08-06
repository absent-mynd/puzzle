class_name HandOrbit extends WrapCanvas

## HandOrbit
##
## The hands you are carrying, drawn as small circles floating beside the body.
##
## Purely presentational. They spring toward an offset near the player and trail
## behind its motion, so they swing when you turn, string out when you run and settle
## when you stop — but nothing reads their positions back. A hand's *position* here
## has no meaning; only the fact that you are holding it does, and that lives in
## `FoldWorld.hands`.
##
## Kept out of `WorldOverlay` because that node is strictly draw-from-current-state,
## redrawn from scratch each frame. These have state of their own — a position and a
## velocity that persist between frames — and mixing the two would make the overlay
## something you have to update rather than something you can just read.
##
## It is a `WrapCanvas`, which is the whole of what it knows about folds: it paints
## the hands beside the body and they turn up in every copy of a strip, because the
## body does. Before that base class existed this node was the standing example of
## the problem — a new object added to the world that quietly appeared in one band
## and nowhere else, while the terrain, the body and the markers each carried their
## own copy of the repeat loop.
##
## The integration itself is `WorldCore.spring_step` / `WorldCore.hand_orbit_offset`,
## so the motion is pure and testable and this file is only the drawing.

## How far from the body's centre a hand orbits.
const ORBIT_RADIUS := 34.0
## Spring constants, tuned for "carried, slightly reluctant" rather than "rigid".
const STIFFNESS := 120.0
const DAMPING := 11.0
## Drawn size. Smaller than the player blob: these are held things, not a second body.
const HAND_RADIUS := 5.0

## One entry per slot: {"pos": Vector2, "vel": Vector2, "type": int, "held": bool}.
## Slots persist while empty so a hand put down and picked back up resumes from where
## its predecessor drifted to, instead of snapping in from the origin.
var _slots: Array = []


## Bring the orbit in line with `hands` (a slot array of HandTypes ids / nulls) and
## step the springs. `motion` is the body's velocity; `facing` its heading.
func follow(hands: Array, body: Vector2, motion: Vector2, facing: int, delta: float) -> void:
	while _slots.size() < hands.size():
		_slots.append({"pos": body, "vel": Vector2.ZERO, "type": HandTypes.PLAIN, "held": false})
	_slots.resize(hands.size())

	var held := 0
	for h in hands:
		if h != null:
			held += 1

	var seen := 0
	for i in range(hands.size()):
		var slot: Dictionary = _slots[i]
		var had: bool = slot["held"]
		slot["held"] = hands[i] != null
		if not slot["held"]:
			continue
		slot["type"] = int(hands[i])
		# A hand that has just arrived starts AT the body and springs outward, so a
		# pickup reads as something flying to your hand rather than fading in.
		if not had:
			slot["pos"] = body
			slot["vel"] = Vector2.ZERO
		var target: Vector2 = body + WorldCore.hand_orbit_offset(
			seen, maxi(held, 1), facing, motion, ORBIT_RADIUS)
		var step := WorldCore.spring_step(
			slot["pos"], slot["vel"], target, STIFFNESS, DAMPING, delta)
		slot["pos"] = step["pos"]
		slot["vel"] = step["vel"]
		seen += 1
	queue_redraw()


func paint() -> void:
	for slot in _slots:
		if slot["held"]:
			draw_hand(self, slot["pos"], int(slot["type"]))


## How a hand looks, wherever it is. STATIC and shared on purpose: a hand carried
## beside you, a cache the world shipped and a hand that popped out of a burst are the
## same object to the player, so they must not be drawn by two different pieces of
## code that could drift apart. `WorldOverlay` draws loose ones through here.
static func draw_hand(on: CanvasItem, at: Vector2, kind: int, scale: float = 1.0) -> void:
	var c: Color = HandTypes.color(kind)
	var r: float = HAND_RADIUS * scale
	# A darker rim so a hand stays legible against ground of its own colour.
	on.draw_circle(at, r + 1.5, Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, 0.85))
	on.draw_circle(at, r, c)
