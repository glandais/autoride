# T038 - Android Release Configuration

**Status**: ⏳ In Progress — all in-repo work shipped in `a945fa3`; only the manual Play Console
items remain (see "Remaining" in `TASKS.md`). The **Overview** and **Current Implementation
Status** sections below describe the tree *before* `a945fa3` and are kept as the task's rationale:
debug-keystore signing, the missing build number and the absent distribution mechanism are all
fixed as of that commit.
**Estimated Time**: 3-4 hours (revised up from 2h in TASKS.md — versioning + publish script were not in the original scope estimate)
**Dependencies**: T033 (Code Quality), T036 (App Icons & Splash Screen)
**Phase**: 10 - Release Preparation

---

## Overview

Make `flutter build appbundle --release` produce an artifact that Google Play will actually
accept, and give the project a repeatable, guarded path to the Play **internal testing** track.

Three things are broken or missing today, in order of severity:

1. Release builds are signed with the **debug** keystore — Play rejects these outright.
2. There is no build number, so `versionCode` is permanently `1` — Play accepts exactly one
   upload, ever.
3. There is no distribution mechanism at all — no fastlane, no script, no listing metadata.

This task fixes all three. iOS is T039; the two tasks share the version scheme and the publish
script, and **T038 must land first** because it creates both.

---

## Reference Implementation

The sibling project `../tribly/mobile` has shipped 23 builds through a local shell + fastlane
pipeline. This task reuses its structure deliberately:

| Borrowed from tribly | Where |
|---|---|
| `key.properties` read in Gradle with a debug fallback | `android/app/build.gradle.kts:17-21, 36-44, 57-63` |
| `key.properties.example` committed, real file + keystore gitignored | `android/.gitignore` |
| `pubspec.yaml` as the single source of both `versionCode` and `CFBundleVersion` | `publish_test.sh` |
| Build-number bump by in-place `perl` on pubspec | `publish_test.sh` |
| `JAVA_HOME` pinned via `/usr/libexec/java_home` | `publish_test.sh` |
| fastlane per platform, each with its own `Gemfile`/`Gemfile.lock` | `android/`, `ios/` |
| Play listing text + screenshots under git in `fastlane/metadata/` | `android/fastlane/metadata/` |
| `skip_upload_metadata`/`_images`/`_screenshots` on the internal lane | `android/fastlane/Fastfile` |

**Two things we deliberately do differently** (both are real defects in tribly, see
"Design Decisions" below):

- tribly's bump can fail silently and leaves `pubspec.yaml` dirty when a build fails, which
  burns build numbers (its history shows `+17 → +19`). We add a format guard, a
  did-it-change assertion, and a rollback trap.
- tribly's `publish_test.sh` runs no checks and doesn't inspect git state, so a WIP tree can be
  published. We gate on a clean tree plus the project's own quality gates.

---

## Current Implementation Status

### ✅ What Exists

1. **Gradle build works** — `android/app/build.gradle.kts`, AGP 9.3.0, Gradle 8.14,
   Kotlin 2.4.10, JVM target 17, core library desugaring for `flutter_local_notifications`.
2. **Application ID is real** — `io.github.glandais.autoride` (not the template default).
3. **Secrets already gitignored** — `android/.gitignore:11-13` covers `key.properties`,
   `**/*.keystore`, `**/*.jks`.
4. **README documents the intent** — `README.md:233-247` already describes generating a
   keystore and creating `android/key.properties`.
5. **Manifest is production-ready** (T028) — permissions, `foregroundServiceType="location"`,
   `allowBackup="false"` with rationale.

### ❌ What's Missing

1. `android/app/build.gradle.kts:35-37` — `// TODO: Add your own signing config` and
   `signingConfig = signingConfigs.getByName("debug")`.
2. **Nothing reads `key.properties`.** Following the README today silently produces a
   debug-signed release — the worst possible failure mode, because it looks like it worked.
3. `pubspec.yaml:4` is `version: 1.0.0` with no `+N`. Verified consequence:
   `updateLocalProperties` (`flutter_tools/lib/src/android/gradle_utils.dart:1186-1192`)
   *removes* `flutter.versionCode` when the manifest has no build number, and
   `FlutterPlugin.kt:133` then falls back to the literal `"1"`.
4. No `android/key.properties.example`.
5. No fastlane: no `Gemfile`, no `Fastfile`, no `Appfile`, no `metadata/`.
6. No publish script.
7. No ProGuard/R8 configuration.
8. `minSdk = flutter.minSdkVersion` resolves to **24** (Android 7.0), while `CLAUDE.md` claims
   "Android 8+ (API 26+)".
9. `AndroidManifest.xml:110` — `android:label="autoride"` (lowercase); `README.md:1` and iOS
   both brand the app differently. Three spellings, no canonical one.
10. `README.md:51` tells users to download an APK from Releases. There are zero git tags and
    zero GitHub releases.

---

## Design Decisions

### D1: `pubspec.yaml` is the single source of truth for versions

`version: X.Y.Z+N` feeds both platforms with no duplication:

- Android: `flutter.versionName` / `flutter.versionCode` → `defaultConfig` (already wired in
  `build.gradle.kts:29-30`).
- iOS: `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` → `CFBundleShortVersionString` /
  `CFBundleVersion` (already wired in `Info.plist`).

Do **not** set `versionCode` in Gradle or `CURRENT_PROJECT_VERSION` in the pbxproj by hand.
`X.Y.Z` is the user-visible marketing version, bumped manually when the release warrants it.
`N` is a monotonic counter bumped by the script on every upload, never reset.

> Note: autoride's pbxproj is already correct here (`CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER)`).
> tribly has a stale hardcoded `1.0.0` in the same slot. Don't copy that part.

### D2: The keystore lives outside the repository, forever

Losing the upload keystore means losing the ability to update the app (unless Play App Signing
key rotation is enabled). Store it outside the working tree and back it up somewhere durable.
`key.properties` holds absolute paths and passwords and is never committed;
`key.properties.example` documents the shape.

### D3: Debug fallback is kept, but must be loud

Gradle keeps tribly's `if (keystorePropertiesFile.exists())` fallback to the debug config so
`flutter run --release` works on a fresh clone without secrets. But a *debug-signed bundle
that reaches a store upload* is the failure we're fixing, so the publish script asserts
`key.properties` exists before building. Gradle stays permissive; the release path does not.

### D4: The bump is guarded and reversible

Three failure modes tribly has, and the fix for each:

| Failure | Fix |
|---|---|
| pubspec version isn't `X.Y.Z+N` → `perl` no-ops, exit 0, build ships the old number | Regex guard *before* the bump |
| Bump silently doesn't apply | Assert `NEW_VERSION != ORIGINAL_VERSION` after |
| Build fails after the bump → dirty pubspec, next run double-bumps | `trap` rolls back **only if no upload succeeded** |

That last condition matters and is not just tidiness: once TestFlight or Play has *accepted*
build `N`, `N` is consumed forever. Rolling back then would guarantee a rejection on the retry.
So the trap tracks whether any upload landed, and keeps the bump if one did.

The rollback uses `git checkout -- pubspec.yaml`, which is only safe because the pre-flight
requires a clean working tree. The two are a pair — don't remove the clean-tree check.

### D5: The script commits and tags on success

The bump is committed as `chore(release): X.Y.Z+N` and tagged `vX.Y.Z+N` only after every
upload succeeded. This is what makes a store build traceable back to a commit — the thing
tribly does by hand and occasionally forgets.

> This does **not** conflict with the "NEVER commit autonomously" rule in `CLAUDE.md`. That rule
> constrains Claude, not the user. `publish_beta.sh` is run by the user, and the commit it makes
> is a mechanical release-bookkeeping commit, not a code change.

### D6: R8/minification is opt-in and gated on a device smoke test

Flutter does not enable minification by default, so today's release builds are unshrunk and
safe. Enabling R8 is worthwhile (smaller download, Play's size limits) but its failures are
**runtime-only** — a stripped class surfaces as a crash in the field, not a build error.
So Step 5 is optional, and its verification is a real install on a real device exercising the
sensor/GPS/notification paths, not a successful build.

`tflite_flutter` is declared in `pubspec.yaml` but **not used anywhere in `lib/`** yet (T016).
Its keep rules go in when T016 lands, not now — writing keep rules for code R8 can't see is
how you end up with rules nobody can justify or delete.

### D7: JDK pinned to 21

The default JDK on this machine is **25** (`/usr/libexec/java_home` → temurin-25). Gradle 8.14
+ AGP 9.3.0 are not validated against 25, and a toolchain mismatch here fails in confusing
ways. temurin-21.0.9 is installed. The script pins it, exactly as tribly does.

### D8: Internal track only, promotion is manual

`fastlane internal` publishes to the internal testing track. A `deploy` lane targeting
production is defined but **no script calls it** — promoting to production is a deliberate
human action in the Play Console. Same posture as tribly.

---

## Implementation Steps

### Step 1: Adopt the `X.Y.Z+N` version scheme

`pubspec.yaml:4`:

```yaml
# Before
version: 1.0.0

# After — N is bumped by publish_beta.sh on every upload, never reset
version: 1.0.0+1
```

Then clear the stale local override. `android/local.properties` currently carries
`flutter.versionName=0.1.0` from an earlier pubspec. It's gitignored and machine-local, so it
only misleads you:

```bash
flutter build appbundle --release   # rewrites flutter.versionName/versionCode from pubspec
grep flutter.version android/local.properties   # expect 1.0.0 / 1
```

Also fix `README.md:434` (`**Version:** 0.1.0`) — pubspec is authoritative.

### Step 2: Generate the upload keystore

```bash
keytool -genkey -v -keystore ~/.secrets/autoride-upload.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Back up `~/.secrets/autoride-upload.jks` somewhere durable and offline. Then create
`android/key.properties` (gitignored):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=/Users/glandais/.secrets/autoride-upload.jks
```

And commit `android/key.properties.example`:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/absolute/path/to/autoride-upload.jks
```

### Step 3: Wire signing into Gradle

`android/app/build.gradle.kts` — add the imports and the properties load above the `android {}`
block, then replace the `buildTypes.release` body:

```kotlin
import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. Absent on a fresh clone and in CI — see the fallback in
// buildTypes.release below.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "io.github.glandais.autoride"
    // ... unchanged ...

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug keys so `flutter run --release` works without secrets.
            // publish_beta.sh refuses to build when key.properties is missing, so a
            // debug-signed bundle can never reach a store upload.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

Delete the two stale `// TODO:` comments at lines 23 and 35 while you're in there.

**Verify the signature is real, not debug:**

```bash
flutter build appbundle --release
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | head -20
# Owner must be your keystore's DN — NOT "CN=Android Debug, O=Android, C=US"
```

That last check is the whole point of this step. Run it.

### Step 4: Pin `minSdk` and settle the app's display name

**minSdk** — `CLAUDE.md` promises API 26+ but the build resolves to 24, and a Flutter upgrade
can move it again without warning. Pin it to match the documented support:

```kotlin
defaultConfig {
    applicationId = "io.github.glandais.autoride"
    minSdk = 26          // Android 8.0 — matches the support claim in CLAUDE.md/README
    targetSdk = flutter.targetSdkVersion   // 36; Play requires 35+ for new apps
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

*Alternative*: keep `flutter.minSdkVersion` and correct `CLAUDE.md` to say API 24+. Pick one —
the current state is a documented promise the build doesn't keep. Pinning is preferred because
it makes the supported floor explicit and immune to SDK bumps.

**Display name** — three spellings exist today: `autoride` (Android label), `Autoride`
(iOS `CFBundleDisplayName`), `AutoRide` (README, all prose). Canonical is **AutoRide**:

```xml
<application
    android:label="AutoRide"
    ...
```

The matching iOS change is in T039. `CFBundleName` (`autoride`) is the internal short name and
can stay.

### Step 5: R8 / ProGuard (optional — read D6 first)

Only do this if you're prepared to smoke-test on a device. Create
`android/app/proguard-rules.pro`:

```proguard
# Flutter plugins that reach native code reflectively. Most Flutter plugins ship their own
# consumer-rules.pro inside their AAR, so this file stays intentionally small — add a rule
# only when you have observed a concrete R8 failure, and note what it was.

# flutter_background_service: the service class is named in AndroidManifest.xml, so R8 sees
# no code reference to it.
-keep class id.flutter.flutter_background_service.** { *; }

# TODO(T016): when TensorFlow Lite is actually wired up, add:
#   -keep class org.tensorflow.** { *; }
#   -dontwarn org.tensorflow.**
# Not added now: tflite_flutter is declared in pubspec but unused in lib/, so R8 correctly
# strips it and a keep rule would be unjustifiable dead config.
```

Then in `buildTypes.release`:

```kotlin
release {
    signingConfig = /* as above */
    isMinifyEnabled = true
    isShrinkResources = true
    proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro",
    )
}
```

**Verification is a device install, not a build**: install the shrunk release on a physical
device and exercise trip detection start→record→stop, the foreground notification, permission
prompts, and the map screen. A clean build proves nothing here.

If anything breaks and the cause isn't obvious in `flutter logs`, revert to
`isMinifyEnabled = false` and move on — this step is not a release blocker.

### Step 6: fastlane for Android

`android/Gemfile`:

```ruby
source "https://rubygems.org"

gem "fastlane"
```

```bash
cd android && bundle install   # commit the resulting Gemfile.lock
```

`android/fastlane/Appfile` — improved over tribly, which hardcodes an absolute path to the
service-account JSON:

```ruby
package_name("io.github.glandais.autoride")

# Service-account JSON lives outside the repo. Override with AUTORIDE_PLAY_JSON_KEY.
json_key_file(
  ENV["AUTORIDE_PLAY_JSON_KEY"] || File.expand_path("~/.secrets/autoride-play.json")
)
```

`android/fastlane/Fastfile`:

```ruby
default_platform(:android)

platform :android do
  desc "Upload the release bundle to the Play internal testing track. " \
       "Run `flutter build appbundle --release` from the project root first."
  lane :internal do
    upload_to_play_store(
      track: "internal",
      # Resolved from android/ (fastlane's working directory). The root build.gradle.kts
      # redirects the build dir to <project>/build, so this points at
      # <project>/build/app/outputs/bundle/release/app-release.aab.
      aab: "../build/app/outputs/bundle/release/app-release.aab",
      # Play refuses a non-draft upload until the app has been published once. Keep
      # "draft" for the very first upload, then switch to "completed".
      release_status: "draft",
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_changelogs: true,
      skip_upload_images: true,
      skip_upload_screenshots: true,
    )
  end

  desc "Promote to the production track. Deliberately not called by any script."
  lane :deploy do
    upload_to_play_store(
      aab: "../build/app/outputs/bundle/release/app-release.aab",
    )
  end
end
```

The `skip_upload_*` flags keep the internal lane from overwriting the store listing on every
build — that's the point of having listing text under git rather than pushed each time.

**Listing metadata** — create `android/fastlane/metadata/android/en-US/` with `title.txt`,
`short_description.txt`, `full_description.txt`, plus `images/icon.png`,
`images/featureGraphic.png` (1024×500) and `images/phoneScreenshots/`. Content depends on
T036 (assets) and T037 (privacy policy URL); the directory structure belongs here.

### Step 7: `publish_beta.sh` (Android half)

At the project root. T039 adds the iOS section ahead of the Android one.

```bash
#!/usr/bin/env bash
# publish_beta.sh — bump the build number, build, and upload to the Play internal track.
# T039 adds the iOS/TestFlight half.
set -euo pipefail

cd "$(dirname "$0")"

die() { echo "publish_beta.sh: $*" >&2; exit 1; }

# ---------------------------------------------------------------- pre-flight

# The rollback in restore_on_failure() is `git checkout -- pubspec.yaml`, which is only safe
# on a clean tree. These two are a pair.
[ -z "$(git status --porcelain)" ] ||
  die "working tree is not clean — commit or stash first"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "$BRANCH" in
  develop | main) ;;
  *) echo ">>> WARNING: publishing from branch '$BRANCH'"; sleep 3 ;;
esac

[ -f android/key.properties ] ||
  die "android/key.properties is missing — a release build would be signed with DEBUG keys"

# Project quality gates, in the order CLAUDE.md mandates.
echo ">>> Code generation"
dart run build_runner build --delete-conflicting-outputs
echo ">>> Analyze"
flutter analyze
echo ">>> Test"
flutter test

# ------------------------------------------------------------ version bump

grep -qE '^version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$' pubspec.yaml ||
  die "pubspec.yaml version must be exactly 'X.Y.Z+N' (see T038 D1/D4)"

ORIGINAL_VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"

# Tracks whether anything reached a store. Once a store accepts build N, N is consumed
# forever, so the rollback below must not fire.
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

# ---------------------------------------------------------------- android

# Default JDK here is 25; Gradle 8.14 / AGP 9.3.0 are not validated against it.
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
export PATH="$JAVA_HOME/bin:$PATH"

flutter build appbundle --release
(cd android && { bundle check || bundle install; })
(cd android && bundle exec fastlane internal --verbose)
UPLOADED="Play internal"

# --------------------------------------------------------- record the release

git add pubspec.yaml
git commit -m "chore(release): $NEW_VERSION"
git tag "v$NEW_VERSION"

echo ">>> Published $NEW_VERSION to: $UPLOADED"
echo ">>> Tagged v$NEW_VERSION — push with: git push && git push --tags"
```

```bash
chmod +x publish_beta.sh
```

### Step 8: `.gitignore` additions

`android/.gitignore` — append (the existing keystore rules already cover the secrets):

```gitignore
# Fastlane. metadata/ is deliberately kept: it is the source of truth for the Play listing.
fastlane/report.xml
fastlane/Preview.html
fastlane/test_output
```

### Step 9: Fix the README

`README.md:49-52` currently points users at a Releases page that has never had a release. Either
publish one (attach the AAB/APK to a `v1.0.0+N` tag) or change the text to say Android
distribution is via Play internal testing during beta. Don't leave a dead link.

`README.md:233-254` should be updated to reflect what the code now actually does: keystore →
`key.properties` → `./publish_beta.sh`, rather than describing `key.properties` as if Gradle
had always read it.

---

## Play Console Prerequisites (manual, outside the repo)

None of this is code, and all of it blocks the first upload:

1. **App record** created in the Play Console with package `io.github.glandais.autoride`.
2. **Internal testing track** created with at least one tester.
3. **Service account** in Google Cloud with the Play Developer API enabled, granted access in
   the Play Console (release-manager level), JSON key saved to `~/.secrets/autoride-play.json`.
   Validate before the first real run: `cd android && bundle exec fastlane run validate_play_store_json_key`.
4. **Data safety form** — must declare precise location, background location, and that data
   stays on-device. Cross-check against `AndroidManifest.xml` and T028's declarations.
5. **Background location declaration** — `ACCESS_BACKGROUND_LOCATION`
   (`AndroidManifest.xml:39`) triggers a separate Play review requiring an in-app prominent
   disclosure, a privacy policy URL, and a **screencast** demonstrating the feature. This has
   the longest turnaround of anything in Phase 10. Needs T037.
6. **App signing** — accept Play App Signing; the keystore from Step 2 becomes the *upload* key.

Consider borrowing tribly's `store-metadata/data-safety.md` pattern: one file under git as the
single source of truth for what the app collects, with the rule that it and the store forms and
the privacy manifest change in the same commit. Five places describing the same thing drift
invisibly otherwise. That file belongs to T037.

---

## Verification Steps

### Automated

```bash
# 1. Quality gates (the script runs these too)
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test

# 2. Release bundle builds and is signed with the UPLOAD key, not debug
flutter build appbundle --release
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | head -20

# 3. versionCode tracks pubspec
grep flutter.versionCode android/local.properties     # matches +N
unzip -p build/app/outputs/bundle/release/app-release.aab BUNDLE-METADATA/*/manifest.json 2>/dev/null | head
# or: bundletool dump manifest --bundle=... | grep versionCode

# 4. fastlane can authenticate without uploading
cd android && bundle exec fastlane run validate_play_store_json_key
```

### Bump-guard tests (do these before trusting the script with a real upload)

| Scenario | Setup | Expected |
|---|---|---|
| Malformed version | set `version: 1.0.0` | dies with the `X.Y.Z+N` message, no build |
| Dirty tree | `touch lib/foo.dart` | dies before the bump |
| Missing keystore config | rename `key.properties` | dies before the bump |
| Failure before upload | temporarily `exit 1` before `flutter build appbundle` | pubspec restored to the original version |
| Failure after upload | temporarily `exit 1` after `UPLOADED=` is set | bump **kept**, message explains why |
| Happy path | — | commit `chore(release): X.Y.Z+N` + tag `vX.Y.Z+N` |

The failure-mode rows are the whole justification for this task's deviation from tribly. Verify
them with a fake `exit 1`, not by hoping.

### Physical device (required if Step 5 was done)

Install the release AAB via `bundletool` or an internal-track download and exercise:
permission prompts, trip start detection, foreground notification with live metrics, trip
stop and persistence, trip history, map rendering.

---

## Edge Cases & Failure Modes

**`versionCode` already used** — Play rejects the upload. The counter must be monotonic across
*all* uploads including deleted drafts. Never hand-edit `N` downward; if the sequence has a gap
that's fine, gaps are legal.

**First upload with `release_status: "completed"`** — fails while the app has never been
published. Start with `"draft"`, switch to `"completed"` afterwards (tribly's Fastfile carries
exactly this comment from having hit it).

**Debug-signed AAB reaching upload** — prevented by the `key.properties` check in the script,
but if you ever build outside the script, run the `keytool -printcert` check. The Play error
message ("signed in debug mode") is clear, but you'll have burned a build number.

**`bundle exec fastlane` picking the wrong Ruby** — the system Ruby on macOS is ancient. This
machine has Homebrew Ruby 4.0.6 first in `PATH` and `fastlane` on `PATH`, so the explicit
`brew --prefix ruby` juggling tribly needs isn't required. If that changes, add it.

**Gradle + JDK 25** — omitting the `JAVA_HOME` pin surfaces as opaque Kotlin/AGP errors, not a
clear "unsupported JDK" message. Keep the pin.

**`git tag` with `+` in the name** — legal in git refs; `v1.0.0+1` works. Some CI systems
dislike `+` in artifact names; if that ever matters, tag `v1.0.0-build1` instead.

---

## Definition of Done

- [ ] `pubspec.yaml` uses `X.Y.Z+N`; `README.md` version line agrees
- [ ] `android/key.properties.example` committed; real `key.properties` present locally and ignored
- [ ] `keytool -printcert` on a release AAB shows the upload key, not `CN=Android Debug`
- [ ] `minSdk` pinned (or `CLAUDE.md` corrected) — code and docs agree
- [ ] `android:label="AutoRide"`
- [ ] `android/Gemfile`, `Gemfile.lock`, `fastlane/Fastfile`, `fastlane/Appfile` committed
- [ ] `fastlane/metadata/android/en-US/` skeleton committed
- [ ] `publish_beta.sh` executable, and all six bump-guard scenarios verified
- [ ] One build accepted on the Play internal track
- [ ] Release commit + tag exist for that build
- [ ] `README.md` build instructions match reality; no dead Releases link
- [ ] R8: either enabled and device-verified, or explicitly deferred with a note
- [ ] `tasks/TASKS.md` updated (☐ → ✅), progress summary refreshed

---

## References

- Reference pipeline: `../tribly/mobile/publish_test.sh`, `../tribly/mobile/android/`
- Flutter Android deployment: https://docs.flutter.dev/deployment/android
- fastlane `supply`: https://docs.fastlane.tools/actions/upload_to_play_store/
- Play background location policy: https://support.google.com/googleplay/android-developer/answer/9799150
- Version resolution, verified in this Flutter install:
  `flutter_tools/lib/src/android/gradle_utils.dart:1186-1192`,
  `flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt:133`
- Next: **T039** (iOS release configuration, extends `publish_beta.sh`), then **T040** (beta testing)
