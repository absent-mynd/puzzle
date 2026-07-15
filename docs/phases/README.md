# Phase Documentation

This directory contains detailed documentation for each implementation phase.

---

## Directory Structure

- **`completed/`** - Completed phases (read-only, historical record)
- **`pending/`** - Future phases (active planning documents)

---

## Completed Phases ✅

Located in `completed/` directory:

| Phase | Name | Status | Completion Date |
|-------|------|--------|----------------|
| 1 | Project Setup & Foundation | ✅ Complete | 2025-11-05 |
| 2 | Basic Grid System | ✅ Complete | 2025-11-05 |
| 3 | Simple Axis-Aligned Folding | ✅ Complete | 2025-11-06 |
| 4 | Geometric Folding | ✅ Complete | 2025-11-07 |
| 5 | Multi-Seam Handling | ✅ Complete | 2025-11-08 |
| 6 | Undo/Unfold System | ✅ Complete | 2025-11-09 |
| 7 | Player Character | ✅ Complete | 2025-11-06 |
| 9 | Level Management | ⚙️ Substantial | In Progress |
| 10 | GUI & Audio | ⚙️ Substantial | In Progress |

**See [STATUS.md](../../STATUS.md) for the authoritative, current test count.**

---

## Pending Phases 📋

| Phase | Name | Priority | Est. Time | Dependencies |
|-------|------|----------|-----------|--------------|
| 8 | Cell Types & Visuals | P2 | 3-4h | Phases 4, 5 ✅ |
| 9 | Level Management (polish) | P2 | 1-2h | Phase 3, 7 |
| 10 | Graphics, GUI & Audio (polish) | P3 | 2-3h | Parallel |
| 11 | Testing & Validation | P4 | 4-5h | All phases |

> The `pending/` directory is currently empty — all phase specs written so far
> have been implemented and moved to `completed/`. Remaining phases (8, 11) are
> tracked in STATUS.md and do not yet have standalone spec documents.

---

## How to Use Phase Documentation

### When Starting a New Phase

1. **Read the phase document** in `pending/`
2. **Check dependencies** - Ensure prerequisite phases are complete
3. **Review acceptance criteria** - Know what "done" looks like
4. **Write tests first** - Follow TDD approach
5. **Implement incrementally** - Follow sub-task breakdown

### When Completing a Phase

1. **Verify all tests pass**
2. **Update STATUS.md** - Add test counts, mark phase complete
3. **Move phase doc** from `pending/` to `completed/`
4. **Add completion date** to phase document header
5. **Commit changes**

---

## Phase Document Format

Each phase document contains:

1. **Overview** - What this phase accomplishes
2. **Objectives** - Specific goals
3. **Dependencies** - What must be done first
4. **Sub-tasks** - Breakdown of work
5. **Acceptance Criteria** - Definition of "done"
6. **Implementation Notes** - Key details for developers
7. **Tests** - Expected test coverage
8. **References** - Related documentation

---

## Next Phase: Phase 8 - Cell Types & Visual Elements

**Status:** 📋 Not started (no spec doc yet)
**Priority:** P2

Enhanced cell type system, goal detection polish, and animations. The core
folding/undo mechanics (Phases 1-7) are complete, so remaining work is content
and polish rather than core-mechanic engineering.

---

## Phase Dependencies

```
Phase 1, 2, 3, 7 (COMPLETE)
    ↓
Phase 4: Geometric Folding (COMPLETE)
    ↓
Phase 5: Multi-Seam Handling (COMPLETE)
    ↓
Phase 6: Undo/Unfold System (COMPLETE)
    ↓
Phase 8: Cell Types & Visuals (NEXT)
    ↓
Phase 11: Final Testing

Parallel tracks (can be done anytime):
- Phase 9: Level Management (substantial - GUI + persistence done)
- Phase 10: Graphics & Audio (substantial - GUI + audio done)
```

---

## Updating Phase Documentation

### Completed Phase Docs (in `completed/`)
**DO NOT EDIT** - These are historical records.

Exception: Only add retrospective notes at the end if valuable lessons learned.

### Pending Phase Docs (in `pending/`)
**CAN UPDATE** - Active planning documents.

Update when:
- Discovering new edge cases during implementation
- Design decisions change
- Dependencies change
- Scope adjustments

Always note the date of updates in the document.

---

## Additional Resources

- [AGENTS.md](../../AGENTS.md) - Quick start for AI agents
- [STATUS.md](../../STATUS.md) - Current project status
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Design decisions
- [DEVELOPMENT.md](../DEVELOPMENT.md) - Development workflow
- [REFERENCE.md](../REFERENCE.md) - API reference

---

**For current project status, see [STATUS.md](../../STATUS.md)**
