# AutoRide — Release Ledger

**Purpose**: everything between `1.0.0+18` on the beta tracks and a **public** listing on Google
Play and the App Store, as one list. `TASKS.md` stays the source of truth for task status and
`LEDGER.md` for field findings; this file only says what a public release is waiting on, in what
order, and points at them.

**Opened**: 2026-09-21, from a store-readiness assessment of `develop` at `c980801`.
**Verdict that day**: ready for a wider beta (TestFlight external, Play closed testing); **not**
ready for production. The release plumbing is mature — the blocker is the product's core promise,
automatic detection (section A).

**Status**: ☐ pending · ⏳ in progress · ✅ done · ❓ needs a fact only the maintainer has

**Rule**: an item closes on evidence (a commit, a console screenshot, a log read through the
`autoride-audit-log` skill), not on an impression. When one closes, keep the line and add the
evidence — do not delete it.

---

## A. Product blockers — what would earn one-star reviews

Publishing before these are settled means a History full of phantom rides and a drained battery.
None of them is a store-compliance matter; no reviewer will catch them, every user will.

| ID | Status | Item | Exit criterion | Refs |
|---|---|---|---|---|
| R-01 | ☐ | **False starts at rest.** 26 trips opened and 4 kept over 26 h on +16; 22 phantom recordings in one idle evening. The replay refuted lengthening the streak; the duty-cycle candidate removes ~40 %. | A false-start **rate** agreed in advance (not zero — T054 says zero is out of reach) and met over a week of ordinary carry, on both platforms, re-measured with `scripts/t054-replay/`. | T054 (1), L-108, L-104, L-114 |
| R-02 | ☐ | **Back-date is dead on iOS.** The riding-tail cut reads `sp`, iOS reports `sp: 0` through a departure, so no `bdate` in 26 h and every start is late by the whole confirmation delay. Must land **before** R-01, whose added latency is only acceptable back-dated away. | A Karoo-paired ride starting within 60 s **with `bdate` present**. | T054 (3), L-110, T041 item 11 |
| R-03 | ☐ | **The speed weight has never voted** (`vt:false` on 26 of 26 starts): delete it and set the threshold on the motion score, or open the gate to decide — and say which. | The decision is written down and `tripStartSpeedWeight` either votes or is gone. | T054 (2), L-109 |
| R-04 | ☐ | **Battery drain is unmeasured.** 55 % → 1 % overnight with no ride (verbose log, so an upper bound); the < 5 %/h target has never been measured at `normal` level. | T041 item 4 measured on a release build, log at `normal`, idle day and ride day, both platforms. Depends on R-01 (phantom recordings hold the GPS gate open). | T041 item 4, T032, L-105 |
| R-05 | ☐ | **Android is barely validated.** Most of the T041 checklist is unrun on Android; the Pixel got no GNSS fix in 25 min of riding (2026-09-03); a 7 min 48 s hole in the fix stream is unexplained. | T041 checklist run on the Pixel on a current build; L-088's cause and L-092 diagnosed or shown not to recur. | T041, L-088, L-092 |
| R-06 | ☐ | **Seven code-complete tasks wait on device runs** (T046, T048–T053), and builds +17/+18 have no field run at all. | Each task's own acceptance section passed and the task set to ✅ in `TASKS.md`. | T046, T048–T053 |
| R-07 | ☐ | **Decide what 1.0 says about cars and walks.** Nothing classifies the mode; a drive is recorded as a ride with a badge. Acceptable for 1.0 only if the listing does not promise otherwise. | Listing copy re-read against this; the IMU classifier (T016–T019, fed by T034) explicitly scheduled after 1.0 or before it. | T053, T016–T019, T034 |
| R-08 | ☐ | `resumeMovementThresholdSeconds` and the 40 Hz iOS request inherit whatever R-01 settles. | Follows R-01. | T054 (4)(5), L-111, L-112 |

## B. Store compliance — hard blockers, short work

| ID | Status | Item | Exit criterion | Refs |
|---|---|---|---|---|
| R-10 | ✅ | `PrivacyInfo.xcprivacy` was on disk and in no Xcode target, so no IPA carried it. | `d51538b` (2026-09-21) — verified in `build/ios/iphoneos/Runner.app/`. **Still to do**: ship it (next `./publish_beta.sh`) and watch for an `ITMS-91053` e-mail. | T039 |
| R-11 | ✅ | Play description promised "Physical activity is used to recognise cycling"; `ACTIVITY_RECOGNITION` is neither declared nor requested. | `363384e` (2026-09-21). **Still to do**: push the listing (`fastlane metadata`). | T037, L-028 |
| R-12 | ☐ | **Screenshots — none exist, for either store.** Rejection is automatic without them. Captured from real rides, not mock-ups; iOS needs the 6.9" size (iPhone 17 Pro Max simulator is the pinned device). | `phoneScreenshots/` populated for Play; screenshots uploaded in App Store Connect. | L-033, `asc-shots-pipeline` / `koubou` skills |
| R-13 | ☐ | **Play feature graphic (1024×500)** — missing, and production refuses a listing without it. | `images/featureGraphic.png` in `android/fastlane/metadata/android/en-US/`. | L-033 |
| R-14 | ☐ | **Play Console, manual**: Data safety form (answers in `store-metadata/data-safety.md` §5), background-location declaration **with its screencast** (§6 — reviewed strictly), accept Play App Signing, content rating, target audience. | Each form saved in the console; the declaration approved. | T038 |
| R-15 | ❓ | **Play's 12-testers / 14-days rule.** A personal developer account created after November 2023 must run a closed test with 12 opted-in testers for 14 days before production access. Not knowable from the repository. If it applies, it sets the earliest possible Play date — start the clock first. | The account's status is written here; if it applies, the closed test's start date too. | — |
| R-16 | ☐ | **App Store Connect**: `asc validate` was down to 2 errors on 2026-09-01 — attach a build, add screenshots. Re-run it; the build to attach must carry R-10. | `asc validate` clean. | T039, `asc-submission-health` skill |
| R-17 | ☐ | **Two `launchUrl` links and the new OSM link are unverified on devices** (Android 11+ package visibility, iOS). | Tapped on a Pixel and an iPhone, each opens the browser. | T037 "Not yet verified on a device", `50fe5ea` |
| R-18 | ☐ | **Motion & Fitness prompt on iOS** still unverified on a device. | T041 item 7 closed. | T039, T041 item 7 |

## C. Decisions to take before going public

| ID | Status | Item | Refs |
|---|---|---|---|
| R-20 | ☐ | **Diagnostics log and Training capture are visible in release builds** — right for testers, a question for the public: they record unrounded GPS and raw sensor streams. Keep (off by default, as today), hide behind a gesture, or strip from production. If kept, `data-safety.md` §3.3's blocking dialog stays load-bearing. | `settings_screen.dart:85-96`, T043, T034 |
| R-21 | ☐ | **R8 / minification is off** (D6) and there is no `proguard-rules.pro`. Its failures are runtime-only: turning it on costs one physical-device smoke test of the whole flow. Decide before production, not before beta. | L-048, T038 |
| R-22 | ☐ | **Play service account is account-level Administrator and shared with Pedalons** — one leaked key publishes both apps. Scope it down before the public release. | L-051, T038 |
| R-23 | ☐ | **OSM tile servers.** `tile.openstreetmap.org` tolerates light use; a public launch may not be light. Changing provider re-opens `data-safety.md` §5 (§7.6) — a provider that retains data makes approximate location *shared*. | `data-safety.md` §7.6 |
| R-24 | ☐ | **English only, every string hardcoded.** No l10n scaffolding at all. Decide whether 1.0 ships English-only (then say so nowhere it matters) or whether French is a launch requirement — the listing has only `en-US` too. | — |
| R-25 | ☐ | **App Store listing is not versioned** (`ios/fastlane/metadata/` absent, managed by hand in ASC). Pull it with `asc metadata pull` so both listings can be reviewed side by side, or accept the asymmetry. | T039, `asc-metadata-sync` skill |

## D. Quality and hygiene — should be done, will not block a review

| ID | Status | Item | Refs |
|---|---|---|---|
| R-30 | ✅ | Open-source licences page, with the bundled Roboto licence registered. | `90118ec` (2026-09-21) |
| R-31 | ✅ | OSM attribution opens the copyright page instead of a `debugPrint`. | `50fe5ea` (2026-09-21) |
| R-32 | ✅ | README no longer advertises an unimplemented "Export data"; `data-safety.md` §10 re-verified (5 of 6 fixed). | `363384e` (2026-09-21), T037 §5.6 |
| R-33 | ☐ | **iOS backup exclusion**: `autoride.db` goes to iCloud backup while Android has `allowBackup="false"`. Set `NSURLIsExcludedFromBackupKey` (native code), then update policy §7.3 and close `data-safety.md` §10 item 5. | T037 §5.7, `data-safety.md` §7.5 |
| R-34 | ☐ | **Accessibility**: not one `Semantics` / `semanticLabel` in `lib/`. At least label the icon-only actions and the map; run a VoiceOver and a TalkBack pass. | `design:accessibility-review` skill |
| R-35 | ☐ | **Dead `activityRecognition` permission model** in `lib/core/permissions/` — no caller. Delete it, or keep it knowingly for the classifier. | L-028 |
| R-36 | ☐ | Widget tests for settings, history, detail, `InitialRouteScreen`; an E2E flow. | T030, T031 |
| R-37 | ☐ | CI: `flutter pub get --enforce-lockfile`, coverage collection. | L-050 |
| R-38 | ☐ | Release lanes: un-skip the changelog upload; remember `release_status` after the first production upload. | L-032, L-035 |
| R-39 | ☐ | FIT export never validated end to end — share sheet on a device, an actual import into Strava / Garmin Connect, encode time of a multi-hour ride. | T042 |
| R-40 | ☐ | Support surface: the listings need a support URL/e-mail that someone reads; `docs/index.md` is the page today. Check it says how to report a bad detection (and how to export the log). | T040 |

---

## Suggested order

1. **Now, in parallel with everything else** — R-15 (find out), R-12/R-13 (assets have lead time),
   R-14, then ship a build carrying R-10 and open **TestFlight external + Play closed testing**
   (T040). That starts any 14-day clock and brings logs from pockets other than the maintainer's.
2. **The detection work** — R-02 → R-01 → R-03 → R-08, each settled by replay first and a device
   run second, as T054 prescribes.
3. **Then measure** — R-04 on the build that carries step 2, with R-05 and R-06 run on the same
   outings wherever one ride can serve several acceptances.
4. **Before flipping to production** — section C decided, R-16 clean, R-17/R-18 tapped through,
   R-33 if the policy is to claim the same protection on both platforms.

**Go / no-go for production**: R-01 and R-04 met over a week of real carry on both platforms, all
of section B ✅, every section C line carrying a written decision.

---

**Last updated**: 2026-09-21
