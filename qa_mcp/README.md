# Ganeti QA MCP server

Read-only MCP server exposing the data produced by `run-cluster-test.py` under
`/var/lib/ganeti-qa/` so AI agents can inspect QA runs and logs.

## Install

```
python3 -m venv /opt/qa-mcp/venv
/opt/qa-mcp/venv/bin/pip install -r requirements.txt
```

## Run

Streamable HTTP (default), bound to `127.0.0.1:8765`:

```
/opt/qa-mcp/venv/bin/python -m qa_mcp.server
```

stdio transport (for local development or `ssh user@host -- python -m qa_mcp.server --stdio`):

```
python -m qa_mcp.server --stdio
```

Environment variables:

- `GANETI_QA_ROOT` (default `/var/lib/ganeti-qa`)
- `QA_MCP_HOST` (default `127.0.0.1`)
- `QA_MCP_PORT` (default `8765`)

## Tools

| Tool | Purpose |
| --- | --- |
| `list_runs` | Filter runs by recipe/state/branch/etc., newest first. |
| `get_run` | Single run with log inventory and embedded `qa-config.json`. |
| `stats` | Aggregate counts + pass rate grouped by recipe/state/os/branch. |
| `list_recipes` / `get_recipe_config` | Inspect `qa-configs/*.json`. |
| `list_logs` | All log files for a run with sizes and mtimes. |
| `read_log` | Line-range read, bounded by line and byte caps. |
| `head_log` / `tail_log` | First/last N lines (common error-localisation pattern). |
| `grep_log` | Regex search within one log, with context lines. |
| `grep_run` | Regex search across all logs of a run, total matches capped. |

All log access is constrained to paths under the run's directory. `..` and
absolute paths are rejected.

## systemd unit

```
[Unit]
Description=Ganeti QA MCP server
After=network.target

[Service]
Type=simple
User=qa-mcp
Group=qa-mcp
ExecStart=/opt/qa-mcp/venv/bin/python -m qa_mcp.server
WorkingDirectory=/opt/qa-mcp/ganeti-cluster-testing
Restart=on-failure
ProtectSystem=strict
ReadOnlyPaths=/var/lib/ganeti-qa /opt/qa-mcp
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

The user `qa-mcp` only needs read access to `/var/lib/ganeti-qa` and the repo's
`qa-configs/`.

## Caddy 1.0.4 reverse proxy

Caddy fronts the server — the MCP process listens only on loopback. Add to
your existing `Caddyfile` block:

```
proxy /mcp 127.0.0.1:8765 {
    transparent
    websocket
    without /mcp
}
```

The QA data is public, so auth is not required. If you want to gate access
anyway (e.g. to rate-limit casual crawlers, since `grep_*` runs regex over
gzipped logs), add a `basicauth` directive:

```
basicauth /mcp/* {
    aiagent <BCRYPT_HASH>
}
```

Generate the bcrypt hash with `caddy -plugin http.basicauth -hash-password`
(Caddy 1.x) or any bcrypt tool. For token-only access, use a `header` matcher
checking `Authorization` instead.

## Caveats

- Pure filesystem reads, no database. `list_runs` does an `os.listdir` per call
  with parsed-`run.json` LRU caching keyed on `(path, mtime_ns)`.
- First `read_log`/`tail_log` on a large gzipped log streams it once to compute
  `total_lines`; subsequent calls hit the cache.
- The server never writes to `/var/lib/ganeti-qa/` and never invokes
  `run-cluster-test.py`.
