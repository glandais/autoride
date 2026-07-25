# T036 - App Icons & Splash Screen

**Status**: ✅ Complete (2026-07-25)
**Actual Time**: ~2 hours
**Dependencies**: T020 (Theme & Design)
**Phase**: 10 - Release Preparation
**Unblocks**: public store submission (App Review rejects placeholder artwork). T038/T039 list
T036 as a dependency, but it never blocked the internal/TestFlight tracks.

---

## Overview

Replace the Flutter template icons with the real AutoRide artwork on both platforms, and give the
app a branded launch screen. Everything is derived from a single master image by a committed
script, so the transformations are reproducible rather than one-off manual edits.

---

## Deliverables

| File | Role |
|---|---|
| `assets/icon/source-1024.png` | **Master artwork.** Full-bleed 1024² square, blue gradient, white bicycle, orange route |
| `assets/icon/icon-1024.png` | Derived: flattened, no alpha → iOS + legacy Android mipmaps |
| `assets/icon/icon-background.png` | Derived: gradient only → Android adaptive background layer |
| `assets/icon/icon-foreground.png` | Derived: artwork on transparency → Android adaptive foreground layer |
| `assets/icon/splash-logo.png` | Derived: logo for the legacy launch screen (4x asset, ~200dp) |
| `assets/icon/splash-logo-android12.png` | Derived: 1152² canvas, logo inside the 768px circle Android 12+ requires |
| `scripts/generate-icons.sh` | Derives all five from the master, then runs both generators |
| `flutter_launcher_icons.yaml` | Icon config |
| `flutter_native_splash.yaml` | Launch screen config |

Generated platform output (committed): `android/app/src/main/res/mipmap-*/`,
`drawable*/ic_launcher_{background,foreground}.png`, `mipmap-anydpi-v26/ic_launcher.xml`,
`values{,-night}{,-v31}/styles.xml`, `drawable{,-v21,-night-*}/launch_background.xml`,
`ios/Runner/Assets.xcassets/{AppIcon,LaunchImage,LaunchBackground}.*`,
`ios/Runner/Base.lproj/LaunchScreen.storyboard`.

The `assets/` directory is **not** declared under `flutter:` in `pubspec.yaml`. These images are
build-time inputs to the generators, not runtime assets — declaring them would ship ~2 MB of
unused PNGs in the app bundle.

---

## Design Decisions

### D1: One master, one script

The three icon layers and two splash logos are all derived from `source-1024.png` by
`scripts/generate-icons.sh` (pattern borrowed from `../tribly/scripts/generate-icons.sh`). Nobody
should have to guess how a derived asset was produced, and replacing the artwork is one file swap
plus one command.

### D2: The artwork had to be split for Android

iOS takes a full-bleed square and applies its own squircle mask. Android adaptive icons need the
artwork and the backdrop as *separate* layers so the launcher can mask, parallax and animate them
independently.

Since the master is a flattened raster with the background baked in, the foreground had to be
keyed out. The palette makes this clean: the background is blue, the artwork white and orange, so
`blue − red` separates them (≈0.70–0.80 for the backdrop, ≈0 for white, negative for orange).

Two refinements were needed and are worth keeping:

- A plain ramp left the white strokes **speckled**, because the master's whites are slightly
  blue-tinted. Widening the ramp to 0.45 and hardening intermediate alphas with
  `-level 25%,75%` fixed it while keeping edge antialiasing.
- A faint alpha veil across the whole canvas defeated `-trim` (it reported the full 1024²).
  `-black-threshold 6%` gives a true zero so the bounding box is the artwork's.

### D3: Foreground sized to the adaptive safe circle

Android guarantees only the central 66/108 (61%) circle is visible. The artwork is set to 600px
of the 1024px layer, so its half-width (300) stays inside that circle's radius (313) and the wheel
edges are never clipped by a circular launcher mask.

`flutter_launcher_icons` then wraps the foreground in `<inset android:inset="16%" />`. That inset
does **not** shrink the artwork excessively — it compensates for the 108dp→72dp visible crop.
Measured on the generated xxxhdpi layer: the artwork ends up **174px within a 288px visible
circle, i.e. 60% of the visible icon**, which is the conventional proportion.

### D4: Solid splash background, not the gradient

Android 12+ draws the system splash from `windowSplashScreenBackground`, which accepts a single
colour only. Using one colour everywhere keeps the launch identical across platforms and Android
generations. `#1E98DD` is the gradient plane's centre, so it reads as the same blue as the icon.

### D5: The sparkle is lost in the adaptive foreground

The master's small light-blue sparkle is a *tint of the background colour*, so `blue − red` cannot
distinguish it from the backdrop and it is keyed out. It survives in `icon-1024.png` (iOS, legacy
Android) and is absent from the adaptive layers. Accepted: it is invisible at launcher sizes.

---

## Verification

Rendered the generated Android layers exactly as a launcher would — foreground inset 16%,
composited on the background, cropped to the 72/108 visible region, masked to a circle — and
inspected at 48 / 72 / 192 px:

- The bicycle is crisp and dominant at all three sizes.
- **The orange dots along the route disappear below ~72px.** Flagged before choosing this
  artwork; accepted, because the bicycle carries the icon and the route still reads as a shape.
- Nothing is clipped by the circular mask.

Other checks:

| Check | Result |
|---|---|
| iOS 1024 icon vs derived source | `magick compare -metric RMSE` → **0** (pixel identical) |
| iOS icon alpha channel | `alpha=Undefined` — App Store rejects icons with alpha |
| Android mipmaps | 48/72/96/144/192 px present |
| Adaptive XML | background + foreground drawables at 5 densities |
| Android 12+ splash | `windowSplashScreenBackground=#1E98DD`, `windowSplashScreenAnimatedIcon`, asset 1152² |
| iOS splash | `LaunchBackground` 1×1 `srgb(30,152,221)` stretched + `LaunchImage` 220/440/660 centred |
| `flutter analyze` | No issues found |
| `flutter test` | 190 passed |

---

## Generator Side Effects (important)

Both generators edit files they have no business editing. `scripts/generate-icons.sh` repairs the
first automatically and warns about the second — **read its output**, don't just commit.

1. **`flutter_launcher_icons` corrupts an Xcode build setting.** It writes the app-icon name into
   `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`, which is a boolean
   (`YES` → `AppIcon`). The setting it meant is `ASSETCATALOG_COMPILER_APPICON_NAME`, which is
   already correct. The script now restores it with `sed` after every run.

2. **`flutter_native_splash` rewrites `ios/Runner/Info.plist`.** It re-indents the entire file —
   turning a one-key change into a 152-line diff — and injects `UIStatusBarHidden=false`, which is
   already the default behaviour. It is *not* auto-reverted, because the file carries hand-written
   comments (T028's permission rationale, T039's notes) that no reformatting should touch. The
   script detects the change and prints the fix:

   ```bash
   git checkout ios/Runner/Info.plist
   ```

   Verified after reverting: all four usage descriptions, `UIBackgroundModes`, the scene manifest
   and `CFBundleDisplayName` intact, `plutil -lint` OK.

---

## Notes for Related Tasks

- **T039** still needs `ITSAppUsesNonExemptEncryption` added to `Info.plist` (its Step 4). It was
  never present; the check during this task confirmed its absence rather than a regression.
- **T038/T039** own the display-name alignment (`android:label` and `CFBundleDisplayName` →
  `AutoRide`). Untouched here.
- **Store screenshots** are not part of T036. They need a device or simulator run and belong with
  the listing work in T038 (Play `fastlane/metadata/`) and T039 (App Store Connect).
- Replacing the artwork later: overwrite `assets/icon/source-1024.png`, re-sample the three
  gradient corners noted in the script, and re-run it. **Do not** reintroduce a corner
  flood-fill — an earlier master had white rounded corners that needed replacing; the current one
  is full-bleed, and flood-filling from a corner would key out the whole backdrop.

---

## Definition of Done

- [x] Master artwork committed at `assets/icon/source-1024.png`
- [x] Derived assets generated by a committed, documented script
- [x] iOS icon set regenerated (21 PNGs), no alpha, pixel-identical to source
- [x] Android legacy mipmaps + adaptive icon layers regenerated
- [x] Adaptive icon verified against the safe circle at launcher sizes
- [x] Branded launch screen on both platforms, including the Android 12+ SplashScreen API
- [x] Generator side effects identified, one auto-repaired, one warned about
- [x] `flutter analyze` clean, `flutter test` 190 passed
- [x] `tasks/TASKS.md` updated
- [ ] Visual check on a physical device (launcher icon, round/squircle masks, launch screen)
