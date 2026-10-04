# App Store listing — PawsitiveSync 1.0.0

Paste into App Store Connect → App Information / version page. Limits are
Apple's; every field below fits. Must stay true to the app: Free = one pet,
one medicine with a morning reminder, dose logging and double-dose checks
always free. Pro = everything else.

## Name (30)

PawsitiveSync: Pet Meds

## Subtitle (30)

Did anyone give the dose?

## Promotional text (170)

Never double-dose or miss a dose again. Log your pet's medicine in one tap, get a reminder when it's due, and see who gave it — even offline.

## Description (4000)

Did someone already give the dose?

PawsitiveSync is the simple pet medicine log for busy households. One tap records a dose, a reminder tells you when the next one is due, and everyone who helps can see who gave it and when — so your pet never gets a dose twice or misses one.

WHY PET PARENTS USE IT
• One-tap dose log — record it the moment you give it
• Double-dose check — if a dose is already logged, PawsitiveSync tells you before you give it again
• "Not sure if given" — mark a doubtful dose so the next person checks first
• Today at a glance — what's due, what's done, what's coming up
• Reminders when a dose is due
• Works offline — log without Wi-Fi, it syncs when you're back online
• No account needed to start — your first dose takes seconds

FREE
• One pet
• One medicine with a daily morning reminder
• Dose logging, double-dose checks and "not sure if given" — always free, never behind a paywall
• 30 days of dose history

PAWSITIVESYNC PRO
• Every medicine, every dose time — morning, afternoon and evening reminders at any time you choose
• Up to 10 pets in one household
• Shared care — invite a partner, family member or sitter; everyone sees who gave each dose
• Vet-ready reports — export a clear week-by-week dose record for checkups
• Low-supply alerts before the bottle runs out
• Full dose history, plus a weekly summary

SUBSCRIPTION DETAILS
PawsitiveSync Pro is available as a monthly or yearly auto-renewing subscription. The yearly plan includes a 1-week free trial for new subscribers. Prices are shown in the app before you buy and may vary by country.
• Payment is charged to your Apple ID account at confirmation of purchase, or when the free trial ends.
• The subscription renews automatically unless it is canceled at least 24 hours before the end of the current period.
• Your account is charged for renewal within 24 hours before the end of the current period.
• You can manage or cancel your subscription in your Apple ID account settings after purchase. Any unused part of a free trial ends when you buy a subscription.

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://sites.google.com/view/pawasitive/home

PawsitiveSync helps you keep a record of care. It is not veterinary advice — always follow your veterinarian's instructions for your pet's medicines and doses.

## Keywords (100)

pet,medication,dog,cat,dose,reminder,vet,pill,tracker,insulin,log,sitter,household,care,refill

## What's New (1.0.0)

Welcome to PawsitiveSync — the shared medicine log for your pet. Log a dose in one tap, get reminded when it's due, and never wonder if someone already gave it.

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | https://sites.google.com/view/pawasitive/home |
| Support URL | *(required — e.g. a contact page or the same site with a support email)* |
| Marketing URL | optional |

## License Agreement (EULA)

The app uses **Apple's Standard EULA** — the same link the app shows as
"Terms of Use" before purchase (`lib/core/legal/app_links.dart`).

- In App Store Connect → App Information → **License Agreement**, keep
  **"Apple's Standard License Agreement"** (no custom EULA needed).
- Apple Guideline 3.1.2 requires a working Terms of Use link for
  subscriptions: it's in the description above and inside the app's paywall.

## App Review — notes (paste into "Notes" for the reviewer)

PawsitiveSync works without an account: complete the short setup (pet name, a few taps) to reach Today.

Free tier: one pet and one medicine with a morning reminder. Dose logging and double-dose checks are always free. Adding a second medicine, or choosing an afternoon/evening dose time, opens the Pro paywall.

Pro is an auto-renewing subscription (monthly, or yearly with a 1-week free trial), purchased through StoreKit via RevenueCat. Use a Sandbox Apple ID to test purchase and "Restore purchases" (Settings → Your plan).

Household sharing (Pro): Household → Invite someone shows a code another device can join with.

## Submit checklist

- [ ] Attach both subscriptions (`com.pawsitivesync.app.pro.monthly`, `com.pawsitivesync.app.pro.annual`) to this version — first-time subscriptions are reviewed with the app
- [ ] Age rating questionnaire, App Privacy answers, screenshots (6.9" and 13" iPad)
- [ ] Support URL
- [ ] Upload `build/ios/ipa/pawsitive_sync.ipa` (Transporter) → choose the build on the version page
