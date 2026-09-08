#!/usr/bin/env python3
"""Lamp session store. Local files only. No network."""

from __future__ import annotations

import errno
import json
import os
import stat
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / ".local" / "state" / "omarchy" / "lamp"
DEFAULT_SHARE_DIR = Path.home() / ".local" / "share" / "omarchy-lamp"
SESSION_PATH = STATE_DIR / "session.json"
MAX_TARGET_SECONDS = 24 * 60 * 60


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def today_stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%d")


def format_duration(total_seconds: int) -> str:
    total = clamp_seconds(total_seconds)
    hours, rest = divmod(total, 3600)
    minutes, seconds = divmod(rest, 60)
    parts = []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if seconds:
        parts.append(f"{seconds}s")
    return " ".join(parts)


def clamp_seconds(value) -> int:
    try:
        return max(0, min(MAX_TARGET_SECONDS, int(value)))
    except (TypeError, ValueError):
        return 0


def session_target(session: dict) -> int:
    """Target in seconds, tolerating sessions written before seconds existed."""
    seconds = clamp_seconds(session.get("targetSeconds"))
    if seconds:
        return seconds
    return clamp_seconds(clamp_seconds(session.get("targetMinutes")) * 60)


def load_session() -> dict:
    if not SESSION_PATH.exists():
        return {"lit": False}
    try:
        data = json.loads(SESSION_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {"lit": False}


def save_session(data: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SESSION_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, SESSION_PATH)


def resolve_journal_dir(raw) -> Path:
    """Where the journal lands. Empty or unset keeps the historical location."""
    candidate = (raw or "").strip()
    if not candidate:
        return DEFAULT_SHARE_DIR
    return Path(os.path.expanduser(os.path.expandvars(candidate)))


class JournalError(Exception):
    """The journal directory or file is not somewhere we are willing to write."""


def open_journal_dir(share_dir: Path) -> tuple[int, Path]:
    """Create and open the journal directory, returning a verified descriptor.

    The directory is canonicalized first, so pointing journalDir at a symlinked
    vault still works, and then opened with O_NOFOLLOW: after resolution the
    final component must not be a symlink, which closes the window where one is
    swapped in between resolving and opening. Every check runs against the
    descriptor rather than the path, so the thing we verified is the thing we
    write into.
    """
    try:
        share_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    except OSError as exc:
        raise JournalError(f"cannot create journal directory {share_dir}: {exc.strerror}")

    canonical = Path(os.path.realpath(share_dir))
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        dir_fd = os.open(canonical, flags)
    except OSError as exc:
        raise JournalError(f"cannot open journal directory {canonical}: {exc.strerror}")

    try:
        info = os.fstat(dir_fd)
        if info.st_uid != os.getuid():
            raise JournalError(f"journal directory is not owned by you: {canonical}")
        if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            raise JournalError(
                f"journal directory is group- or world-writable: {canonical}"
            )
    except Exception:
        os.close(dir_fd)
        raise
    return dir_fd, canonical


def open_journal_file(dir_fd: int, name: str) -> int:
    """Open today's page relative to an already verified directory descriptor.

    O_NOFOLLOW is the point: the daily name is predictable, so anyone able to
    write into the directory could otherwise pre-create it as a symlink and
    have us append to a file somewhere else entirely. O_NOFOLLOW does not stop
    a hard link, which reaches the same target, so the link count is checked
    too.
    """
    flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        fd = os.open(name, flags, 0o600, dir_fd=dir_fd)
    except OSError as exc:
        # O_NOFOLLOW reports a symlink as ELOOP, which reads as nonsense to
        # anyone who has not just been attacked. Say what actually happened.
        if exc.errno == errno.ELOOP:
            raise JournalError(
                f"refusing to write {name}: it is a symbolic link, not a journal page"
            )
        raise JournalError(f"refusing to write {name}: {exc.strerror}")

    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise JournalError(f"journal page is not a regular file: {name}")
        if info.st_uid != os.getuid():
            raise JournalError(f"journal page is not owned by you: {name}")
        if info.st_nlink > 1:
            raise JournalError(f"journal page is hard-linked elsewhere: {name}")
    except Exception:
        os.close(fd)
        raise
    return fd


def append_journal(entry: str, share_dir: Path) -> Path:
    stamp = today_stamp()
    name = f"{stamp}.md"
    dir_fd, canonical = open_journal_dir(share_dir)
    try:
        fd = open_journal_file(dir_fd, name)
        empty = os.fstat(fd).st_size == 0
        with os.fdopen(fd, "a", encoding="utf-8") as fh:
            if empty:
                fh.write(f"# {stamp}\n\n")
            fh.write(entry.rstrip() + "\n\n")
    finally:
        os.close(dir_fd)
    return canonical / name


def cmd_status() -> int:
    session = load_session()
    print(json.dumps(session, ensure_ascii=False))
    return 0


def cmd_light(intention: str, target_seconds: int = 0) -> int:
    intention = " ".join(intention.split()).strip()
    if not intention:
        print(json.dumps({"error": "empty-intention"}))
        return 2
    if len(intention) > 160:
        intention = intention[:160].rstrip()
    session = {
        "lit": True,
        "intention": intention,
        "startedAt": now_iso(),
        "endedAt": None,
        "close": None,
        "targetSeconds": clamp_seconds(target_seconds) or None,
    }
    save_session(session)
    print(json.dumps(session, ensure_ascii=False))
    return 0


def cmd_extinguish(close: str, share_dir: Path) -> int:
    session = load_session()
    if not session.get("lit"):
        print(json.dumps({"error": "not-lit", "lit": False}))
        return 1
    close = " ".join(close.split()).strip()
    session["lit"] = False
    session["endedAt"] = now_iso()
    session["close"] = close or None
    save_session(session)

    started = session.get("startedAt") or "?"
    ended = session.get("endedAt") or "?"
    intention = session.get("intention") or "(none)"
    lines = [
        f"## {started} → {ended}",
        "",
        f"**Intention:** {intention}",
    ]
    target = session_target(session)
    if target:
        lines += ["", f"**Planned:** {format_duration(target)}"]
    if close:
        lines += ["", f"**What moved:** {close}"]
    out = dict(session)
    # The session is already closed on disk. If the page cannot be written
    # safely, say so rather than losing the extinguish.
    try:
        out["journal"] = str(append_journal("\n".join(lines), share_dir))
    except JournalError as exc:
        out["error"] = str(exc)
        print(json.dumps(out, ensure_ascii=False))
        return 1
    print(json.dumps(out, ensure_ascii=False))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        return cmd_status()
    action = argv[0]
    args = argv[1:]

    # "--journal-dir <path>" is honoured only immediately after the action, so a
    # free-form intention or close note may still contain the literal text.
    share_dir = DEFAULT_SHARE_DIR
    if len(args) >= 2 and args[0] == "--journal-dir":
        share_dir = resolve_journal_dir(args[1])
        args = args[2:]

    if action == "status":
        return cmd_status()
    if action == "light":
        target = 0
        # "light --for <seconds> <intention...>"; the flag is optional so the
        # older "light <intention...>" form still works.
        if len(args) >= 2 and args[0] == "--for":
            target = clamp_seconds(args[1])
            args = args[2:]
        return cmd_light(" ".join(args).strip(), target)
    if action == "extinguish":
        return cmd_extinguish(" ".join(args).strip(), share_dir)
    print(json.dumps({"error": "unknown-command"}))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
