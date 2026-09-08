#!/usr/bin/env python3
"""Lamp session store. Local files only. No network."""

from __future__ import annotations

import errno
import json
import os
import secrets
import stat
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / ".local" / "state" / "omarchy" / "lamp"
DEFAULT_SHARE_DIR = Path.home() / ".local" / "share" / "omarchy-lamp"
SESSION_NAME = "session.json"
SESSION_PATH = STATE_DIR / SESSION_NAME
MAX_TARGET_SECONDS = 24 * 60 * 60
# A session is a handful of short fields. Anything larger is not ours, and
# reading it unbounded would let a planted file exhaust the helper and the
# QML collector that buffers its output.
MAX_SESSION_BYTES = 64 * 1024


class LampError(Exception):
    """A path we are not willing to read from or write to."""


class SessionError(LampError):
    """The session file or its directory failed a safety check."""


def open_verified_dir(path: Path, *, private: bool) -> tuple[int, Path]:
    """Create and open a directory, returning a descriptor we have vetted.

    The path is canonicalized first, so a symlinked location still works, then
    opened with O_NOFOLLOW so the final component cannot be swapped for a link
    in the meantime. Every check runs against the descriptor, so what was
    verified is what gets used.

    `private` marks a directory that is ours alone (the state directory): it is
    forced back to 0700 through the descriptor rather than merely accepted. The
    journal directory is the user's own folder, so it is only required not to
    be group- or world-writable.
    """
    try:
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
    except OSError as exc:
        raise LampError(f"cannot create {path}: {exc.strerror}")

    canonical = Path(os.path.realpath(path))
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        dir_fd = os.open(canonical, flags)
    except OSError as exc:
        raise LampError(f"cannot open {canonical}: {exc.strerror}")

    try:
        info = os.fstat(dir_fd)
        if info.st_uid != os.getuid():
            raise LampError(f"directory is not owned by you: {canonical}")
        if private:
            if stat.S_IMODE(info.st_mode) & 0o077:
                os.fchmod(dir_fd, 0o700)
        elif info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            raise LampError(f"directory is group- or world-writable: {canonical}")
    except Exception:
        os.close(dir_fd)
        raise
    return dir_fd, canonical


def read_verified_file(dir_fd: int, name: str, limit: int) -> bytes | None:
    """Read a regular file we own, relative to a vetted directory descriptor.

    O_NOFOLLOW rejects a planted symlink and O_NONBLOCK keeps a planted FIFO
    from parking the helper forever on open; the S_ISREG check then rejects it
    outright. The read is bounded, so a large file cannot exhaust us even if
    it grows between the fstat and the read. Returns None when absent.
    """
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    try:
        fd = os.open(name, flags, dir_fd=dir_fd)
    except FileNotFoundError:
        return None
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            raise SessionError(f"{name} is a symbolic link, not a session file")
        raise SessionError(f"cannot read {name}: {exc.strerror}")

    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise SessionError(f"{name} is not a regular file")
        if info.st_uid != os.getuid():
            raise SessionError(f"{name} is not owned by you")
        if info.st_size > limit:
            raise SessionError(f"{name} is larger than {limit} bytes")
        chunks = []
        total = 0
        while True:
            block = os.read(fd, 65536)
            if not block:
                break
            total += len(block)
            if total > limit:
                raise SessionError(f"{name} is larger than {limit} bytes")
            chunks.append(block)
    finally:
        os.close(fd)
    return b"".join(chunks)


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
    """The session on disk, or an unlit one.

    A malformed file is treated as no session, the way it always was — that is
    an ordinary accident. A file that fails a safety check is not: it is raised
    so the caller can say so instead of quietly reporting the lamp as out.
    """
    dir_fd, _ = open_verified_dir(STATE_DIR, private=True)
    try:
        raw = read_verified_file(dir_fd, SESSION_NAME, MAX_SESSION_BYTES)
    finally:
        os.close(dir_fd)
    if raw is None:
        return {"lit": False}
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {"lit": False}
    return data if isinstance(data, dict) else {"lit": False}


def save_session(data: dict) -> None:
    """Write the session atomically, through a temp name nobody can predict.

    The old temp name was `session.json.tmp`, which anyone able to write into
    the directory could pre-create as a symlink pointing somewhere else. This
    one is random and opened O_EXCL, so it is always ours and always new. The
    payload is fsynced before the rename and the directory after it, so a
    crash leaves either the previous session or the new one, never a stub.
    """
    payload = (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    dir_fd, canonical = open_verified_dir(STATE_DIR, private=True)
    tmp_name = f".{SESSION_NAME}.{os.getpid()}.{secrets.token_hex(8)}.tmp"
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
        fd = os.open(tmp_name, flags, 0o600, dir_fd=dir_fd)
        try:
            written = 0
            while written < len(payload):
                written += os.write(fd, payload[written:])
            os.fsync(fd)
        finally:
            os.close(fd)
        try:
            os.replace(tmp_name, SESSION_NAME, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        except OSError:
            os.unlink(tmp_name, dir_fd=dir_fd)
            raise
        os.fsync(dir_fd)
    except OSError as exc:
        raise SessionError(f"cannot write the session in {canonical}: {exc.strerror}")
    finally:
        os.close(dir_fd)


def resolve_journal_dir(raw) -> Path:
    """Where the journal lands. Empty or unset keeps the historical location."""
    candidate = (raw or "").strip()
    if not candidate:
        return DEFAULT_SHARE_DIR
    return Path(os.path.expanduser(os.path.expandvars(candidate)))


class JournalError(LampError):
    """The journal directory or file is not somewhere we are willing to write."""


def open_journal_dir(share_dir: Path) -> tuple[int, Path]:
    """The user's journal folder, vetted the same way the state directory is.

    Not `private`: this is a folder they chose and may legitimately share with
    their own tools, so it only has to be theirs and not group- or
    world-writable.
    """
    try:
        return open_verified_dir(share_dir, private=False)
    except LampError as exc:
        raise JournalError(str(exc))


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
    """Report a refused path as JSON so the QML service can surface it.

    Every surface parses stdout, and `lit: false` keeps a failed read from
    being mistaken for a lit lamp.
    """
    try:
        return dispatch(argv)
    except LampError as exc:
        print(json.dumps({"error": str(exc), "lit": False}, ensure_ascii=False))
        return 1


def dispatch(argv: list[str]) -> int:
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
