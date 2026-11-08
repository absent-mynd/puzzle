#!/usr/bin/env python3
"""The queue's rules, pinned. Run: python3 tools/test_queue.py"""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import importlib.util

# Loaded by path under another name: "queue" is also a stdlib module.

_spec = importlib.util.spec_from_file_location("workqueue", Path(__file__).parent / "queue.py")
q = importlib.util.module_from_spec(_spec)
sys.modules["workqueue"] = q
_spec.loader.exec_module(q)


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = q.main(list(argv))
    return rc, out.getvalue() + err.getvalue()


class QueueTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["QUEUE_DIR"] = self.tmp.name
        os.environ["QUEUE_TODAY"] = "2026-11-08"

    def tearDown(self):
        self.tmp.cleanup()
        os.environ.pop("QUEUE_DIR")
        os.environ.pop("QUEUE_TODAY")

    def ticket(self, tid="0001"):
        return q.find(q.load_all(), tid)

    def add_decision(self, tid="0001"):
        t = self.ticket(tid)
        t.body += "\n## Decision needed\nA or B?\n\n**Recommendation:** A.\n"
        t.save()

    def test_new_ticket_starts_as_research_and_is_valid(self):
        run("new", "Fix the pit", "--kind", "bug")
        t = self.ticket()
        self.assertEqual(t.state, "new")
        self.assertTrue(t.path.name.startswith("0001-fix-the-pit"))
        self.assertEqual(q.lint(q.load_all()), [])

    def test_ids_increase(self):
        run("new", "a"); run("new", "b")
        self.assertEqual([t.id for t in q.load_all()], ["0001", "0002"])

    def test_agent_can_never_make_a_ticket_ready(self):
        run("new", "a")
        rc, out = run("move", "1", "ready")
        self.assertEqual(rc, 2)
        self.assertIn("cannot move", out)
        self.assertEqual(self.ticket().state, "new")

    def test_ruling_requires_a_decision_with_a_recommendation(self):
        run("new", "a")
        rc, out = run("move", "1", "ruling")
        self.assertEqual(rc, 2)
        self.assertIn("Decision needed", out)
        self.add_decision()
        self.assertEqual(run("move", "1", "ruling")[0], 0)
        t = self.ticket()
        self.assertEqual((t.state, t.asks, t.meta["waiting_since"]), ("ruling", 1, "2026-11-08"))

    def test_build_with_no_note_takes_the_recommendation(self):
        run("new", "a"); self.add_decision(); run("move", "1", "ruling")
        run("rule", "1", "build")
        t = self.ticket()
        self.assertEqual(t.state, "ready")
        self.assertIn("owner · ruling → ready: build — take the recommendation", t.body)
        self.assertNotIn("waiting_since", t.meta)

    def test_answer_and_rework_need_a_note(self):
        run("new", "a"); self.add_decision(); run("move", "1", "ruling")
        self.assertEqual(run("rule", "1", "answer")[0], 2)
        self.assertEqual(run("rule", "1", "answer", "B, actually")[0], 0)
        self.assertEqual(self.ticket().state, "new")

    def test_review_needs_what_was_built_and_a_branch(self):
        run("new", "a"); self.add_decision(); run("move", "1", "ruling")
        run("rule", "1", "build"); run("move", "1", "building")
        self.assertEqual(run("move", "1", "review", "--branch", "claude/x")[0], 2)
        t = self.ticket(); t.body += "\n## What was built\nThe thing.\n"; t.save()
        self.assertEqual(run("move", "1", "review")[0], 2)  # no branch
        self.assertEqual(run("move", "1", "review", "--branch", "claude/x")[0], 0)
        run("rule", "1", "approve"); run("move", "1", "done")
        self.assertEqual(self.ticket().state, "done")

    def test_inbox_orders_by_priority_then_looping_then_review_then_age(self):
        for title in "abcd":
            run("new", title)
        for tid in ("1", "2", "3", "4"):
            self.add_decision(tid.zfill(4)); run("move", tid, "ruling")
        t = self.ticket("0002"); t.meta["asks"] = "3"; t.save()
        t = self.ticket("0003"); t.meta["state"] = "review"; t.meta["branch"] = "b"
        t.body += "\n## What was built\nx\n"; t.save()
        t = self.ticket("0004"); t.meta["waiting_since"] = "2026-10-01"; t.save()
        order = [t.id for t in q.inbox(q.load_all())]
        self.assertEqual(order, ["0002", "0003", "0004", "0001"])
        self.assertIn("LOOPING", run("inbox")[1])

    def test_blocked_ticket_surfaces_once_its_blocker_closes(self):
        run("new", "a"); run("new", "b")
        run("move", "2", "blocked", "--blocked-by", "1")
        self.assertNotIn("0002", [t.id for t in q.agent_next(q.load_all())])
        run("rule", "1", "drop")
        self.assertIn("0002", [t.id for t in q.agent_next(q.load_all())])

    def test_lint_catches_a_hand_edited_state(self):
        run("new", "a")
        t = self.ticket(); t.meta["state"] = "ruling"; t.save()
        self.assertEqual(run("lint")[0], 1)

    def test_html_embeds_every_ticket_safely(self):
        run("new", "</script><b>x")
        out = Path(self.tmp.name) / "b.html"
        run("html", "-o", str(out))
        html = out.read_text()
        self.assertNotIn("</script><b>", html)
        self.assertIn("0001", html)


if __name__ == "__main__":
    unittest.main()
