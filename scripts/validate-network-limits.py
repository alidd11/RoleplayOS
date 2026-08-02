#!/usr/bin/env python3
"""Fail when a server RemoteFunction lacks an explicit rate-limit policy."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
NETWORK = ROOT / "src/server/Services/NetworkService.luau"
CONFIG = ROOT / "src/shared/Config/Config.luau"

endpoint_pattern = re.compile(r'RegisterFunction\(\s*"([^"]+)"')
limit_pattern = re.compile(
    r"^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*\{\s*Capacity\s*=",
    re.MULTILINE,
)


def duplicates(values: list[str]) -> list[str]:
    return sorted({value for value in values if values.count(value) > 1})


endpoints = endpoint_pattern.findall(NETWORK.read_text(encoding="utf-8"))
limits = limit_pattern.findall(CONFIG.read_text(encoding="utf-8"))
problems: list[str] = []

for name in duplicates(endpoints):
    problems.append(f"duplicate registered endpoint: {name}")
for name in duplicates(limits):
    problems.append(f"duplicate endpoint rate limit: {name}")
for name in sorted(set(endpoints) - set(limits)):
    problems.append(f"missing explicit endpoint rate limit: {name}")
for name in sorted(set(limits) - set(endpoints)):
    problems.append(f"stale endpoint rate limit without registered function: {name}")

if problems:
    for problem in problems:
        print(f"ERROR: {problem}", file=sys.stderr)
    raise SystemExit(1)

print(f"Network rate-limit coverage is complete for {len(endpoints)} endpoints.")
