# Push notifications — setup

Household pushes ("Sam gave Miso's Insulin · 8:02 AM") are sent by the API
(`backend/push.js`) straight to Apple (APNs, HTTP/2 + token auth) and Google
(FCM HTTP v1). No SDKs, no extra service. Without the env vars below the
server simply skips sending and logs `push.not_configured` once per process —
everything else keeps working (phones still show local reminders).

## Env vars (Railway → pawsitive-api → Variables)

| Variable | Value | Required |
|---|---|---|
| `APNS_KEY_P8` | Full contents of `AuthKey_XXXXXXXXXX.p8`, including the `-----BEGIN PRIVATE KEY-----` lines. Literal `\n` escapes are accepted. | iOS |
| `APNS_KEY_ID` | The key's 10-character Key ID | iOS |
| `APNS_TEAM_ID` | `48AMK8N4G5` (default) | optional |
| `APNS_TOPIC` | `com.pawsitivesync.app` (default; must equal the app's bundle id) | optional |
| `FCM_SERVICE_ACCOUNT_JSON` | The Firebase service-account JSON file contents (raw JSON or base64 of it) | Android |

Keep the real values in the `~/secrets` sops vault, never in git.

## iOS: APNs key (one time, ~5 minutes)

1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → **+**.
2. Name it "Pawsitive APNs", tick **Apple Push Notifications service (APNs)**,
   Configure → environment **Sandbox & Production**, Continue → Register.
3. **Download** the `.p8` (only downloadable once) and note the **Key ID**.
4. Identifiers → `com.pawsitivesync.app` → make sure **Push Notifications** is
   ticked (Xcode's automatic signing does this on the next build too).
5. Set `APNS_KEY_P8` (file contents) and `APNS_KEY_ID` on Railway, redeploy.

One key serves both sandbox and production. Each phone registers its
environment: debug builds send `environment: "sandbox"`, release builds
(TestFlight / App Store) send `"production"`; the server picks
`api.sandbox.push.apple.com` or `api.push.apple.com` per device.

App side (already in the repo): `aps-environment` in
`ios/Runner/Runner.entitlements`, `UIBackgroundModes = remote-notification` in
`Info.plist`, and the `pawsitive_sync/push` channel in `AppDelegate.swift`
(`PushBridge`). The token is requested without a second permission prompt —
alerts use the permission the reminder step already asked for.

Check it works: log a dose on phone A; phone B (same household, real device —
the simulator gets no APNs token) shows the alert. Server logs `push.sent`
with `sent ≥ 1`. A `push.failed reason=BadDeviceToken` usually means a debug
build registered as production or vice versa.

## Android: Firebase (not built yet — documented debt)

The Android client has no push yet: FCM needs Firebase config the project
doesn't have, and adding `firebase_messaging` without it breaks the build.
`MethodChannelPushPlatform.token()` returns null on Android, so nothing is
registered and nothing breaks. To finish it:

1. console.firebase.google.com → Add project → add an **Android app** with
   package name `com.pawsitivesync.app` (check `android/app/build.gradle*`
   `applicationId`).
2. Download **`google-services.json`** → put it at
   **`android/app/google-services.json`**.
3. Add the Google services Gradle plugin (`com.google.gms.google-services`) to
   `android/settings.gradle*` and apply it in `android/app/build.gradle*`.
4. Add `firebase_core` + `firebase_messaging` to `pubspec.yaml`; in
   `MethodChannelPushPlatform` (lib/data/push_service.dart) return
   `PushToken(platform: 'android', token: 'fcm:<getToken()>', environment: 'production')`,
   forward `onTokenRefresh` to `onToken`, and pass `onMessage` /
   background-message data to `PushService.handleRemoteMessage`.
5. Server: Firebase console → Project settings → **Service accounts** →
   **Generate new private key** → set the JSON as `FCM_SERVICE_ACCOUNT_JSON`.

The server side for FCM (OAuth token exchange, send, `UNREGISTERED` cleanup)
is done and tested.

## What is sent

- A member logs a dose → every **other** member's devices get a visible alert
  (never the person who logged; browser sitter links have no devices).
- iOS also gets a silent `content-available` push with
  `{type: "dose_logged", doses: [{medicationId, part, day, outcome, logId}]}`;
  the app cancels its own reminder when it was for that dose (given/skipped)
  and refreshes in the background.
- An offline batch (outbox replay) sends **one** summary ("Sam logged 3 doses").
- Tokens Apple/Google call dead (410, `BadDeviceToken`, `Unregistered`,
  `UNREGISTERED`) are deleted. Each send times out after 5 s and runs after
  the API has answered (never slows a request). APNs JWTs are reused for
  50 minutes; FCM access tokens until a minute before expiry.

## Known gaps

- Foreground alerts on iOS: `flutter_local_notifications` owns the
  notification-center delegate; a household alert arriving while the app is
  open may not show a banner (the app syncs instead).
- Silent pushes are throttled by iOS (Low Power Mode, force-quit apps); the
  reminder is then corrected on the next launch/sync.
