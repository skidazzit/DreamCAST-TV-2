#!/bin/bash
# Prepares a fresh git worktree of Lume. Run it from inside the worktree.
#
# Deliberately cheap: the git hooks live in the shared .git/hooks and the
# pre-commit tools run from the main checkout's .build/tools
# (Scripts/lint-tool.sh), so nothing here builds a SwiftPM package.
#
#   Scripts/worktree.sh            # secrets, .claude, test fixtures — seconds
#   Scripts/worktree.sh --build    # also warm /tmp/lume-dd-<worktree>
#
# The warm-up build is opt-in because agents build into their own
# -derivedDataPath (/tmp/lume-dd-ios, -test, -w<n>…), so it cost ~85 s and
# ~2 GB per worktree that no later build reused.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
MAIN="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
if [ "$MAIN" = "$PWD" ]; then
  echo "Run this from a worktree, not the main checkout." >&2
  exit 1
fi

cp "$MAIN/.env" .env 2>/dev/null || echo "warning: no .env in $MAIN — secrets not injected"
cp -R "$MAIN/.claude/" .claude/
# DTODecodingTests read these gitignored fixtures from the repo root.
if [ -d "$MAIN/ExampleData" ] && [ ! -e ExampleData ]; then
  ln -s "$MAIN/ExampleData" ExampleData
fi

# Install the hooks once, from the main checkout (see Scripts/setup.sh).
HOOK="$(git rev-parse --path-format=absolute --git-path hooks)/pre-commit"
grep -qF "$MAIN/.build/lefthook/" "$HOOK" 2>/dev/null || Scripts/setup.sh

[ "${1:-}" = "--build" ] || exit 0

# Private DerivedData per worktree: without it this build shares Xcode's own
# DerivedData for the project, and re-resolving the package graph underneath an
# open Xcode leaves it stuck on "Missing package product 'LumeEngine'".
# Pair it with the shared package clone (see CLAUDE.md) so each dir does not
# re-clone the 6.4 GB package graph.
DD="/tmp/lume-dd-$(basename "$PWD")"
# FFmpeg.xcframework (LumeEngine) ships arm64 slices only, so pin the arch —
# a bare `generic/platform=iOS Simulator` also builds x86_64 and fails to link.
xcodebuild build -scheme DreamCAST-iOS -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' ARCHS=arm64 \
  -derivedDataPath "$DD" \
  -clonedSourcePackagesDirPath ~/Library/Developer/Lume-SharedSPM -quiet
