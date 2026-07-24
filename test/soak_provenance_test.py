#!/usr/bin/env python3
"""Regression coverage for soak source-tree provenance."""

from __future__ import annotations

import runpy
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
git_worktree_state = runpy.run_path(str(ROOT / "script/soak"))[
    "git_worktree_state"
]


def git(root: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=root,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def expect(
    root: Path,
    tracked_changes: bool,
    untracked_files: bool,
    message: str,
) -> None:
    actual = git_worktree_state(root)
    expected = (tracked_changes, untracked_files)
    if actual != expected:
        raise AssertionError(f"{message}: expected {expected}, got {actual}")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="ember-soak-provenance-") as path:
        root = Path(path)
        git(root, "init", "-q")
        git(root, "config", "user.email", "soak-test@example.invalid")
        git(root, "config", "user.name", "Soak Test")
        (root / ".gitignore").write_text("ignored/\n", encoding="utf-8")
        (root / "tracked.txt").write_text("committed\n", encoding="utf-8")
        git(root, "add", ".gitignore", "tracked.txt")
        git(root, "commit", "-q", "-m", "fixture")

        expect(root, False, False, "clean checkout")

        (root / "ignored").mkdir()
        (root / "ignored/artifact.txt").write_text("ignored\n", encoding="utf-8")
        expect(root, False, False, "ignored artifacts")

        (root / "untracked.txt").write_text("local\n", encoding="utf-8")
        expect(root, False, True, "untracked files do not dirty tracked state")

        (root / "tracked.txt").write_text("modified\n", encoding="utf-8")
        expect(root, True, True, "unstaged tracked change")

        git(root, "add", "tracked.txt")
        expect(root, True, True, "staged tracked change")

    print("soak_provenance_test: ok")


if __name__ == "__main__":
    main()
