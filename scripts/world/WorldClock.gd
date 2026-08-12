class_name WorldClock extends RefCounted

## What time it is for things in the world.
##
## Not the wall clock. Everything that moves without being pushed — the idle float of
## a hand, a fuse's throb, the flicker of a lamp — reads this, and `FoldWorld` advances
## it by the frame's delta only while the world is actually running. Raise a hand and
## the clock stops with everything else, so a stopped world is a genuine still frame
## rather than a paused simulation with the decorations still playing over it.
##
## Before this there were three clocks: `Time.get_ticks_msec()` read directly in
## `HandOrbit.draw_hand` and again in `WorldOverlay`, and a private `_time` accumulator
## in `LightRig`. Nothing was wrong with any of them while the world always ran. The
## moment it could stop they became three things that could disagree about whether it
## had — and did, all three carrying on through a pause that had stopped everything
## else. One clock cannot disagree with itself.
##
## It is static because its readers are: `draw_hand` is the one shared drawing routine
## for every hand in the game and has no instance to hang a clock on, and the overlay's
## pulse is a pure function of time. The tradeoff is real — this is global mutable
## state, and `AGENTS.md` is otherwise hostile to it — and it is taken deliberately,
## because the alternative is threading a float through every draw call in the world
## so that each one can be given the same number.
##
## Wall time is still the right clock for things that are NOT in the world: the input
## charge (`FoldWorld._tick_hold`) counts your finger on a key, the HUD's flash counts
## how long a message has been readable, and the screen's held-look ease is the effect
## announcing the stop. None of those stop when the world does, and none of them
## should.
static var _now := 0.0


## Seconds of world time elapsed. Zero at launch and only ever moving when the world
## does, so the difference between two readings is how much the WORLD aged.
static func now() -> float:
	return _now


## Advance by one frame. `FoldWorld` is the only caller, because the question of
## whether the world is running is its to answer.
static func advance(delta: float) -> void:
	_now += delta
