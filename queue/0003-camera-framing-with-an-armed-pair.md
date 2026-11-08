---
id: 0003
title: Camera framing with an armed pair
state: ruling
priority: 3
kind: playtest
updated: 2026-11-08
waiting_since: 2026-11-08
asks: 1
---

## Context

The lens holds the player and any ARMED pair, which is finite by construction. A lone
anchor is deliberately not framed. How a frame full of span circles reads has not been
tested by play (`scripts/world/WorldCamera.gd`).

## Decision needed

Arm a pair at full span in east and say whether the framing works:

- **Fine as is**: close this.
- **Too wide / too busy**: say what you saw; the agent researches options.

**Recommendation:** Fine as is unless something jumps out. This is cheap to revisit.

## Log
- 2026-11-08 · agent · created: migrated from STATUS.md when the queue was set up
