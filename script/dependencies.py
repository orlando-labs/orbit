#!/usr/bin/env python3
"""Resolve and verify the exact git inputs recorded for Ember releases."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "release" / "dependencies.lock.json"
DEST_ROOT = ROOT / ".build" / "dependencies"


def run(*args: str, cwd: Path | None = None, capture: bool = False) -> str:
    result = subprocess.run(
        list(args), cwd=cwd, check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def load_dependencies(scope: str) -> list[dict]:
    document = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    dependencies = document["dependencies"]
    if scope == "core":
        return [entry for entry in dependencies if entry["scope"] == "core"]
    return dependencies


def verify_checkout(entry: dict, path: Path) -> None:
    if not (path / ".git").exists():
        raise RuntimeError(f"{entry['name']}: missing git checkout at {path}")
    revision = run("git", "rev-parse", "HEAD", cwd=path, capture=True)
    tree = run("git", "rev-parse", "HEAD^{tree}", cwd=path, capture=True)
    if revision != entry["revision"]:
        raise RuntimeError(
            f"{entry['name']}: expected revision {entry['revision']}, got {revision}")
    if tree != entry["tree"]:
        raise RuntimeError(f"{entry['name']}: expected tree {entry['tree']}, got {tree}")


def source_for(entry: dict, local_source_root: Path | None) -> str:
    if local_source_root is None:
        return entry["source"]
    candidate = local_source_root / entry["name"]
    if not candidate.is_dir():
        raise RuntimeError(f"local source checkout is missing: {candidate}")
    return str(candidate)


def sync(scope: str, local_source_root: Path | None) -> None:
    DEST_ROOT.mkdir(parents=True, exist_ok=True)
    for entry in load_dependencies(scope):
        destination = DEST_ROOT / entry["name"]
        if destination.exists():
            try:
                verify_checkout(entry, destination)
                print(f"verified {entry['name']} {entry['revision']}")
                continue
            except (RuntimeError, subprocess.CalledProcessError):
                shutil.rmtree(destination)
        source = source_for(entry, local_source_root)
        run("git", "clone", "--no-checkout", "--no-hardlinks", source, str(destination))
        run("git", "checkout", "--detach", entry["revision"], cwd=destination)
        verify_checkout(entry, destination)
        print(f"resolved {entry['name']} {entry['revision']}")


def verify(scope: str) -> None:
    for entry in load_dependencies(scope):
        verify_checkout(entry, DEST_ROOT / entry["name"])
        print(f"verified {entry['name']} {entry['revision']}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("sync", "verify"))
    parser.add_argument("--scope", choices=("core", "all"), default="core")
    parser.add_argument("--local-source-root", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "sync":
            sync(args.scope, args.local_source_root)
        else:
            verify(args.scope)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"dependency resolution failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
