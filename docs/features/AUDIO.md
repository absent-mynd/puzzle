# Audio

**Last updated:** 2026-08-06 · **Tests:** `test_audio_manager`, `test_world_audio`

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

Adding a sound means: a const and a `_REGISTRY` line in `Sounds.gd`, a
generator function in `tools/gen_audio.py`, and a call at the moment it
happens. Nothing else learns a new name — a `Sounds` id *is* the asset
basename, so there is no mapping table to fall out of date.

`test_audio_manager` asserts the registry and the shipped assets are the same
set **in both directions**, so a name with no file, or a file no code can
reach, fails the suite instead of going quiet at runtime.

---

## The vocabulary

Named for *this* game. (The set that used to live here — `selection`, `undo`,
`victory` — was the deleted top-down puzzler's, and none of those events exist.)

**Folding**

| Sound | Fires when |
|---|---|
| `hand_place` | a tap pins a hand |
| `pair_armed` | the second hand completes a pair and lights its fuse |
| `fold` | a fold commits and you ride a flap |
| `pinch` | the fold closes over you instead — you are inside it |
| `surface` | you come back out of a subspace |
| `unfold` | a fold comes apart |
| `burst` | the release burst fires and something comes loose |
| `fold_refused` | the fuse went off and the fold would not go |
| `trigger` | a trigger tile fires — the world folding itself |

**Hands** — `hand_pickup`, `hand_drop`.
**Body and world** — `jump`, `land`, `footstep`, `door`, `respawn`, `reset`,
`goal`, `deny`.
**UI** — `ui_click`, `ui_move`.
**Music** — `overworld`, `subspace`.

### Pairs that carry meaning

Three of these are deliberately *mirrors*, because the events are:

- **`pinch` / `surface`** — going into a fold and coming out of it, one gesture
  heard from its two sides.
- **`fold` / `unfold`** — literally the same waveform reversed, which is what
  unfolding *is* in this game (drop the fold and re-derive).
- **`fold` / `fold_refused`** — a fold that goes and a fold that does not must
  never be mistakable for one another, which is why the refusal is short, dull
  and low rather than a quieter whoosh.

### Refusals

Every refusal in `FoldWorld` goes through `_deny(text)` — the flash message and
`Sounds.DENY` together. Kept separate from `_show_flash`, which also carries
good news ("Folded in.", "Picked up a plain hand."): a game that beeps at you
for succeeding is worse than one that says nothing.

`DENY` carries the longest retrigger floor in the registry (0.3s). Most
refusals come from per-frame checks that stay true for many frames running, and
a refusal that repeats stops being information and becomes nagging.

---

## Why there is a registry

Three things belong in one place rather than at twenty call sites.

**The mix.** `tools/gen_audio.py` normalizes every effect to the same peak, so
the whole balance is the `vol` column of `Sounds._REGISTRY` — readable,
diffable, reviewable. Balancing by re-rendering assets would bury the mix in a
binary.

**Pitch jitter.** Anything that repeats gets some; anything the player might
learn to recognise gets none. `pair_armed` is at zero on purpose — it is a
countdown starting, and a countdown that arrives at a different pitch each time
is harder to learn.

**The retrigger floor.** This is the load-bearing one. Footsteps, dropped
hands and refusals all fire from `_physics_process`, and without a floor on the
interval, one frame's worth of events empties the voice pool. Solved once in
the registry instead of at each call site.

One deliberate exception: `hand_drop` has **no** floor. A refused fold scatters
both its hands in the same frame and two hands out of one fold are meant to read
as two; any gap at all would swallow the second. The wide pitch jitter is what
keeps the simultaneous pair sounding like two objects.

---

## Music

Two beds, and which one plays is a function of where you are: `overworld` at
world level, `subspace` inside a fold. `FoldWorld._update_music()` is called
from `_apply_context()`, the single place `mode` changes, and `play_music`
ignores a request for the track already playing — so walking in and out of a
fold crossfades, and everything else costs nothing.

This is the cheapest honest answer to the open question in AGENTS.md about
whether a subspace reads as a **place**. `subspace` is the overworld bed
moved down a fourth and pulled out of tune with itself — the same room, folded.
The beating between its detuned pairs is the only thing in the mix that tells
you where you are without a word of UI.

Neither bed is static: both drift continuously, and how they drift is part of
telling the two apart — see *they drift* below.

---

## The assets are code

Every sound ships as a WAV generated by `tools/gen_audio.py`, from the Python
standard library and nothing else:

```bash
python3 tools/gen_audio.py       # rewrites assets/audio/{sfx,music}
```

Deterministic — one RNG seed per sound name, so retuning one sound never
disturbs another and the whole set is reproducible from that file alone.

**Why synthesize rather than source.** No licence question, no attribution to
track, no binary blob whose provenance is a link in a README. The character of
each sound is a readable function with a comment saying what it is trying to
be, and changing one is a diff. About 1.8 MB for the set, most of it the two
music beds — they are 32 seconds each, and length is what a bed costs.

**These are placeholders, and they read as placeholders.** They are honest,
tuned and mixed, but they are synthesized bleeps. Replacing any of them means
dropping a file with the same basename into `assets/audio/sfx/` — the loader
takes `.ogg`, `.wav` and `.mp3`, and the registry entry carries over untouched.
Delete that sound's generator function when you do, so the file stops claiming
to produce it.

### The music loops are seamless by construction

Both beds are built **entirely from harmonics of the loop fundamental**
(1/32 Hz), so the waveform is exactly periodic over the file and the loop point
is sample-exact. That is why the pads are additive rather than sampled noise:
noise would need a crossfade at the seam, and a crossfade is the one thing you
can hear. Nothing is faded at the file's edges for the same reason — tapering
would carve a dip into the one place that must be continuous.

### …and they drift, which is the same rule applied twice

A static sum of sines loops perfectly and is **monotone** — one colour, held
forever, which the ear stops hearing as sound and starts hearing as a hum. So
the partials do not sit still: each one swells on its own slow cycle and wavers
in pitch by hundredths of a Hz (`drift`, which is `pad` with the monotony taken
out).

That does not cost the seam, because **every modulator is also measured in whole
cycles per loop**. A swell at 3 cycles and a vibrato at 5 are both exactly back
where they started at the last sample. Drift and seamlessness are not a
trade-off here; they are one constraint applied to the modulators as well as the
carriers. The vibrato is phase modulation for this reason — a frequency ramp
would accumulate offset and land the carrier somewhere a continuation would not.

Two consequences worth knowing before retuning:

- **Per-partial LFOs, not one global LFO.** A single LFO over the finished sum
  only changes how *loud* the pad is, which reads as pumping. Independent counts
  per partial change its *balance*, which reads as the timbre moving. The global
  `breathe` is still there but shallow (0.18), under the per-voice motion.
- **The file length is the ceiling on how slow a drift can be.** A motion slower
  than the loop cannot exist, because it would not close. That — not fidelity —
  is what sets `LOOP_SECONDS`, and why it is 32s and not 12s: at 12s the ear
  learns the cycle and waits for it. `MUSIC_RATE` is 12 kHz for the opposite
  reason: nothing in either bed goes above ~1.8 kHz, so the rate is pure cost
  and the length is what the bytes should buy.

The overworld's harmony drifts too, not just its colour. Quiet upper voices —
a ninth and a sixth, at just ratios, mostly absent — swell past each other so
the chord moves between an open fifth, an added ninth and a sixth. Still no
third and nothing that resolves: it should be impossible to hum and impossible
to catch repeating. `subspace` drifts more slowly and flatly on purpose, because
its detuned beating already supplies movement and a subspace should feel
like it is the thing holding still.

`AudioManager` sets the loop flag at load time rather than relying on the import
settings, because `.import` files are gitignored and so nothing on disk can
carry it.

---

## Three things in `AudioManager` that are easy to undo

**The user's volume is applied once, on the bus.** A player's `volume_db` is
never the user's setting — it is the fade envelope for music, and the mix trim
for an effect. The old version set both, so the music volume multiplied into
itself and half volume played at a quarter.

**The autoload runs while the tree is paused** (`PROCESS_MODE_ALWAYS`). Godot
pauses an `AudioStreamPlayer` along with its tree, and the pause menu pauses the
tree — without this, the click that opened the menu is the last thing you hear
and any fade in flight freezes half way.

**Fades are tweens, not `await` loops.** The old fade could not be cancelled,
which is what let a track change during a fade stop the music outright. One
cancellable chain now does out → swap → in.

Two smaller ones, both regressions the tests pin:

- **The pool steals, it does not drop.** When all eight voices are busy the
  oldest is taken. A dropped sound is a fold you did not hear, and the pool
  exists to let sounds overlap, not to cap how many events the game may have.
  Voice age is a monotonic counter, not a clock — several sounds routinely start
  in the same millisecond and a timestamp cannot order those.
- **A missing sound warns once.** It fires from `_physics_process`; one warning
  per frame is how a log becomes useless.

---

## Volumes persist

`AudioManager` loads the three volumes at startup and can save them, sharing
`user://settings.json` with `Settings.gd` — each side owns its own keys and
both read-modify-write, so neither clobbers the other's.

The bug this replaces: the volumes were written by the settings screen and read
back by nothing else, so however the player set them, every session started at
the defaults.

---

## Status

| Component | State |
|---|---|
| `AudioManager` — buses, pool, fades, loading, persistence | ✅ |
| `Sounds` — vocabulary, mix, jitter, throttling | ✅ |
| Assets — 21 effects + 2 music beds, generated | ✅ placeholders, beds drift |
| `FoldWorld` — the whole fold vocabulary | ✅ wired |
| `PlayerBody` — jump, land, footsteps | ✅ wired |
| `PauseMenu` / `Settings` | ✅ wired, ⚠️ **unreachable** |

**The one real gap:** nothing shows the pause menu. `PauseMenu.tscn` and
`Settings.tscn` are complete and correctly wired, but no key opens them and
nothing in the world instantiates either — so the volume sliders cannot be
reached in-game. That is an input/UI gap rather than an audio one (it predates
this work), and closing it means deciding how pausing interacts with a fold in
flight — see AGENTS.md decision 7. Until then, volumes are settable by editing
`user://settings.json`, and they are honoured at startup.

## Open

- **Nothing is positional.** Every sound is a bare `AudioStreamPlayer`. A fold
  going off across the room sounds exactly like one at your feet. `SubViewport`
  already has `audio_listener_enable_2d`, so `AudioStreamPlayer2D` is available
  when it is wanted — but *what a fold's position even is* while the world is
  mid-rearrangement is a real question, not a mechanical change.
- **The fuse does not tick.** It is the one moment of tension the game has, and
  it currently gets one sound at the start and one at the end. A rising tick
  would need a dedicated looping voice whose rate tracks `fuse_progress()`.
- **No ducking.** A fold landing under a music swell is louder than either.
- **No save-point or checkpoint sounds** — those events do not exist yet.
