#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
dart format lib test integration_test tool
flutter analyze
flutter test --dart-define=SWIFTDROP_TEST=true --reporter expanded
