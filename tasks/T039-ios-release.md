# T039 - iOS Release Configuration

**Status**: ☐ Pending
**Estimated Time**: 3-4 hours (revised up from 2-3h in TASKS.md — App Store Connect setup and
privacy-manifest reconciliation were not in the original estimate)
**Dependencies**: **T038 (Android Release Configuration — creates `publish_beta.sh` and the
version scheme this task extends)**, T033 (Code Quality), T036 (App Icons & Splash Screen)
**Phase**: 10 - Release Preparation

---

## Overview

Get a signed, uploadable build to TestFlight, and close the App Store Connect declarations that
cause upload-time and review-time rejections.

iOS starts from a better place than Android did: `CFBundleVersion` is already wired to
`$(FLUTTER_BUILD_NUMBER)`, the team ID is set, the scheme is shared, the privacy manifest exists,
and `LSApplicationCategoryType` is already `public.app-category.sports`. What's missing is the
distribution layer (no fastlane, no `Gemfile`), a handful of Info.plist / project settings that
each cost a round-trip with Apple if wrong, and a decision about iPad.

**T038 must land first** — it introduces the `X.Y.Z+N` version scheme and `publish_beta.sh`, and
this task inserts the iOS half into that script.

---

## Reference Implementation

`../tribly/mobile/ios` has shipped 23 builds to TestFlight from this same Apple team
(`7Q49262697`). Borrowed:

| Borrowed from tribly | Where |
|---|---|
| `build_app` + `upload_to_testflight` in a single `beta` lane | `ios/fastlane/Fastfile` |
| `export_method: "app-store"` with `signingStyle: "automatic"` (no `ExportOptions.plist` to maintain) | `ios/fastlane/Fastfile` |
| `flutter build ios --release --no-codesign` before fastlane archives | `publish_test.sh` |
| Own `Gemfile`/`Gemfile.lock` under `ios/` | `ios/Gemfile` |
| `.gitignore` entries for `*.ipa` / `*.dSYM.zip` / fastlane noise | `ios/.gitignore:37-46` |

Deliberately different:

- **Auth**: tribly relies on an interactive Apple ID session, which expires roughly monthly and
  breaks a release at the worst moment. We use an App Store Connect **API key** (see D3).
- **Export compliance**: tribly answers the encryption question by hand on every build. We
  declare it in `Info.plist` once (see Step 4).
- tribly's pbxproj has a stale hardcoded `CURRENT_PROJECT_VERSION = 1.0.0`. **autoride is already
  correct** (`$(FLUTTER_BUILD_NUMBER)`) — leave it alone.

---

## Current Implementation Status

### ✅ What Exists

1. **Versioning already correct** — `Info.plist` uses `$(FLUTTER_BUILD_NAME)` /
   `$(FLUTTER_BUILD_NUMBER)`; pbxproj has `CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER)`
   on all three Runner configurations. Once T038 sets `version: 1.0.0+N`, iOS picks it up with
   no further wiring.
2. **Bundle ID and team set** — `PRODUCT_BUNDLE_IDENTIFIER = io.github.glandais.autoride`,
   `DEVELOPMENT_TEAM = 7Q49262697` on all Runner configurations.
3. **Shared scheme present** — `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`;
   fastlane's `build_app` needs this.
4. **App category set** — `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports"`.
5. **Privacy manifest exists** (T028) — `ios/Runner/PrivacyInfo.xcprivacy` declares no tracking,
   location + DeviceID collection, and reasons for FileTimestamp (`0A2A.1`) and UserDefaults
   (`1C8F.1`).
6. **Usage descriptions written** (T028) — all four location/motion strings are specific and
   explain the benefit, which is what Review looks for.
7. **CocoaPods working** — `Podfile` with the `permission_handler` `GCC_PREPROCESSOR_DEFINITIONS`
   in `post_install` (fixed in commit `cc1c088`).
8. **Deployment target 13.0**, consistent with the plugin set.

### ❌ What's Missing

1. No fastlane at all — no `ios/Gemfile`, no `Fastfile`, no `Appfile`.
2. No App Store Connect app record, and no upload has ever been attempted.
3. **`ITSAppUsesNonExemptEncryption` absent from `Info.plist`** → TestFlight blocks every build
   on a manual export-compliance answer before testers can install it.
4. `ios/.gitignore` has **no** `*.ipa` / `*.dSYM.zip` / fastlane entries — the first
   `fastlane beta` drops a ~30 MB IPA and a ~40 MB dSYM zip into the tree, ready to be
   committed by accident. (tribly's ignore list exists precisely because of this.)
5. **`TARGETED_DEVICE_FAMILY = "1,2"`** — the app ships as universal iPhone+iPad. That obliges
   iPad screenshots on the product page and puts iPad in scope for Review. Decision needed
   (Step 5).
6. `CFBundleDisplayName` is `Autoride`; README and T038's Android label use **AutoRide**.
7. `CODE_SIGN_STYLE` is not set on the Runner target (defaults to Automatic — works, but
   implicit), and project-level `CODE_SIGN_IDENTITY[sdk=iphoneos*]` is the legacy
   `"iPhone Developer"`.
8. Privacy manifest is probably under-declared — see D4.
9. No App Store screenshots, no product page copy, no privacy policy URL (T036/T037).

---

## Design Decisions

### D1: Automatic signing, local-only releases

Keep `signingStyle: "automatic"`. It works because releases run on this machine, already
authenticated, and it removes provisioning-profile management entirely. The cost is that this
pipeline cannot run in CI — accepted, same as tribly and same as T038's Android half.

If iOS releases ever need to move to CI, that's a separate task: manual signing, `match` or an
imported distribution profile, and an explicit `ExportOptions.plist`. Don't half-build it now.

### D2: Keep CocoaPods

tribly removed CocoaPods in favour of Swift Package Manager. Do **not** copy that here as part
of T039. autoride's `Podfile` carries the `permission_handler` preprocessor definitions that
commit `cc1c088` added to fix iOS permission requests, and re-doing that under SPM is an
independent change with its own regression risk. Migrating is a fine future task; bundling it
into a release-enablement task is how you end up debugging permissions instead of shipping.

### D3: App Store Connect API key, not an Apple ID session

`upload_to_testflight` needs authentication. An interactive Apple ID session (`spaceauth`)
expires roughly every 30 days and fails mid-release. An ASC API key (`.p8`) does not expire and
works unattended. Store the `.p8` outside the repo — it is equivalent to account credentials.

### D4: The privacy manifest is finished by Apple's feedback loop, not by guessing

`PrivacyInfo.xcprivacy` currently declares two required-reason API categories. With `sqflite`,
`path_provider`, `sensors_plus`, `battery_plus` and `device_info_plus` in the dependency set,
`NSPrivacyAccessedAPICategoryDiskSpace` (`E174.1`) and `NSPrivacyAccessedAPICategorySystemBootTime`
(`35F9.1`) are the likely additions — but I can't state that with certainty without auditing
each plugin's native source, and the plugin set changes with every dependabot bump.

The reliable method: upload, then read the `ITMS-91053: Missing API declaration` email, which
names the exact categories and the SDK that triggered each. Fix, bump, re-upload. Apple treats
these as warnings before they become rejections, so the first upload is a safe probe.

Separately: the manifest declares `NSPrivacyCollectedDataTypeDeviceID` as collected. For an app
whose entire premise is that nothing leaves the device, that looks like an over-declaration —
and it must match the App Privacy answers in App Store Connect exactly. Resolve it in Step 6
rather than propagating it into the store forms.

### D5: iOS background detection is weaker than the copy promises

`UIBackgroundModes` is `["location", "fetch"]`. `fetch` is legitimately used —
`background_location_service.dart:99-102` configures `IosConfiguration(onBackground: onIosBackground)` —
but iOS background fetch is opportunistic: the system decides when, and it can be minutes or
hours. The `NSLocationAlwaysAndWhenInUseUsageDescription` string promises detection "even when
the app is closed", which iOS will not reliably deliver.

Review compares permission copy against observed behaviour. Reconcile the wording (T028 owns
those strings) before submitting for App Store review. TestFlight doesn't enforce this, so it
does not block Step 8 — but it will block the eventual public release.

---

## Implementation Steps

### Step 1: App Store Connect prerequisites (manual)

1. **Register the App ID** `io.github.glandais.autoride` in the Developer Portal, with the
   **Background Modes** capability enabled.
2. **Create the app record** in App Store Connect (platform iOS, the bundle ID above, primary
   language, SKU).
3. **Create an ASC API key** (Users and Access → Integrations → App Store Connect API), role
   *App Manager* or *Admin*. Download the `.p8` — **it is downloadable exactly once**. Save it to
   `~/.secrets/AuthKey_<KEY_ID>.p8`. Note the Key ID and Issuer ID.
4. **Confirm the ITC team ID.** tribly uses `itc_team_id("128752970")` under the same Apple
   account, so it is very likely the same value here — but verify rather than assume:
   `cd ios && bundle exec fastlane run get_itc_team_id` (after Step 6).

### Step 2: Make signing settings explicit

In Xcode (or by editing the pbxproj), on the **Runner** target for all three configurations:

- Set `CODE_SIGN_STYLE = Automatic` explicitly. It's the current effective default, but relying
  on an unstated default in the file that decides how your app is signed is not worth the saved
  line.
- Replace the project-level `CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"` (a name
  Apple retired) with `"Apple Development"`, and let the distribution identity come from the
  profile that `export_method: "app-store"` selects.

Verify the archive picks a distribution identity:

```bash
flutter build ipa --release
# Expect the exported IPA to be signed with "Apple Distribution: ..." — not "Apple Development"
```

### Step 3: Align the display name

`ios/Runner/Info.plist`:

```xml
<key>CFBundleDisplayName</key>
<string>AutoRide</string>
```

Matches T038's `android:label="AutoRide"` and the README. `CFBundleName` (`autoride`) is the
internal short name and stays as-is.

### Step 4: Declare export compliance in `Info.plist`

Without this, every TestFlight build stalls on a manual "does your app use encryption?" answer
before testers can install it — a per-build click, forever.

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

This is accurate for AutoRide: the only network use is HTTPS for OpenStreetMap tiles
(`AndroidManifest.xml` documents the same INTERNET usage), which falls under Apple's exemption
for standard encryption in HTTPS. Revisit if trip sync with custom crypto is ever added.

### Step 5: Decide on iPad

`TARGETED_DEVICE_FAMILY = "1,2"` today (iPhone + iPad). Consequences of leaving it:

- The product page **requires** 13" iPad screenshots in addition to iPhone ones.
- Review tests the app on iPad. A bike trip tracker built around phone-carried motion sensors,
  with layouts only ever verified on iPhone, is a plausible "app doesn't function as expected"
  rejection.

**Recommendation: iPhone only.**

```
TARGETED_DEVICE_FAMILY = "1";
```

on all three Runner configurations. This drops the iPad screenshot requirement and removes a
review surface nobody has tested. `UISupportedInterfaceOrientations~ipad` in `Info.plist`
becomes dead weight — harmless, or remove it for tidiness.

Keep `"1,2"` only if iPad is a deliberate product decision, in which case the iPad layouts need
verifying and iPad screenshots are part of T036.

### Step 6: Reconcile the privacy manifest and App Privacy answers

1. **Review the `DeviceID` declaration** in `PrivacyInfo.xcprivacy`. Trace what actually reads a
   device identifier — `device_info_plus` is used by `PlatformInfoService` for OS-version
   branching, which is not "collection" in Apple's sense if the value is never stored or
   transmitted. If nothing persists or sends it, remove the `NSPrivacyCollectedDataTypeDeviceID`
   entry. Over-declaring forces a matching (and wrong) answer in the ASC App Privacy form.
2. **Leave the required-reason API list as-is for the first upload** (see D4), then add whatever
   `ITMS-91053` names. Expect `DiskSpace` / `SystemBootTime`.
3. **Fill the App Privacy form** in ASC to match the manifest exactly: Location — collected, not
   linked to identity, not used for tracking, purpose App Functionality.

Consider adopting tribly's `store-metadata/data-safety.md`: one file under git as the single
source of truth for the manifest, both store forms, and the privacy policy, with the rule that
they change in the same commit. That file belongs to T037; this step is its first consumer.

### Step 7: fastlane for iOS

`ios/Gemfile`:

```ruby
source "https://rubygems.org"

gem "fastlane"
```

```bash
cd ios && bundle install   # commit the resulting Gemfile.lock
```

`ios/fastlane/Appfile`:

```ruby
app_identifier("io.github.glandais.autoride")
apple_id("gabriel.landais@gmail.com")

itc_team_id("128752970") # App Store Connect team — verify with `fastlane run get_itc_team_id`
team_id("7Q49262697")    # Developer Portal team, matches DEVELOPMENT_TEAM in the pbxproj
```

`ios/fastlane/Fastfile`:

```ruby
default_platform(:ios)

platform :ios do
  desc "Upload a build to TestFlight. Run `flutter build ios --release --no-codesign` " \
       "from the project root first. Version comes from pubspec.yaml."
  lane :beta do
    # Non-expiring auth. An interactive Apple ID session dies roughly monthly and takes a
    # release with it.
    app_store_connect_api_key(
      key_id: ENV.fetch("ASC_KEY_ID"),
      issuer_id: ENV.fetch("ASC_ISSUER_ID"),
      key_filepath: File.expand_path(ENV.fetch("ASC_KEY_PATH")),
      in_house: false,
    )

    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      export_method: "app-store",
      export_options: {
        signingStyle: "automatic",
      },
    )

    # Processing is asynchronous; failures (ITMS-*) arrive by email, not here.
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end
```

Export the three `ASC_*` variables in your shell profile (not in the repo):

```bash
export ASC_KEY_ID="XXXXXXXXXX"
export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export ASC_KEY_PATH="~/.secrets/AuthKey_XXXXXXXXXX.p8"
```

`ENV.fetch` is deliberate: it fails loudly with the missing variable's name rather than falling
through to an interactive Apple ID prompt.

### Step 8: Extend `publish_beta.sh` with the iOS half

iOS goes **before** Android: TestFlight processing is asynchronous and slow to start, so kicking
it off first overlaps it with the Android build.

Insert between the version-bump block and the `# --- android` section from T038:

```bash
# -------------------------------------------------------------------- ios

# Builds App.framework and the Dart assets. fastlane's build_app then archives and signs —
# two compilations, but this is the supported flutter + fastlane split.
flutter build ios --release --no-codesign
(cd ios && { bundle check || bundle install; })
(cd ios && bundle exec fastlane beta --verbose)
UPLOADED="TestFlight"
```

And change the Android section's assignment to accumulate rather than overwrite, so the
failure-handling trap from T038 reports accurately:

```bash
flutter build appbundle --release
(cd android && { bundle check || bundle install; })
(cd android && bundle exec fastlane internal --verbose)
UPLOADED="${UPLOADED:+$UPLOADED + }Play internal"
```

Why this matters: if TestFlight accepts the build and Play then fails, `UPLOADED` is non-empty,
so T038's trap **keeps** the bump instead of rolling it back — correct, because that build
number is now permanently consumed on Apple's side. Overwriting `UPLOADED` would still be
non-empty here, but the failure message would name the wrong platform. Also add the iOS
pre-flight next to T038's `key.properties` check:

```bash
[ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ] ||
  die "ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH must be set (see T039 Step 7)"
```

### Step 9: `.gitignore` additions

`ios/.gitignore` — append. Without this the first `fastlane beta` leaves ~70 MB of build output
untracked-but-visible in the tree:

```gitignore
# Fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots
fastlane/test_output

# Build outputs from `fastlane beta`
*.ipa
*.dSYM.zip
*.dSYM
```

Verify: `git check-ignore -v ios/Runner.ipa ios/Runner.app.dSYM.zip`

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

- [ ] T038 landed (version scheme + `publish_beta.sh` exist)
- [ ] App ID registered with Background Modes; app record created in ASC
- [ ] ASC API key created, `.p8` stored outside the repo, `ASC_*` exported
- [ ] `CODE_SIGN_STYLE` explicit; legacy `"iPhone Developer"` identity replaced
- [ ] `CFBundleDisplayName` is `AutoRide`
- [ ] `ITSAppUsesNonExemptEncryption` present and verified in the built app's Info.plist
- [ ] iPad decision made and applied (`TARGETED_DEVICE_FAMILY`)
- [ ] `DeviceID` declaration in the privacy manifest either justified or removed
- [ ] App Privacy form in ASC matches `PrivacyInfo.xcprivacy`
- [ ] `ios/Gemfile`, `Gemfile.lock`, `fastlane/Fastfile`, `fastlane/Appfile` committed
- [ ] `ios/.gitignore` covers `*.ipa`, `*.dSYM.zip`, fastlane noise — verified with `git check-ignore`
- [ ] `publish_beta.sh` runs iOS before Android and accumulates `UPLOADED`
- [ ] One build accepted by TestFlight and installable by a tester with no compliance click
- [ ] Any `ITMS-*` warnings resolved
- [ ] `README.md` iOS instructions match reality
- [ ] `tasks/TASKS.md` updated (☐ → ✅), progress summary refreshed

---

## References

- Reference pipeline: `../tribly/mobile/ios/fastlane/`, `../tribly/mobile/publish_test.sh`
- Flutter iOS deployment: https://docs.flutter.dev/deployment/ios
- fastlane `pilot`: https://docs.fastlane.tools/actions/upload_to_testflight/
- ASC API keys: https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api
- Required-reason APIs: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api
- Review guidelines, location: https://developer.apple.com/app-store/review/guidelines/#location-services
- Privacy manifest background and rationale: `tasks/T028-platform-config.md:468-520`
- Next: **T040** (Beta Testing & Feedback — depends on T038 + T039)
