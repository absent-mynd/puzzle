#!/usr/bin/env python3
"""Generate the game's placeholder audio.

Every sound this game ships is SYNTHESIZED HERE, from the Python standard
library and nothing else. That is not a limitation being worked around, it is
the point: the audio vocabulary is code, so it can be read, diffed, retuned and
regenerated, and no file in `assets/audio/` carries a licence question.

    python3 tools/gen_audio.py            # write assets/audio/{sfx,music}

Two rules the rest of this file follows.

**SFX are normalized to a common peak, and the MIX lives elsewhere.** Every
effect here comes out at the same peak level; how loud a footstep is next to a
fold is decided by the `vol` trim in `scripts/systems/Sounds.gd`. Balancing by
re-rendering would put the mix in a binary, where nobody can see it.

**Music loops are built as harmonics of the loop itself.** Every partial in a
track is an exact integer multiple of 1/loop_seconds, so the waveform is
periodic over exactly the file's length and the loop point is sample-exact.
This is why the pads are additive rather than sampled noise: a noise bed would
need a crossfade at the seam, and a crossfade is the one thing you can hear.

The names written here are the vocabulary in `Sounds.gd`, and
`test_audio_manager` asserts the two agree — a sound added on one side and not
the other fails the suite rather than going quietly missing at runtime.
"""

import math
import os
import random
import struct
import wave

SFX_RATE = 22050
MUSIC_RATE = 16000

## Peak every SFX is normalized to. Below full scale so that several playing at
## once (the pool is 8 deep) do not sum into the clipper.
SFX_PEAK = 0.55
MUSIC_PEAK = 0.42

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")


# ---------------------------------------------------------------------------
# Signal primitives
#
# A "buffer" throughout is a plain list of floats, nominally -1..1, at whatever
# rate the caller is working in. Everything below is deliberately naive: these
# are placeholders, and a readable one-pole filter beats a good one nobody can
# follow.
# ---------------------------------------------------------------------------

def buf(rate, seconds):
    return [0.0] * max(1, int(rate * seconds))


def sine(rate, seconds, f0, f1=None, phase=0.0):
    """A sine, optionally sweeping f0 -> f1 exponentially.

    Exponentially, not linearly, because pitch is heard in ratios: a linear
    sweep from 600 down to 90 spends most of its time in the top octave and
    reads as a stall followed by a drop.
    """
    n = int(rate * seconds)
    f1 = f0 if f1 is None else f1
    out = [0.0] * n
    ph = phase
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 * ((f1 / f0) ** t) if f0 > 0 and f1 > 0 else f0
        ph += 2.0 * math.pi * f / rate
        out[i] = math.sin(ph)
    return out


def noise(rate, seconds, rng):
    n = int(rate * seconds)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(src, rate, f0, f1=None):
    """One-pole lowpass with a sweeping cutoff. The whooshes are all this."""
    f1 = f0 if f1 is None else f1
    out = [0.0] * len(src)
    y = 0.0
    for i, x in enumerate(src):
        t = i / max(1, len(src) - 1)
        f = f0 * ((f1 / f0) ** t) if f0 > 0 and f1 > 0 else f0
        a = 1.0 - math.exp(-2.0 * math.pi * f / rate)
        y += a * (x - y)
        out[i] = y
    return out


def highpass(src, rate, f):
    """Complement of the one-pole: what the lowpass threw away."""
    return [x - y for x, y in zip(src, lowpass(src, rate, f))]


def env(rate, seconds, attack, decay, curve=2.0):
    """Attack/decay envelope over the whole buffer, decay shaped by `curve`."""
    n = int(rate * seconds)
    out = [0.0] * n
    a = max(1, int(rate * attack))
    for i in range(n):
        if i < a:
            out[i] = i / a
        else:
            t = (i - a) / max(1, n - a)
            out[i] = max(0.0, 1.0 - t) ** curve
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def add(*buffers):
    n = max(len(b) for b in buffers)
    out = [0.0] * n
    for b in buffers:
        for i, x in enumerate(b):
            out[i] += x
    return out


def gain(src, g):
    return [x * g for x in src]


def reverse(src):
    return list(reversed(src))


def normalize(src, peak):
    top = max((abs(x) for x in src), default=0.0)
    if top <= 1e-9:
        return src
    return [x * peak / top for x in src]


def declick(src, rate, ms=3.0):
    """Ramp the first and last few milliseconds to zero.

    A buffer that starts or ends on a non-zero sample is a step, and a step is
    a click — which is exactly the artifact the audio doc promises the system
    does not produce. SFX only: doing this to a music loop would put a dip at
    the loop point.
    """
    n = int(rate * ms / 1000.0)
    out = list(src)
    for i in range(min(n, len(out))):
        f = i / max(1, n)
        out[i] *= f
        out[-1 - i] *= f
    return out


def write_wav(path, rate, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = bytearray()
    for x in samples:
        v = int(max(-1.0, min(1.0, x)) * 32767)
        frames += struct.pack("<h", v)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))
    return len(samples) / rate


# ---------------------------------------------------------------------------
# The sound effects
#
# One function per entry in `Sounds.gd`. Each returns a buffer at SFX_RATE and
# is normalized on the way out, so what is written here is CHARACTER only —
# shape, pitch, length — never level.
# ---------------------------------------------------------------------------

def sfx_hand_place(rng):
    """Pinning a hand: a small, dry pin-prick. Deliberately unmusical — this
    happens constantly and anything with a pitch centre would become a tune."""
    s = 0.09
    tick = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 4000, 1200),
               env(SFX_RATE, s, 0.001, 0.0, 3.0))
    body = mul(sine(SFX_RATE, s, 940, 780), env(SFX_RATE, s, 0.001, 0.0, 4.0))
    return add(gain(tick, 0.7), gain(body, 0.5))


def sfx_pair_armed(rng):
    """The second hand lands and the fuse lights: two rising tones. Rising
    because something is now COMING — the pair commits itself, and this is the
    only warning the player gets."""
    s = 0.26
    a = mul(sine(SFX_RATE, s * 0.45, 560), env(SFX_RATE, s * 0.45, 0.004, 0.0, 3.0))
    b = mul(sine(SFX_RATE, s * 0.55, 840), env(SFX_RATE, s * 0.55, 0.004, 0.0, 2.5))
    out = a + b
    air = mul(highpass(noise(SFX_RATE, s, rng), SFX_RATE, 3000),
              env(SFX_RATE, s, 0.01, 0.0, 2.0))
    return add(out, gain(air, 0.18))


def sfx_fold(rng):
    """Space closing. A downward-sweeping wash — the two halves rushing at each
    other — landing on a low thump where they meet."""
    s = 0.72
    wash = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 5200, 260),
               env(SFX_RATE, s, 0.05, 0.0, 1.6))
    swoop = mul(sine(SFX_RATE, s, 520, 110), env(SFX_RATE, s, 0.02, 0.0, 1.4))
    thump = [0.0] * int(SFX_RATE * s * 0.62) + mul(
        sine(SFX_RATE, s * 0.38, 96, 62), env(SFX_RATE, s * 0.38, 0.004, 0.0, 2.2))
    return add(gain(wash, 0.55), gain(swoop, 0.5), gain(thump, 0.9))


def sfx_unfold(rng):
    """The inverse, and it sounds like it: `fold` played backwards, which is
    what unfolding IS in this game. The thump becomes an intake."""
    return reverse(sfx_fold(rng))


def sfx_pinch(rng):
    """The fold swallows you. Falls, and keeps falling — the one fold outcome
    where the world closed over the player rather than under them."""
    s = 0.62
    drop = mul(sine(SFX_RATE, s, 640, 78), env(SFX_RATE, s, 0.01, 0.0, 1.2))
    swirl = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 2400, 180),
                env(SFX_RATE, s, 0.03, 0.0, 1.0))
    sub = mul(sine(SFX_RATE, s, 150, 44), env(SFX_RATE, s, 0.02, 0.0, 1.0))
    return add(gain(drop, 0.5), gain(swirl, 0.45), gain(sub, 0.6))


def sfx_surface(rng):
    """Coming back out of a fold: opening, not closing. The mirror of `pinch`
    so arriving and leaving read as one pair."""
    s = 0.55
    rise = mul(sine(SFX_RATE, s, 190, 560), env(SFX_RATE, s, 0.06, 0.0, 1.3))
    air = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 700, 5000),
              env(SFX_RATE, s, 0.10, 0.0, 1.5))
    return add(gain(rise, 0.55), gain(air, 0.30))


def sfx_burst(rng):
    """The release burst: a soft pop with a short ring. Untargeted, so it wants
    to sound like something leaving you in every direction at once, not like
    something being fired at a target."""
    s = 0.34
    pop = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 6000, 900),
              env(SFX_RATE, s, 0.002, 0.0, 2.4))
    ring = mul(sine(SFX_RATE, s, 1180, 1040), env(SFX_RATE, s, 0.004, 0.0, 3.0))
    return add(gain(pop, 0.6), gain(ring, 0.35))


def sfx_fold_refused(rng):
    """A fuse that went off and produced no fold. Dull and short — this is a
    thing that FAILED, and the hands hitting the ground say the rest."""
    s = 0.30
    a = mul(sine(SFX_RATE, s, 168, 132), env(SFX_RATE, s, 0.004, 0.0, 1.6))
    b = mul(sine(SFX_RATE, s, 84, 66), env(SFX_RATE, s, 0.004, 0.0, 1.6))
    return add(gain(a, 0.55), gain(b, 0.5))


def sfx_deny(rng):
    """A refused action with nothing else to say — two flat low blips. Kept
    quieter and duller than `fold_refused`: this one fires on ordinary
    mistakes and must never start to feel like a scolding."""
    s = 0.17
    half = int(SFX_RATE * s * 0.42)
    blip = mul(sine(SFX_RATE, s * 0.42, 196), env(SFX_RATE, s * 0.42, 0.003, 0.0, 3.0))
    return blip + [0.0] * int(SFX_RATE * s * 0.16) + blip[:half]


def sfx_trigger(rng):
    """A trigger tile firing: the ground answering. Slow attack, low, and with
    no transient at all — the player did not do this, the world did."""
    s = 0.95
    a = mul(sine(SFX_RATE, s, 58), env(SFX_RATE, s, 0.22, 0.0, 1.1))
    b = mul(sine(SFX_RATE, s, 87), env(SFX_RATE, s, 0.28, 0.0, 1.2))
    c = mul(sine(SFX_RATE, s, 232), env(SFX_RATE, s, 0.34, 0.0, 1.6))
    return add(gain(a, 0.6), gain(b, 0.45), gain(c, 0.18))


def sfx_hand_pickup(rng):
    """Picking a hand up. The one unambiguously GOOD event in the loop, so it
    is the only SFX allowed to be plainly musical: a rising bell third."""
    s = 0.38
    def bell(f, start, length):
        e = env(SFX_RATE, length, 0.003, 0.0, 2.4)
        tone = add(mul(sine(SFX_RATE, length, f), e),
                   gain(mul(sine(SFX_RATE, length, f * 2.01), e), 0.35))
        return [0.0] * int(SFX_RATE * start) + tone
    return add(gain(bell(880, 0.0, s * 0.7), 0.55),
               gain(bell(1320, 0.11, s * 0.62), 0.5))


def sfx_hand_drop(rng):
    """A hand hitting the ground. The counterpart to `hand_pickup`, and
    deliberately not its mirror: this is an object landing, not a reward."""
    s = 0.17
    tick = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 3000, 700),
               env(SFX_RATE, s, 0.002, 0.0, 3.0))
    body = mul(sine(SFX_RATE, s, 240, 170), env(SFX_RATE, s, 0.003, 0.0, 2.6))
    return add(gain(tick, 0.45), gain(body, 0.55))


def sfx_jump(rng):
    s = 0.15
    rise = mul(sine(SFX_RATE, s, 300, 660), env(SFX_RATE, s, 0.004, 0.0, 2.2))
    air = mul(highpass(noise(SFX_RATE, s, rng), SFX_RATE, 2000),
              env(SFX_RATE, s, 0.004, 0.0, 3.0))
    return add(gain(rise, 0.55), gain(air, 0.16))


def sfx_land(rng):
    s = 0.13
    thud = mul(sine(SFX_RATE, s, 150, 92), env(SFX_RATE, s, 0.002, 0.0, 2.6))
    dirt = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 2200, 500),
               env(SFX_RATE, s, 0.002, 0.0, 3.2))
    return add(gain(thud, 0.6), gain(dirt, 0.4))


def sfx_footstep(rng):
    """The most-played sound in the game by an order of magnitude, so: short,
    dull, no pitch centre. Variety comes from the pitch jitter the registry
    asks for, not from anything here."""
    s = 0.075
    return mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 1800, 600),
               env(SFX_RATE, s, 0.002, 0.0, 2.8))


def sfx_door(rng):
    """Stepping through. Somewhere between the fold sounds and the UI ones —
    a transition you chose, that costs nothing."""
    s = 0.44
    sweep = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 900, 4200),
                env(SFX_RATE, s, 0.06, 0.0, 1.8))
    tone = mul(sine(SFX_RATE, s, 330, 440), env(SFX_RATE, s, 0.04, 0.0, 1.8))
    return add(gain(sweep, 0.35), gain(tone, 0.45))


def sfx_respawn(rng):
    """Falling out of the world, or being turned back by the fold. Down then
    up: something went wrong, and you are already being put back."""
    s = 0.52
    down = mul(sine(SFX_RATE, s * 0.45, 420, 150), env(SFX_RATE, s * 0.45, 0.005, 0.0, 1.5))
    up = mul(sine(SFX_RATE, s * 0.55, 180, 400), env(SFX_RATE, s * 0.55, 0.02, 0.0, 1.6))
    return gain(down + up, 0.6)


def sfx_reset(rng):
    """R: the whole world goes back. Three descending tones — final, and long
    enough that it cannot be confused with a refusal."""
    s = 0.50
    out = [0.0] * int(SFX_RATE * s)
    for i, f in enumerate((523, 392, 261)):
        start = int(SFX_RATE * 0.13 * i)
        tone = mul(sine(SFX_RATE, 0.22, f), env(SFX_RATE, 0.22, 0.006, 0.0, 2.2))
        for j, x in enumerate(tone):
            if start + j < len(out):
                out[start + j] += x * 0.5
    return out


def sfx_goal(rng):
    s = 1.05
    out = [0.0] * int(SFX_RATE * s)
    for i, f in enumerate((523, 659, 784, 1047)):
        start = int(SFX_RATE * 0.10 * i)
        length = 0.55
        e = env(SFX_RATE, length, 0.005, 0.0, 2.0)
        tone = add(mul(sine(SFX_RATE, length, f), e),
                   gain(mul(sine(SFX_RATE, length, f * 2.0), e), 0.25))
        for j, x in enumerate(tone):
            if start + j < len(out):
                out[start + j] += x * 0.42
    return out


def sfx_ui_move(rng):
    s = 0.045
    return mul(sine(SFX_RATE, s, 1500), env(SFX_RATE, s, 0.001, 0.0, 4.0))


def sfx_ui_click(rng):
    s = 0.085
    tick = mul(lowpass(noise(SFX_RATE, s, rng), SFX_RATE, 5000, 1500),
               env(SFX_RATE, s, 0.001, 0.0, 3.2))
    tone = mul(sine(SFX_RATE, s, 760, 620), env(SFX_RATE, s, 0.002, 0.0, 3.0))
    return add(gain(tick, 0.5), gain(tone, 0.55))


SFX = {
    "hand_place": sfx_hand_place,
    "pair_armed": sfx_pair_armed,
    "fold": sfx_fold,
    "unfold": sfx_unfold,
    "pinch": sfx_pinch,
    "surface": sfx_surface,
    "burst": sfx_burst,
    "fold_refused": sfx_fold_refused,
    "deny": sfx_deny,
    "trigger": sfx_trigger,
    "hand_pickup": sfx_hand_pickup,
    "hand_drop": sfx_hand_drop,
    "jump": sfx_jump,
    "land": sfx_land,
    "footstep": sfx_footstep,
    "door": sfx_door,
    "respawn": sfx_respawn,
    "reset": sfx_reset,
    "goal": sfx_goal,
    "ui_move": sfx_ui_move,
    "ui_click": sfx_ui_click,
}


# ---------------------------------------------------------------------------
# The music
#
# Both tracks are additive pads built ENTIRELY from harmonics of the loop
# fundamental (1 / LOOP_SECONDS), so the rendered buffer is exactly periodic
# over the file and the loop point cannot be heard. Any frequency asked for
# here is snapped to the nearest such harmonic before it is used — see
# `harmonic`. That snap is the whole trick, and it is why there is no fade,
# no crossfade and no sampled noise anywhere below.
# ---------------------------------------------------------------------------

LOOP_SECONDS = 12.0


def harmonic(f):
    """Nearest frequency that completes a whole number of cycles in the loop."""
    k = max(1, round(f * LOOP_SECONDS))
    return k / LOOP_SECONDS


def pad(rate, partials, rng):
    """Sum of steady harmonics with fixed random phases.

    Random phase rather than aligned: with every partial starting at zero the
    loop opens on a spike as they all peak together, which is audible as a tick
    once a loop even though the seam itself is perfect.
    """
    n = int(rate * LOOP_SECONDS)
    out = [0.0] * n
    for f, amp in partials:
        fh = harmonic(f)
        ph = rng.uniform(0.0, 2.0 * math.pi)
        step = 2.0 * math.pi * fh / rate
        for i in range(n):
            out[i] += amp * math.sin(ph + step * i)
    return out


def breathe(rate, depth, cycles, phase=0.0):
    """A slow amplitude LFO that also completes whole cycles in the loop."""
    n = int(rate * LOOP_SECONDS)
    return [1.0 - depth + depth * 0.5 * (1.0 + math.sin(
        phase + 2.0 * math.pi * cycles * i / n)) for i in range(n)]


def music_overworld(rng):
    """The overworld bed: open, low, and almost still.

    Ambient to the point of being barely there. The game's own vocabulary is
    quiet and sparse, and a track with any melodic opinion would be competing
    with the fuse — the one sound the player genuinely has to hear.
    """
    root = 55.0                       # A1
    partials = [(root, 0.50), (root * 2, 0.34), (root * 3, 0.14),
                (root * 4, 0.10), (root * 5, 0.05),
                (root * 1.5, 0.22),                      # the fifth
                (root * 6.0, 0.045), (root * 8.0, 0.03)]
    body = pad(MUSIC_RATE, partials, rng)
    body = mul(body, breathe(MUSIC_RATE, 0.35, 2))
    shimmer = pad(MUSIC_RATE, [(880, 0.05), (1320, 0.035), (1760, 0.02)], rng)
    shimmer = mul(shimmer, breathe(MUSIC_RATE, 0.85, 3, math.pi * 0.5))
    return add(body, shimmer)


def music_subspace(rng):
    """Inside a fold.

    A fold's interior is a PLACE, and the doc's open question is whether it
    reads as one. So this is the overworld bed moved down a fourth and pulled
    out of tune with itself: the same room, folded. The beating between the
    detuned pairs is the point — it is the only thing in the mix that tells you
    where you are without a word of UI.
    """
    root = 41.25                      # E1, a fourth below the overworld
    partials = []
    for mult, amp in ((1.0, 0.50), (2.0, 0.32), (3.0, 0.12), (4.0, 0.08)):
        # Two partials a hair apart, each snapped to its own loop harmonic, so
        # they beat at the (also periodic) difference between them.
        partials.append((root * mult, amp))
        partials.append((root * mult + 0.58, amp * 0.8))
    partials.append((root * 1.5, 0.16))
    body = pad(MUSIC_RATE, partials, rng)
    body = mul(body, breathe(MUSIC_RATE, 0.30, 1))
    # A high wash, built the same additive way rather than from noise: dense
    # enough to read as air, still exactly periodic.
    wash = pad(MUSIC_RATE, [(600 + 37 * i, 0.016) for i in range(26)], rng)
    wash = mul(wash, breathe(MUSIC_RATE, 0.7, 2, math.pi))
    return add(body, gain(wash, 0.8))


MUSIC = {
    "overworld": music_overworld,
    "subspace": music_subspace,
}


def main():
    total = 0
    print("SFX  -> %s" % SFX_DIR)
    for name in sorted(SFX):
        # One seed per name, so regenerating one sound never disturbs another
        # and the whole set is reproducible from this file alone.
        rng = random.Random("sfx:" + name)
        samples = declick(normalize(SFX[name](rng), SFX_PEAK), SFX_RATE)
        path = os.path.join(SFX_DIR, name + ".wav")
        secs = write_wav(path, SFX_RATE, samples)
        size = os.path.getsize(path)
        total += size
        print("  %-14s %5.2fs  %6.1f KB" % (name, secs, size / 1024.0))

    print("music-> %s" % MUSIC_DIR)
    for name in sorted(MUSIC):
        rng = random.Random("music:" + name)
        # NO declick here: the loop is seamless by construction, and tapering
        # the ends would carve a dip into the one place it must be continuous.
        samples = normalize(MUSIC[name](rng), MUSIC_PEAK)
        path = os.path.join(MUSIC_DIR, name + ".wav")
        secs = write_wav(path, MUSIC_RATE, samples)
        size = os.path.getsize(path)
        total += size
        print("  %-14s %5.2fs  %6.1f KB" % (name, secs, size / 1024.0))

    print("total %.1f KB" % (total / 1024.0))


if __name__ == "__main__":
    main()
