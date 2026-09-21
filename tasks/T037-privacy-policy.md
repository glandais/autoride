# T037 - Privacy Policy & Terms

**Status (2026-09-13)**: ⏳ In progress. The legal documents, the data-safety source of truth, GitHub
Pages hosting, and code changes §5.1–§5.5 all shipped and are verified in the repo (see Delivered
below). Still open: device verification of the two `launchUrl` links and the §5.7 iOS
backup-exclusion half (§5.6 was resolved on 2026-09-21; the version-string half of §5.7 has since shipped —
`data_management_section.dart` now reads `PackageInfo.fromPlatform()` rather than a hardcoded
string), legal review before public release, and flipping `TASKS.md` to ✅.

---

## Documents, audit, and hosting (done)

**Why:** Both stores require a privacy policy and terms of use, and App Review/Play rejects a
listing whose own UI or README contradicts its privacy declarations. The task started by auditing
what the app actually collects/stores/transmits, then wrote the documents from that audit rather
than a template, and fixed the contradictions the audit found.

**Durable decisions:**
- The T034 dependency was inverted: the policy documents today's behavior, and
  `store-metadata/data-safety.md` §7 lists what future features (T034 first) will force to be
  re-declared — `TASKS.md`'s T037 dependency is now `None`.
- Only one network endpoint exists: OSM map tiles. No analytics, no crash reporting, no backend,
  no account, no device identifier read anywhere. With no map open the app makes zero network
  requests — stated plainly in the policy rather than left implicit.
- Play "Approximate location" is declared as *shared* (defensible either way, but Play punishes
  under-declaration harder than over-declaration) — reasoning kept in `data-safety.md` §5 so it can
  be revisited rather than re-guessed.
- Hosting is GitHub Pages built from `docs/` on `develop`, chosen over a `github.com/.../blob/...`
  URL because a blob URL encodes the branch/path and would silently 404 if either changed.
- `store-metadata/data-safety.md` is the single source of truth for both stores' privacy
  declarations (ASC App Privacy, Play Data safety, the Play background-location screencast script,
  and the re-verification commands) — do not restate these answers elsewhere.

**Delivered:** `docs/legal/privacy-policy.md`, `docs/legal/terms-of-service.md`,
`store-metadata/data-safety.md`, `store-metadata/README.md`, `LICENSE` (MIT), `docs/_config.yml`,
`docs/index.md`, `README.md` (privacy section, FAQ, "Optional sharing" bullet corrected). GitHub
Pages is live and verified (`https://glandais.github.io/autoride/legal/privacy-policy.html` →
HTTP 200 as of this trim).

**Pitfalls:**
- These documents were drafted from a code audit, not by a lawyer — legal review is still required
  before the **public** release (not needed for TestFlight/internal). See "Remaining work" below.
- The iOS backup asymmetry (Android excludes the route DB from platform backups, iOS does not) is
  disclosed in the policy §7.3 rather than silently implied symmetric — fixing the asymmetry itself
  is still open, see §5.7 below.

## Code changes §5.1–§5.5 (done, 2026-07-25)

**Why:** The Settings screen advertised two data-transmission toggles the app does not implement,
the privacy-policy link was a "coming soon" stub, Play requires a prominent disclosure before the
background-location permission prompt, the OSM tile requests carried a fake User-Agent, and the iOS
privacy manifest over-declared a device-identifier collection that doesn't happen in code.

**Durable decisions:**
- The misleading `dataCollectionConsent` / `anonymousUsageStats` toggles were removed from
  `PrivacySettingsSection` (now a `StatelessWidget`) rather than reworded — a toggle that persists a
  preference nothing reads is still a control that does nothing. The `UserSettings` fields
  themselves were kept for T034 to wire up for real; T034 has since done so
  (`dataCollectionConsent` is now read by real code, per the comment in
  `privacy_settings_section.dart:19`).
- Privacy policy/terms links open the hosted GitHub Pages URL externally
  (`lib/core/utils/legal_links.dart`, `AppConstants.privacyPolicyUrl`/`.termsOfUseUrl`) rather than
  bundling a copy in-app, so the published document is always current.
- OSM User-Agent corrected to `io.github.glandais.autoride` in both map widgets.
- `NSPrivacyCollectedDataTypeDeviceID` removed from `ios/Runner/PrivacyInfo.xcprivacy`.

**Delivered:** `lib/features/settings/presentation/widgets/privacy_settings_section.dart`,
`lib/core/utils/legal_links.dart`, `lib/core/constants/app_constants.dart` (URL constants),
`lib/features/onboarding/presentation/screens/background_permission_screen.dart` (prominent
disclosure block), `lib/features/trip_detection/presentation/widgets/trip_map_view.dart`,
`lib/features/trip_history/presentation/widgets/trip_route_map.dart`, `ios/Runner/PrivacyInfo.xcprivacy`.

**Pitfalls:**
- No `<queries>` entry was added to `AndroidManifest.xml` for the two `launchUrl(...,
  LaunchMode.externalApplication)` calls — `canLaunchUrl`, which needs one, isn't used, only
  `launchUrl` is. This is deliberate but unverified on a real device; still listed under Remaining
  work below since it wasn't re-confirmed in this pass.

---

## Remaining work

### Not yet verified on a device

The two new links call `launchUrl` with `LaunchMode.externalApplication`. No `<queries>` entry was
added to `AndroidManifest.xml` because Android's package-visibility rules constrain `canLaunchUrl`
(which the code does not use), not launching itself — but this should be confirmed on a physical
Android 11+ device and on iOS before submission.

### 5.6 README "Export data" claim — resolved 2026-09-21

*As found:* `README.md:30` listed "**Export data** - Download your trip data for analysis" as a feature under
Trip Management. It was not implemented (T035). The surrounding context — "App is currently in
development" — makes the features list read as partly
aspirational, so this was left alone rather than silently rewritten: which features to advertise
before they ship is a product decision, not a privacy one. The privacy-relevant claims were the
ones corrected (§2.4 item 4 of the original audit).

It was worth resolving before the store listings were written, because App Review does reject
listings that advertise absent functionality.

**Resolved 2026-09-21.** The line now reads "Export a ride — Share a single trip as a Garmin FIT
file through the system share sheet", which is exactly what `lib/features/trip_export/` does; the
generic "download your trip data for analysis" of T035 is no longer advertised.

### 5.7 Two smaller cleanups

- **iOS backup exclusion** (`data-safety.md` §7.5) — set `NSURLIsExcludedFromBackupKey` on
  `autoride.db` to match the Android posture. Optional, but it is a genuine privacy improvement
  and it lets the policy claim the same protection on both platforms. If done, update
  policy §7.3.
- **Hardcoded version string** — `data_management_section.dart:117-118` hardcodes
  `"AutoRide v1.0.0 (build 1)"`. Correct today, false the moment T038's first release build ships.
  Read it from `package_info_plus` instead, or fold into T038.

  *(Note added during this trim: the `package_info_plus` half of this item has since shipped —
  `data_management_section.dart` now calls `PackageInfo.fromPlatform()`. The iOS backup-exclusion
  half above is still open.)*

## Verification

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
- [ ] Same URL used in all six places listed in `data-safety.md` §9
- [ ] ASC App Privacy answers match `data-safety.md` §4
- [ ] Play Data safety answers match `data-safety.md` §5
- [ ] Background-location declaration submitted with the §6.3 screencast
- [ ] Policy "Last updated" date matches the release

## Definition of Done

- [x] `docs/legal/privacy-policy.md` written from a code audit, not a template
- [x] `docs/legal/terms-of-service.md` written, with safety and accuracy disclaimers
- [x] `store-metadata/data-safety.md` — five-artefact source of truth, form answers, screencast
      script, re-verification commands
- [x] `store-metadata/README.md` — co-modification rule
- [x] `LICENSE` created (MIT, matching the README badge)
- [x] T034 dependency knot resolved
- [x] `README.md` privacy claims corrected to match the audit
- [x] GitHub Pages configured and activated — verified live 2026-07-25, still HTTP 200 as of this trim
- [x] §5.1 — misleading Settings toggles removed
- [x] §5.2 — privacy policy and terms open in the browser from Settings
- [x] §5.3 — Play prominent disclosure added to `background_permission_screen.dart`
- [x] §5.4 — OSM User-Agent corrected in both map widgets
- [x] §5.5 — `DeviceID` removed from `PrivacyInfo.xcprivacy`
- [ ] Links verified on a physical Android 11+ device and on iOS
- [x] §5.6 — README "Export data" feature claim resolved (2026-09-21: reworded to the FIT export
      that ships)
- [ ] §5.7 — iOS backup exclusion decided (version string is now de-hardcoded)
- [x] `TASKS.md` dependency for T037 changed from T034 to none
- [ ] Legal review before the **public** release (not required for TestFlight/internal)
- [ ] `TASKS.md` updated (⏳ → ✅) once remaining items are complete

## References

- Reference pattern: `../tribly/mobile/store-metadata/` (five-artefact rule, §7/§8 structure)
- Play Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Play background location policy: https://support.google.com/googleplay/android-developer/answer/9799150
- Play prominent disclosure requirements: https://support.google.com/googleplay/android-developer/answer/11150561
- Apple App Privacy details: https://developer.apple.com/app-store/app-privacy-details/
- OSMF tile usage policy: https://operations.osmfoundation.org/policies/tiles/
- OSMF privacy policy: https://wiki.osmfoundation.org/wiki/Privacy_Policy
- Related: `tasks/ARCHIVE.md` → T028 (permission strings, privacy manifest origin),
  `tasks/T038-android-release.md` (needs the URL + declaration),
  `tasks/T039-ios-release.md` (needs the App Privacy answers)
