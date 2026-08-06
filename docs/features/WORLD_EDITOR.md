# The world editor

**Last updated:** 2026-08-06 · **Tests:** `test_editor_tools`, `test_editor_doc`,
`test_world_editor`

An MS-Paint canvas for terrain, on a Mural-style board of canvases you can
arrange, resize and connect.

```bash
./run_editor.sh                      # edit worlds/overworld.json
./run_editor.sh worlds/other.json    # edit something else
```

It is a **scene in this project**, not a Godot editor plugin — so it runs the
way the game runs, and it draws terrain with the game's own tileset. What you
paint is what you will be standing on.

> **It writes to the world file.** `Ctrl+S` overwrites `worlds/overworld.json` in
> place. Work in a tree you can `git checkout --`.

---

## Why it is called a WORLD editor

Because there are no levels. One world, many regions — see `AGENTS.md`
§"the 2026-08-04 consolidation", where the `LevelEditor` that is listed as
deleted is the old top-down one. This is a new thing with a different job.

So the vocabulary lines up like this:

| On the board | In the file | In the game |
|---|---|---|
| a **canvas** (card) | a region | its own sheet of foldable space |
| where the card **sits** | `regions.<id>.editor.pos` | *nothing* |
| a **door** | `doors.<id>` | a warp point at a base tile's centre |
| a **connected pair of anchors** | `regions.<id>.folds[]` | a fold applied before you spawn |
| a **loose anchor** | `regions.<id>.editor.anchors[]` | *nothing* |

**A card's position is not a fact about the world.** Regions have no spatial
relationship to each other — they are connected by doors, not by adjacency — so
where you put a card is a note to yourself about how you are thinking. That is
why it lives in an authoring-only `editor` block that nothing in
`scripts/world/` reads, and why dragging cards around can never break anything.

---

## The tools

| Key | Tool | What a click does | What a right-click does |
|---|---|---|---|
| `B` | Paint | paint the brush | erase to air |
| `E` | Rect | drag a filled rectangle | drag a cleared rectangle |
| `I` | Pick | load that tile into the brush | — |
| `P` | Spawn | move the region's spawn point | — |
| `D` | Door | place a door; **drag door→door to connect** | remove the door |
| `A` | Fold anchor | place an anchor; **drag anchor→anchor to make a fold** | disconnect / remove |
| `L` | Light | place a light | remove it |
| `H` | Hand | leave a hand of the chosen kind on the ground | remove it |
| `T` | Tile data | select a tile and edit what it DOES | clear its settings |

`1`–`9` pick a brush from the palette. Navigation is the same whatever tool is
selected: **wheel** zooms about the cursor, **middle-drag** or **space-drag**
pans, **Home** frames everything, **Ctrl+Z / Ctrl+Shift+Z** undo and redo,
**Ctrl+S** saves.

Chrome always wins a click. A card's title bar moves it and its corner grips
resize it, whichever tool is armed — that is what makes the board navigable
without a modal "select" tool to switch back to.

### The palette is derived, not listed

`EditorTools.palette()` is built from `WorldCore.CHARS` and `TileTypes`.
**Register a tile type and it appears in the editor** — there is no list to
update, and `test_editor_tools` asserts the palette and the loader understand
the same set of characters in both directions. The human name comes from
`TileTypes`' registry too, which is why adding a type is still one file.

---

## Per-tile parameters

The ASCII grid says what a tile IS. A region's `tile_data` says what *this
particular one* DOES — a trigger plate's channel, and the two cells the fold it
fires is pinned between. Take the **Tile data** tool (`T`), click a tile, and an
inspector opens on the right with a field per parameter.

**The form is generated from the registry.** `TileTypes` declares what
parameters a tile type takes; `TileParams` says what those declarations mean;
the inspector builds itself from the two. Nothing in the editor has heard of a
channel. So declaring a parameter is the whole job — it becomes editable,
validated, drawn on the board and saved, with no editor change:

```gdscript
TRIGGER_FOLD: {
    ...,
    "params": [
        {"key": "channel", "type": "string", "default": "", "label": "channel",
         "hint": "names the fold this plate makes..."},
        {"key": "anchors", "type": "cells", "default": [], "count": 2,
         "required": true, "label": "fold anchors", "hint": "..."},
    ]},
```

| `type` | stored as | edited as |
|---|---|---|
| `string` | String | a text field |
| `int` / `float` | number | a spinner |
| `bool` | bool | a checkbox |
| `cells` | `[[x, y], ...]` | a row per slot, **clicked on the board** |

### Cells are picked, not typed

A `cells` parameter's rows each have a button; pressing one arms the next board
click. That is the reason this is worth a UI at all — the values are base cells
of the region, and nobody can read a fold out of two integers. While a pick is
armed it beats every tool and all the chrome, so a click cannot land on a resize
grip by accident; right-click or `Escape` cancels.

The picked cell must be in the **same region** as the tile. Base ids are
per-region and do overlap, so a cell from another card would silently resolve
onto whatever tile shares its numbers — the same trap `AGENTS.md` records for
fold anchors.

### What the board shows

Every configured tile is outlined, with a dashed line to each cell it names and
a numbered ring on each. The tile you are *inspecting* additionally gets the
fold its reaction will make, drawn with the same guides as a pre-placed fold.
Both are driven off the schema — a `cells` parameter added to any tile type
appears on the board the day it is declared.

### Two rules about storage

**Only non-default values are written.** A freshly painted trigger stores
nothing at all, so painting a hundred of them does not put a hundred empty
dictionaries in the world file, and clearing a field really clears it — the
whole entry disappears with the last value.

**Unknown keys are kept.** A key this build has no spec for is data somebody
meant, whether from a hand edit or a newer version. Dropping it would make
opening a file in the editor a lossy operation.

### Painting over a tile drops its parameters

Change a cell's *type* and its `tile_data` goes with it, in the same undo step
as the paint. A trigger's channel left behind under a wall is invisible state:
it does nothing, it is shown nowhere, and it would come back to life the day
somebody painted a trigger there again. Repainting the *same* type changes
nothing and so costs nothing.

### What validation says

All of it is a warning, deliberately — the runtime already refuses to act on a
half-configured tile (`TriggerResolver` returns no reaction when the anchors are
missing), so the world loads; it just contains a plate that does nothing, which
is precisely the thing worth being told. Reported:

- a tile whose type takes parameters with **no entry at all** — it will do nothing
- a `cells` parameter with slots unfilled, out of bounds, or naming one cell twice
- `tile_data` left on a tile type that takes none

Only data stranded outside the grid is an error, because that is a file the
loader cannot make sense of at all.

---

## Resizing a canvas

Dragging any of the eight grips is one operation:

```
EditorDoc.resize_region(id, offset, size)
```

`offset` is where the OLD grid's origin lands in the NEW one. Growing the right
edge by 3 is `(offset=(0,0), size=(w+3,h))`; growing the LEFT edge by 3 is
`(offset=(3,0), size=(w+3,h))` — the content slides right so it stays put on
screen, and the card's board position moves the opposite way so the boundary is
what appears to move. Cropping is the same with a negative offset.

**Everything cell-addressed moves with the terrain** — tile data, the spawn,
doors, lights, loose hands, fold anchors — because otherwise dragging the left
edge would slide the walls out from under the doors. Anything that ends up
outside the new grid is dropped, and you are told how much.

---

## Pre-placed folds

A fold is authored the way the player makes one: **pin an anchor, pin another,
and the pair becomes a fold.** The difference is that an editor anchor waits
indefinitely — it is saved as a loose anchor in the region's `editor` block, so
a half-finished design is still half-finished tomorrow.

**They are drawn, not applied.** The card keeps its full shape and the fold is
shown as:

- the two **crease lines**, where the sheet will be cut;
- the **band** between them, shaded — the space the fold excises;
- the **meeting line**, drawn bright: where the two halves come to rest;
- a dashed line joining the two anchors.

A card that shipped already folded would show you a hole and no way to reason
about what is sealed inside it, which is the opposite of what a pre-placed fold
is for.

The band is not a lookalike. `EditorTools.fold_guides` builds a real `Fold` from
the two anchors and asks `CollisionCore.fold_polygons` what it drops — the same
call `FoldReplay` makes when the fold is applied for real. `test_editor_tools`
pins that equality.

### What the editor refuses, and what it only warns about

The only pair that is **refused** is two anchors on the same cell: it has no
crease direction at all, and it is the one impossible pair in the game too.

Everything else is allowed and then *reported*. The surface rules a player's
fold answers to are asked at the fuse, of a fold being made in a live world
(`AGENTS.md` §"the hand economy") — an author placing a fold in a region is not
standing in it. So an anchor on an unanchorable tile is a warning, not a veto:
a design should be drawable before it is legal.

The panel splits the report the same way everywhere:

- **error** — `FoldWorld._setup_all` will refuse or `push_error` on this; the
  world does not boot correctly.
- **warning** — the game will load it happily, but you probably did not mean it.

The error count rides at the top of the panel, not only at the bottom of a list
you would have to scroll for.

---

## Nested pre-placed folds

Not implemented. **The format reserves room for it and the loader ignores what
it cannot apply**, which is the part that mattered to get right now.

A fold entry is:

```json
{"anchor1": {"x": 10, "y": 6}, "anchor2": {"x": 16, "y": 6}, "in": []}
```

`in` is the **index path of the interiors the fold lives in**: `[]` (or absent)
is the region's own sheet, `[0]` is inside the interior of the region's first
pre-placed fold, `[0, 1]` one level deeper. `WorldData.fold_pairs` returns only
the entries with an empty path, so a nested one is authored, saved and drawn but
does not ship folded — rather than being applied at world level, where its
anchors would fold a stranger part of the region.

### What implementing it would take

The runtime already has the two halves; what is missing is the seam between
them.

1. **A fold's interior is already a real place.** `FoldWorld._ensure_interiors(fid)`
   keeps a fold list per fold id, and `do_sub_fold` folds inside one. So "a fold
   in an interior" is a state the engine can represent — it is reached by play
   today, just never by authoring.
2. **The boot pass would have to recurse.** `_setup_all` walks a region's folds
   in order, capturing each strip before applying the next. A nested entry needs
   the same walk over the *strip content* its parent captured: build the parent,
   capture its strip, then apply the child's anchors to that. The anchors are
   base cells of the parent's captured pieces, which `WorldCore.capture_strip`
   already keeps `base_id` and `src_offset` for — so the coordinates mean
   something without new machinery.
3. **Order becomes a tree, not a list.** `in: [0]` refers to fold index 0 *of the
   same region*, so the list has to be applied parent-before-child. A topological
   pass, or simply requiring that a parent appears earlier in the array.
4. **The editor would need a way in.** The natural gesture is to open a fold's
   interior as its own canvas on the board — a card whose content is the strip
   its parent excises — and place anchors in there normally. That reuses every
   tool as-is and keeps "a canvas is a sheet you paint on" true.

The reason to defer is item 2's interaction with `AGENTS.md` §open question
"Triggers are world-level only" — the resolver does not model splicing folds
into an interior list mid-cascade either. Both want the same machinery, and
building it once for both is better than building it twice.

---

## The files

| Concern | File |
|---|---|
| **What a tile type's parameters ARE** (the schema) | `scripts/model/TileTypes.gd` |
| What they MEAN — defaults, coercion, storage, validation | `scripts/model/TileParams.gd` |
| Palette, raster ops, resize arithmetic, fold guides — **pure** | `scripts/editor/EditorTools.gd` |
| The document: every mutation, plus undo and validation | `scripts/editor/EditorDoc.gd` |
| The board, the cards, every overlay, the whole palette | `scripts/editor/EditorBoard.gd` |
| The mouse, the camera, the tools — what an event MEANS | `scripts/editor/WorldEditor.gd` |
| The panel | `scripts/editor/EditorUI.gd` |
| The scene | `scenes/editor/WorldEditor.tscn` |

The split mirrors `WorldCore` / `FoldWorld`: `EditorTools` and `EditorDoc` are
headless and carry most of the tests; the other three need a viewport.

Dependencies run one way — `EditorUI` names `WorldEditor` (for its tool enum and
limits), `WorldEditor` does not name `EditorUI`. The scene owns the tree instead,
and the two shared things they would otherwise pass through each other are a
`panel_width()` method and the palette constants, which live in `EditorBoard`.

### Undo is document history

`AGENTS.md` says the game has no undo, and it still does not — that is about a
continuous physics world having no discrete move to reverse. An editor is a
different thing: it edits a file, and a paint tool without undo is not a paint
tool.

History is a list of `WorldData.to_dict()` snapshots, for the same reason the
kernel derives rather than mutates: no per-operation inverse to get wrong, and
it composes with operations that touch six collections at once. A brush drag is
**one** step — mutators take a coalescing tag, and the controller ends the
gesture when the mouse comes up.

---

## Known gaps

- **No copy/paste, no flood fill, no multi-select.** Paint, rect and the object
  tools are the whole vocabulary.
- **Lights are placed with defaults.** Colour, radius, energy and flicker are
  editable through `EditorDoc.update_light` but have no panel controls yet. They
  are the obvious next thing to move onto the `TileParams` pattern — a light is
  an occupant rather than a tile, so it wants a schema of its own shape.
- **No file dialog.** `--world=` on the command line, or edit the shipped one.
- **Starting hands have no panel control** (`EditorDoc.set_starting_hands` exists).
- Nested pre-placed folds, as above.
