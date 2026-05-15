#!/usr/bin/env python3

import os
import json
import datetime
from datetime import timezone
import time
from jinja2 import Environment, FileSystemLoader, select_autoescape

WEB_PATH = "/var/lib/ganeti-qa/"

STATE_IMAGES = {
    "running": "progress.svg",
    "failed": "alert.svg",
    "alloc-failed": "alert.svg",
    "setup-failed": "alert.svg",
    "canceled": "alert.svg",
    "finished": "ok.svg",
}

STATE_LABELS = {
    "running": "Running",
    "finished": "Finished",
    "failed": "Failed",
    "alloc-failed": "Alloc Failed",
    "setup-failed": "Setup Failed",
    "canceled": "Canceled",
    "built": "Built",
    "removed": "Removed",
    "timed-out": "Timed Out",
}


def fmt_duration(seconds):
    return time.strftime("%H:%M", time.gmtime(seconds)) if seconds > 0 else "—"


def main():
    ganeti_runs = []
    for entry in os.listdir(WEB_PATH):
        run_dir = os.path.join(WEB_PATH, entry)
        if os.path.isdir(run_dir):
            run_id = os.path.basename(run_dir)
            run_path = os.path.join(run_dir, "run.json")
            if os.path.exists(run_path):
                with open(run_path) as f:
                    ganeti_runs.append(json.load(f))
                    ganeti_runs[-1]["id"] = run_id

    ganeti_runs.sort(reverse=True, key=lambda x: x["started"])

    template_data = []
    for run in ganeti_runs:
        start_ts = datetime.datetime.fromtimestamp(run["started"], timezone.utc)
        template_data.append({
            "started": start_ts.strftime("%Y-%m-%d %H:%M UTC"),
            "started_unix": int(run["started"]),
            "state": run["state"],
            "state_label": STATE_LABELS.get(run["state"], run["state"]),
            "tag": run.get("tag", "n/a"),
            "state_image": STATE_IMAGES.get(run["state"], "blah"),
            "os_version": run["os-version"],
            "source_repository": run["source-repository"],
            "source_branch": run["source-branch"],
            "recipe": run["recipe"],
            "log_folder_link": "/{}".format(run["id"]),
            "duration": fmt_duration(run.get("runtimes", {}).get("overall", 0)),
            "instance_create_duration": fmt_duration(run.get("runtimes", {}).get("instance-create", 0)),
            "playbook_duration": fmt_duration(run.get("runtimes", {}).get("playbook", 0)),
            "qa_duration": fmt_duration(run.get("runtimes", {}).get("qa", 0)),
        })

    env = Environment(
        loader=FileSystemLoader(os.path.dirname(os.path.realpath(__file__))),
        autoescape=select_autoescape(),
    )
    template = env.get_template("index.html.j2")
    now = datetime.datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    index_html = template.render(runs=template_data, now=now)
    with open(os.path.join(WEB_PATH, "index.html"), "w") as f:
        f.write(index_html)


if __name__ == "__main__":
    main()
