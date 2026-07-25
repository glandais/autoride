# store-metadata

Store-submission declarations that have no natural home in either store's tooling but must stay
under version control, because getting them wrong means an App Review rejection or a
privacy-policy contradiction.

| File | What it is |
|---|---|
| [`data-safety.md`](data-safety.md) | Source of truth for what the app collects, the iOS privacy manifest contents, the App Store Connect *App Privacy* answers, the Google Play *Data safety* answers, and the Play background-location declaration |

Listing copy and screenshots are **not** duplicated here. They live where their tooling expects
them: `android/fastlane/metadata/` for Play (created by T038) and App Store Connect for iOS.

## Rule

`data-safety.md`, `ios/Runner/PrivacyInfo.xcprivacy`, the two store forms, and
`docs/legal/privacy-policy.md` describe the same thing in five places. Change one and you must
change the others in the same commit, or they drift — and the drift is invisible until a reviewer
finds it.

`data-safety.md` §7 lists which feature additions force a re-declaration. §8 is a
copy-pasteable audit of the code the declarations rest on; run it before any submission.
