# Sprites — the tileset

The world is drawn from **one tilesheet**, laid out as a grid of 16×16 art
pixels: **one row per tile kind, one column per variant**.

Right now that sheet is **generated in code** by `TileAtlas.build_image()` — the
tileset ships as readable painter functions rather than a binary, and headless
tests never depend on the import pipeline. It is a real tileset, not a
placeholder hack: same layout, same UVs, same sampling as a drawn one.

## Dropping in a hand-drawn sheet

Save it as **`assets/sprites/tiles.png`** (`TileAtlas.ATLAS_PATH`). If that file
exists it is loaded instead of the generated image, with no code change.

It must match the layout exactly:

| | |
|---|---|
| Tile size | 16×16 px (`PixelArt.TILE_PX`) |
| Width | `VARIANTS × 16` = **64 px** |
| Height | `KINDS × 16` = **176 px** |
| Format | RGBA, no premultiplied alpha |

Rows, top to bottom — the `K_*` constants in `scripts/world/TileAtlas.gd`:

| Row | Kind | Notes |
|---:|---|---|
| 0 | `K_EMPTY` | the background "paper" the sheet is made of; must be **opaque**, or folded-away space and empty space look alike |
| 1 | `K_WALL` | solid |
| 2 | `K_WALL_TOP` | a wall whose base neighbour above is air — the sky-facing edge |
| 3 | `K_WATER` | |
| 4 | `K_GOAL` | walkable: paint the motif over paper |
| 5 | `K_TRIGGER` | pressure plate — the motif belongs at the **bottom** of the cell, since the player stands on the tile below |
| 6 | `K_PIN` | fold-proof: it should read as a solid fact |
| 7 | `K_UFLOOR` | unanchorable floor (walkable) |
| 8 | `K_UWALL` | unanchorable wall (solid) |
| 9 | `K_LAMP` | the glyph drawn at a light source; transparent ground |
| 10 | `K_CACHE` | an anchor cache: two spare anchors, drawn as a pair of upright pegs so the pickup states its denomination (two is what it grants, and what a fold costs) |

## Two rules the art has to respect

- **Paint pre-lighting.** Everything except the lamp glyph is multiplied by the
  ambient floor before it reaches the screen (see `LightRig`), so paint brighter
  than the tile should read. Unlit is roughly 0.4× for background kinds and
  0.7× for solids; a lamp can push a surface to 1.75×.
- **Tiles must tile against themselves, not against their neighbours.** Folds
  cut tiles into arbitrary polygons and slide them next to strangers, so a tile
  cannot assume what is beside it. That is why there is a variant column and
  only one edge kind rather than a 47-tile blob set.

Per-tile *variant* is hashed from the stable `base_id`, so a tile keeps its
variant through every fold, ride and cut.
