#!/usr/bin/env python3
"""Restore missing and zero-byte tracked source/resources from pinned StreamVault.

Does not overwrite non-empty DreamCAST changes. Produces an audit of repairs.
Run from the DreamCAST repo root, on a generated workspace.
"""
from pathlib import Path
import argparse
import subprocess
import shutil
import sys
import xml.etree.ElementTree as ET

PIN = "bc32f389b37969e387df83df032d2a8235024222"
SOURCE_TYPES = {".kt", ".java", ".xml"}
SKIP_TOP = {"validation", "docs", "tools", "benchmark", "build"}
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--workspace", type=Path)
    args = parser.parse_args()
    repo = args.repo.expanduser().resolve()
    upstream = repo / "AndroidTV/StreamVault"
    workspace = (args.workspace or repo / "AndroidTV/DreamCAST-StreamVault").expanduser().resolve()
    if not (workspace / "settings.gradle.kts").exists():
        raise SystemExit(f"Workspace not found: {workspace}")
    if not upstream.exists():
        raise SystemExit("Missing StreamVault submodule; run git submodule update --init --recursive")
    version = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
    if version != PIN:
        raise SystemExit(f"Wrong upstream revision: {version}; expected {PIN}")

    tracked = subprocess.check_output(
        ["git", "-C", str(upstream), "ls-files", "-z"]
    ).split(b"\0")
    candidates = []
    for raw in tracked:
        if not raw:
            continue
        rel = Path(raw.decode("utf-8"))
        if rel.parts[0] in SKIP_TOP or rel.suffix.lower() not in SOURCE_TYPES:
            continue
        if "src" not in rel.parts:
            continue
        source = upstream / rel
        dest = workspace / rel
        if not source.is_file() or source.stat().st_size == 0:
            continue
        if not dest.exists() or (dest.is_file() and dest.stat().st_size == 0):
            candidates.append((source, dest, rel))

    if not candidates:
        print("No missing or empty tracked source/resource files found.")
        return

    print(f"Restoring {len(candidates)} missing or zero-byte files from the pinned source:")
    for source, dest, rel in candidates:
        if dest.exists() and not dest.is_file():
            raise SystemExit(f"Unexpected non-file at {dest}. No changes made.")
        print("  ", rel)
    for source, dest, rel in candidates:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)

    remaining = []
    for path in workspace.glob("**/src/main/res/values*/*.xml"):
        if path.is_file() and path.stat().st_size == 0:
            remaining.append(str(path.relative_to(workspace)))
    if remaining:
        print("Warning: additional empty resource files were not tracked upstream:")
        for path in remaining:
            print(" ", path)
    print("Repair complete. Existing non-empty work was left unchanged.")
    print("Next: cd AndroidTV/DreamCAST-StreamVault && ./gradlew :app:assembleDebug --no-configuration-cache")

if __name__ == "__main__":
    main()
