import json
import os
from functools import lru_cache
from typing import Optional

from . import config


def _mtime_ns(path: str) -> int:
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return 0


@lru_cache(maxsize=1024)
def _load_run_json_cached(path: str, mtime_ns: int) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _load_run(run_dir: str) -> Optional[dict]:
    run_path = os.path.join(run_dir, "run.json")
    if not os.path.isfile(run_path):
        return None
    try:
        data = dict(_load_run_json_cached(run_path, _mtime_ns(run_path)))
    except (OSError, ValueError):
        return None
    data["id"] = os.path.basename(run_dir)
    return data


def iter_runs():
    try:
        entries = os.listdir(config.QA_ROOT)
    except OSError:
        return
    for entry in entries:
        run_dir = os.path.join(config.QA_ROOT, entry)
        if not os.path.isdir(run_dir):
            continue
        run = _load_run(run_dir)
        if run is not None:
            yield run


def list_runs(
    recipe: Optional[str] = None,
    state: Optional[str] = None,
    source_branch: Optional[str] = None,
    source_repository: Optional[str] = None,
    os_version: Optional[str] = None,
    tag: Optional[str] = None,
    started_after: Optional[float] = None,
    started_before: Optional[float] = None,
    limit: int = config.LIST_RUNS_DEFAULT_LIMIT,
) -> list[dict]:
    limit = max(1, min(int(limit), config.LIST_RUNS_MAX_LIMIT))
    out = []
    for run in iter_runs():
        if recipe is not None and run.get("recipe") != recipe:
            continue
        if state is not None and run.get("state") != state:
            continue
        if source_branch is not None and run.get("source-branch") != source_branch:
            continue
        if source_repository is not None and run.get("source-repository") != source_repository:
            continue
        if os_version is not None and run.get("os-version") != os_version:
            continue
        if tag is not None and run.get("tag") != tag:
            continue
        started = run.get("started", 0) or 0
        if started_after is not None and started < started_after:
            continue
        if started_before is not None and started > started_before:
            continue
        out.append(run)
    out.sort(key=lambda r: r.get("started", 0) or 0, reverse=True)
    return out[:limit]


def find_run(run_id_or_tag: str) -> Optional[dict]:
    if not run_id_or_tag:
        return None
    candidate_dir = os.path.join(config.QA_ROOT, run_id_or_tag)
    if os.path.isdir(candidate_dir) and config.is_inside_qa_root(candidate_dir):
        run = _load_run(candidate_dir)
        if run is not None:
            return run
    for run in iter_runs():
        if run.get("tag") == run_id_or_tag:
            return run
    return None


def run_dir_for(run_id: str) -> str:
    path = os.path.join(config.QA_ROOT, run_id)
    if not config.is_inside_qa_root(path) or not os.path.isdir(path):
        raise FileNotFoundError(f"unknown run: {run_id}")
    return path


def stats(
    group_by: str = "recipe",
    started_after: Optional[float] = None,
    started_before: Optional[float] = None,
) -> dict:
    valid = {
        "recipe": "recipe",
        "state": "state",
        "os_version": "os-version",
        "source_branch": "source-branch",
        "source_repository": "source-repository",
    }
    if group_by not in valid:
        raise ValueError(f"group_by must be one of {sorted(valid)}")
    key = valid[group_by]

    buckets: dict[str, dict] = {}
    total = 0
    for run in iter_runs():
        started = run.get("started", 0) or 0
        if started_after is not None and started < started_after:
            continue
        if started_before is not None and started > started_before:
            continue
        total += 1
        bucket = buckets.setdefault(
            str(run.get(key, "<unknown>")),
            {"total": 0, "finished": 0, "failed": 0, "running": 0, "other": 0},
        )
        bucket["total"] += 1
        st = run.get("state")
        if st in ("finished", "failed", "running"):
            bucket[st] += 1
        else:
            bucket["other"] += 1

    for b in buckets.values():
        done = b["finished"] + b["failed"]
        b["pass_rate"] = round(b["finished"] / done, 4) if done else None
    return {"group_by": group_by, "total_runs": total, "buckets": buckets}
