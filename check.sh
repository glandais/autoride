#!/usr/bin/env bash
# check.sh — the project quality gates, in the order CLAUDE.md mandates.
#
# Split out of publish_beta.sh so the gates can be run on their own: before this existed the
# only way to execute them was to start a release. publish_beta.sh now calls this script, so
# there is a single definition of what "green" means.
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

flutter pub get

# Freezed / Riverpod / json_serializable. --delete-conflicting-outputs matches the form used
# in CI and documented in CLAUDE.md.
dart run build_runner build --delete-conflicting-outputs

# Formatting gate. Enabled once the backlog it would have tripped on was cleared by the
# dart-format commit (834451f); that revision is listed in .git-blame-ignore-revs.
dart format --output=none --set-exit-if-changed lib test

flutter analyze

flutter test
