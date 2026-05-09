"""Read-only MCP server exposing Ganeti QA run data and logs.

Run modes:
    python -m qa_mcp.server                # streamable HTTP on 127.0.0.1:8765
    python -m qa_mcp.server --stdio        # stdio transport (for local dev)

All tools are read-only. Path inputs are resolved under QA_ROOT and rejected
otherwise.
"""
from __future__ import annotations

import argparse
import sys
from typing import Optional

from mcp.server.fastmcp import FastMCP

from . import config, logs, recipes, runs

_INSTRUCTIONS = f"""\
Read-only access to Ganeti QA runs stored under {config.QA_ROOT}.

Workflow
--------
- list_runs / get_run: discover and inspect runs (newest first).
- list_logs: enumerate a run's log files. Each entry carries `kind` and,
  for known files, a `description` explaining the file's purpose -- prefer
  these to filename guessing when choosing what to read.
- grep_run / grep_log: regex search across all or selected files of a run.
- head_log / tail_log / read_log: inspect specific line ranges.
All log responses are size-bounded (line and byte caps).

Run directory layout
--------------------
Each run is a folder named by SHA-1 (the run_id). At the run root:
  run.json        run config: OS version, Ganeti source repo, timings, state
  qa-config.json  config passed to Ganeti's QA suite (tests enabled/disabled)
  qa.log          Ganeti QA suite output -- on failure the last 50-100 lines
                  usually show the cause; start here
  playbook.log    Ansible output for staging VM setup, Ganeti build/install,
                  and cluster init; check when failure occurs before QA starts

Per-node subdirectories
-----------------------
One folder per staging VM, named `<host>.staging.ganeti.org`. One node is
the Ganeti master and therefore has additional master-only daemon logs.
Files of interest (kinds reported by list_logs in parentheses):
  node-daemon.log.gz   (node-daemon)  per-node daemon: storage/network ops,
                                      qemu/xen process spawning. For node-
                                      or instance-level failures, tail this
                                      on the affected node(s).
  kvm-daemon.log.gz    (kvm-daemon)   KVM helper daemon (per node).
  luxi-daemon.log.gz   (luxi-daemon)  luxid -- job submission, RAPI backend
                                      (master only).
  rapi-daemon.log.gz   (rapi-daemon)  RAPI HTTP daemon (master only).
  conf-daemon.log.gz   (conf-daemon)  config daemon (master only).
  wconf-daemon.log.gz  (wconf-daemon) write-config daemon (master only).
  jobs.log.gz          (jobs)         Ganeti jobqueue log (master only).
  commands.log.gz      (commands)     master command log (master only).
  qa-output.log.gz     (qa-output)    verbose QA output on the master.
  qa-profile.log.gz    (qa-profile)   compact list of QA test names with
                                      timecodes; compare across runs to
                                      spot timing regressions (master only).
  os/add-<provider>-<instance>-<date>.log.gz       (os-add)
                                      OS provider output for instance-add;
                                      check on instance-create failures.
  os/rename-<provider>-<old>-<new>-<date>.log.gz   (os-rename)
                                      OS provider output for instance-rename.
  kvm/<instance>.log.gz                (kvm-instance)
                                      qemu output on instance start; check
                                      when a KVM instance refuses to start
                                      (e.g. illegal qemu/kvm command line).
  xen/<instance>-<date>/...            (xen-config)
                                      generated libxl/xen config files,
                                      handed by node-daemon to xen.

Triage hints
------------
- QA failed: tail qa.log first.
- Setup never reached QA: tail playbook.log.
- KVM instance failed to start: kvm/<instance>.log.gz on the host node.
- Xen instance failed to start: xen/<instance>-<date>/ on the host node,
  plus node-daemon.log.gz on that node.
- Node-level operation failed: tail node-daemon.log.gz on the affected node.
- Cluster-wide job failed: jobs.log.gz on the master.
"""


mcp = FastMCP(
    name="ganeti-qa",
    instructions=_INSTRUCTIONS,
)


@mcp.tool()
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
    """List QA runs, newest first. All filters are optional and combine with AND."""
    return runs.list_runs(
        recipe=recipe,
        state=state,
        source_branch=source_branch,
        source_repository=source_repository,
        os_version=os_version,
        tag=tag,
        started_after=started_after,
        started_before=started_before,
        limit=limit,
    )


@mcp.tool()
def get_run(run_id_or_tag: str) -> dict:
    """Return a single run with its log inventory and embedded qa-config.json."""
    run = runs.find_run(run_id_or_tag)
    if run is None:
        raise ValueError(f"no such run: {run_id_or_tag}")
    run_id = run["id"]
    run_dir = runs.run_dir_for(run_id)
    qa_config = None
    qa_config_path = f"{run_dir}/qa-config.json"
    try:
        import json as _json
        with open(qa_config_path, "r", encoding="utf-8") as f:
            qa_config = _json.load(f)
    except (OSError, ValueError):
        qa_config = None
    return {
        "run": run,
        "logs": logs.list_logs(run_id),
        "interesting_logs": logs.interesting_logs(run_id),
        "qa_config": qa_config,
    }


@mcp.tool()
def stats(
    group_by: str = "recipe",
    started_after: Optional[float] = None,
    started_before: Optional[float] = None,
) -> dict:
    """Aggregate run counts and pass rate. group_by: recipe|state|os_version|source_branch|source_repository."""
    return runs.stats(
        group_by=group_by,
        started_after=started_after,
        started_before=started_before,
    )


@mcp.tool()
def list_recipes() -> list[dict]:
    """List available QA recipe configurations from qa-configs/."""
    return recipes.list_recipes()


@mcp.tool()
def get_recipe_config(name: str) -> dict:
    """Return the parsed qa-configs/<name>.json content."""
    out = recipes.get_recipe_config(name)
    if out is None:
        raise ValueError(f"no such recipe: {name}")
    return out


@mcp.tool()
def list_logs(run_id: str) -> list[dict]:
    """List all log files in a run with sizes, mtimes, and gzip flag."""
    return logs.list_logs(run_id)


@mcp.tool()
def read_log(
    run_id: str,
    path: str,
    start_line: int = 1,
    num_lines: int = config.READ_LOG_DEFAULT_LINES,
) -> dict:
    """Read a line range from a log. Bounded by num_lines and a byte cap."""
    return logs.read_log(run_id, path, start_line=start_line, num_lines=num_lines)


@mcp.tool()
def head_log(run_id: str, path: str, n: int = 200) -> dict:
    """Return the first n lines of a log."""
    return logs.head_log(run_id, path, n=n)


@mcp.tool()
def tail_log(run_id: str, path: str, n: int = 200) -> dict:
    """Return the last n lines of a log."""
    return logs.tail_log(run_id, path, n=n)


@mcp.tool()
def grep_log(
    run_id: str,
    path: str,
    pattern: str,
    context: int = config.GREP_DEFAULT_CONTEXT,
    max_matches: int = config.GREP_DEFAULT_MAX_MATCHES,
    ignore_case: bool = True,
) -> dict:
    """Regex search within a single log. Returns matching regions with context."""
    return logs.grep_log(
        run_id, path, pattern,
        context=context, max_matches=max_matches, ignore_case=ignore_case,
    )


@mcp.tool()
def grep_run(
    run_id: str,
    pattern: str,
    files: Optional[list[str]] = None,
    context: int = config.GREP_DEFAULT_CONTEXT,
    max_matches: int = config.GREP_DEFAULT_MAX_MATCHES,
    ignore_case: bool = True,
) -> dict:
    """Regex search across all (or selected) logs of a run. Total matches capped."""
    return logs.grep_run(
        run_id, pattern, files=files,
        context=context, max_matches=max_matches, ignore_case=ignore_case,
    )


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Ganeti QA MCP server")
    parser.add_argument("--stdio", action="store_true", help="use stdio transport instead of HTTP")
    parser.add_argument("--host", default=config.HTTP_HOST)
    parser.add_argument("--port", type=int, default=config.HTTP_PORT)
    args = parser.parse_args(argv)

    if args.stdio:
        mcp.run(transport="stdio")
    else:
        mcp.settings.host = args.host
        mcp.settings.port = args.port
        mcp.run(transport="streamable-http")
    return 0


if __name__ == "__main__":
    sys.exit(main())
