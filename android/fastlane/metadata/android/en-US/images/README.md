# Play Store listing images

`supply` picks these up automatically. The `internal` lane skips image upload entirely
(`skip_upload_images` / `skip_upload_screenshots`), so these are pushed only by
`bundle exec fastlane metadata`, deliberately, when the listing changes.

| File | Required by Play | Spec | Status |
|---|---|---|---|
| `icon.png` | yes | 512×512 PNG, 32-bit | ✅ generated from `assets/icon/icon-1024.png` (T036) |
| `featureGraphic.png` | yes | 1024×500 PNG or JPEG, no alpha | ❌ missing — must be designed |
| `phoneScreenshots/*.png` | yes, min 2 | 16:9 or 9:16, 320–3840 px per side | ❌ missing — capture on a device |

Regenerate the icon after any change to the source asset:

```bash
sips -z 512 512 assets/icon/icon-1024.png \
  --out android/fastlane/metadata/android/en-US/images/icon.png
```

Screenshots to capture, in listing order: live tracking with the route map, trip history,
a trip detail with route and stats, settings. Take them on a real device — the map and the
recording notification are the two things a reviewer looks for, and neither renders
convincingly on an emulator.

Play rejects a submission that is missing the feature graphic or has fewer than two phone
screenshots, but neither blocks an **internal testing** upload — that is why the first beta
can ship without them.
