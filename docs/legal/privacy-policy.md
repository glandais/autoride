---
title: Privacy Policy
description: What AutoRide stores on your device, what leaves it, and how to delete everything.
---

# AutoRide — Privacy Policy

**Effective date:** 2026-07-25
**Last updated:** 2026-09-02
**Applies to:** AutoRide for iOS and Android (`io.github.glandais.autoride`)
**Contact:** gabriel.landais@gmail.com

---

## Summary

AutoRide records your bike trips on your phone. Trip data — including the GPS route of every
ride — is stored only in the app's private storage on your device. There is no AutoRide account,
no AutoRide server, and no analytics or advertising SDK in the app.

One exception to that, and it is the only automatic one: when you view a map, your device requests
map images directly from the OpenStreetMap Foundation's tile servers. Those requests necessarily
reveal your IP address and the area of the map you are looking at to that third party. Details
in §3.

Separately, you can *choose* to export a file — a ride as a `.fit` activity, or an optional
diagnostic log — and send it wherever you like through your device's own share sheet. Nothing
leaves until you pick a destination. Details in §3.3.

Uninstalling AutoRide deletes everything it stored.

---

## 1. Who is responsible

AutoRide is developed and published by Gabriel Landais, an individual developer based in France.

Because AutoRide has no server component, there is no copy of your data for the developer to
hold, access, search, or hand over. Requests to access or delete your data cannot be fulfilled by
the developer for the simple reason that the developer never receives it — you delete it yourself,
in the app (§7).

## 2. What AutoRide stores on your device

### 2.1 Trip records

Stored in a local SQLite database (`autoride.db`) in the app's private storage:

| Data | Detail |
|---|---|
| Start and end time | Timestamps of each detected or recorded trip |
| Distance and duration | Computed totals |
| Average and maximum speed | Computed from GPS |
| Detected activity and confidence score | The classification result (e.g. cycling) and how confident the detection was |
| Confirmation flag | Whether you confirmed or corrected the detection |

### 2.2 Route points

For each trip, the app stores the series of points that make up your route:

| Data | Detail |
|---|---|
| Latitude and longitude | Precise GPS coordinates |
| Altitude | Where the device reports it |
| Timestamp | When the point was recorded |
| Accuracy | The reported accuracy of the fix |
| Speed | Instantaneous speed at that point |

**This is precise location history.** A route log shows where you were and when, which typically
reveals where you live, work, and ride. It is the most sensitive data the app holds. It never
leaves your device except by your own action (§7.3).

### 2.3 Settings

Stored in the platform's standard preferences store (`SharedPreferences` / `NSUserDefaults`):
your detection, battery, notification, unit and theme preferences (key `user_settings`), your
selected theme (`theme_mode`), and whether you have completed onboarding
(`onboarding_complete`). No location or trip data is stored here.

### 2.4 Motion sensor data — used, not stored

AutoRide continuously reads your device's accelerometer and gyroscope to recognise the motion
pattern of pedalling. This is what allows the app to keep GPS switched off until you actually
start riding, which is the app's main battery-saving mechanism.

Sensor readings are processed in memory and discarded. They are not written to the trip database
and not transmitted. If you turn the diagnostic log on (§2.5) and set it to "Verbose", one
*summary* per second — an average and a variability figure — is written to that log; the raw
readings, which arrive fifty times a second, are never recorded at any setting.

### 2.5 Diagnostic log (off by default)

**Settings → Diagnostic log** records what trip detection is doing, so a problem you report can be
diagnosed from evidence instead of guesswork. It is **off unless you turn it on**.

When it is on, the log holds: trip state changes, the detector's decisions and scores, **GPS fixes
including latitude, longitude, accuracy, speed, altitude and heading**, battery level and power
mode, permission status, which notification was shown, cancelled or tapped (never the text it
displayed), app foreground/background changes, and error messages. At the "Verbose" setting it
also holds the sensor summaries described above and the GPS fixes the recorder rejected.

It does not hold your name, your email address, any account, or any advertising or device
identifier. It does hold your device model, OS version and app version.

The log lives in its own database on your device, separate from your trips. It expires
automatically (§6), you can erase it at any time (§7.1), and it goes nowhere unless you export and
send it yourself (§3.3).

## 3. What leaves your device

### 3.1 Map tiles (the only automatic transmission)

When a screen shows a map — the tracking screen and a trip's route map — your device requests
map images from `tile.openstreetmap.org`, operated by the OpenStreetMap Foundation (OSMF).

Each request unavoidably discloses to OSMF:

- your **IP address**, which approximates your location and identifies your internet connection;
- the **tile coordinates** requested, which reveal the geographic area you are viewing — and
  since the map is centred on your route, that is approximately where you have been;
- a **User-Agent** string identifying the app.

AutoRide does not add your identity, your trip records, or any identifier to these requests, and
it does not send your stored routes anywhere. But requesting a map of a place is itself a
disclosure of interest in that place, and you should understand that before viewing maps.

OSMF's handling of this data is governed by its own policy, not this one:
https://wiki.osmfoundation.org/wiki/Privacy_Policy

If you never open a map view, AutoRide makes no network requests at all.

### 3.2 What is *not* transmitted automatically

There is no analytics SDK, no crash-reporting SDK, no advertising SDK, and no AutoRide backend.
The app has no login, no account, and no sync. Your trips, routes, sensor data and settings are
never uploaded, shared, sold, or used for advertising or profiling — by anyone, including the
developer.

The one qualification is §3.3: files *you* choose to export and send. If you send the developer a
diagnostic log, the developer does then have the data in it. It is used only to diagnose the
problem you reported, is not kept beyond that, is not combined with anything else, and is deleted
on request.

### 3.3 Files you export yourself

Two features write a file and hand it to your device's own share sheet. Nothing is sent anywhere
until you pick a destination there, and AutoRide never learns what you picked.

- **Export as FIT** (on a trip) writes that ride — its route, timings and speeds — as a standard
  `.fit` activity file, so you can put it into Strava, Garmin Connect, Files, or anything else
  that reads one.
- **Export log** (Settings → Diagnostic log) writes the diagnostic log (§2.5) as a compressed
  `.ndjson.gz` file. **It contains your precise GPS positions.** The app shows you exactly what
  the file holds and asks you to confirm before the share sheet opens.

Both are entirely your decision, one file at a time. Share them only with someone you trust.

## 4. Permissions, and why each is needed

| Permission | Why | Optional? |
|---|---|---|
| **Location — while using the app** | Record the GPS route, distance and speed of a trip | No; without it the app cannot record trips |
| **Location — always / background** | Detect that a ride has started and record it when the app is closed or in the background | **Yes.** Decline it and AutoRide still works; you start and stop recording manually |
| **Motion and fitness (iOS) / body sensors** | Read accelerometer and gyroscope to recognise pedalling, so GPS stays off when you are not riding | No; declining it forces continuous GPS or manual recording |
| **Notifications** | Show the ongoing-trip notification, which Android requires for background location tracking, and trip start/stop alerts | Partly; Android needs a visible notification while tracking in the background |

Background location is the permission worth thinking about, because it means the app can receive
your location when you are not looking at your phone. It is used for exactly one purpose:
noticing that you started cycling and recording that ride. You can revoke it at any time in your
device's system settings, and you can turn background tracking off inside AutoRide's settings
without touching system permissions.

## 5. Why the app processes this data (legal basis)

For users in the EU/EEA and the UK, the processing described in §2 happens **on your own device,
under your control**, to deliver the feature you asked for — recording your rides. The developer
is not a recipient of that data.

For §3.1, the map tile request is necessary to display the map you chose to open.

## 6. How long data is kept

Trip records and route points are kept **until you delete them**. There is no automatic expiry —
the app assumes you want your riding history.

Settings persist until you reset them or uninstall.

The diagnostic log (§2.5) is the one exception, and the only data in the app that expires on its
own: entries are removed once they are older than 7 days, and the log is capped in size (about
20 MB) and in number of entries, whichever limit is reached first. At the "Verbose" setting the
size limit is normally what bites, so a full log reaches back some hours of riding rather than
seven days. The Settings screen shows the period actually covered.

## 7. Your control over your data

### 7.1 Delete everything

**Settings → Data Management → Clear all trips** permanently deletes every trip and every route
point from the database. This cannot be undone.

**Settings → Data Management → Reset settings** restores all preferences to their defaults.

**Settings → Diagnostic log → Clear log** permanently deletes every recorded diagnostic event.
Note that turning the log *off* does not erase what it already recorded — deliberately, so you can
stop recording and still export the ride you just did. Use "Clear log" to erase it.

### 7.2 Uninstall

Uninstalling AutoRide removes the app's private storage, including the trip database and all
settings. Nothing survives on any server, because nothing was ever sent to one.

### 7.3 Device backups

On **Android**, AutoRide sets `allowBackup="false"`. The trip database is deliberately excluded
from Google's automatic backup and from `adb backup`, so your route history is not copied off the
device by the platform.

On **iOS**, the trip database is currently included in your device's normal iCloud or local
backups, like other app data. That backup is yours and is governed by Apple's terms, not by this
policy; it is encrypted according to your iCloud/backup settings. If you would rather your route
history never be included in a backup, disable iCloud backup for AutoRide in iOS settings.

## 8. Children

AutoRide is not directed at children and collects no data from anyone through a server. It is
rated for general audiences. If a child uses the app, the same on-device-only behaviour applies.

## 9. Security

Trip data is held in the app's private per-app storage, which the operating system isolates from
other apps. It is protected by your device's own protections — screen lock and device encryption.
The database itself is not separately encrypted, so an attacker with unlocked access to your
device, or with the ability to read an unencrypted backup, could read your route history. Use a
device passcode.

The only network connection the app makes (§3.1) uses HTTPS.

## 10. Changes to this policy

Material changes — in particular, any change that would cause data to leave your device — will
be reflected here with a new "Last updated" date before the feature ships, and the app's store
listings and privacy declarations will be updated in the same release.

**2026-09-02** — two changes, both of them things you start yourself: exporting a ride as a `.fit`
activity file, and an optional, off-by-default diagnostic log you can export and send. §2.5 and
§3.3 describe them, §6 covers how long the log is kept and §7.1 how to erase it. Neither sends
anything on its own.

One feature remains planned but **not present**: opt-in contribution of anonymised sensor data to
improve activity detection. If it ships, this policy will be updated first, and it will be off
unless you explicitly turn it on.

## 11. Contact

Questions about this policy: **gabriel.landais@gmail.com**

Source code: https://github.com/glandais/autoride
