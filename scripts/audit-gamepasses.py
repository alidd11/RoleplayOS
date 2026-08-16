#!/usr/bin/env python3
"""Read-only live audit of configured Roblox game-pass products."""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "src/shared/Config/EDIT_HERE/03_Gamepasses.luau"
EXPECTED_CREATOR_ID = 33809042


def main() -> int:
    source = CONFIG.read_text(encoding="utf-8")
    configured = {
        name: int(gamepass_id)
        for name, gamepass_id in re.findall(
            r"^\s*([A-Za-z0-9_]+)\s*=\s*\{\s*GamepassId\s*=\s*(\d+)",
            source,
            re.MULTILINE,
        )
    }
    failures = 0
    for config_name, gamepass_id in sorted(configured.items()):
        if gamepass_id <= 0:
            print(f"INFO:  {config_name} is disabled until a GamepassId is configured")
            continue
        url = (
            "https://apis.roblox.com/game-passes/v1/game-passes/"
            f"{gamepass_id}/product-info"
        )
        try:
            with urllib.request.urlopen(url, timeout=10) as response:
                product = json.load(response)
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as problem:
            failures += 1
            print(f"ERROR: {config_name} ({gamepass_id}) could not be read: {problem}")
            continue
        creator = product.get("Creator") or {}
        problems: list[str] = []
        if creator.get("CreatorTargetId") != EXPECTED_CREATOR_ID:
            problems.append("wrong creator")
        if product.get("IsForSale") is not True:
            problems.append("not for sale")
        price = product.get("PriceInRobux")
        if not isinstance(price, int) or price <= 0:
            problems.append("no positive Robux price")
        if problems:
            failures += 1
            print(
                f"ERROR: {config_name} ({gamepass_id}) — "
                + ", ".join(problems)
                + f"; Roblox name={product.get('Name')!r}"
            )
        else:
            print(
                f"PASS:  {config_name} ({gamepass_id}) — "
                f"{price} Robux; Roblox name={product.get('Name')!r}"
            )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
