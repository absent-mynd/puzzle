class_name WorldCamera extends RefCounted

## What the camera should be SHOWING — how much (zoom) and from where (lookahead).
##
## The player owns the camera node itself (see `PlayerBody`): it supplies motion and
## the look keys, because it knows its own limits and its own input. The world
## supplies what the moment is about — the points that must stay on screen, which
## axes the space repeats on, whether a fold is mid-animation. This class is the
## part in between: it turns those facts into a lens, a lead, and a render-target
## size.
##
## The arithmetic is not here. `WorldCore.camera_lookahead_for`,
## `WorldCore.camera_zoom_for` and `PixelArt.target_size` are pure and already
## tested as such; this is the orchestration that was tangled into `FoldWorld`
## around them.
##
## It takes the world's facts as an argument rather than holding a reference back to
## `FoldWorld`. The two things it does keep — the body it drives and the render
## target it sizes — are the things it exists to act on.

## Facts the world must supply on every framing call:
##   `focus`    (PackedVector2Array) world points it would be a mistake to crop
##   `periods`  (Vector2) which axes the current space repeats on
##   `frozen`   (bool) a fold is animating; hold the lead still and widen out
##   `viewport` (Vector2) window size in pixels
var _player: PlayerBody
var _pixel_view: SubViewport


func _init(player: PlayerBody, pixel_view: SubViewport) -> void:
	_player = player
	_pixel_view = pixel_view


## `center` overrides where the BODY is taken to be — a cut needs the framing of
## where it is going, not of where the lens still is.
func frame(ctx: Dictionary, center: Vector2 = Vector2.INF) -> void:
	if _player == null:
		return
	var body: Vector2 = _player.global_position if center == Vector2.INF else center

	# The lead first: it moves the camera, and the zoom's focus distances are
	# measured from where the camera ends up. Decided in the other order, a hard
	# lead would quietly crop the very things the focus set exists to keep on screen.
	_player.lookahead_target = WorldCore.camera_lookahead_for({
		"velocity": _player.motion_fraction(),
		"look": _player.look_dir(),
		# A repeating space already shows every copy there is along the axes it
		# repeats on, so leading along one slides the view across identical bands
		# for nothing. On a torus that is both axes, and the lead is the body's
		# alone.
		"flat_axes": ctx.get("periods", Vector2.ZERO),
		"frozen": ctx.get("frozen", false),
	})

	var eye := (_player.camera_position() if center == Vector2.INF
		else body + _player.lookahead_target)
	# A fold ride reports still: the body's velocity is left over from before the
	# transition, and the transition frames itself from its own endpoints. That is a
	# framing decision about what is happening in the world, which is why it is made
	# here and not in `motion_intensity` — the body is also held still while a hand is
	# raised, and there the velocity is exactly what the frame should still be reading.
	var still: bool = ctx.get("frozen", false)
	_player.zoom_target = WorldCore.camera_zoom_for({
		"viewport": ctx.get("viewport", Vector2.ZERO),
		"center": eye,
		"motion": 0.0 if still else _player.motion_intensity(),
		# A fold rearranging the world is its own reason to step back and watch.
		"widen": 1.0 if still else 0.0,
		"focus": ctx.get("focus", PackedVector2Array()),
	})

	size_render_target(ctx.get("viewport", Vector2.ZERO))


## Cut — position, lens AND lead — to where the body now is. For hard relocations
## (spawn, doors, being turned back by the fold): the destination's framing is
## computed first, because easing into it would read as the new room inflating
## around you.
func cut(ctx: Dictionary) -> void:
	if _player == null:
		return
	frame(ctx, _player.global_position)
	_player.snap_camera()


## Give the render target the resolution the CURRENT zoom asks for. The camera's
## lens never moves — inside a render target, zoom is what sets the size of an art
## pixel, so moving it would resample the 16px tileset and soften the world. A wider
## frame is therefore MORE pixels, not bigger ones.
##
## Sized from `camera_zoom()` (the eased value) rather than the target, so the
## buffer tracks what is actually on screen while the frame is still opening.
func size_render_target(viewport: Vector2) -> void:
	if _pixel_view == null or _player == null:
		return
	var want := PixelArt.target_size(viewport, _player.camera_zoom())
	# Only on change: assigning size re-allocates the render target.
	if _pixel_view.size != want:
		_pixel_view.size = want
