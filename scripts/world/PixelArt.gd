class_name PixelArt extends RefCounted

## PixelArt
##
## The one place that says how big an art pixel is.
##
## World coordinates are NOT changed by the pixel-art pass — a cell is still
## `WorldCore.CELL` (64) world units and every physics constant stays put. What
## changes is the RESOLUTION the world is drawn at: the whole scene renders into
## a small SubViewport and is scaled up with nearest-neighbour filtering, so one
## art pixel covers `WORLD_PER_PIXEL` world units.
##
##     CELL (64 world units)  /  WORLD_PER_PIXEL (4)  =  TILE_PX (16 art px)
##
## 16px tiles drawn into a low-resolution target and upscaled with nearest
## filtering into the window. `VIEW_PX` (320x180) is the 1:1 shape.
##
## **The camera's zoom never moves.** Inside a render target, the size of an art
## pixel is purely a function of zoom — so if the lens moved, a 16px tile would
## stop covering 16 target pixels, the atlas would be resampled, and the world
## would go soft. That is the one thing this pass exists to prevent.
##
## But the camera IS dynamic: the frame opens with the moment (see
## `WorldCore.camera_zoom_for`). Both facts hold at once because "show more world"
## is answered with more PIXELS, not a wider lens — `target_size` resizes the
## render target so that world-per-target-pixel stays `WORLD_PER_PIXEL` at every
## zoom. The tile is never resampled; there is simply more of the world in the
## buffer, and the upscale to the window absorbs the difference.
##
## The HUD is deliberately outside this: it lives on a normal CanvasLayer at
## window resolution, so text stays legible while the world stays chunky.
##
## Window scaling is left FRACTIONAL on purpose. Forcing integer stretch on the
## CANVAS would mean a 1080p window playing in a 1280x720 box with black bars
## around it. With a resizing target the upscale factor is fractional at most
## zooms anyway — the crispness that matters is the tile landing 1:1 in the
## buffer, which `target_size` guarantees; the final blit is a clean nearest
## magnification of an already-correct image.

## World units covered by one art pixel.
const WORLD_PER_PIXEL := 4.0

## Art pixels across one cell. Derived, but stated as a constant because it is
## the number a tileset is authored against (see `TileAtlas`).
const TILE_PX := 16

## Size of the low-resolution render target at the RESTING zoom, in art pixels.
## The target grows past this as the camera opens — see `target_size`.
const VIEW_PX := Vector2i(320, 180)

## Ceiling on the render target. `target_size` is called every frame, so the
## growth has to be bounded: a cap is what makes it safe. Generous enough for the
## widest zoom on a 4K window.
const MAX_VIEW_PX := Vector2i(1280, 720)

## The camera's FIXED zoom. This is the single fact that keeps the art crisp: at
## this zoom one target pixel covers exactly WORLD_PER_PIXEL world units, so the
## 16px tileset lands 1:1 and a cell spans TILE_PX pixels. It never changes — see
## `target_size` for why.
const CAMERA_ZOOM := Vector2(1.0 / WORLD_PER_PIXEL, 1.0 / WORLD_PER_PIXEL)


## World extent a VIEW_PX target covers, in world units — the 1:1 frame the
## tileset was authored against. The live target is `target_size` of the current
## zoom, which is larger whenever the frame has opened past 1:1.
static func view_world_size() -> Vector2:
	return Vector2(VIEW_PX) * WORLD_PER_PIXEL


## How big the render target must be for a logical `zoom` to show the right amount
## of world at the right resolution.
##
## The camera's lens is fixed (`CAMERA_ZOOM`), because inside a render target the
## size of an art pixel is purely a function of zoom: move the lens and a 16px
## tile stops covering 16 target pixels, the atlas gets resampled, and the world
## goes soft — which is the one thing the pixel pass exists to prevent.
##
## So "show more world" is answered with more PIXELS instead. The target is sized
## so that world-per-target-pixel stays WORLD_PER_PIXEL at any zoom; the upscale
## to the window absorbs the difference. At the resting zoom this returns exactly
## `VIEW_PX`, the shape the tileset was authored against.
static func target_size(window: Vector2, zoom: float) -> Vector2i:
	var world_seen := window / maxf(zoom, 0.01)
	var px := (world_seen / WORLD_PER_PIXEL).round()
	return Vector2i(
		clampi(int(px.x), 1, MAX_VIEW_PX.x),
		clampi(int(px.y), 1, MAX_VIEW_PX.y))


## Snap a world point DOWN to the art-pixel grid (the top-left of the art pixel
## containing it). Used for anything that must not shimmer between pixels.
static func snap(p: Vector2) -> Vector2:
	return (p / WORLD_PER_PIXEL).floor() * WORLD_PER_PIXEL


## Snap a world point to the NEAREST art pixel. Used for the camera, where
## rounding keeps the view centred rather than biased up-left.
static func snap_round(p: Vector2) -> Vector2:
	return (p / WORLD_PER_PIXEL).round() * WORLD_PER_PIXEL


## Art-pixel coordinates of a world point.
static func art_pixel(p: Vector2) -> Vector2i:
	return Vector2i((p / WORLD_PER_PIXEL).floor())


## Art pixels per world unit — the scale factor from world geometry to texture
## space (see `TileAtlas.uv_for`).
static func px_per_world(cell_size: float) -> float:
	return float(TILE_PX) / cell_size


## A one-pixel line from `a` to `b`, as the RUNS of art pixels it covers — pairs of
## endpoints, the shape `draw_multiline` takes.
##
## A drawn line is not a pixel-art line. `draw_line` at one art pixel of width is a
## quad four world units across, and at an angle that quad covers a fraction of each
## pixel it crosses: the line comes out dim, thinned and broken, while every other
## edge in the frame is a hard step. Axis-aligned the quad lands exactly on the grid,
## which is why nothing showed it until a fold ran diagonally.
##
## So the line is stepped in pixels here and each one is painted once. Painted ONCE
## matters as much as painted at all: these lines are translucent, and a pixel covered
## by two runs would blend twice and sit brighter than the rest of the same line.
##
## Runs rather than pixels because a line that is mostly flat is mostly long spans —
## an axis-aligned line comes back as ONE run, which is the whole of the common case.
## A 45° diagonal is the worst case at one run per pixel; it is still a single draw
## call, and it is the only shape of line this costs anything for.
##
## Endpoints are the OUTER EDGES of the first and last pixel of a run, not their
## centres, so a run of one pixel is still a segment with a length — a zero-length
## segment draws nothing at all.
static func hairline_runs(a: Vector2, b: Vector2) -> PackedVector2Array:
	var p0 := art_pixel(a)
	var p1 := art_pixel(b)
	var span := p1 - p0
	var flat := absi(span.x) >= absi(span.y)
	# One axis is walked a pixel at a time; the other is whatever the line is doing
	# there. Swapping them is what keeps this one piece of code rather than two.
	var major := absi(span.x) if flat else absi(span.y)
	var minor := absi(span.y) if flat else absi(span.x)
	var step_major := signi(span.x) if flat else signi(span.y)
	var step_minor := signi(span.y) if flat else signi(span.x)
	var from_major := p0.x if flat else p0.y
	var from_minor := p0.y if flat else p0.x

	var out := PackedVector2Array()
	var run_start := from_major
	var run_minor := from_minor
	for i in range(major + 1):
		var at_major := from_major + i * step_major
		var at_minor := from_minor + (0 if major == 0 else roundi(
			float(i) * float(minor) / float(major)) * step_minor)
		if at_minor != run_minor:
			out.append_array(_run(run_start, at_major - step_major, run_minor, flat))
			run_start = at_major
			run_minor = at_minor
	out.append_array(_run(run_start, from_major + major * step_major, run_minor, flat))
	return out


## One run, as its two endpoints in world space: across the full width of the pixels it
## covers on the major axis, down the middle of its single pixel on the minor one.
static func _run(from_major: int, to_major: int, minor: int, flat: bool) -> PackedVector2Array:
	var lo := float(mini(from_major, to_major)) * WORLD_PER_PIXEL
	var hi := float(maxi(from_major, to_major) + 1) * WORLD_PER_PIXEL
	var mid := (float(minor) + 0.5) * WORLD_PER_PIXEL
	if flat:
		return PackedVector2Array([Vector2(lo, mid), Vector2(hi, mid)])
	return PackedVector2Array([Vector2(mid, lo), Vector2(mid, hi)])
