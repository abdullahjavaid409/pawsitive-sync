# PawsitiveSync — setup (plain English)

You can run the app with **zero configuration**. Everything below is optional.

---

## Run locally (no setup)

```bash
flutter pub get
flutter run
```

- Pets, doses, and reminders work on this phone.
- Pro trial unlocks locally for testing.
- No account, no Apple Sign-In, no API keys needed.

---

## Optional: share a household online

Lets partners and sitters see doses in real time.

| Setting | What to pass | Default |
|---------|--------------|---------|
| API server | `--dart-define=API_BASE_URL=https://your-api.example.com` | Railway production URL |

**Fully offline:** pass an empty URL:

```bash
flutter run --dart-define=API_BASE_URL=
```

---

## Optional: App Store / Play purchases (RevenueCat)

Without keys, the paywall still works — “Continue free” and local Pro trial for QA.

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

## Optional: turn off analytics

Anonymous funnel counts only (onboarding finished, first dose, etc.). No pet names or emails.

```bash
flutter run --dart-define=ANALYTICS_ENABLED=false
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
flutter build ipa \
  --dart-define=REVENUECAT_IOS_KEY=appl_xxxx \
  --dart-define=API_BASE_URL=https://pawsitive-api-production.up.railway.app
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “Can’t reach the household” | Check internet, or run with `API_BASE_URL=` for offline-only |
| Paywall says purchases unavailable | Add RevenueCat keys or use “Continue free” |
| “Sign in again to reach this household” | Re-join with your invite code from **Invite** — no Apple ID needed |
