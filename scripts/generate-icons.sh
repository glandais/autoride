#!/usr/bin/env bash
# generate-icons.sh — derive the launcher-icon assets from the master artwork, then run
# flutter_launcher_icons to write the platform icon sets. (T036)
#
# Master artwork: assets/icon/source-1024.png
#
# The master is a flattened, full-bleed square raster with the background baked in. That suits
# iOS directly (it applies its own squircle mask and must not receive rounded corners of its own),
# but Android adaptive icons need the artwork and the background as SEPARATE layers, with the
# artwork inside a 66/108 (61%) safe circle. Steps 2-3 split them.
#
# NOTE: do not reintroduce a corner flood-fill here. An earlier master had white rounded corners
# that had to be replaced with extrapolated background; the current artwork is full-bleed, and
# flood-filling from a corner would key out the whole contiguous blue backdrop instead.
#
# Prerequisites: ImageMagick 7 (`brew install imagemagick`), Flutter.
# Usage: ./scripts/generate-icons.sh [--assets-only]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$ROOT/assets/icon"
SRC="$ICON_DIR/source-1024.png"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v magick >/dev/null 2>&1 ||
  { echo "generate-icons.sh: ImageMagick 'magick' not found — brew install imagemagick" >&2; exit 1; }
[ -f "$SRC" ] || { echo "generate-icons.sh: master artwork not found: $SRC" >&2; exit 1; }

# Background colours sampled from the master's own corners. Three points define the linear plane
# that `-sparse-color barycentric` reproduces for the Android adaptive background layer; the
# implied fourth corner lands within 6/255 of the master's real pixel there.
# Re-sample these if the artwork is ever replaced:
#   magick assets/icon/source-1024.png -format "%[pixel:p{0,0}]" info:
GRAD_TL="#1B9CDE" # p{0,0}
GRAD_TR="#30C2FD" # p{1023,0}
GRAD_BL="#0C6DBE" # p{0,1023}
# Plane centre, used as the launch-screen background in flutter_native_splash.yaml. Keep the two
# in sync so the splash reads as the same blue as the icon.
#   SPLASH_COLOR = #1E98DD

# Artwork is white and orange on a blue background, so (blue - red) separates them cleanly:
# blue background ~0.70-0.80, white ~0.00, orange negative. KEY_RAMP is the width of the
# transition; the -level pass afterwards hardens the intermediate alphas that would otherwise
# speckle the white strokes (the master has slightly blue-tinted whites).
KEY_RAMP=0.45

# Artwork width inside the 1024 adaptive layer. 600px keeps the half-width (300) inside the
# radius of Android's 61% safe circle (313), so the wheel edges are never clipped by a
# circular launcher mask.
FG_WIDTH=600

echo "==> 1/3 full-bleed square (iOS + legacy Android)"
# The master is already full-bleed, so this only flattens the (fully opaque) alpha channel that
# the App Store refuses and normalises to 8-bit.
magick "$SRC" -alpha remove -alpha off -depth 8 -strip PNG24:"$ICON_DIR/icon-1024.png"

echo "==> 2/3 adaptive background (gradient only)"
magick -size 1024x1024 xc: -sparse-color barycentric \
  "0,0 $GRAD_TL  1023,0 $GRAD_TR  0,1023 $GRAD_BL" \
  -depth 8 -strip PNG24:"$ICON_DIR/icon-background.png"

echo "==> 3/3 adaptive foreground (artwork on transparency, inside the safe circle)"
magick "$ICON_DIR/icon-1024.png" -alpha set -channel A \
  -fx "1 - min(1, max(0, (b - r) / $KEY_RAMP))" +channel \
  -channel A -level 25%,75% -black-threshold 6% +channel \
  -trim +repage \
  -resize "${FG_WIDTH}x${FG_WIDTH}" \
  -background none -gravity center -extent 1024x1024 \
  -depth 8 -strip PNG32:"$ICON_DIR/icon-foreground.png"

# The light-blue sparkle in the bottom right of the master is keyed out as background: it is a
# tint of the background colour, so (blue - red) cannot distinguish it from the backdrop. It
# survives in icon-1024.png (iOS, legacy Android) and is absent from the adaptive foreground —
# acceptable, since it is invisible at launcher sizes.

echo "==> splash logos"
# Standard splash: supplied as a 4x asset, so 800px wide renders at ~200dp.
magick "$ICON_DIR/icon-foreground.png" -trim +repage -resize 800x800 \
  -background none -gravity center -extent 880x880 \
  -depth 8 -strip PNG32:"$ICON_DIR/splash-logo.png"
# Android 12+ splash: the framework requires a 1152x1152 canvas with the logo inside a circle of
# 768px diameter. The artwork is 1.68:1, so its diagonal caps the width at 768/1.164 = 660px.
magick "$ICON_DIR/icon-foreground.png" -trim +repage -resize 640x640 \
  -background none -gravity center -extent 1152x1152 \
  -depth 8 -strip PNG32:"$ICON_DIR/splash-logo-android12.png"

for f in icon-1024.png icon-background.png icon-foreground.png \
         splash-logo.png splash-logo-android12.png; do
  magick identify -format "    %f  %wx%h  alpha=%A\n" "$ICON_DIR/$f"
done

if [ "${1:-}" = "--assets-only" ]; then
  echo "==> stopping before the generators (--assets-only)"
  exit 0
fi

cd "$ROOT"
echo "==> flutter_launcher_icons"
dart run flutter_launcher_icons
echo "==> flutter_native_splash"
dart run flutter_native_splash:create

echo "==> repairing generator side effects"
# flutter_launcher_icons overwrites the wrong Xcode build setting: it writes the app-icon name
# into ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS, which is a boolean.
# ASSETCATALOG_COMPILER_APPICON_NAME is the setting it meant, and that one is already correct.
PBX="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
if grep -q "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;" "$PBX"; then
  sed -i '' \
    's/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;/g' \
    "$PBX"
  echo "    project.pbxproj: restored ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES"
fi

# flutter_native_splash re-indents the whole Info.plist and injects UIStatusBarHidden=false, which
# is already the default. Reverting is not scripted here because the file carries hand-written
# comments (T028 permission rationale, T037/T039 notes) that no reformatting should touch.
if ! git -C "$ROOT" diff --quiet -- ios/Runner/Info.plist 2>/dev/null; then
  echo
  echo "    !! ios/Runner/Info.plist was rewritten by flutter_native_splash."
  echo "    !! It only re-indents the file and adds UIStatusBarHidden=false (already the default),"
  echo "    !! so unless you changed it yourself, discard it to keep the diff reviewable:"
  echo "    !!     git checkout ios/Runner/Info.plist"
fi

echo
echo "Done. Review the output, then commit assets/icon/ together with the generated platform files:"
echo "  android/app/src/main/res/mipmap-*/  android/app/src/main/res/drawable*/"
echo "  android/app/src/main/res/values*/styles.xml"
echo "  ios/Runner/Assets.xcassets/{AppIcon,LaunchImage}.*  ios/Runner/Base.lproj/LaunchScreen.storyboard"
