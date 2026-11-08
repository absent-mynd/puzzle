---
name: inbox
description: Walk the owner through their queue inbox one item at a time — load one ticket's context, take their ruling, record it with tools/queue.py, commit, then offer the next. Use when the owner says "inbox", "what needs me", or "let's rule on things".
---

# The owner's inbox, one item at a time

The point is focus: **one ticket in context at a time, closed before the next opens.**

1. `./tools/queue.py inbox`. Show the count and the top item only, not the list.
2. Load that one ticket (`./tools/queue.py show <id>`) and present it in under a
   screen: the decision (or what was built, with the PR link) first, then only the
   context needed to rule. Name the recommendation. For a `review`, say how it was
   checked and whether the PR is green.
3. Take the ruling in the owner's words and map it to a verdict:
   `build` (empty note = take the recommendation), `answer`, `approve` (they have
   merged the PR), `rework`, `park`, `drop`. If it is ambiguous, ask once.
4. `./tools/queue.py rule <id> <verdict> "<note>"`, commit (`queue: rule <id> <verdict>`),
   push.
5. Say "closed" in one line and offer the next item. Do not carry anything from the
   last ticket into the next one.

Never rule for the owner, and never merge. If the owner asks you to act on a ticket
right away, record the ruling first, then do the work as `/queue-cycle` would.
