---
name: beta-release
description: Ship an AutoRide beta — run ./publish_beta.sh, which bumps the build number, runs the quality gates, builds both platforms and uploads to TestFlight and the Play internal track, then commits and tags. Covers the pre-flight, how to read a long unattended run, the partial-failure recovery (a consumed build number must never be reused), and what to verify afterwards. Use when asked to publish, ship or push a beta, cut a build, get a build onto the phone/TestFlight/Play, or when a publish_beta.sh run failed and has to be resumed.
---

# Shipping an AutoRide beta

`./publish_beta.sh` is the whole pipeline. **It is the only supported way to cut a beta** —
do not hand-run `flutter build` + `fastlane` and do not bump `pubspec.yaml` yourself. The
script's guards exist because each one is a way a release has gone wrong (T038 D4).

## 0. This uploads to two stores — confirm first

Running this publishes binaries to **TestFlight** and the **Play internal track**. Both are
outward-facing and neither is undoable: once a store accepts build `N`, `N` is consumed
forever. Ask the user before starting unless they have just told you to ship, in that message.

Only the user runs `git push`. The script tags locally and says so; pushing is their call.

## 1. Pre-flight

The script checks these and dies with a clear message, but checking first turns a four-minute
failure into a five-second one:

```bash
git status --porcelain          # must be EMPTY — see below, this is load-bearing
git rev-parse --abbrev-ref HEAD # develop or main; anything else gets a warning + 3 s pause
ls android/key.properties       # missing => a DEBUG-signed bundle Play would reject
ls ~/.secrets/autoride-asc.env  # or ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH in the env
```

**The clean tree is not tidiness.** The failure rollback is `git checkout -- pubspec.yaml`,
which would destroy uncommitted work. If the tree is dirty, say what is uncommitted and let
the user decide — never stash or commit on their behalf.

Credentials are the sibling Pedalons project's and live outside git; if one is missing, that
is for the user to fix, not for you to recreate.

## 2. Running it

It takes several minutes — two full iOS compilations (the flutter + fastlane split is
deliberate, T039), then the Android build. **Run it with `run_in_background`**: a foreground
Bash call defaults to a 2-minute timeout and caps at 10, and a release killed mid-upload is the
one state this script cannot clean up after.

```bash
./publish_beta.sh          # run_in_background: true
```

Order is iOS first on purpose: TestFlight processing is asynchronous and slow to start, so the
Android build overlaps it.

The phases in the output, so you can say where a failure happened:

| Marker | Phase |
|---|---|
| `>>> Quality gates (check.sh)` | pub get → codegen → format → analyze → test |
| `>>> Building X.Y.Z+N` | the bump landed; this is the new build number |
| `fastlane beta` | iOS archive, sign, upload to TestFlight |
| `fastlane internal` | Play internal upload |
| `>>> Published X.Y.Z+N to: TestFlight + Play internal` | both stores took it |
| `>>> Tagged vX.Y.Z+N` | the release commit and tag exist locally |

## 3. When it fails — read `UPLOADED` before doing anything

The script's own trap already made the decision. **Read which of the two messages it printed
and follow it; do not improvise a fix.**

**`>>> Failed before any upload — rolled pubspec.yaml back`**
Nothing reached a store, the version is restored, the tree is clean again. Fix the cause and
re-run `./publish_beta.sh` from the top. This is the ordinary case.

**`>>> FAILED AFTER <store> accepted the build.`**
The bump was **kept on purpose**. That build number is consumed — a store already has it — and
reusing it guarantees a rejection (`Duplicate CFBundleVersion` on the iOS side). So:

1. `git add pubspec.yaml && git commit -m "chore(release): X.Y.Z+N"` — the script did not get
   that far.
2. Re-run **only the platform that failed**, by hand, from the project root:
   - iOS: `flutter build ios --release --no-codesign` then `(cd ios && bundle exec fastlane beta)`
   - Android: `export JAVA_HOME="$(/usr/libexec/java_home -v 21)"`, then
     `flutter build appbundle --release` and `(cd android && bundle exec fastlane internal)`
3. Tag by hand once it lands: `git tag vX.Y.Z+N`.

**Never re-run the whole script after a partial upload** — it would bump again and burn a
second build number for the same code.

### Known failure modes

| Symptom | What it is |
|---|---|
| `working tree is not clean` | pre-flight; §1 |
| `pubspec.yaml version must be exactly 'X.Y.Z+N'` | someone edited the version by hand |
| `bundler ... unusable` then a reinstall | a Homebrew Ruby upgrade; the script self-heals, not an error |
| Automatic signing fails during archive | missing distribution cert or a capability off in the App ID — open `ios/Runner.xcworkspace`, let Xcode repair signing, re-run (T039) |
| Opaque Kotlin/AGP errors | a JDK other than 21; the script forces 21, so this means it was run outside the script |
| `check.sh` fails | **not a release problem** — fix the code, nothing was bumped or uploaded |

## 4. Afterwards

- **`skip_waiting_for_build_processing: true`** — the script exits before Apple finishes
  processing, so *a build that fails processing looks like a success in the terminal*. ITMS-\*
  failures arrive by email. Say this to the user rather than reporting the beta as live on
  TestFlight; verify with the `asc` skills (`asc-build-lifecycle`) if they want certainty.
- The Play internal upload goes straight to testers (`release_status: "completed"`).
- Tell the user the tag exists locally and that `git push && git push --tags` is theirs to run.
- Store listings are **not** touched by a beta. Metadata is version-controlled and pushed
  deliberately: `fastlane metadata` on Android (or the `gplay` skill), by hand in App Store
  Connect on iOS. Play changelogs live in
  `android/fastlane/metadata/android/*/changelogs/`.

## 5. Related

- **`check.sh`** — the same gates, on their own. Run this while iterating; it is what "green"
  means for CI and for the release.
- **`gplay` skill** — the Play side: tracks, rollouts, vitals, reviews.
- **`asc-*` skills** — the App Store Connect side: build processing, TestFlight groups and
  What-to-Test notes, crash triage.
- **`tasks/T038-android-release.md`** (D3/D4/D5) and **`tasks/T039-ios-release.md`** (D1/D3,
  Edge Cases) — why each guard exists. Read these before changing the script.
