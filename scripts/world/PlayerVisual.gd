class_name PlayerVisual extends WrapCanvas

## PlayerVisual
##
## The player, drawn wherever the space says the body is.
##
## Outside a fold that is one place. Inside one, the strip is a cylinder and you
## are one point on it, so you are in every copy at once — and inside a fold
## inside a perpendicular fold it is a torus, so you are in every copy both ways.
## None of which this file knows: it paints the body once, and `WrapCanvas`
## repeats it wherever the lattice says there is another copy of here.
##
## That replaces a hand-managed list of ghost `Polygon2D`s that had to be created
## on every rebuild, positioned every frame, and kept off the copy the real body
## was in. The body is not special; it is just another thing standing in a space
## that repeats.
##
## ## The face
##
## Two dark pixels. They sit toward the side you face and lift or drop with the key
## that aims a hand, so the face says what the body is about to do; and they blink,
## which is the whole difference between a disc and somebody.
##
## The blink is a function of `WorldClock`, like everything else in the world that
## moves without being pushed: a held world holds the face.

var player: PlayerBody


func _process(_delta: float) -> void:
	queue_redraw()


func paint() -> void:
	if player == null:
		return
	var at := player.global_position
	var squash := player.visual_squash()
	var col := player.visual_color()
	var pts := PackedVector2Array()
	for v in player.visual_outline():
		pts.append(at + Vector2(v) * squash)
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)
	# The face rides the body's squash, then lands on whole art pixels: half a pixel
	# of eye is a pixel that is there on some frames and not on others.
	var ink := col.darkened(EYE_DARKEN)
	for r in eyes(player.facing, player.look_dir(), blinking(WorldClock.now())):
		var rect: Rect2 = r
		var corner := PixelArt.snap_round(at + rect.position * squash)
		draw_rect(Rect2(corner, rect.size), ink)


# ---------------------------------------------------------------------------
# The face
# ---------------------------------------------------------------------------

## How far toward black the eyes are from the body. A darker shade of whatever the
## body is, so they survive the charge turning it teal.
const EYE_DARKEN := 0.74

## Seconds between blinks, and how long one lasts.
const BLINK_EVERY := 3.4
const BLINK_FOR := 0.12


## The two eyes, as rects in body-local space on the art-pixel grid.
##
## `facing` is -1 or +1, `look` is `PlayerBody.look_dir()` (-1 up, +1 down, 0 level).
## Facing left is the mirror of facing right. A blink closes the lid DOWN: the shut
## eye is the bottom row of the open one, so the face does not hop when it blinks.
static func eyes(facing: int, look: float, blink: bool) -> Array:
	var px := PixelArt.WORLD_PER_PIXEL
	var top := (-2.0 + signf(look)) * px
	var height := 2.0 * px
	if blink:
		top += height - px
		height = px
	var out: Array = []
	for column in [0.0, 2.0]:
		var x: float = column * px
		if facing < 0:
			x = -x - px
		out.append(Rect2(Vector2(x, top), Vector2(px, height)))
	return out


## Whether the eyes are shut at world time `now`. Every `BLINK_EVERY` seconds, with
## every third one doubled — a metronome reads as a machine.
static func blinking(now: float) -> bool:
	var phase := fposmod(now, BLINK_EVERY)
	if phase < BLINK_FOR:
		return true
	var third := int(floor(now / BLINK_EVERY)) % 3 == 0
	return third and phase > BLINK_FOR * 2.2 and phase < BLINK_FOR * 3.2
