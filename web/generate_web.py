#!/usr/bin/env python3

import os
import json
import datetime
from datetime import timezone
import time
from jinja2 import Environment, FileSystemLoader, select_autoescape

WEB_PATH = "/var/lib/ganeti-qa/"

ganeti_runs = []
for file in os.listdir(WEB_PATH):
    d = os.path.join(WEB_PATH, file)
    if os.path.isdir(d):
        id = os.path.basename(d)
        run_path = d + "/run.json"
        if os.path.exists(run_path):
            with open(run_path) as f:
                ganeti_runs.append(json.load(f))
                ganeti_runs[-1]["id"] = id

ganeti_runs.sort(reverse=True, key=lambda x: x["started"])
template_data = []
for run in ganeti_runs:
    start_ts = datetime.datetime.fromtimestamp(run["started"], timezone.utc)
    if run["state"] == "running":
        image = "progress.svg"
    elif run["state"] == "failed":
        image = "alert.svg"
    elif run["state"] == "finished":
        image = "ok.svg"
    else:
        image = "blah"

    if "tag" in run:
        tag = run["tag"]
    else:
        tag = "n/a"

    seconds_format = time.gmtime(run["runtimes"]["overall"])

    template_data.append({
        "started": start_ts.strftime("%Y-%m-%d %H:%M:%S UTC"),
        "state": run["state"],
        "tag": tag,
        "state_image": image,
        "os_version": run["os-version"],
        "source_repository": run["source-repository"],
        "source_branch": run["source-branch"],
        "recipe": run["recipe"],
        "log_folder_link": "/{}".format(run["id"]),
        "duration": time.strftime("%H:%M:%S", seconds_format)
    })
env = Environment(
    loader=FileSystemLoader(os.path.dirname(os.path.realpath(__file__))),
    autoescape=select_autoescape()
)

template = env.get_template("index.html.j2")
dt = datetime.datetime.now(timezone.utc)
utc_time = dt.replace(tzinfo=timezone.utc)
now = utc_time.strftime("%Y-%m-%d %H:%M:%S UTC")

index_html = template.render(runs=template_data, now=now)
with open(WEB_PATH + "index.html","w") as f:
    f.write(index_html)

