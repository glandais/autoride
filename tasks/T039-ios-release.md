# T039 - iOS Release Configuration

**Status (2026-09-13)**: ⏳ In Progress. The release pipeline shipped and is proven — TestFlight
builds 3 and 4 uploaded via `fastlane beta`, and `1.0.0+4` went out through the first full
dual-platform `publish_beta.sh` run. `asc validate` is down to 2 errors (attach a build — use
build 4, build 3 carries a crash — and screenshots) per `tasks/TASKS.md`. What's left is public
submission, not TestFlight: README still promises "Coming soon" for iOS, the App Review
considerations (background-location copy, privacy policy URL, screenshots, app icon) are
unaddressed, and the Definition of Done has unchecked items. See **Remaining work** below —
preserved verbatim from the original guide, do not shorten it.

**Dependencies**: T038 (Android Release Configuration — version scheme + `publish_beta.sh`, now
satisfied), T033 (Code Quality), T036 (App Icons & Splash Screen)
**Phase**: 10 - Release Preparation

---

## What shipped

**Why:** Get a signed, uploadable build to TestFlight without the recurring pain points a
sibling project (`../tribly/mobile`) already hit — an expiring Apple ID session, a manual
export-compliance click on every build, an untracked IPA/dSYM in the tree.

**Durable decisions:**
- Automatic signing, local-only releases (D1) — this pipeline can't run in CI; a future move to
  CI is a separate task (manual signing, `match` or an imported profile, explicit
  `ExportOptions.plist`).
- Keep CocoaPods, don't migrate to SPM (D2) — the `Podfile`'s `permission_handler` preprocessor
  macros are unrelated risk to bundle into a release-enablement task. (Since superseded in
  practice: Flutter 3.47 resolves `permission_handler_apple` via SPM regardless — see
  `tasks/T041-device-validation.md` item 7 — but the Podfile itself was deliberately left alone.)
- App Store Connect API key, not an Apple ID session (D3) — non-expiring, works unattended;
  `.p8` stored outside the repo (`~/.secrets/autoride-asc.env`), never committed.
- The privacy manifest is finished by Apple's `ITMS-91053` feedback loop, not by guessing which
  required-reason API categories each plugin trips (D4).
- iPhone only, not universal — `TARGETED_DEVICE_FAMILY = 1` on all three Runner configurations,
  to avoid the iPad screenshot requirement and an untested review surface (Step 5's decision,
  applied).

**Delivered:** `ios/Gemfile`, `ios/Gemfile.lock`, `ios/fastlane/Appfile`, `ios/fastlane/Fastfile`
(`beta` and `release` lanes, both authenticating via `asc_api_key` sourced from
`~/.secrets/autoride-asc.env`), `ios/.gitignore` (fastlane noise + `*.ipa`/`*.dSYM.zip`/`*.dSYM`),
`ios/Runner/Info.plist` (`CFBundleDisplayName = AutoRide`, `ITSAppUsesNonExemptEncryption = false`),
`ios/Runner.xcodeproj/project.pbxproj` (`CODE_SIGN_STYLE = Automatic` explicit,
`CODE_SIGN_IDENTITY[sdk=iphoneos*] = "Apple Development"` on all three configs,
`TARGETED_DEVICE_FAMILY = 1`), `ios/Runner/PrivacyInfo.xcprivacy` (`DeviceID` deliberately *not*
declared, with the reasoning recorded inline; `FileTimestamp` 0A2A.1 and `UserDefaults` CA92.1
reasons present), `publish_beta.sh` (iOS runs before Android, `UPLOADED` accumulates rather than
overwrites, `ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_KEY_PATH` pre-flight check).

**Pitfalls:**
- `UserDefaults` reason was `1C8F.1` (App Group) until 2026-09-03 — wrong, because AutoRide has
  no App Group (no `.entitlements` file at all). Corrected to `CA92.1` ("accessible to the app
  itself"). Watch for the same mistake if a new UserDefaults use is added.
- `skip_waiting_for_build_processing: true` in the `beta` lane means the script can exit "green"
  before Apple finishes processing — a build that later fails processing still needs checking by
  email/TestFlight, not just by script exit code.
- Two full compilations happen per release (`flutter build ios --no-codesign` then `build_app`
  archiving again) — this is the standard flutter+fastlane split, not a bug to "optimise" away.

---

## Remaining work

The sections below describe work that has **not** shipped. Preserved verbatim from the original
task guide — do not shorten, reorder, or paraphrase.

### D5: iOS background detection is weaker than the copy promises

`UIBackgroundModes` is `["location", "fetch"]`. `fetch` is legitimately used —
`background_location_service.dart:99-102` configures `IosConfiguration(onBackground: onIosBackground)` —
but iOS background fetch is opportunistic: the system decides when, and it can be minutes or
hours. The `NSLocationAlwaysAndWhenInUseUsageDescription` string promises detection "even when
the app is closed", which iOS will not reliably deliver.

Review compares permission copy against observed behaviour. Reconcile the wording (T028 owns
those strings) before submitting for App Store review. TestFlight doesn't enforce this, so it
does not block Step 8 — but it will block the eventual public release.

### Step 10: Fix the README

`README.md:57` says iOS is "Download from the App Store *(Coming soon)*" — accurate for now, but
once TestFlight works, say so and explain how to request access. `README.md:256-268` should
mention `./publish_beta.sh` and the ASC API key setup rather than only `flutter build ipa`.

---

## App Review Considerations

TestFlight (Step 8) does not enforce most of these. Public App Store submission does.

1. **Background location justification (Guideline 2.5.4 / 5.1.1)** — Review asks why persistent
   location is required. The answer is the app's premise (hands-free trip detection) and it must
   be visible in the app, not just in the review notes.
2. **Permission copy must match behaviour** — see D5. The "even when the app is closed" promise
   overstates what iOS background fetch delivers.
3. **Privacy policy URL is mandatory** for an app collecting location (T037).
4. **Screenshots** — iPhone 6.9" (or 6.7") required; 13" iPad too unless Step 5 makes the app
   iPhone-only. T036.
5. **Placeholder assets are rejected.** The current `AppIcon.appiconset` is the unmodified Flutter
   template icon. T036 blocks public submission (not TestFlight).
6. **Minimum SDK** — Apple requires builds made with a recent iOS SDK. Check `xcodebuild -version`
   against the current requirement before a submission window.

---

## Verification Steps

### Automated

```bash
# 1. Quality gates
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test

# 2. Release archive builds and exports
flutter build ipa --release

# 3. Version wiring — both must show X.Y.Z / N from pubspec, not 1.0.0 / 1.0.0
grep -A1 "FLUTTER_BUILD_NAME\|FLUTTER_BUILD_NUMBER" ios/Flutter/Generated.xcconfig
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
  build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist

# 4. Export compliance flag is present in the built app
/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" \
  build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist

# 5. fastlane can authenticate without uploading
cd ios && bundle exec fastlane run get_itc_team_id

# 6. Build artifacts are ignored
git check-ignore -v ios/Runner.ipa ios/Runner.app.dSYM.zip
```

> Step 3 is the one to actually run before the first upload. `FLUTTER_BUILD_NUMBER=1.0.0`
> (the value in `Generated.xcconfig` today, because pubspec has no `+N`) means T038's Step 1
> hasn't been applied — and a duplicate `CFBundleVersion` is the single most common
> first-upload rejection.

### Manual

- Install the TestFlight build on a physical device (sensors and GPS don't work on Simulator).
- Confirm the tester install needs **no** export-compliance click (Step 4 worked).
- Exercise: permission prompts (When In Use → Always), trip detection, foreground behaviour,
  trip persistence, history, map rendering.
- Check email for `ITMS-*` warnings and fold them into Step 6.

---

## Edge Cases & Failure Modes

**Duplicate `CFBundleVersion`** — ASC rejects the build. Caused by running the publish script
twice after a failed upload without the bump, or by never applying T038's `+N`. T038's guards
cover the first; verification Step 3 covers the second.

**`ITMS-91053: Missing API declaration`** — expected on the first upload (D4). It's a warning
first; it becomes a hard rejection later. Add the named categories, bump, re-upload.

**Automatic signing fails during archive** — usually a missing distribution certificate or an
App ID whose Background Modes capability wasn't enabled (Step 1.1). Open
`ios/Runner.xcworkspace`, let Xcode repair signing, then re-run.

**`skip_waiting_for_build_processing: true`** — the script exits before Apple finishes
processing. A build that fails processing looks like a success in the terminal. Check TestFlight
or your email before telling testers.

**dSYM is produced and then abandoned** — `fastlane beta` leaves `Runner.app.dSYM.zip` (~40 MB)
on disk, now gitignored. Symbolication depends entirely on the copy ASC keeps. Fine while there
is no crash reporting; if Crashlytics or Sentry is ever added, uploading the dSYM becomes part
of this lane.

**Two full compilations per release** — `flutter build ios --no-codesign` then `build_app`
archiving again. This is the standard flutter+fastlane split, not a mistake. It's several
minutes; don't "optimise" it by dropping the first step, which is what produces `App.framework`
and the Dart assets.

---

## Definition of Done

- [x] T038 landed (version scheme + `publish_beta.sh` exist)
- [x] App ID registered with Background Modes; app record created in ASC
- [x] ASC API key created, `.p8` stored outside the repo, `ASC_*` exported
- [x] `CODE_SIGN_STYLE` explicit; legacy `"iPhone Developer"` identity replaced
- [x] `CFBundleDisplayName` is `AutoRide`
- [x] `ITSAppUsesNonExemptEncryption` present and verified in the built app's Info.plist
- [x] iPad decision made and applied (`TARGETED_DEVICE_FAMILY`)
- [x] `DeviceID` declaration in the privacy manifest either justified or removed
- [x] App Privacy form in ASC matches `PrivacyInfo.xcprivacy`
- [x] `ios/Gemfile`, `Gemfile.lock`, `fastlane/Fastfile`, `fastlane/Appfile` committed
- [x] `ios/.gitignore` covers `*.ipa`, `*.dSYM.zip`, fastlane noise — verified with `git check-ignore`
- [x] `publish_beta.sh` runs iOS before Android and accumulates `UPLOADED`
- [x] One build accepted by TestFlight and installable by a tester with no compliance click
- [ ] Any `ITMS-*` warnings resolved
- [ ] `README.md` iOS instructions match reality
- [ ] `tasks/TASKS.md` updated (☐ → ✅), progress summary refreshed
- [ ] Build attached to the App Store Connect version, screenshots uploaded (per `tasks/TASKS.md` T039 status — the 2 remaining `asc validate` errors)

---

## References

- Reference pipeline: `../tribly/mobile/ios/fastlane/`, `../tribly/mobile/publish_test.sh`
- Flutter iOS deployment: https://docs.flutter.dev/deployment/ios
- fastlane `pilot`: https://docs.fastlane.tools/actions/upload_to_testflight/
- ASC API keys: https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api
- Required-reason APIs: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api
- Review guidelines, location: https://developer.apple.com/app-store/review/guidelines/#location-services
- Privacy manifest background and rationale: `tasks/ARCHIVE.md` → T028
- Next: **T040** (Beta Testing & Feedback — depends on T038 + T039)
