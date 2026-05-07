import gzip
import io
import os
import re
from collections import deque
from functools import lru_cache
from typing import Iterator, Optional

from . import config, runs

_LOG_SUFFIXES = (".log", ".log.gz", ".json")


def _safe_join(run_id: str, rel_path: str) -> str:
    run_dir = runs.run_dir_for(run_id)
    if not rel_path or rel_path.startswith("/"):
        raise ValueError("path must be relative to the run directory")
    candidate = os.path.realpath(os.path.join(run_dir, rel_path))
    run_real = os.path.realpath(run_dir)
    if candidate != run_real and not candidate.startswith(run_real + os.sep):
        raise ValueError("path escapes run directory")
    if not os.path.isfile(candidate):
        raise FileNotFoundError(f"log not found: {rel_path}")
    return candidate


def _open_text(abs_path: str) -> io.TextIOBase:
    if abs_path.endswith(".gz"):
        return gzip.open(abs_path, "rt", encoding="utf-8", errors="replace")
    return open(abs_path, "r", encoding="utf-8", errors="replace")


def _is_log_like(name: str) -> bool:
    return name.endswith(_LOG_SUFFIXES) or name == "qa-config.json" or name == "run.json"


def list_logs(run_id: str) -> list[dict]:
    run_dir = runs.run_dir_for(run_id)
    out = []
    for dirpath, _dirnames, filenames in os.walk(run_dir):
        rel_dir = os.path.relpath(dirpath, run_dir)
        node = None
        if rel_dir != ".":
            node = rel_dir.split(os.sep, 1)[0]
        for name in filenames:
            if not _is_log_like(name):
                continue
            abs_path = os.path.join(dirpath, name)
            try:
                st = os.stat(abs_path)
            except OSError:
                continue
            rel = os.path.relpath(abs_path, run_dir)
            out.append({
                "path": rel,
                "size_bytes": st.st_size,
                "gzipped": name.endswith(".gz"),
                "node": node,
                "mtime": st.st_mtime,
            })
    out.sort(key=lambda e: e["path"])
    return out


def interesting_logs(run_id: str) -> list[str]:
    run_dir = runs.run_dir_for(run_id)
    candidates = ["qa.log", "playbook.log"]
    out = []
    for c in candidates:
        if os.path.isfile(os.path.join(run_dir, c)):
            out.append(c)
    for entry in sorted(os.listdir(run_dir)):
        node_dir = os.path.join(run_dir, entry)
        if not os.path.isdir(node_dir):
            continue
        for name in ("qa-output.log.gz", "qa-output.log", "jobs.log.gz", "jobs.log"):
            p = os.path.join(node_dir, name)
            if os.path.isfile(p):
                rel = os.path.relpath(p, run_dir)
                out.append(rel)
    return out


@lru_cache(maxsize=1024)
def _total_lines_cached(abs_path: str, mtime_ns: int) -> int:
    n = 0
    with _open_text(abs_path) as f:
        for _ in f:
            n += 1
    return n


def _total_lines(abs_path: str) -> int:
    try:
        mt = os.stat(abs_path).st_mtime_ns
    except OSError:
        mt = 0
    return _total_lines_cached(abs_path, mt)


def read_log(
    run_id: str,
    path: str,
    start_line: int = 1,
    num_lines: int = config.READ_LOG_DEFAULT_LINES,
) -> dict:
    abs_path = _safe_join(run_id, path)
    start_line = max(1, int(start_line))
    num_lines = max(1, min(int(num_lines), config.READ_LOG_MAX_LINES))

    lines: list[str] = []
    bytes_used = 0
    truncated_by_bytes = False
    end_line = start_line - 1
    with _open_text(abs_path) as f:
        for idx, raw in enumerate(f, start=1):
            if idx < start_line:
                continue
            if len(lines) >= num_lines:
                break
            line = raw.rstrip("\n")
            bytes_used += len(line.encode("utf-8", errors="replace")) + 1
            if bytes_used > config.READ_LOG_MAX_BYTES and lines:
                truncated_by_bytes = True
                break
            lines.append(line)
            end_line = idx

    total = _total_lines(abs_path)
    return {
        "path": path,
        "start_line": start_line,
        "end_line": end_line,
        "returned_lines": len(lines),
        "total_lines": total,
        "truncated": truncated_by_bytes or (end_line < total and len(lines) >= num_lines),
        "lines": lines,
    }


def head_log(run_id: str, path: str, n: int = 200) -> dict:
    return read_log(run_id, path, start_line=1, num_lines=n)


def tail_log(run_id: str, path: str, n: int = 200) -> dict:
    abs_path = _safe_join(run_id, path)
    n = max(1, min(int(n), config.READ_LOG_MAX_LINES))
    buf: deque[str] = deque(maxlen=n)
    total = 0
    with _open_text(abs_path) as f:
        for line in f:
            buf.append(line.rstrip("\n"))
            total += 1
    start_line = max(1, total - len(buf) + 1)
    return {
        "path": path,
        "start_line": start_line,
        "end_line": total,
        "returned_lines": len(buf),
        "total_lines": total,
        "truncated": False,
        "lines": list(buf),
    }


def _grep_iter(
    abs_path: str,
    regex: re.Pattern,
    context: int,
    max_matches: int,
) -> Iterator[dict]:
    context = max(0, min(int(context), 20))
    before: deque[tuple[int, str]] = deque(maxlen=context) if context else deque()
    pending_after = 0
    current: Optional[dict] = None
    matches_yielded = 0

    with _open_text(abs_path) as f:
        for idx, raw in enumerate(f, start=1):
            line = raw.rstrip("\n")
            if regex.search(line):
                if current is None or idx - current["match_lines"][-1] > context + 1:
                    if current is not None:
                        yield current
                        matches_yielded += 1
                        if matches_yielded >= max_matches:
                            return
                    current = {
                        "start_line": before[0][0] if before else idx,
                        "match_lines": [idx],
                        "lines": [b[1] for b in before] + [line],
                    }
                else:
                    current["match_lines"].append(idx)
                    current["lines"].append(line)
                pending_after = context
                before.clear()
            else:
                if pending_after > 0 and current is not None:
                    current["lines"].append(line)
                    pending_after -= 1
                    if pending_after == 0:
                        yield current
                        matches_yielded += 1
                        current = None
                        if matches_yielded >= max_matches:
                            return
                else:
                    if context:
                        before.append((idx, line))

    if current is not None:
        yield current


def grep_log(
    run_id: str,
    path: str,
    pattern: str,
    context: int = config.GREP_DEFAULT_CONTEXT,
    max_matches: int = config.GREP_DEFAULT_MAX_MATCHES,
    ignore_case: bool = True,
) -> dict:
    abs_path = _safe_join(run_id, path)
    flags = re.IGNORECASE if ignore_case else 0
    try:
        regex = re.compile(pattern, flags)
    except re.error as e:
        raise ValueError(f"invalid regex: {e}")
    cap = max(1, min(int(max_matches), config.GREP_MAX_MATCHES_HARD_CAP))
    hits = list(_grep_iter(abs_path, regex, context, cap))
    return {
        "path": path,
        "pattern": pattern,
        "matches": hits,
        "match_count": sum(len(h["match_lines"]) for h in hits),
        "truncated": len(hits) >= cap,
    }


def grep_run(
    run_id: str,
    pattern: str,
    files: Optional[list[str]] = None,
    context: int = config.GREP_DEFAULT_CONTEXT,
    max_matches: int = config.GREP_DEFAULT_MAX_MATCHES,
    ignore_case: bool = True,
) -> dict:
    flags = re.IGNORECASE if ignore_case else 0
    try:
        regex = re.compile(pattern, flags)
    except re.error as e:
        raise ValueError(f"invalid regex: {e}")
    cap = max(1, min(int(max_matches), config.GREP_MAX_MATCHES_HARD_CAP))

    if files is None:
        files = [e["path"] for e in list_logs(run_id)]

    per_file = []
    remaining = cap
    truncated = False
    for rel in files:
        if remaining <= 0:
            truncated = True
            break
        try:
            abs_path = _safe_join(run_id, rel)
        except (FileNotFoundError, ValueError):
            continue
        hits = list(_grep_iter(abs_path, regex, context, remaining))
        if hits:
            per_file.append({
                "path": rel,
                "matches": hits,
                "match_count": sum(len(h["match_lines"]) for h in hits),
            })
            remaining -= len(hits)
    return {
        "pattern": pattern,
        "files": per_file,
        "truncated": truncated or remaining <= 0,
    }
