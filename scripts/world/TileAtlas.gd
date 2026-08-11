class_name TileAtlas extends RefCounted

## TileAtlas
##
## The tileset. One texture, laid out as a grid of `TILE_PX` (16) art-pixel
## tiles: one ROW per tile KIND, one COLUMN per VARIANT.
##
##     column = variant (0..VARIANTS-1)   row = kind (K_*)
##
## Two things it has to do, and one it deliberately does not:
##
##   - **Map a piece to texture space.** Folds cut tiles into arbitrary
##     polygons, so tiles cannot be blitted on a grid. `uv_for` uses the fold
##     kernel's invariant (`polygon == base_polygon + src_offset`) to send every
##     vertex back to its BASE cell and read the UV from there. A piece
##     therefore carries the exact patch of tile art it was cut from, and the
##     art is cut by the crease as cleanly as the geometry is — which is what
##     keeps the seam a hard line.
##   - **Pick the kind and variant from BASE facts.** Variant is hashed from
##     `base_id`, and the "open sky above" edge tile is decided from the base
##     grid, so a tile's appearance never changes when it is folded, ridden or
##     cut. Material is a property of the sheet; folding moves it, it does not
##     re-carve it.
##
## What it does not do is autotiling against the FOLDED neighbourhood. A 47-tile
## blob set assumes a piece has neighbours; after a diagonal fold it may have
## a hypotenuse instead. Base-space edge kinds are the honest version of that.
##
## The texture is generated procedurally so the tileset ships as readable code
## rather than a binary blob, and so headless tests never depend on the import
## pipeline. Drop a real tilesheet at `ATLAS_PATH` — same layout, same tile size
## — and it is used instead, with no code change.

const TILE_PX := PixelArt.TILE_PX
const VARIANTS := 4

## Optional hand-drawn override. Must be VARIANTS*TILE_PX wide by KINDS*TILE_PX tall.
const ATLAS_PATH := "res://assets/sprites/tiles.png"

# --- Kinds (rows) ---
const K_EMPTY := 0          ## background "paper" — the sheet itself
const K_WALL := 1
const K_WALL_TOP := 2       ## a wall with open air above it in BASE space
const K_WATER := 3
const K_GOAL := 4
const K_TRIGGER := 5
const K_PIN := 6
const K_UFLOOR := 7
const K_UWALL := 8
const K_LAMP := 9           ## the glyph drawn at a light source
const KINDS := 10

# --- Palette -----------------------------------------------------------------
# Hues carry over from the flat-colour build so the world reads the same; the
# tileset adds the shading, not a repaint.
## Tileset colours are authored PRE-lighting: everything is multiplied by the
## ambient floor before it reaches the screen (see LightRig), so the sheet is
## painted brighter than it reads. Unlit paper lands at roughly the flat build's
## #212333, and a lamp has somewhere to push it.
const PAPER := Color(0.32, 0.33, 0.38)
const PAPER_DARK := Color(0.24, 0.25, 0.30)
const PAPER_LIGHT := Color(0.42, 0.44, 0.52)

const _PALETTE := {
	K_WALL: [Color(0.55, 0.60, 0.70), Color(0.34, 0.38, 0.47), Color(0.70, 0.76, 0.86)],
	K_WALL_TOP: [Color(0.55, 0.60, 0.70), Color(0.34, 0.38, 0.47), Color(0.74, 0.81, 0.92)],
	K_WATER: [Color(0.25, 0.45, 0.75), Color(0.16, 0.31, 0.58), Color(0.45, 0.66, 0.92)],
	K_GOAL: [Color(0.91, 0.76, 0.35), Color(0.62, 0.48, 0.18), Color(1.00, 0.93, 0.66)],
	K_TRIGGER: [Color(0.85, 0.45, 0.75), Color(0.55, 0.25, 0.48), Color(0.98, 0.70, 0.90)],
	K_PIN: [Color(0.90, 0.30, 0.28), Color(0.55, 0.16, 0.16), Color(1.00, 0.56, 0.48)],
	K_UFLOOR: [Color(0.20, 0.22, 0.26), Color(0.13, 0.14, 0.18), Color(0.30, 0.33, 0.39)],
	K_UWALL: [Color(0.42, 0.44, 0.50), Color(0.26, 0.28, 0.33), Color(0.56, 0.59, 0.67)],
	K_LAMP: [Color(1.00, 0.82, 0.50), Color(0.24, 0.18, 0.12), Color(1.00, 0.97, 0.86)],
}

## type -> kind, for types that do not depend on their surroundings.
const _KIND_OF_TYPE := {
	TileTypes.EMPTY: K_EMPTY,
	TileTypes.WALL: K_WALL,
	TileTypes.WATER: K_WATER,
	TileTypes.GOAL: K_GOAL,
	TileTypes.TRIGGER_FOLD: K_TRIGGER,
	TileTypes.PIN: K_PIN,
	TileTypes.UNANCHORABLE_FLOOR: K_UFLOOR,
	TileTypes.UNANCHORABLE_WALL: K_UWALL,
}

static var _texture: Texture2D = null


# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

## The tileset texture: the override at ATLAS_PATH if present, else generated.
## Built once per run.
static func texture() -> Texture2D:
	if _texture == null:
		if ResourceLoader.exists(ATLAS_PATH):
			_texture = load(ATLAS_PATH)
		if _texture == null:
			_texture = ImageTexture.create_from_image(build_image())
	return _texture


## Drop the cached texture (tests, and hot-swapping a tilesheet).
static func clear_cache() -> void:
	_texture = null


## Which row a tile draws from. `open_above` selects the edge kind for solids
## whose BASE neighbour above is air — the one piece of context the tileset uses.
static func kind_for(type: int, open_above: bool = false) -> int:
	if open_above and type == TileTypes.WALL:
		return K_WALL_TOP
	return _KIND_OF_TYPE.get(type, K_EMPTY)


## Which column a tile draws from. Hashed from the STABLE base id, so a tile
## keeps its variant through every fold, ride and cut.
static func variant_for(base_id: int) -> int:
	return int(_hash01(base_id, 0, 991) * float(VARIANTS)) % VARIANTS


## Flat colour of a type — the pre-tileset look, kept as the fallback for any
## path that cannot texture (and as the source of truth for the palette).
static func base_color(type: int) -> Color:
	var kind: int = _KIND_OF_TYPE.get(type, K_EMPTY)
	if kind == K_EMPTY:
		return PAPER
	return _PALETTE[kind][0]


## Texture-space UVs for a piece polygon, in atlas pixels.
##
## `src_offset` is the piece's cumulative fold translation, so subtracting it
## lands the polygon back on its base tile; the base CELL is taken from the
## centroid rather than a vertex, because a piece's vertices can sit exactly
## on a cell boundary while its interior cannot.
static func uv_for(poly: PackedVector2Array, src_offset: Vector2, kind: int,
		variant: int, cell_size: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.size() < 3:
		return out
	var base_poly := PackedVector2Array()
	for v in poly:
		base_poly.append(Vector2(v) - src_offset)
	var cell := (GeometryCore.polygon_centroid(base_poly) / cell_size).floor() * cell_size
	var scale := PixelArt.px_per_world(cell_size)
	var origin := Vector2(variant % VARIANTS, kind) * float(TILE_PX)
	# Stay a hair inside the tile: a UV landing exactly on the next tile's first
	# texel would bleed a neighbouring kind in under nearest filtering.
	var hi := float(TILE_PX) - 0.01
	for v in base_poly:
		var local := (Vector2(v) - cell) * scale
		out.append(origin + Vector2(clampf(local.x, 0.0, hi), clampf(local.y, 0.0, hi)))
	return out


## UVs for a whole atlas tile, as a quad matching `quad_polygon`.
static func quad_uv(kind: int, variant: int) -> PackedVector2Array:
	var o := Vector2(variant % VARIANTS, kind) * float(TILE_PX)
	var hi := float(TILE_PX) - 0.01
	return PackedVector2Array([o, o + Vector2(hi, 0), o + Vector2(hi, hi), o + Vector2(0, hi)])


## A cell-sized quad centred on a point, for glyphs drawn from the atlas.
static func quad_polygon(center: Vector2, size: float) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([
		center + Vector2(-h, -h), center + Vector2(h, -h),
		center + Vector2(h, h), center + Vector2(-h, h),
	])


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

## Paint the whole sheet. Deterministic: same bytes every run, so a tile's look
## is reproducible and diffable through the painter functions below.
static func build_image() -> Image:
	var img := Image.create(VARIANTS * TILE_PX, KINDS * TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for kind in range(KINDS):
		for variant in range(VARIANTS):
			_paint(img, kind, variant, Vector2i(variant * TILE_PX, kind * TILE_PX))
	return img


static func _paint(img: Image, kind: int, v: int, o: Vector2i) -> void:
	match kind:
		K_EMPTY:
			_paint_paper(img, o, v)
		K_WALL:
			_paint_masonry(img, o, v, kind, false)
		K_WALL_TOP:
			_paint_masonry(img, o, v, kind, true)
		K_WATER:
			_paint_water(img, o, v)
		K_GOAL:
			_paint_goal(img, o, v)
		K_TRIGGER:
			_paint_plate(img, o, v)
		K_PIN:
			_paint_pin(img, o, v)
		K_UFLOOR:
			_paint_hatched_floor(img, o, v)
		K_UWALL:
			_paint_hatched_wall(img, o, v)
		K_LAMP:
			_paint_lamp(img, o, v)


## The sheet itself: near-black with a faint lattice, so folded-away space
## (which draws nothing) still reads as a hole rather than more of the same.
static func _paint_paper(img: Image, o: Vector2i, v: int) -> void:
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			var n := _hash01(x, y, v + 17)
			var c := PAPER
			if n > 0.95:
				c = PAPER_LIGHT
			elif n < 0.07:
				c = PAPER_DARK
			if x % 8 == 0 and y % 8 == 0:
				c = PAPER_LIGHT
			img.set_pixel(o.x + x, o.y + y, c)


## Brick courses with a lit top-left edge per brick. `capped` adds the sky-facing
## rim used when the base tile above is air.
static func _paint_masonry(img: Image, o: Vector2i, v: int, kind: int, capped: bool) -> void:
	var pal: Array = _PALETTE[kind]
	var base: Color = pal[0]
	var dark: Color = pal[1]
	var light: Color = pal[2]
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			var course := y / 4
			var bx := (x + (course % 2) * 4 + v * 2) % 8
			var n := _hash01(x, y, v + kind * 31)
			var c := base
			if n > 0.82:
				c = base.lerp(light, 0.30)
			elif n < 0.18:
				c = base.lerp(dark, 0.35)
			if y % 4 == 3 or bx == 7:
				c = dark                      # mortar
			elif y % 4 == 0 or bx == 0:
				c = c.lerp(light, 0.35)       # brick's lit edge
			img.set_pixel(o.x + x, o.y + y, c)
	if not capped:
		return
	for x in range(TILE_PX):
		img.set_pixel(o.x + x, o.y, light)
		img.set_pixel(o.x + x, o.y + 1, base.lerp(light, 0.55))
		# Dithered third row: the cap fades into the masonry instead of stopping.
		if (x + v) % 2 == 0:
			img.set_pixel(o.x + x, o.y + 2, base.lerp(light, 0.30))


static func _paint_water(img: Image, o: Vector2i, v: int) -> void:
	var pal: Array = _PALETTE[K_WATER]
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			var wobble := int(round(1.5 * sin(float(x) * 0.55 + float(v) * 1.3)))
			var stripe := (y + wobble) % 5
			var c: Color = pal[0]
			if stripe == 0:
				c = pal[2]
			elif stripe == 3:
				c = pal[1]
			if _hash01(x, y, v + 53) > 0.93:
				c = pal[2]
			c.a = 0.88
			img.set_pixel(o.x + x, o.y + y, c)


## Walkable tiles paint their motif over paper, so the cell still reads as
## floor you can stand in front of.
static func _paint_goal(img: Image, o: Vector2i, v: int) -> void:
	_paint_paper(img, o, v)
	var pal: Array = _PALETTE[K_GOAL]
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			var d := absf(float(x) - 7.5) + absf(float(y) - 7.5)
			if d > 6.0:
				continue
			var c: Color = pal[0]
			if d > 5.0:
				c = pal[1]
			elif d < 2.5:
				c = pal[2]
			if (x + y + v) % 2 == 0 and d > 4.0:
				continue          # dithered outer edge
			img.set_pixel(o.x + x, o.y + y, c)


## A pressure plate sits on the FLOOR of its cell: the player stands on the tile
## below, so the motif hugs the bottom edge.
static func _paint_plate(img: Image, o: Vector2i, v: int) -> void:
	_paint_paper(img, o, v)
	var pal: Array = _PALETTE[K_TRIGGER]
	for y in range(11, TILE_PX):
		for x in range(1, TILE_PX - 1):
			var c: Color = pal[0]
			if y == 11:
				c = pal[2]
			elif y >= TILE_PX - 2:
				c = pal[1]
			if (x == 3 or x == 12) and y == 13:
				c = pal[1]        # rivets
			img.set_pixel(o.x + x, o.y + y, c)
	if v % 2 == 1:
		img.set_pixel(o.x + 7, o.y + 13, pal[2])


static func _paint_pin(img: Image, o: Vector2i, v: int) -> void:
	var pal: Array = _PALETTE[K_PIN]
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			var c: Color = pal[0]
			if x % 4 == 0:
				c = pal[0].lerp(pal[1], 0.45)      # vertical grain
			if _hash01(x, y, v + 71) > 0.90:
				c = pal[2]
			if x == 0 or x == TILE_PX - 1 or y == 0 or y == TILE_PX - 1:
				c = pal[1]                          # hard outline: reads as fact
			img.set_pixel(o.x + x, o.y + y, c)
	for ry in [3, 8, 13]:
		for rx in [5, 10]:
			img.set_pixel(o.x + rx, o.y + ry + (v % 2), pal[2])


static func _paint_hatched_floor(img: Image, o: Vector2i, v: int) -> void:
	_paint_paper(img, o, v)
	var pal: Array = _PALETTE[K_UFLOOR]
	for y in range(10, TILE_PX):
		for x in range(TILE_PX):
			var c: Color = pal[0]
			if (x + y + v) % 4 == 0:
				c = pal[2]
			elif y == 10:
				c = pal[1]
			img.set_pixel(o.x + x, o.y + y, c)


static func _paint_hatched_wall(img: Image, o: Vector2i, v: int) -> void:
	var pal: Array = _PALETTE[K_UWALL]
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			var c: Color = pal[0]
			if (x - y + v * 2 + 64) % 4 == 0:
				c = pal[2]
			elif (x + y + v) % 4 == 0:
				c = pal[1]
			img.set_pixel(o.x + x, o.y + y, c)


## The lamp glyph, on transparent ground: drawn at a light's position so the
## source is an object in the scene, not a disembodied glow.
static func _paint_lamp(img: Image, o: Vector2i, v: int) -> void:
	var pal: Array = _PALETTE[K_LAMP]
	var glow: Color = pal[0]
	var frame: Color = pal[1]
	var core: Color = pal[2]
	for y in range(1, 4):                      # hook
		img.set_pixel(o.x + 7, o.y + y, frame)
		img.set_pixel(o.x + 8, o.y + y, frame)
	for y in range(4, 13):
		for x in range(4, 12):
			var edge := x == 4 or x == 11 or y == 4 or y == 12
			var c := frame if edge else glow
			if not edge and x >= 6 and x <= 9 and y >= 6 and y <= 10:
				c = core
			if not edge and _hash01(x, y, v + 97) > 0.88:
				c = core
			img.set_pixel(o.x + x, o.y + y, c)
	# Variant flicker-shape: a notch in the housing, so a row of lamps is not
	# four copies of one sprite.
	img.set_pixel(o.x + 4 + (v % 2), o.y + 5 + (v % 3), frame)


# ---------------------------------------------------------------------------

## Deterministic [0,1) hash. Kept local so the tileset never depends on RNG
## seeding order — the same tile always paints the same bytes.
static func _hash01(x: int, y: int, seed_value: int) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (seed_value * 83492791)
	n = n & 0x7FFFFFFF
	n = (n ^ (n >> 15)) * 1103515245
	n = n & 0x7FFFFFFF
	return float(n % 65536) / 65536.0
