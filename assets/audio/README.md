# Audio assets

```
audio/
├── music/     region.wav, subspace.wav      — 12s seamless loops
└── sfx/       21 effects, one per Sounds id
```

**Every file here is generated**, by `tools/gen_audio.py`, from the Python
standard library and nothing else:

```bash
python3 tools/gen_audio.py
```

Deterministic — one RNG seed per sound name — so regenerating is a no-op unless
you changed the generator, and retuning one sound never disturbs another.

See `docs/features/AUDIO.md` for the design; this file is about the files.

## What the names mean

A filename here **is** a `Sounds` id (`scripts/systems/Sounds.gd`) with an
extension on it. `AudioManager` loads every audio file in these two directories
at startup and keys them by basename, so there is no manifest and no mapping
table.

`test_audio_manager` asserts the two sets match in both directions: a
registered sound with no file, or a file with no registry entry, fails the
suite. **Adding a file here without adding it to `Sounds` will break the
build** — that is deliberate, since a sound nothing can name and nothing has
mixed is not an asset, it is a stray.

## Replacing a placeholder

These are honest placeholders: mixed, tuned, and audibly synthesized. To
replace one with real audio:

1. Drop a file with the **same basename** in the same directory. `.ogg`, `.wav`
   and `.mp3` all load; `.ogg` is the best fit for anything long.
2. Delete the old file, and delete that sound's generator function in
   `tools/gen_audio.py` so it stops claiming to produce it.
3. Leave `Sounds.gd` alone unless the balance has changed. The `vol` trim there
   is the mix, and it assumes assets are normalized to a common peak — a new
   file that is hot or quiet should be normalized rather than compensated for.

Nothing else needs to change. No code references a path or an extension.

## Format

Generated at 22.05 kHz mono for effects, 16 kHz mono for music — low, because
these are placeholders and the whole set is ~1.1 MB in version control.
Replacements are not held to that: use 44.1 kHz stereo `.ogg` if you have it.

## Music loops

`region.wav` and `subspace.wav` are built **entirely from harmonics of the
loop fundamental** (1/12 Hz), so each file is exactly periodic over its own
length and the loop point is sample-exact. Nothing is faded at the edges —
tapering would carve a dip into the one place that has to be continuous.

`AudioManager` sets the loop flag when it loads them, because the `.import`
files that would normally carry it are gitignored.

If you replace a bed, make sure your file actually loops. A crossfaded loop is
audible; a mismatched one is worse.
