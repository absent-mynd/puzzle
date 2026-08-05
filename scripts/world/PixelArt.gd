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
## 16px tiles at a 320x180 render target upscaled 4x into the 1280x720 window.
## Keeping the render target's world extent equal to the window's world extent
## (via `CAMERA_ZOOM`) means the pixel pass changes the LOOK and nothing else:
## the same amount of world is on screen as before.
##
## The HUD is deliberately outside this: it lives on a normal CanvasLayer at
## window resolution, so text stays legible while the world stays chunky.
##
## Window scaling is left FRACTIONAL on purpose. The render target is already an
## exact quarter of the 1280x720 canvas, so an art pixel is 4 canvas units and
## any window that is a whole multiple of 320 wide lands on a whole number of
## screen pixels per art pixel — 1920 gives 6x, 2560 gives 8x. Forcing integer
## stretch on the CANVAS would do the opposite: 1920/1280 rounds down to 1x and
## a 1080p window would play in a 1280x720 box with black bars around it.

## World units covered by one art pixel.
const WORLD_PER_PIXEL := 4.0

## Art pixels across one cell. Derived, but stated as a constant because it is
## the number a tileset is authored against (see `TileAtlas`).
const TILE_PX := 16

## Size of the low-resolution render target, in art pixels.
const VIEW_PX := Vector2i(320, 180)

## Camera zoom that makes VIEW_PX show the same world extent the un-pixelated
## camera did (VIEW_PX * WORLD_PER_PIXEL == 1280x720 world units).
const CAMERA_ZOOM := Vector2(1.0 / WORLD_PER_PIXEL, 1.0 / WORLD_PER_PIXEL)


## World extent visible in the render target, in world units.
static func view_world_size() -> Vector2:
	return Vector2(VIEW_PX) * WORLD_PER_PIXEL


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
