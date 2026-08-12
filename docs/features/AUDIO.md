# Audio

The game has a voice. Folding, unfolding, being pinched in, surfacing, arming a
fuse, scattering a failed pair, taking a hand off the ground — all of it is
audible, and all of it ships with sound.

Audio here is a **leaf**. Nothing reads back from it and no gameplay decision
depends on it; the game is fully playable with the master volume at zero. That
is the constraint that lets call sites be one line in the middle of world logic
without anyone having to reason about ordering.

---

## The three files

| Concern | File |
|---|---|
| **The vocabulary and the mix** — what sounds exist, how loud, how jittered, how often | `scripts/systems/Sounds.gd` |
| **The engine** — buses, players, fades, loading, persistence | `scripts/systems/AudioManager.gd` (autoload) |
| **The assets** — every sound, synthesized | `tools/gen_audio.py` → `assets/audio/` |

Adding a sound means: a const and a `_REGISTRY` line in `Sounds.gd`, a generator
function in `tools/gen_audio.py`, and a call at the moment it happens. Nothing else
learns a new name — a `Sounds` id *is* the asset basename, so there is no mapping
table to fall out of date.

`test_audio_manager` asserts the registry and the shipped assets are the same set
**in both directions**, so a name with no file, or a file no code can reach, fails
the suite instead of going quiet at runtime. That is also why the list of sounds is
not repeated here: `Sounds.gd` is the list, and it is the only one a test can check.

Each file carries its own reasoning where someone editing it will see it —
`AudioManager.gd`'s header has the three things about buses, pausing and fades that
are easy to undo, and `tools/gen_audio.py` has why the music loops are seamless and
why drift costs nothing at the loop point.

---

## Pairs that carry meaning

Three sounds are deliberately *mirrors*, because the events are:

- **`pinch` / `surface`** — going into a fold and coming out of it, one gesture
  heard from its two sides.
- **`fold` / `unfold`** — literally the same waveform reversed, which is what
  unfolding *is* in this game (drop the fold and re-derive).
- **`fold` / `fold_refused`** — a fold that goes and a fold that does not must
  never be mistakable for one another, which is why the refusal is short, dull
  and low rather than a quieter whoosh.

## Refusals

Every refusal in `FoldWorld` goes through `_deny(text)` — the flash message and
`Sounds.DENY` together. Kept separate from `_show_flash`, which also carries good
news ("Folded in.", "Picked up a plain hand."): a game that beeps at you for
succeeding is worse than one that says nothing.

`DENY` carries the longest retrigger floor in the registry. Most refusals come from
per-frame checks that stay true for many frames running, and a refusal that repeats
stops being information and becomes nagging.

---

## Why there is a registry

Three things belong in one place rather than at twenty call sites.

**The mix.** `tools/gen_audio.py` normalizes every effect to the same peak, so the
whole balance is the `vol` column of `Sounds._REGISTRY` — readable, diffable,
reviewable. Balancing by re-rendering assets would bury the mix in a binary.

**Pitch jitter.** Anything that repeats gets some; anything the player might learn
to recognise gets none. `pair_armed` is at zero on purpose — it is a countdown
starting, and a countdown that arrives at a different pitch each time is harder to
learn.

**The retrigger floor.** This is the load-bearing one. Footsteps, dropped hands and
refusals all fire from `_physics_process`, and without a floor on the interval, one
frame's worth of events empties the voice pool. Solved once in the registry instead
of at each call site.

One deliberate exception: `hand_drop` has **no** floor. A refused fold scatters both
its hands in the same frame and two hands out of one fold are meant to read as two;
any gap at all would swallow the second. The wide pitch jitter is what keeps the
simultaneous pair sounding like two objects.

---

## Music

Two beds, and which one plays is a function of where you are: `region` in a region,
`subspace` inside a fold. `FoldWorld._update_music()` is called from
`_apply_context()`, the single place `mode` changes, and `play_music` ignores a
request for the track already playing — so walking in and out of a fold crossfades,
and everything else costs nothing.

This is the cheapest honest answer to the open question about whether a subspace
reads as a **place**. `subspace` is the region bed moved down a fourth and pulled
out of tune with itself — the same room, folded. The beating between its detuned
pairs is the only thing in the mix that tells you where you are without a word of UI.

Neither bed is static: both drift continuously, and how they drift is part of
telling the two apart. Why that is possible without a seam is in `gen_audio.py`,
above the music section.

**Volumes persist** in `user://settings.json`, shared with `Settings.gd` — each side
owns its own keys and both read-modify-write, so neither clobbers the other's. They
are read at startup, which is what makes the settings screen's unreachability
survivable (see `STATUS.md` §"Known issues").

---

## Open

- **Nothing is positional.** Every sound is a bare `AudioStreamPlayer`. A fold going
  off across the room sounds exactly like one at your feet. `SubViewport` already has
  `audio_listener_enable_2d`, so `AudioStreamPlayer2D` is available when it is
  wanted — but *what a fold's position even is* while the world is mid-rearrangement
  is a real question, not a mechanical change.
- **The fuse does not tick.** It is the one moment of tension the game has, and it
  currently gets one sound at the start and one at the end. A rising tick would need
  a dedicated looping voice whose rate tracks `fuse_progress()`.
- **No ducking.** A fold landing under a music swell is louder than either.
