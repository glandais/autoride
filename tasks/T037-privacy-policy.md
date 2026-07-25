# T037 - Privacy Policy & Terms

**Status**: ⏳ In Progress — documents written, six code changes outstanding (§5)
**Estimated Time**: 2-3 hours documents (done) + ~2 hours code changes
**Dependencies**: T034 (Data Collection Service) — **resolved, see §1**
**Phase**: 10 - Release Preparation
**Blocks**: T038 (Play needs a privacy policy URL + background-location declaration), T039 (ASC
App Privacy answers)

---

## Overview

Write the legal documents both stores require, and — more importantly — make them *true*.

The audit for this task found that AutoRide's own Settings screen advertises two kinds of data
transmission the app does not perform. A privacy policy cannot be written around that: either the
policy lies, or the UI does. §5.1 resolves it.

---

## 1. The T034 dependency, resolved

`TASKS.md` lists T037 as depending on **T034 (Data Collection Service)**, which is still ☐. The
reasoning was presumably that you cannot describe data collection before building it. But T038 and
T039 both need a privacy policy URL *now*, and T034 sits in Phase 9 behind the whole ML track.

**Resolution:** the policy documents what the app does **today**, and
`store-metadata/data-safety.md` §7 enumerates exactly which future features force a
re-declaration — with T034 as entry §7.1, flagged as a major privacy change rather than an
increment. This is the tribly pattern (`../tribly/mobile/store-metadata/data-safety.md` §8) and it
inverts the dependency correctly: T034 depends on T037's declarations being updated, not the other
way round.

**Action:** change T037's dependency in `TASKS.md` from `T034` to none, and add "update
`store-metadata/data-safety.md` §7.1" to T034's scope when that task is written.

---

## 2. The audit (2026-07-25, commit `cc1c088`)

Everything in the documents rests on this. Re-run §8 of `store-metadata/data-safety.md` before any
submission.

### 2.1 Stored on device

| Data | Where | Evidence |
|---|---|---|
| Trip: times, distance, duration, avg/max speed, activity, confidence, confirmation | SQLite `trips` | `database_service.dart:71-81` |
| Route: lat, lon, altitude, timestamp, accuracy, speed | SQLite `route_points` | `database_service.dart:87-95` |
| Preferences (JSON) | `SharedPreferences` `user_settings` | `settings_repository.dart:11` |
| Theme | `SharedPreferences` `theme_mode` | `theme_provider.dart:10` |
| Onboarding flag | `SharedPreferences` `onboarding_complete` | `app_constants.dart:178` |

### 2.2 Processed, not stored

Accelerometer/gyroscope readings — in memory only; there is no sensor table in the schema.
OS version / API level / `isPhysicalDevice` via `device_info_plus` — `platform_info_service.dart:23-36`.

### 2.3 Transmitted off device

Exactly one endpoint: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
(`trip_map_view.dart:106`, `trip_route_map.dart:134`). Discloses IP address, tile coordinates
(≈ where the user has been) and User-Agent to the OpenStreetMap Foundation. No analytics, no crash
reporting, no backend, no account.

**With no map open, the app makes zero network requests.** That is a strong and unusual privacy
position, and it is worth stating plainly in the store listing.

### 2.4 Findings that contradict existing declarations

1. **No device identifier is read anywhere.** `PlatformInfoService` uses `device_info_plus` for OS
   version only — no `identifierForVendor`, no Android ID, no advertising ID. So
   `NSPrivacyCollectedDataTypeDeviceID` in `PrivacyInfo.xcprivacy` is an over-declaration. (This
   confirms with evidence the suspicion raised in T039 D4.)
2. **The Settings screen promises transmission that does not exist** — see §5.1.
3. **The OSM User-Agent is wrong** — `'com.autoride.app'` instead of the real
   `io.github.glandais.autoride`.
4. **The README described a different product.** `README.md` claimed "**Optional Cloud
   Collection** (with your consent): Anonymized sensor data…, Trip statistics", "Sensor data
   during trips" among locally stored data, "**Access** - Export all your data anytime", and in
   the FAQ "Optional cloud sync is encrypted". There is no cloud, no sync, no sensor persistence
   and no export. On a public repository this contradicted the privacy policy in the same
   breath — and a store reviewer can read it. Corrected as part of this task (§3).

---

## 3. Deliverables (done)

| File | Purpose |
|---|---|
| `docs/legal/privacy-policy.md` | The policy. Store-facing; URL goes in both consoles |
| `docs/legal/terms-of-service.md` | Terms of use, including the cycling safety and accuracy disclaimers |
| `store-metadata/data-safety.md` | Single source of truth for all five declaration artefacts; contains the exact ASC and Play form answers, the Play background-location screencast script, and the re-verification commands |
| `store-metadata/README.md` | The co-modification rule |
| `LICENSE` | MIT. `README.md:9` has advertised an MIT badge linking to `LICENSE` since the first commit, and the file did not exist — a dead link and an unstated licence on a public repo |
| `docs/_config.yml`, `docs/index.md` | GitHub Pages site so the stores get a stable URL — see §4 |
| `README.md` (edited) | "Privacy & Data Collection" section rewritten to match reality (§2.4 item 4), FAQ "data secure" answer corrected, "Optional sharing" bullet replaced, policy and terms linked |

### Notable content decisions

**The map-tile disclosure is prominent, not buried.** The README and the app's own copy say data
stays on the device. That is true of trip data and false of the fact that opening a map tells OSMF
roughly where you have been. The policy states this in the summary rather than in a footnote,
because a reader who takes "everything stays on device" literally would otherwise be misled.

**Play "Approximate location" is declared as *shared*.** Defensible either way — the transfer is
transient and unattributed — but Play treats under-declaration as a policy violation and
over-declaration as merely conservative. `data-safety.md` §5 records the reasoning so the answer
can be defended or revisited rather than re-guessed.

**The iOS backup asymmetry is disclosed, not hidden.** Android excludes the route database from
platform backups; iOS does not. Rather than let the policy imply symmetry, §7.3 states the
difference and tells iOS users how to opt out. §7.5 of `data-safety.md` tracks fixing it in code.

**Terms include a road-safety section.** An app whose premise is "you don't need to touch your
phone while riding" should say so explicitly, and say that the user is responsible for riding
safely.

**Accuracy disclaimers are specific, not boilerplate.** They name the real failure modes found in
the code: misclassification with a confidence score, GPS error worsened deliberately by battery
optimisation, and OS-initiated background termination — with iOS called out as weaker because
`fetch` is opportunistic (the same point as T039 D5).

### ⚠️ Not legal advice

These documents were drafted from a code audit, not by a lawyer. They are accurate about the
app's behaviour, which is the part that gets you rejected or fined. Before the **public** release
(not TestFlight/internal), have someone qualified review them — particularly §5 and §8-§10 of the
Terms, and the GDPR framing in §5 of the policy, given you are established in France.

---

## 4. Hosting — GitHub Pages

Decided and configured. The site is built by GitHub Pages from `docs/` on branch `develop`.

| Document | Canonical URL |
|---|---|
| Privacy policy | `https://glandais.github.io/autoride/legal/privacy-policy.html` |
| Terms of use | `https://glandais.github.io/autoride/legal/terms-of-service.html` |
| Landing page | `https://glandais.github.io/autoride/` |

Files added: `docs/_config.yml` (Jekyll config, `jekyll-theme-primer`), `docs/index.md` (landing
page), plus front matter on both legal documents.

Chosen over a `github.com/.../blob/develop/...` URL because a blob URL encodes the branch name and
file path — renaming `develop` or moving `docs/legal/` would silently 404 a URL filed with both
stores, with no warning. The markdown files stay the single source of truth: Pages renders them,
and `jekyll-relative-links` (on by default for GitHub Pages) keeps the relative `.md` links
working both on github.com and on the published site.

The one link that could not stay relative is Terms §2 → `LICENSE`, which sits outside `docs/` and
so is outside the site root. It now points at an absolute github.com URL.

### Activation (one-off, requires the files to be on `develop` first)

The site cannot build until these files are merged to `develop`. After that:

```bash
# Option A — one command
gh api -X POST repos/glandais/autoride/pages \
  -f 'source[branch]=develop' -f 'source[path]=/docs'

# Option B — Settings → Pages → Source: "Deploy from a branch" → develop / /docs

# Then verify (first build takes ~1 minute)
gh api repos/glandais/autoride/pages -q '.html_url, .status'
curl -sI https://glandais.github.io/autoride/legal/privacy-policy.html | head -1   # expect 200
```

Only once that returns 200 should the URL be entered in the store consoles. Filing a URL that
404s is worse than filing none.

**The URL must be identical in all six places** listed in `store-metadata/data-safety.md` §9.

---

## 5. Outstanding code changes

None of these are in T037's original "write the documents" scope, but the documents are not
truthful without the first, and Play rejects without the second and third. Each is small.

### 5.1 Remove the two toggles that promise transmission (REQUIRED)

`lib/features/settings/presentation/widgets/privacy_settings_section.dart:24-49`

```
"Data collection — Allow anonymous sensor data collection for ML improvement"  → dataCollectionConsent
"Usage statistics — Send anonymous app usage stats"                           → anonymousUsageStats
```

Neither does anything. There is no code path that transmits sensor data or usage statistics —
§2.3 confirms the only network call is map tiles. A user who switches "Send anonymous app usage
stats" **on** reasonably believes data is now being sent. It is not. And a reviewer reading the UI
sees an app that claims to transmit analytics while its Data Safety form says it does not.

**Fix: remove both `SettingTile`s from the widget.** Keep the `dataCollectionConsent` and
`anonymousUsageStats` fields in `UserSettings` — they are harmless, already default to `false`, and
T034 will need the first one. Re-introduce the toggle in T034, next to the code that actually
honours it, with copy that describes real behaviour.

Do **not** just reword the labels. A toggle that persists a preference nothing reads is still a
control that does nothing, and users notice.

### 5.2 Make the privacy policy link work (REQUIRED for Play)

`privacy_settings_section.dart:56-66` currently shows a `"Privacy policy coming soon"` snackbar
behind a `// TODO`. Play requires the policy to be accessible.

Two options — pick one:

- **Open the hosted URL externally.** Add `url_launcher` to `pubspec.yaml`, launch the §4 URL with
  `LaunchMode.externalApplication`. Simplest, one dependency, and the policy is always the current
  published version. **Recommended.**
- **Bundle and render it in-app.** Copy `docs/legal/privacy-policy.md` into `assets/legal/`,
  declare the asset, render with a markdown widget. No network needed, but adds a dependency for
  rendering and the bundled copy goes stale between releases unless the build copies it (tribly
  does this for its web frontend in `build.sh`).

Add a Terms of Use entry next to it either way.

### 5.3 Add the Play prominent disclosure (REQUIRED for Play)

`lib/features/onboarding/presentation/screens/background_permission_screen.dart`

The screen is in the right place in the flow but its copy is a feature pitch. Play requires a
disclosure naming the app, stating background collection, and stating the purpose — before the
permission request, and not only in the privacy policy. Add as a distinct, visually separated
block above the action button:

> **AutoRide collects location data to detect and record your bike trips, even when the app is
> closed or not in use.**
>
> Your trips are stored only on this device. AutoRide has no account and no server — your routes
> are never uploaded. See our Privacy Policy for details.

with "Privacy Policy" tappable (same target as §5.2). The screencast script in
`store-metadata/data-safety.md` §6.3 assumes this block exists and lingers on it.

### 5.4 Fix the OSM User-Agent

`trip_map_view.dart:107` and `trip_route_map.dart:135`:

```dart
userAgentPackageName: 'io.github.glandais.autoride',   // was 'com.autoride.app'
```

The OSMF tile usage policy requires a valid identifying User-Agent; `com.autoride.app` identifies
nothing that exists.

### 5.5 Remove the `DeviceID` declaration from the iOS privacy manifest

`ios/Runner/PrivacyInfo.xcprivacy` — delete the `NSPrivacyCollectedDataTypeDeviceID` dict.
Justification and evidence in §2.4. Overlaps T039 Step 6; do it in whichever lands first, and note
it in the other.

### 5.6 One remaining README claim, left for the product owner

`README.md:30` lists "**Export data** - Download your trip data for analysis" as a feature under
Trip Management. It is not implemented (T035). The surrounding context — "App is currently in
development", "Version: 0.1.0 (Early Development)" — makes the features list read as partly
aspirational, so this was left alone rather than silently rewritten: which features to advertise
before they ship is a product decision, not a privacy one. The privacy-relevant claims were the
ones corrected (§2.4 item 4).

Worth resolving before the store listings are written, because App Review does reject listings
that advertise absent functionality.

### 5.7 Two smaller cleanups

- **iOS backup exclusion** (`data-safety.md` §7.5) — set `NSURLIsExcludedFromBackupKey` on
  `autoride.db` to match the Android posture. Optional, but it is a genuine privacy improvement
  and it lets the policy claim the same protection on both platforms. If done, update
  policy §7.3.
- **Hardcoded version string** — `data_management_section.dart:117-118` hardcodes
  `"AutoRide v1.0.0 (build 1)"`. Correct today, false the moment T038's first release build ships.
  Read it from `package_info_plus` instead, or fold into T038.

---

## 6. Verification

```bash
# Re-run the full data audit — every command's output must match data-safety.md §1-§3
# (the commands live in store-metadata/data-safety.md §8)

# Documents render on GitHub and internal links resolve
#   docs/legal/privacy-policy.md      -> terms-of-service.md, ../../LICENSE
#   docs/legal/terms-of-service.md    -> privacy-policy.md, ../../LICENSE
#   store-metadata/README.md          -> data-safety.md

# README's MIT badge link is no longer dead
ls LICENSE

# After §5: no dead privacy TODO remains
grep -rn "TODO.*privacy\|coming soon" lib --include="*.dart"

# After §5.1: no UI claims transmission
grep -rn "anonymous\|usage stats\|Send " lib/features/settings/presentation/widgets/
```

Then, before submission:

- [ ] Policy URL live and reachable in a private browser window
- [ ] Same URL used in all six places listed in §4
- [ ] ASC App Privacy answers match `data-safety.md` §4
- [ ] Play Data safety answers match `data-safety.md` §5
- [ ] Background-location declaration submitted with the §6.3 screencast
- [ ] Policy "Last updated" date matches the release

---

## 7. Definition of Done

- [x] `docs/legal/privacy-policy.md` written from a code audit, not a template
- [x] `docs/legal/terms-of-service.md` written, with safety and accuracy disclaimers
- [x] `store-metadata/data-safety.md` — five-artefact source of truth, form answers, screencast
      script, re-verification commands
- [x] `store-metadata/README.md` — co-modification rule
- [x] `LICENSE` created (MIT, matching the README badge)
- [x] T034 dependency knot resolved (§1)
- [x] `README.md` privacy claims corrected to match the audit (§2.4 item 4)
- [x] GitHub Pages configured — `docs/_config.yml`, `docs/index.md`, front matter, absolute
      `LICENSE` link (§4)
- [ ] Pages **activated** after these files reach `develop`, and the policy URL returns 200 (§4)
- [ ] §5.1 — misleading Settings toggles removed
- [ ] §5.2 — privacy policy reachable from Settings
- [ ] §5.3 — Play prominent disclosure on the background permission screen
- [ ] §5.4 — OSM User-Agent corrected
- [ ] §5.5 — `DeviceID` removed from the iOS privacy manifest
- [ ] §5.6 — README "Export data" feature claim resolved (product decision)
- [ ] §5.7 — iOS backup exclusion decided; version string de-hardcoded
- [ ] `TASKS.md` dependency for T037 changed from T034 to none
- [ ] Legal review before the **public** release (not required for TestFlight/internal)
- [ ] `TASKS.md` updated (⏳ → ✅) once §5 is complete

---

## 8. References

- Reference pattern: `../tribly/mobile/store-metadata/` (five-artefact rule, §7/§8 structure)
- Play Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Play background location policy: https://support.google.com/googleplay/android-developer/answer/9799150
- Play prominent disclosure requirements: https://support.google.com/googleplay/android-developer/answer/11150561
- Apple App Privacy details: https://developer.apple.com/app-store/app-privacy-details/
- OSMF tile usage policy: https://operations.osmfoundation.org/policies/tiles/
- OSMF privacy policy: https://wiki.osmfoundation.org/wiki/Privacy_Policy
- Related: `tasks/T028-platform-config.md` (permission strings, privacy manifest origin),
  `tasks/T038-android-release.md` (needs the URL + declaration),
  `tasks/T039-ios-release.md` (needs the App Privacy answers)
