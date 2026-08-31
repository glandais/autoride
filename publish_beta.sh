#!/usr/bin/env bash
# publish_beta.sh — bump the build number, build, and upload to the Play internal track.
#
# T039 adds the iOS/TestFlight half, ahead of the Android section (a TestFlight upload takes
# longer to process, so it goes first).
#
# Design notes and the reasoning behind each guard: tasks/T038-android-release.md (D3, D4, D5).
set -euo pipefail

cd "$(dirname "$0")"

die() { echo "publish_beta.sh: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------- pre-flight

# The rollback in restore_on_failure() is `git checkout -- pubspec.yaml`, which is only safe
# on a clean tree. These two are a pair — don't remove one without the other.
[ -z "$(git status --porcelain)" ] ||
  die "working tree is not clean — commit or stash first"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "$BRANCH" in
  develop | main) ;;
  *) echo ">>> WARNING: publishing from branch '$BRANCH'"; sleep 3 ;;
esac

# Without this the release build silently falls back to the DEBUG keystore (see the fallback
# in android/app/build.gradle.kts) and Play rejects the upload after the build number is gone.
[ -f android/key.properties ] ||
  die "android/key.properties is missing — a release build would be signed with DEBUG keys"

# Project quality gates, in the order CLAUDE.md mandates.
echo ">>> Code generation"
dart run build_runner build --delete-conflicting-outputs
echo ">>> Analyze"
flutter analyze
echo ">>> Test"
flutter test

# ------------------------------------------------------------------------- version bump

grep -qE '^version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$' pubspec.yaml ||
  die "pubspec.yaml version must be exactly 'X.Y.Z+N' (see T038 D1/D4)"

ORIGINAL_VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"

# Tracks whether anything reached a store. Once a store accepts build N, N is consumed
# forever, so the rollback below must not fire after that point.
UPLOADED=""

restore_on_failure() {
  local exit_code=$?
  [ "$exit_code" -eq 0 ] && return 0
  if [ -z "$UPLOADED" ]; then
    git checkout -- pubspec.yaml
    echo ">>> Failed before any upload — rolled pubspec.yaml back to $ORIGINAL_VERSION" >&2
  else
    echo ">>> FAILED AFTER $UPLOADED accepted the build." >&2
    echo ">>> Keeping the bump: that build number is consumed and must not be reused." >&2
    echo ">>> Commit pubspec.yaml, then re-run only the platform that failed." >&2
  fi
}
trap restore_on_failure EXIT

perl -i -pe 's/^(version:\s*\d+\.\d+\.\d+\+)(\d+)\s*$/$1 . ($2 + 1) . "\n"/e' pubspec.yaml
NEW_VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
[ "$NEW_VERSION" != "$ORIGINAL_VERSION" ] ||
  die "build-number bump did not change the version (was '$ORIGINAL_VERSION')"

echo ">>> Building $NEW_VERSION"

# ------------------------------------------------------------------------------- android

# The default JDK on this machine is 25; Gradle 8.14 / AGP 9.3.0 are not validated against it
# and the mismatch surfaces as opaque Kotlin/AGP errors, not a clear "unsupported JDK".
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
export PATH="$JAVA_HOME/bin:$PATH"

flutter build appbundle --release
(cd android && { bundle check >/dev/null 2>&1 || bundle install; })
(cd android && bundle exec fastlane internal --verbose)
UPLOADED="Play internal"

# -------------------------------------------------------------------- record the release

git add pubspec.yaml
git commit -m "chore(release): $NEW_VERSION"
git tag "v$NEW_VERSION"

echo ">>> Published $NEW_VERSION to: $UPLOADED"
echo ">>> Tagged v$NEW_VERSION — push with: git push && git push --tags"
