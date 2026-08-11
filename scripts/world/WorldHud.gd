class_name WorldHud extends Node

## The window-resolution overlay: the ground the pixel viewport is composited onto,
## the controls line, the status readout, and the centre flash.
##
## This is presentation only — what a label looks like, where it sits, how long a
## message stays up. It does NOT know what a fold is, how many hands you are
## holding, or what region you are in. `FoldWorld` decides what to say, because
## that is a statement about game state; this decides how it appears.
##
## The interface is deliberately four setters and a tick, all taking plain values.
## That is the point of the split, and `WorldOverlay` is what it looks like when the
## split is not made: it held an untyped back-reference to `FoldWorld` and reached
## into two dozen of its members, having given up its type annotation to avoid the
## load-order cycle that creates. Two of those reaches turned out to be allocating
## queries sitting on a path that runs once per copy of the space, which cost most of
## a frame on a torus. It now takes an `OverlayView` like this takes strings. A view
## that receives what it needs cannot form the cycle, and cannot quietly acquire a
## cost inside a draw call.
##
## The HUD lives OUTSIDE the pixel viewport, at window resolution, so text stays
## legible rather than being scaled up as art pixels. See PixelArt.

## How long a flash message stays on screen, in seconds.
const FLASH_TIME := 2.5

## The ground behind the world, and what it becomes at depth. Deeper reads darker
## and more lavender; the sheet's own tint follows in the light rig.
const BG_BASE := Color("0a0b12")
const BG_DEEP := Color("140a2a")

## How fast the ground reaches BG_DEEP as you nest. At 0.7 per level you are most
## of the way there by the second fold, which is where "deep" stops being news.
const DEPTH_TINT_RATE := 0.7

const HELP_TEXT := \
	"A/D move   Space tap/hold: jump   W/S aim   F tap: place hand · hold: pull back   R reset"

var _bg: ColorRect
var _status: Label
var _flash: Label
var _flash_left := 0.0


func _ready() -> void:
	if _bg == null:
		build()


## Create the layers. Called from `_ready`, or directly by a caller that wants the
## HUD usable before the frame it is added on.
func build() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	_bg = ColorRect.new()
	_bg.color = BG_BASE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Controls default to MOUSE_FILTER_STOP; a full-screen rect would eat every
	# click before _unhandled_input sees it. HUD must never take the mouse.
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(_bg)

	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	# Controls only — what the keys are, not what they mean. The mechanics are the
	# game's to teach: the aim ring, the preview strip, the seam diamonds and the
	# anchor readout all say their piece in place, and a wall of text on top of
	# them explains away the thing the player is meant to work out.
	var help := Label.new()
	help.text = HELP_TEXT
	help.position = Vector2(12, 8)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hud.add_child(help)

	_status = Label.new()
	_status.position = Vector2(12, 30)
	_status.add_theme_color_override("font_color", Color("59e0d0"))
	hud.add_child(_status)

	_flash = Label.new()
	_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash.position = Vector2(340, 130)
	_flash.add_theme_font_size_override("font_size", 22)
	_flash.add_theme_color_override("font_color", Color("ffd27f"))
	_flash.visible = false
	hud.add_child(_flash)


## The persistent readout, already composed by whoever knows what it means.
func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


## How deep in folds the player is, which is all this needs to know to tint the
## ground behind the world.
func set_depth(depth: int) -> void:
	if _bg != null:
		_bg.color = BG_BASE.lerp(BG_DEEP, minf(float(depth) * DEPTH_TINT_RATE, 1.0))


## Put a message up for `FLASH_TIME`. An empty message is ignored rather than
## clearing the one already showing — a caller with nothing to say should not
## silence a caller that had something.
func flash(text: String) -> void:
	if text.is_empty() or _flash == null:
		return
	_flash.text = text
	_flash.visible = true
	_flash_left = FLASH_TIME


## Seconds left on the current flash; 0 when nothing is showing.
func flash_left() -> float:
	return _flash_left


## The message currently up, or "" if none. Exists so a test can assert what the
## player was told without reaching through to the Label — the whole reason this
## class has an interface rather than public nodes.
func flash_text() -> String:
	if _flash == null or not _flash.visible:
		return ""
	return _flash.text


## Age the flash. Driven by the world's frame rather than a Timer so it steps in
## lockstep with everything else the tests advance by hand.
func tick(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left == 0.0 and _flash != null:
		_flash.visible = false
