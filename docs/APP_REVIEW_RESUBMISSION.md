# App Review resubmission pack — Gave It 1.1.0

Context: 1.0 was rejected twice under 4.3(a)/(b) spam and 4.2.6. The written
reply (2026-10-06) did not change the outcome, and Apple said: do not
resubmit until **significant changes** are made. Nothing here guarantees
approval. This pack removes every reason we know of to reject.

Related: [REDESIGN_GAVE_IT.md](REDESIGN_GAVE_IT.md) (identity),
[ASO_KEYWORDS.md](ASO_KEYWORDS.md) (name, subtitle, keywords, search data).

## 1. Gate: do not submit until every box is ticked

Apple compares the new binary and listing with the rejected one. Metadata
changes alone read as the same app.

**Identity (what the reviewer sees first)**
- [ ] Home-screen name `Gave It`: `CFBundleDisplayName` in
      `ios/Runner/Info.plist`, `android:label` in `AndroidManifest.xml`
- [ ] In-app name strings: `lib/app.dart`, `welcome_screen.dart`,
      `notifications_screen.dart`, `lock_screen.dart`, `paws_widgets.dart`,
      `vet_report_pdf.dart` (PDF creator), household invite/share text
- [ ] New premium icon (ledger check, no paw) in every iOS/Android size
- [ ] New theme: ink blue + paper palette, Bricolage Grotesque / Atkinson
      Hyperlegible / JetBrains Mono, 4–10px radii, hairlines (no sage, no Geist)
- [ ] Core screens rebuilt, not recolored: ledger dose rows, "Gave it" button,
      stamp-style guard sheet, ledger strip on Today

**Product (substance, not paint)**
- [ ] The guard is the first thing a new user meets (onboarding shows a
      worked example of "already given" before the first dose)
- [ ] Sitter browser link and "Not sure if given" are reachable in Free or
      clearly shown in screenshots, since they are the differentiators
- [ ] Version bumped to `1.1.0` in `pubspec.yaml`

**Listing**
- [ ] Name, subtitle, keywords, description, promo text from section 2
- [ ] New screenshots, guard stamp first (6.9" and 13" iPad)
- [ ] New App Preview / demo video recorded on the new design
      (`marketing/app-review/` holds the old-design recordings; do not reuse)

**Brand consistency (mismatches look like a reskinned template)**
- [ ] Privacy policy, support page and invite emails say "Gave It", not
      PawsitiveSync. The privacy URL is `sites.google.com/view/pawasitive`:
      move it to a Gave It page, or at least retitle the page
- [ ] Support URL set (it is still blank in APP_STORE_LISTING.md)
- [ ] USPTO search for "Gave It", class 9, is clean

**4.2.6 (template / generation service)**
- [ ] The Apple Developer account's legal name is the owner of the app and
      brand. If the account holder and the person replying in App Review
      differ, say in the notes that the replier is a member of the same team
- [ ] Nothing in the binary carries a template's or generator's name
      (check `Info.plist` copyright, bundle display strings, about screen)

**Beta (Apple asked for this; answer only with real data)**
- [ ] TestFlight round with real multi-caregiver households, run before
      submitting
- [ ] At least 2–3 concrete pieces of tester feedback that changed the build,
      written into section 4. Do not invent any.

## 2. App Store Connect metadata

**Name** (25/30): `Gave It – Shared Pet Meds`

**Subtitle** (28/30): `Shared Insulin & Pet Med Log`

**Keywords** (98/100):
`dog,cat,medication,reminder,tracker,pill,medicine,dose,diabetic,feline,sitter,household,vet,refill`

**Promotional text** (170):
> Two people, one pet, one dose. Gave It shows who already gave it and stops a second dose before it happens. Log in one tap, even offline.

**Description**:

> Did someone already give the insulin?
>
> When two or more people care for a pet on daily medicine, doses get missed or given twice, because each person thinks the other did it. Gave It is one shared log for the whole household. Each dose shows who gave it and when, and the app stops you before a dose is given twice.
>
> HOW IT WORKS
> • Tap "Gave it" the moment you give a dose. It works offline and syncs later.
> • If someone already logged it, Gave It stops you and shows who gave it and when: "Sara gave it at 8:02 AM."
> • Not sure? Mark "Not sure if given" so the next person checks first.
> • Sitters log from a browser link, with no app and no account.
> • Today shows what's due, what's done and what's coming up.
> • No sign-up to start. Your first dose takes seconds.
>
> BUILT FOR
> Diabetic cats and dogs on insulin, pets on seizure, kidney, heart or arthritis medicine, post-surgery courses, and any home where more than one person helps.
>
> FREE, ALWAYS
> • One pet and one medicine with a morning reminder
> • Dose logging, the double-dose stop and "Not sure if given". Safety is never behind a paywall.
> • 30 days of history
>
> GAVE IT PRO
> • Every medicine and dose time (morning, afternoon and evening)
> • Up to 10 pets in one household
> • Invite a partner, family member or sitter
> • Vet-ready dose reports
> • Low-supply alerts and full history
>
> SUBSCRIPTION DETAILS
> Gave It Pro is a monthly or yearly auto-renewing subscription. The yearly plan includes a 1-week free trial for new subscribers. Prices are shown in the app before you buy.
> • Payment is charged to your Apple ID at confirmation of purchase, or when the free trial ends.
> • It renews automatically unless canceled at least 24 hours before the end of the current period.
> • Renewal is charged within 24 hours before the end of the period.
> • Manage or cancel in your Apple ID account settings. Any unused part of a free trial ends when you buy a subscription.
>
> Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: <new Gave It privacy URL>
>
> Gave It keeps a record of care. It is not veterinary advice. Always follow your veterinarian's instructions.

**What's New (1.1.0)**:
> Gave It is the new name and look for our shared pet medicine log, rebuilt around one question: has anyone already given this dose? New: the "Gave it" log, the already-given stamp, and a clearer Today ledger.

## 3. App Review notes (paste into "Notes")

> Gave It is a shared dose log for households where several people medicate one pet. Its core feature is a pre-dose guard: when a second caregiver tries to log a dose that someone already gave, the app stops them and shows who gave it and when.
>
> This version is a substantial redesign following the 4.3 / 4.2.6 rejection of 1.0: new name, icon, visual design and core screens, built around the guard instead of general pet care. A demo video is attached.
>
> To see the guard in about 1 minute, without an account:
> 1. Finish the short setup (pet name, one medicine) to reach Today.
> 2. Tap "Gave it" on the dose.
> 3. Tap it again. The "Already given" stamp appears with who gave it and the time. This is the double-dose stop a second caregiver sees.
> 4. Open the dose and choose "Not sure if given" to see the third state.
>
> Household sharing and sitter links are Pro (auto-renewing subscription via StoreKit and RevenueCat). Use a Sandbox Apple ID; Restore is in Settings → Your plan.
>
> The app was written from scratch by the account holder in Flutter. It uses no template, white-label product or app generator. The sync server, offline sync, guard logic, sitter web page, vet report and widgets are original. It is the only app on this account.

Attach the new demo video (under 2 minutes, real device or simulator, new
design, showing steps 1–4 and a sitter logging from the browser link).

## 4. If Apple asks the 9 questions again

Reuse the 2026-10-06 answers with these fixes:

- **Re-paste cleanly.** The 1.0 reply reached Apple with broken text
  ("ost-surgery", "oftendosing", "ofl" and cut-off sentences in answers 2, 3,
  4 and 8). Paste from a plain-text editor and re-read it in App Store Connect
  before sending.
- **Q4 (beta):** add the real TestFlight feedback from the gate checklist,
  with dates and what changed in the build. Leave out anything you can't
  show.
- **Q1/Q3:** describe the changes since 1.0 (section 1), not only the
  features.
- Use the same company or person name as the developer account throughout.

## 5. Other rejection risks to clear in the same build

| Guideline | Check |
|---|---|
| 2.1 completeness | No placeholder copy, dead buttons or broken links; works on a fresh install with no network |
| 2.3.7 metadata | No competitor or insulin brand names in keywords; screenshots show the real app |
| 3.1.2 subscriptions | Paywall shows price, period, trial terms, Terms + Privacy links and Restore |
| 1.4.1 medical | "Not veterinary advice" in the app (settings/about) and description; no dosing advice |
| 5.1.1(v) account deletion | Delete account is reachable in the app (the `delete_account` sheet) |
| 5.1.2 privacy | App Privacy answers match RevenueCat, push and sync data actually collected |
| 4.0 design | Light and dark mode, iPad layout, Dynamic Type at large sizes without clipping |
