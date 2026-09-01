---
name: gplay
description: Drive the Google Play side of AutoRide with the gplay CLI — inspect tracks and releases, upload an AAB to internal, push the store listing, read Play vitals and reviews. Use when asked about the Play Console, Play tracks, an Android release or upload, Play store metadata or screenshots, crash/ANR rates, or when replacing the fastlane `supply` lanes under `android/`.
---

# gplay (AutoRide / Google Play)

`gplay` is a single static Go binary for the Google Play Developer API (MIT,
<https://gplay.sh>, `brew install PollyGlot/tap/gplay`). It is the Android counterpart of
`asc` on the iOS side, and covers what `fastlane supply` does here plus rollouts, vitals and
reviews.

## Project facts

| | |
|---|---|
| Package | `io.github.glandais.autoride` (also in `android/fastlane/Appfile`) |
| Credential | `~/.secrets/autoride-play.json` — outside git, the repo is public |
| Metadata tree | `android/fastlane/metadata/android` (fastlane layout, gplay reads it as-is) |
| AAB (from repo root) | `build/app/outputs/bundle/release/app-release.aab` |
| Release script | `publish_beta.sh` — still calls `bundle exec fastlane internal` |

Export the credential once per shell; every command below assumes it:

```bash
export GPLAY_SERVICE_ACCOUNT="$HOME/.secrets/autoride-play.json"
```

`--package` can be dropped after `gplay init --package io.github.glandais.autoride` (writes
`.gplay/config.json`), which has **not** been run in this repo yet — pass `--package`
explicitly until it is.

## Safety rules

- **Never upload or mutate autonomously.** Uploading consumes a build number forever, exactly
  like the `UPLOADED` guard in `publish_beta.sh` documents. Read-only commands are fine; any
  write waits for the user.
- Preview any write with `--dry-run` (validates and prints the payload, zero HTTP).
- Set `GPLAY_READONLY=1` to make the environment refuse every mutating command (exit 4) when
  you only mean to look around.
- Production stays a draft unless `--complete`/`--staged`, and those additionally demand
  `--confirm`. Promoting to production is a human decision — same stance as the deliberately
  unscripted `deploy` lane in `android/fastlane/Fastfile`.

## Read-only commands

```bash
gplay tracks list --package io.github.glandais.autoride     # tracks + current releases
gplay releases list --track internal --package …            # what is on one track
gplay metadata list --package …                             # listings live on Play
gplay metadata validate --dir android/fastlane/metadata/android        # offline lint
gplay metadata images validate --dir android/fastlane/metadata/android # offline lint
gplay vitals crashes --package …                            # crash rate (also: anr, lmk,
                                                            # slowstart, excessivewakeup…)
gplay reviews list --package …
gplay auth doctor                                           # diagnose the credential
```

Both `metadata validate` invocations pass on the current tree, so the fastlane layout needs no
conversion.

## Replacing the fastlane lanes

`android/fastlane/Fastfile` maps one-to-one:

| Lane | gplay equivalent |
|---|---|
| `internal` | `gplay releases upload build/app/outputs/bundle/release/app-release.aab --track internal --draft --package …` |
| `metadata` | `gplay metadata apply --dir android/fastlane/metadata/android --package …` (plus `gplay metadata images apply` for images) |
| `deploy` | `gplay releases upload … --track production` (draft by default; `--complete`/`--staged` need `--confirm`) |

The `skip_upload_*` flags have no equivalent: gplay never pushes metadata alongside a build,
which is the behaviour the Fastfile comments already ask for. Changelogs differ — fastlane
reads `metadata/android/<locale>/changelogs/<versionCode>.txt`, gplay takes
`--release-notes-dir` holding `<locale>.txt`; check this before wiring the release notes.

Cutting Android over would let `publish_beta.sh` drop its Android `ensure_bundler`,
`bundle install` and `android/Gemfile*`. iOS stays on fastlane.

Beyond `supply`: `gplay releases rollout|halt|resume|complete` for staged rollouts,
`--mapping` on upload so Play vitals can symbolicate R8 stacks, and `gplay compliance` for
Data Safety.

## Exit codes

`0` ok · `3` a named `--confirm` flag is missing (re-run with it) · `4` refused by
`GPLAY_READONLY` · `10`/`11` auth/permission · `20` client-side validation · `30` API 4xx ·
`40`/`50` 5xx and network, **retry-safe** (`--retry N`) · `60` state conflict (open edit,
rate limit) · `70` a read-only check reported drift, not an error.

Full list: `gplay exit-codes`. Offline API introspection: `gplay schema`.
