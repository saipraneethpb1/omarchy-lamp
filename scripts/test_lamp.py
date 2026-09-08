#!/usr/bin/env python3
"""Regression tests for the journal write path. Standard library only.

Run: python3 scripts/test_lamp.py
"""

import importlib.util
import os
import stat
import tempfile
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "lamp", Path(__file__).resolve().parent / "lamp.py"
)
lamp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lamp)


class JournalWriteTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.journal = self.root / "journal"
        self.journal.mkdir(mode=0o700)
        self.today = f"{lamp.today_stamp()}.md"

    def tearDown(self):
        self._tmp.cleanup()

    def test_writes_a_page_in_a_private_directory(self):
        path = lamp.append_journal("**Intention:** ship it", self.journal)
        self.assertEqual(path, self.journal / self.today)
        body = path.read_text(encoding="utf-8")
        self.assertIn("**Intention:** ship it", body)
        self.assertTrue(body.startswith("# "))

    def test_creates_the_directory_when_missing(self):
        target = self.root / "made" / "on demand"
        lamp.append_journal("first page", target)
        self.assertTrue((target / self.today).is_file())

    def test_appends_without_repeating_the_header(self):
        lamp.append_journal("one", self.journal)
        lamp.append_journal("two", self.journal)
        body = (self.journal / self.today).read_text(encoding="utf-8")
        self.assertEqual(body.count("# "), 1)
        self.assertIn("one", body)
        self.assertIn("two", body)

    def test_symlinked_daily_name_is_refused_and_target_untouched(self):
        """The reported attack: pre-create today's page as a symlink out."""
        victim = self.root / "victim.txt"
        original = "important user data\n"
        victim.write_text(original, encoding="utf-8")
        os.symlink(victim, self.journal / self.today)

        with self.assertRaises(lamp.JournalError):
            lamp.append_journal("attacker wrote this", self.journal)

        self.assertEqual(victim.read_text(encoding="utf-8"), original)

    def test_hardlinked_daily_name_is_refused_and_target_untouched(self):
        """O_NOFOLLOW does not stop a hard link, so the link count is checked."""
        victim = self.root / "victim-hard.txt"
        original = "important user data\n"
        victim.write_text(original, encoding="utf-8")
        os.link(victim, self.journal / self.today)

        with self.assertRaises(lamp.JournalError):
            lamp.append_journal("attacker wrote this", self.journal)

        self.assertEqual(victim.read_text(encoding="utf-8"), original)

    def test_world_writable_directory_is_refused(self):
        shared = self.root / "shared"
        shared.mkdir()
        # chmod, not mkdir(mode=): umask would mask the write bits away.
        os.chmod(shared, 0o777)
        with self.assertRaises(lamp.JournalError):
            lamp.append_journal("page", shared)
        self.assertFalse((shared / self.today).exists())

    def test_group_writable_directory_is_refused(self):
        shared = self.root / "group-shared"
        shared.mkdir()
        os.chmod(shared, 0o770)
        with self.assertRaises(lamp.JournalError):
            lamp.append_journal("page", shared)
        self.assertFalse((shared / self.today).exists())

    def test_symlinked_journal_directory_still_works(self):
        """Pointing journalDir at a symlinked vault is legitimate."""
        real = self.root / "real vault"
        real.mkdir(mode=0o700)
        link = self.root / "vault-link"
        os.symlink(real, link)

        path = lamp.append_journal("through a link", link)

        self.assertEqual(path, real / self.today)
        self.assertIn("through a link", (real / self.today).read_text(encoding="utf-8"))

    def test_page_is_created_private(self):
        path = lamp.append_journal("page", self.journal)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode) & 0o077, 0)


class SessionStateTests(unittest.TestCase):
    """The session file is at a predictable path, so it is an attack surface."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.state = self.root / "state"
        self._saved = lamp.STATE_DIR
        lamp.STATE_DIR = self.state

    def tearDown(self):
        lamp.STATE_DIR = self._saved
        self._tmp.cleanup()

    def test_round_trip(self):
        lamp.save_session({"lit": True, "intention": "ship it"})
        self.assertEqual(lamp.load_session()["intention"], "ship it")

    def test_missing_file_reads_as_unlit(self):
        self.assertEqual(lamp.load_session(), {"lit": False})

    def test_malformed_json_reads_as_unlit(self):
        lamp.save_session({"lit": True})
        (self.state / lamp.SESSION_NAME).write_text("{ not json", encoding="utf-8")
        self.assertEqual(lamp.load_session(), {"lit": False})

    def test_state_directory_is_forced_private(self):
        lamp.save_session({"lit": False})
        os.chmod(self.state, 0o755)
        lamp.load_session()
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)

    def test_symlinked_session_file_is_refused(self):
        victim = self.root / "victim.txt"
        original = "important user data\n"
        victim.write_text(original, encoding="utf-8")
        self.state.mkdir(mode=0o700, parents=True)
        os.symlink(victim, self.state / lamp.SESSION_NAME)

        with self.assertRaises(lamp.SessionError):
            lamp.load_session()
        self.assertEqual(victim.read_text(encoding="utf-8"), original)

    def test_fifo_session_file_is_refused_without_blocking(self):
        """O_NONBLOCK on open, then S_ISREG rejects it: no hang, no read."""
        self.state.mkdir(mode=0o700, parents=True)
        os.mkfifo(self.state / lamp.SESSION_NAME)
        with self.assertRaises(lamp.SessionError):
            lamp.load_session()

    def test_oversized_session_file_is_refused(self):
        self.state.mkdir(mode=0o700, parents=True)
        blob = "x" * (lamp.MAX_SESSION_BYTES + 1)
        (self.state / lamp.SESSION_NAME).write_text(blob, encoding="utf-8")
        with self.assertRaises(lamp.SessionError):
            lamp.load_session()

    def test_planted_predictable_temp_symlink_is_not_followed(self):
        """The old code wrote through session.json.tmp, which was guessable."""
        victim = self.root / "victim-tmp.txt"
        original = "important user data\n"
        victim.write_text(original, encoding="utf-8")
        self.state.mkdir(mode=0o700, parents=True)
        os.symlink(victim, self.state / f"{lamp.SESSION_NAME}.tmp")

        lamp.save_session({"lit": True, "intention": "unaffected"})

        self.assertEqual(victim.read_text(encoding="utf-8"), original)
        self.assertEqual(lamp.load_session()["intention"], "unaffected")

    def test_no_temp_files_are_left_behind(self):
        lamp.save_session({"lit": True})
        leftovers = [p.name for p in self.state.iterdir() if p.name.endswith(".tmp")]
        self.assertEqual(leftovers, [])

    def test_session_file_is_private(self):
        lamp.save_session({"lit": True})
        mode = (self.state / lamp.SESSION_NAME).stat().st_mode
        self.assertEqual(stat.S_IMODE(mode) & 0o077, 0)


class ResolveJournalDirTests(unittest.TestCase):
    def test_empty_falls_back_to_the_default(self):
        for value in ("", "   ", None):
            self.assertEqual(lamp.resolve_journal_dir(value), lamp.DEFAULT_SHARE_DIR)

    def test_expands_user_and_vars(self):
        os.environ["LAMP_TEST_VAR"] = "vault"
        try:
            self.assertEqual(
                lamp.resolve_journal_dir("~/$LAMP_TEST_VAR/notes"),
                Path.home() / "vault" / "notes",
            )
        finally:
            del os.environ["LAMP_TEST_VAR"]


if __name__ == "__main__":
    unittest.main(verbosity=2)
