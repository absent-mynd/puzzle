---
id: 0010
title: Finish the Space migration
state: new
priority: 3
kind: chore
updated: 2026-11-08
---

## Context

`FoldWorld` still carries getter/setter properties forwarding to `space.x`
(`scripts/world/FoldWorld.gd:210` onward), so the current space can be read two ways.
Moving the call sites over and deleting the forwarders is mechanical.

## Log
- 2026-11-08 · agent · created: migrated from STATUS.md when the queue was set up
