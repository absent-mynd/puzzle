# The shell — one app, three screens

Editing a world and playing it used to be two processes. `./run_editor.sh` opened
the editor, `godot --path .` opened the game, and the only thing joining them was a
file you had to save first and a world you then had to *walk across* to reach the
thing you had just changed.

They are now three screens of one app: the **launcher**, the **editor**, and a
**run** of the game.

```
                    ┌──────────────┐
        ⏎ / E       │   launcher   │  the worlds in worlds/
     ┌──────────────│  (Launcher)  │  ⏎ play · E edit
     │              └──────────────┘
     ▼                     ▲                    ▲
┌──────────┐   F5 / F6     │ Esc                │ Esc
│  editor  │───────────────┼────────────┐       │
│(WorldEdit)│◀──── Esc ────┼────────┐   │       │
└──────────┘               │        ▼   ▼       │
                           │   ┌──────────────┐ │
                           └───│    a run     │─┘
                               │ (FoldWorld)  │
                               └──────────────┘
```

| Key | Where | What |
|---|---|---|
| `⏎` | launcher | play the selected world |
| `E` | launcher | edit it — landing on the region you picked, if you picked one |
| **`F5`** | editor | **play this world**, from its start |
| **`F6`** | editor | **play from the cell under the cursor** |
| `Esc` | anywhere | back to whatever is underneath |

---

## The one that earns its keep: F6

`F5` plays the world from its start, which is what a "test" button does everywhere.
**`F6` plays from the cell the mouse is over**, and that is the one you will wear
out. An edit is almost never at the spawn — it is two doors and a fold away, down a
shaft you have to climb — and the loop that matters is *change a tile, stand on it,
change it again*. Ultimate Doom Builder's "test from current position" is the same
idea and for the same reason.

Off the board, `F6` falls back to the selected canvas's own spawn, and then to the
world's start. **The answer to "play from here" is never "no".**

Where you drop in stays the region's spawn for the whole run, so `R` and falling out
of the world both bring you back to it rather than to the world's start.

### Two things it does not ask about

- **It does not ask what is in the cell.** Click on a wall and you spawn in the wall
  and get pushed out of it, which is what the depenetration in the frame is for. A
  tool that argues with you about where to stand is a tool you stop using.
- **It does not ask whether the world is finished.** A world with validation errors
  plays; the panel says how many. The runtime already declines to act on a
  half-configured tile, so what you get is a plate that does nothing — which is
  precisely the thing worth finding out by walking onto it.

A cell that a pre-placed fold has taken away is the one case that cannot be
honoured: a strip is not a place yet. The run starts at the region's spawn and says
so.

---

## What a playtest runs on

**The document, not the file.** The editor hands over the `WorldData` it is holding,
unsaved edits and all.

That is the whole reason this is a loop worth having. You do not save to try
something, so a change you tried and did not like is still a change you can `Ctrl+Z`,
and `worlds/overworld.json` changes only when you press `Ctrl+S`. The run **clones**
what it is given (`FoldWorld.data_override`) — a run binds lights, loose hands and
anchors into the world it is playing, and the editor is still holding the original.
That clone is also what makes `R` exact: it re-derives from the document rather than
from what the last two minutes of play did to it.

The launcher hands over a **path** instead, because it has no world in memory. That
one difference is the entire distance between the two ways of starting a run, and
`Shell.play_screen` is where it lives.

---

## Coming back

**A screen you open does not replace the one below it — it suspends it.** The
suspended screen leaves the tree and is kept: not drawn, not stepped, not asked about
input, and otherwise untouched. Escape out of a playtest and the editor is exactly
as you left it — the same camera, the same selection, the same tool, the same undo
history, the same unsaved edits — because none of it was ever taken apart.

Leaving the tree is what does that, rather than a list of things to disable and put
back. There is no list, so there is nothing to forget to restore.

**Where "back" goes is not stored anywhere.** It is whatever is under you on the
stack. A run launched from the editor returns to the editor and the same run
launched from the launcher returns to the launcher, and neither of them holds a
field that says which. Same argument as the fold list, one level up: a relationship
you can derive cannot go stale.

Leaving the *bottom* screen quits, because there is nothing under it. Which is why
`--edit` boots straight into the editor rather than pushing one on top of a launcher
you never asked for.

### Unsaved work gets one refusal

Escape in the editor with a dirty document toasts *"unsaved changes — Esc again to
leave, Ctrl+S to save"* and stays put. The next Escape is believed. The refusal
expires the moment you press anything else, so the two have to be consecutive.

An editor that will not let go of a world you are finished with is worse than one
that drops an edit you could have saved, and the message it refuses with names the
key that saves it.

---

## Booting

`scenes/Shell.tscn` is the project's main scene, so pressing play in Godot opens the
launcher.

```bash
./run.sh                      # the launcher: pick a world to play or edit
./run.sh testbed              # play worlds/testbed.json
./run.sh --edit               # edit the shipped world  (= ./run_editor.sh)
./run.sh --edit testbed       # edit worlds/testbed.json (= ./run_editor.sh testbed)
```

Naming a world says you already know which one you want, so you get it; naming none
is the question the app opens by asking. `--world=` is read by
`WorldData.path_from_args` — the same code the game and the editor have always used,
so nothing can disagree about which world a run means.

Every screen still runs on its own, and that is not an accident:

```bash
godot --path . scenes/world/World.tscn -- --world=testbed   # just the game
godot --path . scenes/editor/WorldEditor.tscn               # just the editor
```

**Screens never name `Shell`.** They say what they want by signal — `left`,
`play_requested`, `edit_requested` — and the shell decides what that means. With
nothing connected the signals go nowhere and the screen behaves exactly as it did
before any of this existed, which is what every scene-driven test relies on:
`test_world_editor.gd` and `test_fold_world.gd` instantiate a screen directly, and
`test_shell.gd` is the only place the wiring is asserted.

---

## The launcher is a world select, not a campaign

There are no levels (`AGENTS.md` §"the 2026-08-04 consolidation"). The list is a list
of **files in `worlds/`**, and nothing about its order or its contents means anything
to the game — it is what a developer happens to have in the tree.

Picking a **region** starts the run in that region, which is the closest thing this
game has to picking a level, and it exists because the beat you are working on is
usually not the one the world spawns you in. The launcher stops there and does not
offer a cell: it is not standing anywhere, and a region's spawn is as specific as it
can honestly be. Cells are the editor's to pick, because the editor is where you can
see them.

`worlds/fixtures/` never appears. The scan is one directory deep, so the suite's
fixtures stay out of a list of things to play without this screen having to know they
exist — see [`worlds/fixtures/README.md`](../../worlds/fixtures/README.md) for why
editing one would be a bad afternoon.

The list is rebuilt every time the launcher comes back into the tree, so a world the
editor wrote while you were away is current when you land on it.

---

## The files

| Concern | File |
|---|---|
| The stack, what a screen may say, and how a run is built | `scripts/ui/Shell.gd` |
| The world select | `scripts/ui/Launcher.gd` |
| `F5`/`F6`, and what the editor hands over | `scripts/editor/WorldEditor.gd` |
| Running a document, and where a run drops you | `scripts/world/FoldWorld.gd` |
| The scenes | `scenes/Shell.tscn`, `scenes/ui/Launcher.tscn` |
| What all of it does | `scripts/tests/test_shell.gd`, `test_launcher.gd`, `test_playtest.gd` |

---

## Known gaps

- **The pause menu is still unreachable.** `Esc` leaves the run; nothing opens
  `scenes/ui/PauseMenu.tscn`, so the volume sliders are still only settable by hand
  (`STATUS.md`). Wiring it is a decision about what `Esc` should mean in a *finished*
  game, and this is a developer's loop.
- **Nothing is remembered between sessions.** Which world you were on survives while
  the launcher is alive — it is suspended, not rebuilt — and is forgotten when the
  app closes.
- **No file dialog and no new-world button.** A world is a file you make by copying
  one, and `--world=` opens it.
- **A run cannot open anything**, so the stack is never deeper than three. Nothing
  depends on that; it is simply all there is to open.
