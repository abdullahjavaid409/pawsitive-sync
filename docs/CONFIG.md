# PawsitiveSync — setup (plain English)

You can run the app with **zero configuration**. Everything below is optional.

---

## App identifiers

One identifier on both stores. Use it when creating the App Store Connect app,
the Google Play app, and the RevenueCat apps. It can never change after the
first store upload.

| What | Value |
|------|-------|
| iOS bundle ID | `com.pawsitivesync.app` |
| iOS widget extension | `com.pawsitivesync.app.widgets` |
| iOS App Group (app ↔ widget) | `group.com.pawsitivesync.shared` |
| Android application ID | `com.pawsitivesync.app` |
| Apple developer team | `48AMK8N4G5` (Abdul Manan) |

The Dart package stays `pawsitive_sync` — that is the code name, not the store ID.

---

## Run locally (no setup)

```bash
flutter pub get
flutter run
```

- Pets, doses, and reminders work on this phone, offline too.
- Every build (debug included) talks to the **live** Railway API and RevenueCat.
- Pro and free trials come only from RevenueCat — there is no local, debug or server trial.
- No account, no Apple Sign-In, nothing to pass.

---

## Optional: share a household online

Lets partners and sitters see doses in real time.

| Setting | What to pass | Default |
|---------|--------------|---------|
| API server | `--dart-define=API_BASE_URL=https://your-api.example.com` | Railway production URL in every build |

Debug runs write to the live server, like a real user. Analytics stays off
outside release builds. For automated tests, run the backend (see `backend/`)
and point the app at it:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3100
```

**Fully offline release build:** pass an empty URL:

```bash
flutter build ios --dart-define=API_BASE_URL=
```

---

## Optional: App Store / Play purchases (RevenueCat)

Pro status, prices and free trials come only from RevenueCat. The public iOS
key is the default in `AppConfig`, so every build is configured. The paywall
shows no price or trial until RevenueCat sends the offering. Trials are App
Store introductory offers that RevenueCat reports, never granted by the app or
server.

The server checks a purchase made before sharing with RevenueCat's REST API.
That needs a **secret** key on Railway: `REVENUECAT_SECRET_KEY` (RevenueCat →
Project settings → API keys → secret key). Without it, household Pro arrives
only through the webhook.

| Setting | Where to get it |
|---------|-----------------|
| `REVENUECAT_IOS_KEY` | RevenueCat → Project → iOS app → Public API key |
| `REVENUECAT_ANDROID_KEY` | RevenueCat → Project → Android app → Public API key |

```bash
flutter run \
  --dart-define=REVENUECAT_IOS_KEY=appl_xxxx \
  --dart-define=REVENUECAT_ANDROID_KEY=goog_xxxx
```

---

## Optional: analytics

Anonymous funnel counts only (onboarding finished, first dose, etc.). No pet names or emails.
On by default in release builds, off in debug/profile builds.

```bash
flutter build ios --dart-define=ANALYTICS_ENABLED=false   # turn off in release
```

---

## What we deliberately skip in v1

| Feature | Why |
|---------|-----|
| **Sign in with Apple** | Phase 2 — not required to log doses or join with an invite code |
| **Custom login / passwords** | Device link + invite code is enough for households |
| **Push (partner logged a dose)** | Needs FCM/APNs keys on the server — local reminders work without it |

---

## Release build example

```bash
flutter build ipa --dart-define-from-file=config/release.json
```

`config/release.json` holds only public client values (API URL, RevenueCat
`appl_` SDK key). Server secrets — the RevenueCat webhook secret and the
Railway SSH target — live in `config/secrets.local.env` (gitignored; template
in `config/secrets.example.env`). The webhook secret is also stored in Railway
and in the RevenueCat webhook's Authorization header; change all three together.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “Can’t reach the household” | Check internet, or run with `API_BASE_URL=` for offline-only |
| Paywall says purchases unavailable | Add RevenueCat keys or use “Continue free” |
| “Sign in again to reach this household” | Re-join with your invite code from **Invite** — no Apple ID needed |
