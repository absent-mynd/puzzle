---
id: 0001
title: Playtest the spans, and re-cut west around them
state: ruling
priority: 1
kind: playtest
updated: 2026-11-08
waiting_since: 2026-11-08
asks: 1
---

## Context

Spans are plain 4 / swift 3 / patient 6 cells (`scripts/model/HandTypes.gd:44`), first
guesses, and now the hardest constraint in the game: two plain hands reach eight cells
and nothing folds wider. West was authored when a fold could span the region, so its
beats need a pass. Beat 1 works (the pit lost a column); beat 4 does not (0005).

## Decision needed

Play west (`./run.sh`) and say which way spans go:

- **Keep** 4 / 3 / 6 and re-cut west's beats to fit them.
- **Shorter**, with long reach as a hand you *find*, then re-cut west.
- **Longer**, so west mostly stands as authored.

Spans are tuning in `HandTypes`; none of this touches the kernel.

**Recommendation:** Keep, and let the agent re-cut west to fit (this also unblocks 0005).
Shorter is the more interesting game but wants a found-hand design first, which is a
bigger ticket.

## Log
- 2026-11-08 · agent · created: migrated from STATUS.md when the queue was set up
