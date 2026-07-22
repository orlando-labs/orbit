#!/usr/bin/env python3
"""Static release, documentation, package-lock, and public-API checks."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def exported_names(path: Path) -> tuple[str, set[str]]:
    source = path.read_text(encoding="utf-8")
    package_match = re.search(r"^package\s+([\w.]+)\s*$", source, re.MULTILINE)
    if not package_match:
        raise ValueError(f"missing package declaration: {path}")
    names: set[str] = set()
    for match in re.finditer(r"^export(?:\s+macro)?\s+(.+)$", source, re.MULTILINE):
        names.update(name.strip() for name in match.group(1).split(","))
    return package_match.group(1), names


def check_public_api(errors: list[str]) -> None:
    manifest = json.loads((ROOT / "release/public-api.json").read_text(encoding="utf-8"))
    reference = (ROOT / "docs/API_REFERENCE.md").read_text(encoding="utf-8")
    sources = list((ROOT / "src").rglob("*.am"))
    sources += list((ROOT / "packages/ember-orm/src").rglob("*.am"))
    actual: dict[str, set[str]] = {}
    for source in sources:
        package, names = exported_names(source)
        actual[package] = names
    declared_modules = manifest["modules"]
    if set(actual) != set(declared_modules):
        fail(errors, f"public API module inventory differs: source={sorted(actual)}, manifest={sorted(declared_modules)}")
    for package, section in declared_modules.items():
        declared = set(section["public"]) | set(section["internal_exports"])
        if actual.get(package, set()) != declared:
            fail(errors, f"{package}: export inventory differs: source={sorted(actual.get(package, set()))}, declared={sorted(declared)}")
        for name in section["public"]:
            if not re.search(rf"(?<![\w]){re.escape(name)}(?![\w])", reference):
                fail(errors, f"{package}.{name}: missing from API reference")


def check_links(errors: list[str]) -> None:
    markdown_files = [ROOT / "README.md", ROOT / "CHANGELOG.md", ROOT / "SECURITY.md"]
    markdown_files += list((ROOT / "docs").rglob("*.md"))
    link_pattern = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
    for path in markdown_files:
        source = path.read_text(encoding="utf-8")
        for raw_target in link_pattern.findall(source):
            target = raw_target.split("#", 1)[0].strip()
            if not target or re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                continue
            resolved = (path.parent / unquote(target)).resolve()
            if ROOT not in resolved.parents and resolved != ROOT:
                fail(errors, f"{path.relative_to(ROOT)}: link escapes repository: {raw_target}")
            elif not resolved.exists():
                fail(errors, f"{path.relative_to(ROOT)}: broken local link: {raw_target}")


def package_lock(amberc: Path, manifest: Path) -> str:
    result = subprocess.run(
        [str(amberc), "package-lock", str(manifest)], cwd=ROOT,
        check=True, text=True, stdout=subprocess.PIPE,
    )
    return result.stdout


def check_release_files(errors: list[str], amberc: Path | None) -> None:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        fail(errors, f"VERSION is not SemVer: {version}")
    for path in (ROOT / "amber.toml", ROOT / "packages/ember-orm/amber.toml"):
        source = path.read_text(encoding="utf-8")
        if f'version = "{version}"' not in source:
            fail(errors, f"{path.relative_to(ROOT)} does not match VERSION")
    api = json.loads((ROOT / "release/public-api.json").read_text(encoding="utf-8"))
    deps = json.loads((ROOT / "release/dependencies.lock.json").read_text(encoding="utf-8"))
    if api["version"] != version or deps["ember_version"] != version:
        fail(errors, "machine-readable release manifests do not match VERSION")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"[{version}]" not in changelog:
        fail(errors, "CHANGELOG has no current version entry")
    tracked = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE,
    ).stdout.splitlines()
    tracked_text = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for relative in tracked
        if (path := ROOT / relative).is_file()
        and path != ROOT / "script/stage5_checks.py"
    )
    for forbidden in ("../../amber-orm", "../../sqlite3-amber", "../amber-lang/build/amberc"):
        if forbidden in tracked_text:
            fail(errors, f"tracked release path still contains sibling dependency: {forbidden}")
    required = [
        "LICENSE", "SECURITY.md", "CHANGELOG.md", "docs/API_REFERENCE.md",
        "docs/CONFIGURATION.md", "docs/RUNBOOK.md", "docs/MIGRATION_1_0.md",
        "docs/RELEASING.md", "deploy/nginx.conf", "deploy/systemd/ember.service",
        "deploy/kubernetes/ember.yaml", ".github/workflows/ci.yml",
        ".github/workflows/release.yml",
    ]
    for relative in required:
        if not (ROOT / relative).is_file():
            fail(errors, f"missing stage-5 deliverable: {relative}")
    if amberc:
        pairs = [
            (ROOT / "amber.toml", ROOT / "amber.lock"),
            (ROOT / "packages/ember-orm/amber.toml", ROOT / "packages/ember-orm/amber.lock"),
        ]
        for manifest, lock in pairs:
            generated = package_lock(amberc, manifest)
            if generated != lock.read_text(encoding="utf-8"):
                fail(errors, f"stale generated lock: {lock.relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--amberc", type=Path)
    args = parser.parse_args()
    errors: list[str] = []
    try:
        check_release_files(errors, args.amberc)
        check_links(errors)
        check_public_api(errors)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        errors.append(str(error))
    if errors:
        for error in errors:
            print(f"stage5 check failed: {error}", file=sys.stderr)
        return 1
    print("stage5 static checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
