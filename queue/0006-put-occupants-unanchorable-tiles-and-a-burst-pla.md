---
id: 0006
title: Put occupants, unanchorable tiles and a burst plate in the shipped world
state: new
priority: 3
kind: feature
updated: 2026-11-08
---

## Context

`Occupants`, `UNANCHORABLE_*` (`_`, `X`) and burst plates (`B`) are covered by tests and
placed in the testbed, but not in `worlds/overworld.json`. Placing them is how their
design gets pressure-tested. A burst plate in west could open a fold you were meant to
walk around, which is why none was dropped into west's authored beats.

## Log
- 2026-11-08 · agent · created: migrated from STATUS.md when the queue was set up
