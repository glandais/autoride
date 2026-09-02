# AutoRide — Data Collection Declarations (source of truth)

**Last verified against the code:** 2026-09-02
**Verified at commit:** `cc1c088` (branch `wip`); §1-§3 re-verified 2026-09-02 for T042/T043
**Play Console answers filed:** 2026-07-25 (T038) — app `io.github.glandais.autoride`, ID
`4975962567441094743`. §5 reflects what is actually filed, including the approximate-location
decision recorded there.

This file is the single source of truth for what AutoRide collects. Five artefacts describe the
same facts and must agree:

1. `ios/Runner/PrivacyInfo.xcprivacy` — the iOS privacy manifest (validated at upload)
2. App Store Connect → **App Privacy** answers
3. Google Play Console → **Data safety** form
4. `docs/legal/privacy-policy.md`
5. This file

**The rule:** change one, change all five in the same commit. They drift silently otherwise, and
the drift is invisible until a reviewer finds it — at which point you are arguing with App Review
about whether you misrepresented your app.

§7 lists which future features force a re-declaration. §8 is a copy-pasteable re-verification.

---

## 1. What the app stores on the device

| Data | Where | Code |
|---|---|---|
| Trip: start/end time, distance, duration, avg/max speed, detected activity, confidence score, confirmation flag | SQLite `trips` table in `autoride.db` | `database_service.dart:71-81` |
| Route: latitude, longitude, altitude, timestamp, accuracy, speed | SQLite `route_points` table | `database_service.dart:87-95` |
| Preferences (detection, battery, notifications, units, theme) | `SharedPreferences` key `user_settings` (JSON) | `settings_repository.dart:11` |
| Theme selection | `SharedPreferences` key `theme_mode` | `theme_provider.dart:10` |
| Onboarding completion flag | `SharedPreferences` key `onboarding_complete` | `app_constants.dart:178` |
| **Diagnostic log (opt-in, off by default)**: trip state changes, detector decisions and scores, GPS fixes (lat/lon/accuracy/speed/altitude/heading), battery level and power mode, permission status, which notification was shown/cancelled/tapped (never its text), app lifecycle, errors — and, at "Verbose", one-per-second sensor *summaries* and rejected fixes | SQLite `audit_events` table in a **separate** `autoride_audit.db` | `audit_database.dart`, `sqlite_audit_sink.dart` |

Database names and versions: `autoride.db` v3 and `autoride_audit.db` v1
(`app_constants.dart`, `databaseVersion` / `auditDatabaseVersion`).

**The diagnostic log is off unless the user turns it on** (`UserSettings.auditLogEnabled`,
default `false`); until then no audit database file is created at all. It self-expires after 7
days / 200 000 entries / ~20 MB, whichever comes first, and Settings → Diagnostic log → Clear log
deletes the file. It never leaves the device on its own — see §3.4.

**Android backup posture:** `allowBackup="false"` and `fullBackupContent="false"`
(`AndroidManifest.xml`, with rationale in the comment above the `<application>` tag). The route
database is deliberately excluded from Google auto-backup and `adb backup`.

**iOS backup posture:** no backup exclusion is set, so `autoride.db` is included in iCloud and
local device backups. This is a **known inconsistency** with the Android posture — see §7.5.

## 2. Data processed but NOT stored

| Data | Why it is not "collected" |
|---|---|
| Accelerometer and gyroscope readings | Read continuously for pedalling detection, processed in memory, never written to the trip database (there is no sensor table) or transmitted. `sensor_service.dart`, `motion_detection_service.dart`, `cycling_pattern_detector.dart`. **Caveat since T043:** with the opt-in diagnostic log at "Verbose", one aggregate per second (mean, std-dev, motion state) is written to `autoride_audit.db`. The raw 50 Hz stream is never recorded at any level. |
| OS version, API level, `isPhysicalDevice` | Read at runtime for per-version permission branching. Not persisted, not transmitted. `platform_info_service.dart:23-36` |

**No device identifier is read anywhere.** `PlatformInfoService` uses `device_info_plus` for OS
version only — it does not touch `identifierForVendor`, Android ID, or any advertising ID.
Verified 2026-07-25. This is why §3.1 removes the `DeviceID` entry from the iOS manifest.

## 3. Data transmitted off the device

### 3.1 Map tiles — the only network egress

`https://tile.openstreetmap.org/{z}/{x}/{y}.png`, requested by `flutter_map` when a map is
displayed.

- `trip_map_view.dart:106` (live tracking screen)
- `trip_route_map.dart:134` (trip detail route)

Each request discloses to the OpenStreetMap Foundation: the client **IP address**, the **tile
coordinates** (which reveal the map area being viewed, i.e. approximately where the user has
been), and a **User-Agent**. No trip data, route history, or identifier is attached.

If no map view is opened, the app makes **zero** network requests.

> **Open defect:** `userAgentPackageName` is `'com.autoride.app'` in both files — not the real
> application ID `io.github.glandais.autoride`. The OSMF tile usage policy requires a valid
> identifying User-Agent, so this is both a factual error and a policy-compliance issue. Fix
> tracked in `tasks/T037-privacy-policy.md`.

### 3.2 What is absent

No analytics SDK. No crash reporting. No advertising SDK. No AutoRide backend, account, login, or
sync. Confirmed by §8's egress grep: the two tile URLs above are the only outbound endpoints in
`lib/`.

### 3.3 Files the user exports (T042, T043)

Two features write a file and pass it to the OS share sheet. Neither performs a network request:
the app hands `share_plus` a path and learns nothing about where it goes.

| Feature | File | Contents | Code |
|---|---|---|---|
| Export as FIT | `.fit` activity | One trip: route, timings, speeds | `trip_export_service.dart` |
| Export log | `.ndjson.gz` | The diagnostic log of §1, **including precise coordinates** | `audit_export_service.dart` |

**Why this is not "sharing" under either store's definition, and the condition attached.**
Google's and Apple's definitions both exclude a transfer the *user* initiates through system UI,
**provided the user is informed of what is being transferred**. For the FIT file the content is
self-evident (it is the ride the user asked to export). For the diagnostic log it is not, so the
app shows a blocking dialog naming what the file holds — precise GPS positions, routes, departure
points, device model, OS and app version — and what it does not (name, email, advertising ID),
before the share sheet opens.

That dialog is therefore **a condition of the declarations in §5 and §4 being accurate, not a
nicety**. `AuditPrivacyDialog` (`audit_privacy_dialog.dart`) implements it and
`audit_log_section_test.dart` pins that cancelling it performs no export. Removing or weakening it
re-opens the "Data shared" answer on both stores.

## 4. iOS — `PrivacyInfo.xcprivacy` target contents

### 4.1 Collected data types

| Type | Collected | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| `NSPrivacyCollectedDataTypeLocation` | Yes | No | No | App Functionality |

Location is declared as collected — the conservative reading, and it matches the Play answer for
precise location in §5. Under a strict reading of Apple's definition (data retained beyond
servicing the request) the app arguably collects nothing, since routes never leave the device;
over-declaring here is safe.

Do **not** justify this entry by the map tile requests in §3.1. That argument was considered and
rejected on 2026-07-25 — see §5 — and an iOS declaration resting on a premise the Play
declaration denies is exactly the kind of drift this file exists to prevent.

`NSPrivacyTracking` = `false`. `NSPrivacyTrackingDomains` = empty.

**Required change:** remove the `NSPrivacyCollectedDataTypeDeviceID` entry currently in the
manifest. Nothing in the app reads a device identifier (§2). Leaving it forces a matching — and
false — answer in the App Store Connect form.

### 4.2 Required-reason API declarations

Currently declared:

| Category | Reason | For |
|---|---|---|
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `0A2A.1` | SQLite database files in the app container |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `1C8F.1` | Settings storage |

**Expected additions** — `NSPrivacyAccessedAPICategoryDiskSpace` (`E174.1`) and
`NSPrivacyAccessedAPICategorySystemBootTime` (`35F9.1`), likely triggered by `sqflite`,
`path_provider` or `sensors_plus`. Do not add these speculatively: the authoritative list arrives
as an `ITMS-91053` email after the first upload, naming the exact category and the SDK
responsible. See T039 D4.

## 5. Google Play — Data safety answers

**Does your app collect or share any of the required user data types?** — **Yes**

| Data type | Collected | Shared | Processed ephemerally | Required or optional | Purpose |
|---|---|---|---|---|---|
| Location → **Precise location** | Yes | No | No | Required | App functionality |
| Location → **Approximate location** | No | No | — | — | — |

**Precise location — collected, not shared:** GPS routes are stored on the device
(§1). Not transmitted to the developer or anyone else.

**Approximate location — declared as neither collected nor shared.** Decided by the product
owner on 2026-07-25, and this is the answer filed in the Play Console. The reasoning:

- No coordinate belonging to the user is ever transmitted. The map tile requests in §3.1 carry
  *tile* coordinates for the viewport plus the IP address that any HTTP request carries. Play's
  data types cover user data the app sends; a viewport identifier and a transport-level IP are
  not the user's position as a declared data type.
- Play's "shared" definition carries an exception for data transferred by a specific
  user-initiated action where the transfer is what the user asked for. Rendering a map the user
  opened is that: no map view, no request at all (§3.1).

**The counter-argument, recorded so this is not silently re-decided:** §3.1 states that on the
live-tracking screen the map is centred on the rider, so the requested tile coordinates do reveal
roughly where they are, at tile granularity. An earlier revision of this file declared approximate
location as *shared* on that basis, reasoning that Play treats under-declaration as a policy
violation and over-declaration as merely conservative. Both readings are defensible; the one above
is the one filed. If Play ever queries the declaration, this paragraph is the argument to weigh
against, not a loose end to tidy up.

Note this changes nothing about what the app actually does, and nothing in
`docs/legal/privacy-policy.md` §3.1 — that section discloses the tile requests, the IP, and the
"approximately where you have been" implication in full, deliberately telling users more than the
Play taxonomy asks for. Disclosing more to users than a store form requires is not an
inconsistency; declaring less to users than the store form would be.

Answers for every other section: **No** — no personal info, no financial info, no health or
fitness data type (trip distance/speed is not declared as "Fitness info": that Play category
covers health-app data such as heart rate and workouts logged as fitness records; revisit if
AutoRide ever exports to a fitness platform), no messages, no photos or videos, no audio, no
files, no calendar, no contacts, no app activity, no web browsing, no app info and performance
(there is no crash reporting), no device or other IDs.

**Data handling questions:**

- Is all user data encrypted in transit? **Yes** — the only network call is HTTPS.
- Do you provide a way for users to request data deletion? **Yes** — in-app deletion,
  Settings → Data Management → Clear all trips. There is no server-side data to request deletion
  of.
- Has your app's data collection been independently validated? **No.**
- Data types collected are handled as: not linked to identity, not used for tracking.

## 6. Play background location declaration

`ACCESS_BACKGROUND_LOCATION` (`AndroidManifest.xml:39`) triggers a separate Play review with its
own form. It requires all three of:

**6.1 A privacy policy URL** — see §9.

**6.2 A prominent in-app disclosure**, shown *before* the background permission is requested,
that is not only in the privacy policy. It must name the app, say that location is collected in
the background, and say what for.

`background_permission_screen.dart` already sits in the right place in the flow and explains the
feature, but its current copy ("Enable background location to automatically detect and record
trips even when the app is closed") reads as a feature pitch rather than a collection
disclosure. Required copy, to be added as a distinct disclosure block on that screen:

> **AutoRide collects location data to detect and record your bike trips, even when the app is
> closed or not in use.**
>
> Your trips are stored only on this device. AutoRide has no account and no server — your routes
> are never uploaded. See our Privacy Policy for details.

**6.3 A screencast** demonstrating the background feature and the disclosure. Recording script:

1. Fresh install, app launch, through onboarding to the background permission screen.
2. Hold on the disclosure text long enough to read it.
3. Grant background location, showing the system dialog and "Allow all the time".
4. Close the app entirely (not just backgrounded).
5. Start cycling; show the ongoing notification appearing on its own.
6. Reopen the app; show the trip that was recorded while it was closed.
7. Show Settings → Data Management → Clear all trips as the deletion path.

Upload as an unlisted YouTube video and put the URL in the declaration form.

## 7. What forces a re-declaration

Adding any of these means updating all five artefacts in §0 **in the same commit**:

| Change | New declaration required |
|---|---|
| **7.1 T034 — Data Collection Service** (contribute sensor data for ML) | This is the first feature that would transmit user data to the developer. Requires: iOS manifest addition, ASC App Privacy update, Play "Collected" + purpose "Analytics"/"App functionality", privacy policy §3 and §10 rewritten, explicit opt-in consent flow, and a data-retention statement. Treat as a major privacy change, not an increment. |
| **7.2 T035 — Training Data Export** (CSV/JSON export) | Depends on destination. Export to a user-chosen local file is not "collection". Export that uploads anywhere is. Also touches the iOS `FileTimestamp` reasons. |
| **7.2b T043 — Diagnostic log** (shipped 2026-09-02) | Handled without a re-declaration, on the §3.3 reasoning: opt-in, stored locally, self-expiring, and exported only by an informed user through the system share sheet. What would re-open it: uploading a log automatically, sending one anywhere without the confirmation dialog, or recording raw sensor streams. |
| **7.3 Any analytics or crash-reporting SDK** (Firebase, Sentry, …) | Play "App info and performance → Crash logs / Diagnostics", ASC "Diagnostics", iOS manifest additions plus the SDK's own privacy manifest, and possibly `NSPrivacyTrackingDomains`. |
| **7.4 Accounts, sync, or a backend** | Rewrites everything. The current policy's central claim ("no server") stops being true. |
| **7.5 iOS backup exclusion** (setting `NSURLIsExcludedFromBackupKey` on `autoride.db`) | Would let the privacy policy §7.3 claim the same protection on both platforms. Currently the policy discloses the asymmetry honestly instead. Small code change, meaningful privacy improvement — worth doing, but it changes what the policy says. |
| **7.6 Replacing or adding a map tile provider** | §3.1 names OSMF specifically, and §5's "not shared" answer rests on OSMF serving a tile and keeping nothing. A commercial provider (Mapbox, Google) usually means a third party that *retains* data, likely an API key tied to an account — which breaks that reasoning and would make approximate location genuinely **shared**. Re-open §5 before switching providers. |
| **7.7 Health/fitness platform integration** (Apple Health, Google Fit, Strava) | Adds a health data type on both stores and, for HealthKit, its own set of manifest and review requirements. |

## 8. How to re-verify (run this before any submission)

```bash
# 1. Network egress. Expect ONLY the two tile.openstreetmap.org URLs from §3.1.
grep -rn "http://\|https://\|Uri\.\|HttpClient\|Dio\|package:http" lib --include="*.dart" \
  | grep -v "\.g\.dart\|\.freezed\.dart"

# 2. Persistent storage. Expect trips + route_points in the trip database, and
#    audit_events (opt-in diagnostic log, §1) in its own database. No sensor or
#    identifier table in either.
grep -n "CREATE TABLE" lib/features/trip_detection/data/services/database_service.dart
grep -rn "CREATE TABLE" lib/features/diagnostics/data/services/audit_database.dart

# 2b. The diagnostic log must stay off by default and gated behind the warning
#     dialog. Expect `@Default(false) bool auditLogEnabled` and a call to
#     AuditPrivacyDialog.show before any shareLog().
grep -n "auditLogEnabled" lib/features/settings/domain/models/user_settings.dart
grep -n "AuditPrivacyDialog.show" -A3 lib/features/diagnostics/presentation/widgets/audit_log_section.dart

# 3. Preferences keys. Expect user_settings, theme_mode, onboarding_complete.
grep -rn "SharedPreferences\|prefs\.set" lib --include="*.dart" \
  | grep -v "\.g\.dart\|\.freezed\.dart"

# 4. Device identifiers. Expect NO hits.
grep -rn "identifierForVendor\|androidId\|advertisingId\|AdvertisingId\|deviceId" lib

# 5. Analytics/crash SDKs. Expect NO hits.
grep -riE "firebase|sentry|crashlytics|analytics|mixpanel|amplitude|posthog" pubspec.yaml

# 6. Permissions actually requested vs declared.
grep -n "uses-permission" android/app/src/main/AndroidManifest.xml
grep -n "UsageDescription\|UIBackgroundModes" -A2 ios/Runner/Info.plist
```

Any hit that contradicts §1-§3 means this file is stale. Update it and the other four artefacts
before submitting.

## 9. Hosting the privacy policy

Both stores need a public URL. **These are the canonical URLs** — GitHub Pages, built from the
`docs/` folder of branch `develop` (config in `docs/_config.yml`):

| Document | URL |
|---|---|
| Privacy policy | `https://glandais.github.io/autoride/legal/privacy-policy.html` |
| Terms of use | `https://glandais.github.io/autoride/legal/terms-of-service.html` |
| Landing page | `https://glandais.github.io/autoride/` |

Pages rather than a `github.com/.../blob/develop/...` URL because a blob URL encodes the branch
name and the file path: renaming `develop`, or moving `docs/legal/`, would silently 404 a URL
filed with both stores. The markdown files remain the single source of truth — Pages renders
them, it does not copy them.

**The privacy policy URL must be identical in all six places:**

1. Play Console → store listing → privacy policy
2. Play Console → Data safety form
3. Play Console → background location access declaration
4. App Store Connect → App Privacy → privacy policy URL
5. In-app link — `privacy_settings_section.dart` (T037 §5.2)
6. In-app background-location disclosure — `background_permission_screen.dart` (§6.2)

## 10. Known inconsistencies to resolve before submission

Tracked in `tasks/T037-privacy-policy.md`:

1. **Settings UI claims data transmission that does not happen** — "Data collection" and "Usage
   statistics" toggles (`privacy_settings_section.dart:24-49`) imply the app sends sensor data and
   usage stats. It sends neither. This contradicts §3.2 and the privacy policy.
2. **Privacy policy link is a stub** — `privacy_settings_section.dart:56-66` shows a "coming soon"
   snackbar. Play requires an accessible policy.
3. **`DeviceID` over-declared** in the iOS manifest (§4.1).
4. **OSM User-Agent is wrong** (§3.1).
5. **iOS backup asymmetry** (§7.5).
6. **Hardcoded version string** — `data_management_section.dart:117-118` hardcodes
   "AutoRide v1.0.0 (build 1)", which becomes false at the first release build.
