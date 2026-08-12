# Unifying the anchor system — a design exploration

> **Point-in-time document.** It is a proposal, not a description of the code. Act on
> it and delete it (`AGENTS.md` §doc rule 4); what survives belongs in
> `ARCHITECTURE.md` as decisions, in `GLOSSARY.md` as words, and in the tests as
> behaviour. Measurements were taken 2026-08-12 against `6d6d0e1`.

---

## 0. What is being asked

Four changes, which are really one:

1. **Every anchor in the world is the same kind of object** — the ones you pin, the
   ones a plate fires, the ones an authored fold was built from.
2. **A pair forms by PROXIMITY, not by recency.** Today the next hand you place pairs
   with the last unpaired anchor you can see, at any distance across the region.
3. **Anchors arm by different means** — proximity for a hand you place, a channel for
   a plate, and whatever else later. So the number of anchors standing in the world is
   not bounded by two, and anchors out of each other's range simply sit there.
4. **The interaction radius is a property of the hand kind**, so kinds differ in more
   than their fuse.

The unifying claim underneath: *a fold is not something you do, it is something that
happens when two anchors that can reach each other are both present.* Everything else
— your hands, a pressure plate, the world's own authored state — is a way of getting
an anchor to a place.

---

## 1. What exists today

There are **four** ways a fold comes to exist, and no two of them share a code path.

| # | Route | Anchors are… | Holds hands? | Pairing rule | Fuse? | Where |
|---|---|---|---|---|---|---|
| 1 | You pin two hands | `{bid, bp, hand, region}` dicts in `unpaired` / `armed` | 2, kinds kept | newest resolvable unpaired anchor, **any distance** | yes, per pair | `FoldWorld.place_hand` → `partner_index` → `_prime` → `_tick_fuse` → `fire_pair` |
| 2 | A `TRIGGER_FOLD` plate | cells in the tile's `data.anchors`, resolved per cascade, never stored | no | declared inline by the tile | no — instant | `TriggerResolver.resolve` |
| 3 | An authored pre-fold | `worlds/*.json` `regions[].folds[]`, consumed at load | no | declared inline | no — applied before spawn | `FoldWorld._setup_all` |
| 4 | `do_fold` bare | two cells | takes from your slots | none | no | tests, debug |

So "anchor" is **three unrelated things**: a runtime dict with a hand in it (1), a pair
of numbers in a tile's params that exists only for the length of a cascade (2), and a
JSON literal that is consumed and forgotten at boot (3). A *pre-placed anchor* — an
anchor standing in the world with no partner — **does not exist at all**. The world
editor has one (`WorldData.unpaired_anchors`), and its docstring is explicit that it is
authoring scratch, not a world object: *"an unpaired anchor is a design in progress,
not a fold."*

That sentence is exactly what this change repeals.

Two more facts worth having in front of you, because the proposal turns on them:

- **`unpaired` and `armed` are stored state**, and they are the only stored fold-side
  state in a codebase whose first decision is *derive, never mutate*. The traffic
  between the two lists runs both ways (`_prime`, `_disarm_pair`), and each direction
  needed its own careful docstring about what must not be lost.
- **"Two hands in play" is not a rule anywhere.** `HandStock.SLOTS = 2` bounds what you
  *carry*; `unpaired` has no bound. The reason you never see three anchors standing is
  that the third one always pairs on placement. Recency-pairing is the constraint,
  not the ledger.

---

## 2. The shape of the unified system

### 2.1 The anchor becomes an occupant

`scripts/model/Anchor.gd`, alongside `LightSource` and `HandPickup` — the pattern
Decision 10 already names:

```
id       int         stable, monotonic. The fuse and every marker key off this.
bid, bp  int, Vector2  base identity + point in that tile. Already the storage today.
region   String      base ids overlap between regions; without this a west anchor
                     resolves onto an east tile.
hand     int         HandTypes id. One hand per anchor, always.
arms     Variant     PROXIMITY | channel name | NEVER      (§3.2)
bond     int         LOOSE | BOLTED — what a burst may take back (§3.7)
```

`point_in(pieces)` is `BaseFrame.world_point_from_base`, which is what `anchor_point`
already does. Nothing about transport changes: an anchor is a base-frame point and it
rides folds because it always has.

### 2.2 The field, and the pair as a derived edge

`scripts/model/AnchorField.gd` — kernel, pure, headless-testable. It holds the anchors
and answers one question per frame:

```
pairs(pieces, lattice) -> [{a: Anchor, b: Anchor, gap: float}]
```

An **edge** exists between two anchors when both are resolvable in this frame and

```
declared:   they name each other (an authored pair, a plate's two anchors), AND
            their arming condition is satisfied
proximity:  both arm on proximity, AND  gap <= span(a) + span(b)
```

That is the whole model. `unpaired` and `armed` collapse into **one list plus a pure
function**, which is the same move `FoldReplay` made against the old mutating fold
system, for the same reason: the two-list version has to keep two things agreeing, and
every rule about how they stay in step (`_disarm_pair`'s "the far half goes back to
unpaired, still newest, so your next tap pairs with it") becomes a fact you no longer
have to state, because there is nothing to put back.

### 2.3 The fuse is the only stored state, and it is keyed by the edge

Time cannot be derived. So the field keeps `Dictionary[edge_key] -> {left, total}`,
where `edge_key` is the ordered pair of anchor ids, and each frame:

| Edge state | Meaning | What happens to its fuse |
|---|---|---|
| new | appeared this frame | create at `HandTypes.fuse_for(a, b)` |
| live | both resolvable, still in range | tick down; fire at zero |
| **suspended** | one endpoint unresolvable here — other region, folded away | **keep, do not tick** |
| **broken** | both resolvable, out of range | **drop** |

The suspended/broken split is load-bearing and is not a detail: today `_tick_fuse`
`continue`s when either half is unresolvable, which is what makes *"leave a pair
armed, walk through a door, come back and it is still counting"* true. Under a derived
edge set the naive implementation loses that, because an unresolvable anchor produces
no edge and the fuse would be garbage-collected. A pair that came apart is a new pair;
a pair you walked away from is the same pair.

### 2.4 What fires

Every edge that exists arms. Whichever fuse reaches zero first fires; firing consumes
both its anchors, which deletes every other edge they were in. **No matching algorithm
is needed** — the matching is emergent and first-past-the-post. Ties break on shorter
gap, then lower anchor id, and that ordering wants a test, because it is the one place
determinism is not free.

The alternative — compute a maximal matching, arm only those — was considered and
rejected: it needs a rule for *which* matching, that rule has to be re-run every time
geometry moves, and it hides from the player the thing the fuses would otherwise show
them plainly, which is that a hand dropped between two anchors has started a race.

---

## 3. The decisions this forces

### 3.1 What "within reach of each other" means

Three readings, and two of them are the same:

| Reading | Test | Character |
|---|---|---|
| spheres touch | `gap <= span_a + span_b` | a long hand carries a short partner |
| mean span | `gap/2 <= (span_a + span_b)/2` | **identical to the above** |
| both must reach | `gap <= 2·min(span_a, span_b)` | the weakest hand governs the pair |

The middle one collapsing into the first is a gift: **`span_for(a, b)` has the same
shape as `HandTypes.fuse_for`** — the mean — so mixed pairs obey one rule for both
stats, and the registry gains one row and one function rather than a second idea.

The third reading is the one the geometry actually justifies. A fold slides *both*
flaps inward by half the gap (Decision 3), so under the sum reading a plain hand paired
with a long one is dragging its own flap much further than its span says it can. If
"span" is to mean "how far this hand can pull its side of the sheet", `min` is the
honest test and `sum` is the generous one.

**Recommendation: the mean/sum reading**, because generosity is what makes mixed pairs
interesting (the same argument `fuse_for`'s docstring already makes: taking the max
would make a swift hand worthless the moment it met a patient one) — and because the
alternative is to bias the seam toward the weaker hand, which means non-half shifts,
which means `meeting_pos` stops being grid-aligned. That is Decision 3's foundation and
it is not worth spending here.

### 3.2 Arming conditions, and what a "declared" pair is

An anchor's `arms` field answers *what has to be true before this anchor will pair*:

- `PROXIMITY` — the default for a hand you place. Pairs with anything else nearby that
  also arms on proximity.
- `channel:"vault"` — pairs only with its declared partner, and only once that channel
  is live. Distance is irrelevant, which is how an authored fold spanning half a region
  stays possible when player folds no longer are.
- `NEVER` — inert scenery: an anchor that is a fact about the world and nothing else.

The pair set is therefore `declared ∪ proximity`, and that union is the whole of the
unification. It also means **a plate no longer creates a fold; it makes a channel
live**, and the anchors do the rest.

### 3.3 The distance metric — and an existing bug it turns up

Distance must be measured **in the current frame, in the current space, through the
lattice.** The first two are already true of everything anchors do. The third is not
implemented anywhere:

`FoldLattice` has `wrap_delta` and `wrap`, but no shortest-image delta. Inside a fold
the space is a cylinder, so two anchors either side of a glue line are drawn adjacent
and measure a full period apart. The new system needs
`FoldLattice.shortest_delta(from, to)` — per-axis reduction into `[-len/2, +len/2)`,
which is cheap and exact because the axes are orthogonal and periods are whole cells
(the class docstring proves both).

**This is already a bug, not a new requirement.** `_anchor_within`, `_glue_within`,
`_unfoldable_within`, `seams_within_burst` and `_check_pickups` all use raw
`distance_to`. In a region that is correct — no periods. In a subspace whose period is
small, a burst refuses to reach a hand drawn a few pixels from your feet. Nobody has
reported it because you rarely burst inside a tight strip, and it is exactly the class
of thing that reads as "the key didn't work".

A hazard on the other side of the same fact: **on a short-period cylinder, every anchor
is close to every other** — the nearest image is at most half a period away. Fold
yourself into a two-cell strip and any two anchors in there are within one cell.
Proximity pairing inside tight subspaces will be wild. That may be good (it is the
tense place already) but it should be met deliberately.

### 3.4 One anchor per site

Today two hands may be pinned to the same cell. It is legal at placement — placement
asks only that there be sheet — and `fire_pair` refuses it at the fuse with *"Both
hands came down on one spot."* Under proximity that pair is at gap 0, so it is
*guaranteed* to arm and *guaranteed* to fail: a hole you cannot avoid falling into.

**Refuse a second anchor on an occupied site.** It is not a fold question (which is
what §"placement asks nothing of the fold" protects), it is a question about the site,
in the same family as "there is nothing there to pin to". And it pays for itself three
times: it removes the guaranteed-scatter case, it gives plates their idempotence for
free (§3.6), and it makes "an anchor site" a thing the overlay can mark.

### 3.5 Cascades terminate, and the fuse is the cascade

A fold fires, the sheet moves, anchors move with it, new edges appear, new fuses light.
Nothing needs a fixpoint resolver: `animating()` already serialises transitions, and
every new pair costs at least the shortest fuse in the registry (0.65 s). The cascade
*is* the fuse loop, spread over time, watchable.

And it terminates, provably: **each fold consumes two anchors, and nothing automatic
creates one.** Anchor count is non-increasing while the player does nothing, so at most
`floor(N/2)` folds can fire from N anchors. Hand conservation is what bounds the
cascade — `TriggerResolver.MAX_CASCADE` was a backstop for a loop this model cannot
have.

Two conditions that proof rests on, and both must be honoured:

- **Unfolding must never restore anchors** — only hands, to slots or to the ground, as
  `_take_back` does today. Restore the anchors and a fold whose anchors are still in
  range refolds immediately: a perpetual motion machine, one frame long. This is now a
  correctness constraint, not a preference.
- **Plates must not be able to re-spawn an anchor that is standing.** §3.4's one-per-site
  rule is what gives that; the current guard (per-channel idempotence, plus a per-cascade
  `fired` set) does not survive the move to time-spread cascades, because there is no
  longer a cascade to scope `fired` to.

### 3.6 Triggers dissolve into the same pipeline

`TriggerResolver` currently owns: anchor resolution through the current fold state,
fold creation, pin-blocking, player transport, occupant splitting, a fire-once set, a
channel guard, and a bounded fixpoint. Under the unified model a plate's whole job is
*make this channel live*, and the rest is the ordinary path — which already does every
one of those things, better, because it is the path with the animation, the ride, the
pinch and the hand ledger in it.

What that buys, beyond deletion:

- **Triggers work at any depth.** ARCHITECTURE lists *"triggers are region-level only:
  firing inside a subspace would require splicing folds into an inner-fold list
  mid-cascade, which the resolver does not model"* as an open limit. `do_fold` splices
  into whatever list the current space owns, at any depth, today. Routing plates
  through it closes that limitation by deleting the code that had it.
- **A triggered fold gets a fuse**, so the ground answering you comes with a beat of
  warning instead of a teleport.

What it costs, and these are real:

- A triggered fold can now **pinch the player**, because `do_fold` swallows whoever is
  in the strip. The resolver explicitly refuses that today: *"a trap the player cannot
  see coming should not pinch them into a subspace."* With a fuse the player *can* see
  it coming, which is most of the objection — but it is a deliberate reversal, not a
  side effect, and it wants to be written down.
- A triggered fold would hold hands (§3.7), where today it holds none.
- The instant multi-fold cascade becomes a sequence over seconds. The testbed has
  "every trigger outcome" in it; some of those are chains, and they will feel
  different.

### 3.7 Hands in world anchors, and what "resistant" means

If an authored fold is to be *the same thing* as a fold you made, it holds two hands,
and unfolding it gives them to you. That is the unification working; it is also a
permanent injection into an economy whose whole point is scarcity.

Conservation survives untouched — `HandStock.total` already sums slots, pending, folds
and loose, so authored hands simply make the world's constant larger from boot. What
changes is meaning: the total stops being *your* hands and becomes *the world's*, and
`test_hand_stock` needs re-basing to say so.

The pressure valve is the `bond` field, and it is why the request mentions resistance:

| `bond` | A burst in reach… | Freed by |
|---|---|---|
| `LOOSE` | pops it, as now | you |
| `BOLTED` | does nothing | its own channel — a lever, a plate, elsewhere |

A bolted anchor is a hand the world has driven into the sheet. You cannot pocket it by
walking up to it; you find the thing that lets go of it. That makes an authored fold a
**progression gate that pays out** — the metroidvania shape the project keeps saying it
wants — and it costs no new verb, because "a channel releases it" is the same mechanism
as "a channel arms it" pointed the other way.

Weaker variants exist (a longer charge frees it; N bursts free it) and can be tuned in
later. Start with binary; a counter on an anchor is stored state with no derivation
behind it, and this design is trying to have less of that, not more.

### 3.8 The word, and the collision

`ANCHOR_REACH` already means *arm's length* — the nine cells you may pin into. The new
radius is a different quantity and must not borrow that word.

Proposal: a hand's **span**. "A pair folds when the gap is within their combined span."
Then `ANCHOR_REACH` → `ARM_REACH`, one row in `GLOSSARY.md`, and the two ideas never
get confused in a docstring. (Rejected: *grasp* — nothing else in the game grasps;
*pull* — collides with the burst's pull-back direction; *radius* — says nothing.)

---

## 4. What the shipped world demands — the measurements

This is where the proposal meets content, and it is the biggest risk in it.

| Beat | Fold it needs | Gap |
|---|---|---|
| 1 — ride a fold over the wide pit (west) | rim (col 9) to rim (col 18) | **9 cells** |
| 4 — bite the corner off the sealed chamber | diagonal, ~(31,13)→(41,9) | **10.8 cells** |
| east's authored pre-fold | (10,6)→(16,6) | 6 cells |
| east's plate fold | (26,9)→(28,9) | 2 cells |

So the shipped beats put a floor under the plain hand: **span ≥ ~5.5 cells** (352 world
units) for two plain hands to close the chamber diagonal. Consequences, in order of how
much they should worry you:

1. **The span circle is enormous next to everything else on screen.** `BURST_RADIUS` is
   1.3 cells. A 5.5-cell radius is roughly a quarter of the visible width (the pixel
   target is 320 art px ≈ 20 cells at 1:1). Two of them overlapping is most of the
   frame. The overlay language that works for the burst will not scale to this — it
   wants an edge-and-gap vocabulary (draw the *line* between two anchors that can
   reach, brightening as the fuse runs) rather than two big rings.
2. **Non-interaction needs room the shipped regions do not have.** At 5.5 cells per
   hand, two anchors must be **11+ cells apart** to ignore each other. West is 44 cells
   wide: about four independent anchor sites, wall to wall. The mechanic the request
   is reaching for — a network of hands placed around the world, most of them inert —
   needs either bigger regions or a smaller span, and a smaller span needs the beats
   redesigned.
3. **The cap is a design gift as well as a constraint.** Fold gap ≤ combined span means
   the excised strip now has a **bounded width**, which is a real dent in the
   infinite-crease problem: a fold here still guts a structure over there, but only
   ever in a strip of bounded width. That is not a fix and must not be presented as
   one — see §6.
4. **Span is the second axis hand kinds have been waiting for.** *"Whether a fuse is
   enough to make picking up a colour feel like a choice"* is an open question in
   ARCHITECTURE; a kind that folds *further* is a traversal upgrade you find lying on
   the ground, which is the most metroidvania thing the hand economy could do. It also
   gives the shipped world an exit from (2): keep plain hands short, and put the
   long-span hand where beat 1 needs it.

---

## 5. What must survive

A checklist, because each of these is a property some earlier version of this codebase
lost and had to win back:

| Invariant | Where it is pinned | How the change threatens it |
|---|---|---|
| Nothing creates or destroys a hand | `HandStock.total`, `test_hand_stock` | world anchors re-base the constant; bolted hands add a fourth-and-a-half place a hand can be |
| No second source of truth for the ledger | `AGENTS.md` §2 | the fuse map is keyed state — it must hold *only* the countdown, never a copy of the pair |
| Derive, never mutate | Decision 1 | the whole point: the edge set must be recomputed, never incrementally maintained |
| One transition at a time; the frame belongs to it | `AGENTS.md` §3 | more firings per second means the `animating()` guard after `_tick_fuse` gets exercised far harder |
| Time stops while a hand is raised | `AGENTS.md` §7 | the field must be stepped inside the same guard, below the `placing()` return |
| The kernel never sees the world | Decision 9, `test_layering` | `AnchorField` needs `BaseFrame`, `FoldLattice`, `HandTypes` — all kernel. It must not learn about `FoldWorld` |
| The burst reaches exactly what is inside it | `_disarm_pair` | falls out for free once there is one list; verify rather than assume |
| A fold refused at the fuse scatters, never refunds | `_scatter_pair` | unchanged, but now reachable from far more paths |

Two get *stronger*, and they are the argument for doing this at all:

- **Pairing becomes a pure function of state**, so it is testable headless. Today
  `partner_index` / `_prime` / `_disarm_pair` can only be exercised by booting a scene
  (89 of the references live in `test_fold_world.gd`).
- **The cascade bound stops being a constant** (`MAX_CASCADE = 64`) and becomes a
  consequence of conservation (§3.5).

---

## 6. What this closes — and what it must not close silently

`ARCHITECTURE.md` §"What is deliberately still open" is a list of positions being held.
This change touches three of them, and two of the three must be **argued in the diff,
not absorbed by it**:

| Open question | What this does to it |
|---|---|
| *A hand's kind changes only its fuse* | **Closes it.** Span is the second axis. The registry stays the one file to edit, which is the constraint that was actually attached to it. |
| *Fold extent is infinite-crease* | **Changes its magnitude, does not resolve it.** Creases are still full lines; the strip is now bounded in width. Do not let this quietly become "solved" — barrier-scoped folds are still the candidate, and this makes them *cheaper* to add, not unnecessary. |
| *Triggers are region-level only* | **Closes it,** by deleting the resolver that had the limit (§3.6). |

---

## 7. Blast radius

Measured 2026-08-12 by grep; the runner is the authority on the test suite.

**New (kernel):** `Anchor.gd`, `AnchorField.gd`, `FoldLattice.shortest_delta`,
`HandTypes.span` + `span_for`, `test_anchor_field.gd`.

**Heavily rewritten:** `FoldWorld.gd` — 122 lines mention `unpaired` / `armed` /
`anchor`. Deleted outright: `partner_index`, `_prime`, `_disarm_pair`, the
`unpaired`/`armed` members and `hands_pending`'s arithmetic. Rewritten: `place_hand`,
`hold_action`'s first two blocks, `_tick_fuse`, `all_anchors`, `_build_overlay_view`.

**Changed, smaller:** `TriggerResolver.gd` (most of it dissolves), `TileTypes` (the
`TRIGGER_FOLD` param schema loses `anchors`, gains nothing), `WorldData` (`folds[]` →
`anchors[]`; the `in` path question comes back), `OverlayView` (`aim_pair` → `aim_pairs`;
spans; edges), `WorldOverlay`, `EditorDoc` / `EditorTools` (the editor's scratch anchors
graduate into world objects — the tool that pairs them stops being a tool).

**Tests touching the pairing surface:** `test_fold_world` 89 refs, then
`test_world_overlay`, `test_world_audio`, `test_nested_folds`, `test_editor_doc` at 4
each, `test_world_editor` 2, `test_wrap_canvas_contract` 1 (an API list). Plus
`test_trigger_cascade` and `test_hand_stock` wholesale.

**Worlds:** all three JSON files need migrating, and `worlds/fixtures/kernel.json` is
what the suite pins itself to.

**Performance:** anchors resolve through `BaseFrame.world_point_from_base`, which is a
linear scan of the piece list — up to two passes over ~792 pieces *per anchor*. One
resolution per anchor per frame already happens (the overlay asks). With N growing past
a handful, index pieces by `base_id` at rebuild and hand the field the index. The
pairwise distance loop itself is O(N²) over resolved points and is free by comparison.
Note that the region check short-circuits before the scan, so anchors in other regions
cost nothing — keep it first.

---

## 8. A staged plan

Each stage is shippable, testable, and leaves the game playable.

1. **`FoldLattice.shortest_delta`, and route the five existing distance tests through
   it.** Independent of everything else, fixes a live bug, and the new system needs it.
2. **Extract `Anchor` and `AnchorField` with today's semantics.** One list, recency
   pairing preserved as a rule *inside* the field, fuses keyed by edge. No behaviour
   change; the entire test suite must stay green. This is the refactor that makes the
   rest small.
3. **Swap the pairing rule to proximity**, span in `HandTypes`, plain span calibrated
   to the shipped beats (§4). Behaviour changes here and nowhere else. Playtest before
   going further — questions 1 and 2 in §9 are answered by feel, not by argument.
4. **World anchors:** `arms`, `bond`, authored anchors in the world file, boot settling
   declared pairs with expired fuses. Migrate the three worlds; pre-folds become anchor
   pairs.
5. **Plates make channels live**, and `TriggerResolver` shrinks to that. Delete the
   cascade machinery once its properties have somewhere else to live.
6. **The editor** follows the format: place anchors, not fold pairs; draw spans; preview
   the folds that boot will form.

Stage 2 is the one worth insisting on. Doing 2 and 3 together means a rewrite whose
tests all change at once, and there is then no moment at which the suite says the
extraction was faithful.

---

## 9. Questions only you can answer

1. **How big is a span, really?** §4 says the shipped beats need ~5.5 cells from a plain
   hand. Is the answer to accept that, or to keep spans short (2–3 cells, folds as local
   stitches) and rebuild west's beats around the long-span hand as a found upgrade?
2. **Should placing a lone anchor feel like arming a trap or like leaving a bookmark?**
   Proximity pairing makes an inert anchor a normal thing to have. Whether the world
   tells you what it *would* reach — a span circle always drawn — or stays quiet until
   two of them see each other is the difference between a planning tool and a surprise.
3. **May a plate's fold pinch you?** §3.6 hands that back to the general path. Keeping
   the refusal means a flag on the fold's origin, which is a seam in the unification.
4. **Do authored folds pay out?** Two bolted hands per authored fold, freed by finding
   the thing that lets go of them, is a progression economy. It is also the end of
   "your hands" as a fixed quantity you plan around.
5. **How much is on screen?** Every anchor drawing a 5.5-cell circle is a lot of frame.
   The proposal above assumes edges get drawn and spans mostly do not, which is a
   readability bet that should be made on purpose.
