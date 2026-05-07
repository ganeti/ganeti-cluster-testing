import json
import os
from typing import Optional

from . import config


def list_recipes() -> list[dict]:
    out = []
    try:
        entries = sorted(os.listdir(config.RECIPES_DIR))
    except OSError:
        return out
    for name in entries:
        if not name.endswith(".json"):
            continue
        path = os.path.join(config.RECIPES_DIR, name)
        if not os.path.isfile(path):
            continue
        out.append({
            "name": name[:-len(".json")],
            "path": path,
        })
    return out


def get_recipe_config(name: str) -> Optional[dict]:
    if "/" in name or name.startswith("."):
        raise ValueError("invalid recipe name")
    path = os.path.join(config.RECIPES_DIR, name + ".json")
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        return {"name": name, "path": path, "config": json.load(f)}
