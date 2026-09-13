# T038 - Android Release Configuration

**Status**: ⏳ In Progress, as of 2026-09-13. All in-repo work shipped in `a945fa3` and has been
exercised for real: `pubspec.yaml` is at `1.0.0+17`, tags `v1.0.0+5` through `v1.0.0+17` exist, and
`publish_beta.sh` (now covering both platforms, iOS first) is the live release path. Only the
manual Play Console setup remains — see "Remaining work" below.

**Dependencies**: T033 (Code Quality), T036 (App Icons & Splash Screen)
**Phase**: 10 - Release Preparation

---

## What shipped (summary)

**Why:** `flutter build appbundle --release` needed to produce a Play-acceptable artifact —
release builds were debug-signed, there was no build number, and there was no distribution
mechanism at all. The fix reused the sibling `tribly` project's fastlane/shell pipeline, with two
deliberate deviations (a guarded, reversible version bump; pre-flight quality gates) documented
below.

**Durable decisions:**
- `pubspec.yaml`'s `X.Y.Z+N` is the single source of truth for both platforms' version/build
  number — never hand-edit `versionCode` in Gradle or `CURRENT_PROJECT_VERSION` in the pbxproj.
- The upload keystore lives outside the repo forever (`~/.secrets`-style path via
  `key.properties`, gitignored); losing it loses the ability to update the app.
- Gradle keeps a silent debug-signing fallback for local `flutter run --release`, but
  `publish_beta.sh` refuses to build when `android/key.properties` is missing, so a debug-signed
  bundle can never reach a store upload.
- The version bump is guarded and reversible: a regex format check, a did-it-change assertion,
  and a `trap`-based rollback that fires only if no upload has yet succeeded (once a store
  accepts build `N`, `N` is consumed forever and must never be reused).
- The script commits (`chore(release): X.Y.Z+N`) and tags (`vX.Y.Z+N`) only after every upload
  succeeds, so every store build is traceable to a commit.
- R8/minification stays **off** (D6): its failures are runtime-only, so enabling it is gated on
  a physical-device smoke test rather than a green build; `android/app/build.gradle.kts:69` and
  `android/app/build.gradle.kts:74` (`isMinifyEnabled = false`) carry the rationale in a comment.
  No `proguard-rules.pro` exists yet — correctly, since nothing has enabled minification.
- `minSdk` is pinned to 26 (not `flutter.minSdkVersion`, which resolves to 24), matching the
  API 26+ claim elsewhere in the docs.
- Play credentials are shared with the sibling `tribly` project by design, both kept outside
  git: the upload keystore (`android/key.properties` → `~/Documents/pedalons/android/tribly-release.keystore`,
  alias `tribly`) and the Play service account (`~/.secrets/autoride-play.json`, a symlink to
  tribly's service-account JSON, which holds account-level Administrator). One leaked key can
  publish both apps — accepted knowingly, not an oversight.

**Delivered:** `pubspec.yaml` (`version: 1.0.0+17`), `android/key.properties.example`,
`android/app/build.gradle.kts` (signing config, `minSdk = 26`), `android/app/src/main/AndroidManifest.xml`
(`android:label="AutoRide"`), `android/Gemfile`, `android/Gemfile.lock`, `android/fastlane/Appfile`,
`android/fastlane/Fastfile`, `android/fastlane/metadata/`, `publish_beta.sh`, `README.md`
(build/publish sections).

**Pitfalls:**
- The Gradle wrapper was pinned at 8.14 while AGP 9.3.0 requires 9.5.0 —
  `flutter build appbundle --release` failed at plugin resolution before any of this task's
  changes were even reachable. Wrapper bumped; upstream `develop` has since moved it to 9.7.1.
- `updateLocalProperties` removes `flutter.versionCode` when the manifest has no build number,
  silently falling back to `versionCode "1"` — this is why a bare `version: 1.0.0` (no `+N`)
  is actively dangerous, not just incomplete.
- The default JDK on the dev machine is 25; Gradle 8.14 + AGP 9.3.0 are not validated against
  it and fail in confusing, non-"unsupported JDK" ways. `publish_beta.sh` pins `JAVA_HOME` to
  temurin-21 explicitly.
- `tflite_flutter` was declared in `pubspec.yaml` but unused in `lib/` (T016), so no R8 keep
  rules were written for it — writing rules for code R8 can't see yet produces unjustifiable
  dead config. The dependency itself was removed on 2026-09-13; when T016 lands, whichever
  inference runtime it brings will need its keep rules written then.

---

## Remaining work

The following is copied unchanged from the task guide's "Play Console Prerequisites" section —
none of it is code, and it's what actually blocks calling T038 done. Confirmed still open per
`tasks/TASKS.md`'s "*Remaining (manual, Play Console)*" note.

### Play Console Prerequisites (manual, outside the repo)

None of this is code, and all of it blocks the first upload:

1. **App record** created in the Play Console with package `io.github.glandais.autoride`.
   — *Already done*: app record `AutoRide: Bike Trip Tracker` created (app ID
   `4975962567441094743`), package available, en-US, App, Free; internal testing track page
   reachable; API auth verified (`validate_play_store_json_key` → "Successfully established
   connection").
2. **Internal testing track** created with at least one tester. — Track page exists; **no
   tester added yet**.
3. **Service account** in Google Cloud with the Play Developer API enabled, granted access in
   the Play Console (release-manager level), JSON key saved to `~/.secrets/autoride-play.json`.
   Validate before the first real run: `cd android && bundle exec fastlane run validate_play_store_json_key`.
   — Done and verified.
4. **Data safety form** — must declare precise location, background location, and that data
   stays on-device. Cross-check against `AndroidManifest.xml` and T028's declarations. — **Not
   done.**
5. **Background location declaration** — `ACCESS_BACKGROUND_LOCATION`
   (`AndroidManifest.xml:39`) triggers a separate Play review requiring an in-app prominent
   disclosure, a privacy policy URL, and a **screencast** demonstrating the feature. This has
   the longest turnaround of anything in Phase 10. Needs T037. — **Not done**; needs T037's
   policy URL.
6. **App signing** — accept Play App Signing; the keystore becomes the *upload* key. — **Not
   done.**

Consider borrowing tribly's `store-metadata/data-safety.md` pattern: one file under git as the
single source of truth for what the app collects, with the rule that it and the store forms and
the privacy manifest change in the same commit. Five places describing the same thing drift
invisibly otherwise. That file belongs to T037.

---

## Verification (for the remaining Play Console work)

```bash
# fastlane can authenticate without uploading
cd android && bundle exec fastlane run validate_play_store_json_key
```

## Definition of Done (outstanding items only)

- [ ] Internal testing track has at least one tester
- [ ] Data safety form completed in the Play Console
- [ ] Background-location declaration submitted (prominent disclosure + privacy policy URL
      from T037 + screencast)
- [ ] Play App Signing accepted
- [ ] `tasks/TASKS.md` updated (⏳ → ✅) once the above are done

---

## References

- Reference pipeline: `../tribly/mobile/publish_test.sh`, `../tribly/mobile/android/`
- fastlane `supply`: https://docs.fastlane.tools/actions/upload_to_play_store/
- Play background location policy: https://support.google.com/googleplay/android-developer/answer/9799150
- Next: **T039** (iOS release configuration, extends `publish_beta.sh`), then **T040** (beta testing)
