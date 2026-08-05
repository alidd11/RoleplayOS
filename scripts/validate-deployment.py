#!/usr/bin/env python3
"""Read-only checks for a safe RoleplayOS real-place deployment."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "real-baseplate.project.json"
CONFIG = ROOT / "src/shared/Config/Config.luau"
EDITABLE = ROOT / "src/shared/Config/EDIT_HERE"


def fail(message: str, errors: list[str]) -> None:
    errors.append(message)
    print(f"ERROR: {message}")


def warn(message: str) -> None:
    print(f"WARN:  {message}")


def contains_assignment(source: str, key: str, value: str) -> bool:
    return re.search(rf"\b{re.escape(key)}\s*=\s*{re.escape(value)}\b", source) is not None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--production",
        action="store_true",
        help="Fail when development-only configuration remains enabled.",
    )
    args = parser.parse_args()
    errors: list[str] = []

    project = json.loads(PROJECT.read_text(encoding="utf-8"))
    tree = project.get("tree", {})
    if "Workspace" in tree:
        fail("real-baseplate.project.json must never manage Workspace.", errors)
    if "Teams" in tree:
        fail("real-baseplate.project.json must not replace the place's Teams service.", errors)

    required_paths = (
        ("ReplicatedStorage", "RoleplayOS"),
        ("ServerScriptService", "RoleplayOS"),
        ("ServerStorage", "RoleplayOSAssets"),
        ("StarterPlayer", "StarterPlayerScripts", "RoleplayOSClient"),
    )
    for path in required_paths:
        node = tree
        for component in path:
            node = node.get(component, {})
        if not node:
            fail(f"Missing deployment mapping: {'/'.join(path)}", errors)

    def check_preservation(node: object, label: str) -> None:
        if isinstance(node, dict):
            if node.get("$ignoreUnknownInstances") is not True:
                fail(f"{label} must set $ignoreUnknownInstances to true.", errors)

    check_preservation(tree, "DataModel")
    check_preservation(tree.get("ReplicatedStorage"), "ReplicatedStorage")
    check_preservation(tree.get("ServerScriptService"), "ServerScriptService")
    check_preservation(tree.get("ServerStorage"), "ServerStorage")
    check_preservation(tree.get("StarterPlayer"), "StarterPlayer")

    config = CONFIG.read_text(encoding="utf-8")
    deployment = (EDITABLE / "01_Deployment.luau").read_text(encoding="utf-8")
    groups = (EDITABLE / "02_Groups.luau").read_text(encoding="utf-8")
    uniforms = (EDITABLE / "04_Uniforms.luau").read_text(encoding="utf-8")
    production_issues: list[str] = []
    if not re.search(r'Environment\s*=\s*"Production"', deployment):
        production_issues.append('Framework.Environment is not "Production"')
    if not contains_assignment(deployment, "UseMockDataInStudio", "false"):
        production_issues.append("UseMockDataInStudio is not false")
    if not contains_assignment(deployment, "GrantMockEmergencyAccessInStudio", "false"):
        production_issues.append("GrantMockEmergencyAccessInStudio is not false")
    if re.search(r"Control\s*=\s*\{[^}]*GroupId\s*=\s*33809042", groups, re.DOTALL):
        production_issues.append("Control still uses the temporary Universal Projects group link")
    if re.search(r'ShirtTemplate\s*=\s*""', uniforms) or re.search(
        r'TrousersTemplate\s*=\s*""', uniforms
    ):
        production_issues.append("one or more uniform template IDs are empty")

    for issue in production_issues:
        if args.production:
            fail(issue, errors)
        else:
            warn(issue)

    print(
        "PASS: deployment project does not own Workspace or Teams and preserves unknown instances."
    )
    if args.production and not errors:
        print("PASS: production configuration gate passed.")
    elif not args.production:
        print("INFO: run again with --production before publishing the staging place.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
