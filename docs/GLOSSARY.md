# Glossary — one name per thing

**Purpose:** this file decides the vocabulary. Where the project had two words for
one thing, one of them wins here and the other is *retired* — not deprecated, not
"also acceptable", retired. Where one word had grown two meanings, it is split.

Why it is worth a file: the code and the prose drifted apart, and each of them was
internally consistent, so neither looked wrong. The hand ledger was a class with
"anchor" in its name whose docstring opened "The ledger of HANDS". The armed-pair
list was called `primed` and every comment around it said *armed*. Prose said
*fragment* everywhere the code said `piece`.
None of that is a bug and all of it costs a reader the same thing: a paragraph spent
working out that two words are one thing.

**If you add a word to this project, add it here first.** If you find a retired word
in the tree, it is a leftover — fix it.

---

## The table

| The thing | Call it | Not | Why |
|---|---|---|---|
| The resource you carry, pin and spend | **hand** | anchor, peg | A hand is an *object*: you hold two, and the game never creates or destroys one. `HandTypes`, `HandStock`, `HandPickup`. |
| A hand pinned to a cell | **anchor** | pin, marker | Not a synonym for *hand* — it is the *role* a hand takes while it is down. `Fold.anchor_a/anchor_b` are positions, and they outlive the fold's hands. |
| A hand lying in the world | **loose hand** | cache, pickup, drop | One object (`HandPickup`) for the ones a world ships and the ones a burst pops out; say **authored** or **dropped** when the difference matters (only one of them respawns). |
| A pair whose fuse is running | **armed** | primed | The countdown is a *fuse*, and a fuse is armed. Also the word the player-facing README already used. |
| A derived polygon of a base tile | **piece** | fragment | `FoldedPiece` is the type, `pieces` is the list, `derive_pieces` builds it. A piece no fold has touched is not a fragment of anything. |
| The region between a fold's two creases | **strip** | band, excision band, gap | What the fold excises and what its subspace is made of — one word for both, because they are the same sheet. |
| One image of a repeating space | **copy** | band | `FoldLattice.offsets()` returns where to draw them. Distinct from *strip*: inside a fold you stand in one **copy** of the **strip**. |
| The inside of a fold, as a place | **subspace** | fold interior, strip interior | It is a *space* you can be in, fold within, and surface from — not a property of the fold. |
| Folds made inside a fold's subspace | **inner folds** | interiors | `Fold.inner_folds`. Reads as what it is; `interiors` collided with the retired sense of *interior*. |
| Whatever space is on screen right now | **space** (`Space`) | level, world path | The region is the space with an empty context; a subspace is the space with a non-empty one. One space is on screen, always. |
| An authored area of the world | **region** | zone, area, map | West and east. `WorldData.regions`, ids in every anchor and ball. |
| The outermost space — a region, not inside any fold | **region** ("in a region") | overworld, world level, surface | *Overworld* implied an underworld. There is a region, and there are folds inside it. |
| How many folds deep you are | **depth** | level, layer, stack | `FoldLattice.depth()`, "a fold at depth three". |
| The material the world is made of | **sheet** | paper, terrain, canvas | "There is sheet to pin to." Distinct from `WrapCanvas`, which is a *drawer*, and from the tilesheet, which is a texture. |
| The line a fold's anchor cuts along | **crease** | fold line | Two per fold, one through each anchor. |
| Where the two halves meet after folding | **seam** | join, meeting line | One per fold. It is what you return to in order to unfold. |
| Where a subspace's edges are identified | **glue** / glue line | wrap line, boundary | Walking through it puts you in the next copy. |
| The two outer halves a fold slides inward | **flap** | side, half, wing | Already consistent; recorded so it stays that way. |
| Holding the fold key | **burst** | release burst, retrieve, pull-back | One word for the untargeted release. |
| The character you drive | **player** | blob, avatar | `PlayerBody` is its physics body, `PlayerVisual` its drawing. *Blob* is a description of the art, not the name of the thing. |
| Memoizing a computed value | **cache** | — | The only surviving use of the word: `_tile_cache`, `drop_tile_cache`. Never a hand. |

---

## Words that look like synonyms and are not

Three pairs get confused often enough to be worth stating flat.

**hand ≠ anchor.** A hand is a thing you own; an anchor is a place a hand is
pinned. The distinction is load-bearing: a fold *holds hands* (`Fold.held_hands`,
and it holds their kinds, because unfolding must give the same two back) while it
*has anchors* (`anchor_a`, `anchor_b`, which are cells and define the geometry).
Folds the world makes have anchors and hold no hands.

**crease ≠ seam ≠ glue.** Three lines, three jobs. A fold has two **creases** (one
per anchor, where the cut happens), one **seam** (where the halves meet after they
slide, at `anchor_a + shift_a_grid`, and the only place you can unfold it), and its
subspace has a **glue** line at each end of the strip (where the space repeats, and
where you surface). Unfold blocking is a rule about folds crossing a *seam*; exit
blocking is about folds crossing a *glue*.

**strip ≠ copy.** The strip is a piece of sheet — the one a fold takes. A copy is
one image of a space under its lattice. Inside a fold you are standing in one copy
of one strip, and the camera frames a copy, glue to glue.

---

## Retired words, and what to say instead

Grep for these; each is a leftover.

| Retired | Say | Note |
|---|---|---|
| anchor stock, anchor economy | hand ledger, **hand economy** | The ledger counts hands, wherever they are. |
| anchor cache, hand cache, pickup | **loose hand** | |
| primed | **armed** | |
| fragment | **piece** | The one exception is `void fragment()` in the shaders, which is GLSL and means something else entirely. |
| band | **strip** or **copy** | Whichever it meant; they are not the same. |
| excision band | **excised strip** | |
| fold interior, strip interior | **subspace** | |
| interiors | **inner folds** | |
| level | **space**, **region**, or **depth** | Whichever it meant. See below. |
| world level, at region level | **in a region** | |
| overworld | **the region** | The *filename* `worlds/overworld.json` is not renamed; it is a path, not a term. |
| blob | **the player** | |

### The four levels

`level` is retired because it had grown four meanings, and three of them already had
better words:

1. **A stage in a campaign.** There is no campaign — see `AGENTS.md` §"the 2026-08-04
   consolidation". This is the sense that made the word unusable: the docs said "there
   are no levels" on one page and named a class `Level` on the next.
2. **The space you are in now.** Now `Space`.
3. **How deep in folds you are** ("world level", "at every level"). Now **depth**, or
   name the place: "in a region", "inside a fold".
4. **A severity** — the editor's validation issues. Now `severity`, which is what
   every other tool in the world calls it.

*Level design* survives as a phrase about authoring, because it is about how a space
is composed and no other phrase means it. It is the one place the word is allowed.

---

## Where the words live

The vocabulary is enforced by nothing — there is no lint for prose. What there is:

- `AGENTS.md` — the game in its own words. The canonical usage; if this file and
  that one disagree, one of them is wrong and it is worth ten minutes to find out
  which.
- `scripts/world/README.md` — the player-facing version. Design beats, controls.
- Class docstrings — the *definition* of a term lives on the type that owns it
  (`HandStock`, `FoldLattice`, `Space`), not in this file. This file only decides
  which word to use.
