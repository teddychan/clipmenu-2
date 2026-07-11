#!/bin/sh
# Canonical test command for ClipMenu.
#
# Runs SERIALLY (--no-parallel) on purpose: several test suites exercise
# process-global singletons — NSPasteboard.general (Paster / PasteboardReader /
# ActionEngine / BuiltInActions tests) and the shared UserDefaults.standard backup
# baseline — which Swift Testing's default cross-suite parallelism would race.
# Swift Testing's `.serialized` trait only orders tests *within* a suite, not
# across suites, so serial execution is what keeps the run deterministic.
#
# Usage: app/scripts/test.sh [extra swift-test args]
#   app/scripts/test.sh --enable-code-coverage
#   app/scripts/test.sh --filter BackupManagerTests
set -e
cd "$(dirname "$0")/.."
# Sparkle stays unlinked for tests (matches CI); arm64 per the single-slice policy.
CLIPMENU_SPARKLE= exec swift test --arch arm64 --no-parallel "$@"
