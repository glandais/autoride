#!/usr/bin/env bash
# publish_beta.sh — bump the build number, build, and upload to TestFlight and the Play
# internal track. iOS goes first: TestFlight processing is asynchronous and slow to start, so
# kicking it off ahead of the Android build overlaps the two.
#
# Design notes and the reasoning behind each guard: tasks/T038-android-release.md (D3, D4, D5)
# for the Android half, tasks/T039-ios-release.md (D1, D3) for the iOS half.
set -euo pipefail

cd "$(dirname "$0")"

die() { echo "publish_beta.sh: $*" >&2; exit 1; }

# Use the Homebrew Ruby (which carries the bundler version pinned in each fastlane
# Gemfile.lock) instead of the macOS system Ruby.
if command -v brew >/dev/null 2>&1; then
  export PATH="$(brew --prefix ruby)/bin:$PATH"
fi

# Each Gemfile.lock pins a bundler version (BUNDLED WITH). A Homebrew Ruby upgrade removes
# that gem's directory while leaving its gemspec behind, so the `bundle` shim dies with a
# LoadError before it even parses a subcommand. Reinstall the pinned version when the shim can
# no longer run. Call this from the directory holding the Gemfile.lock.
ensure_bundler() {
  bundle --version >/dev/null 2>&1 && return 0
  local pinned
  pinned=$(awk '/^BUNDLED WITH$/ { getline; gsub(/[[:space:]]/, ""); print; exit }' Gemfile.lock)
  echo ">>> bundler $pinned unusable in $(pwd), reinstalling"
  gem install bundler -v "$pinned"
}

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

# The iOS lanes authenticate with an App Store Connect API key. Without these, fastlane falls
# through to an interactive Apple ID prompt in the middle of the run (see T039 Step 7).
[ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ] ||
  die "ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH must be set (see T039 Step 7)"

# Get both Ruby sides ready first: a missing gem is a five-second failure, and there is no
# reason to discover it after a four-minute build.
(cd ios && ensure_bundler && { bundle check >/dev/null 2>&1 || bundle install; })
(cd android && ensure_bundler && { bundle check >/dev/null 2>&1 || bundle install; })

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

# ----------------------------------------------------------------------------------- ios

# This builds App.framework and the Dart assets; fastlane's build_app then archives and signs.
# Two compilations, but it is the supported flutter + fastlane split — dropping the first step
# leaves build_app with nothing to archive.
flutter build ios --release --no-codesign
(cd ios && bundle exec fastlane beta --verbose)
UPLOADED="TestFlight"

# ------------------------------------------------------------------------------- android

# The default JDK on this machine is 25; Gradle 9.7.1 / AGP 9.3.2 are not validated against it
# and the mismatch surfaces as opaque Kotlin/AGP errors, not a clear "unsupported JDK".
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
export PATH="$JAVA_HOME/bin:$PATH"

flutter build appbundle --release
(cd android && bundle exec fastlane internal --verbose)
# Accumulate rather than overwrite, so the failure trap names every store that already took
# this build number.
UPLOADED="${UPLOADED:+$UPLOADED + }Play internal"

# -------------------------------------------------------------------- record the release

git add pubspec.yaml
git commit -m "chore(release): $NEW_VERSION"

# The keep-the-bump recovery path (a re-run after a partial failure) can reach this point with
# the tag already created, and `git tag` on an existing name exits 1 — after both uploads.
if git rev-parse -q --verify "refs/tags/v$NEW_VERSION" >/dev/null; then
  echo ">>> Tag v$NEW_VERSION already exists — leaving it in place"
else
  git tag "v$NEW_VERSION"
fi

echo ">>> Published $NEW_VERSION to: $UPLOADED"
echo ">>> Tagged v$NEW_VERSION — push with: git push && git push --tags"
