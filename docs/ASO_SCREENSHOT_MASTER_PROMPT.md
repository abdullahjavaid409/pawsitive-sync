# Master prompt — App Store screenshots, custom product pages, A/B tests

Paste everything inside the fence into Claude, ChatGPT, or Cowork. Attach the
raw simulator screenshots from `marketing/screenshots/raw/` (and, if you have
them, screenshots of competitor listings). Run it in each tool, then compare
the three answers and keep what is best.

```
ROLE
You are a senior App Store Optimization (ASO) strategist and conversion
designer. You have shipped screenshot sets for top-grossing subscription apps
(health, family, pet). You think in tap-through rate (search impression →
product page), conversion rate (page view → install), and trial-start rate.
You are blunt. You cite evidence for every claim, and you flag guesses as guesses.

PRODUCT
- App: PawsitiveSync — App Store name "PawsitiveSync: Pet Meds",
  subtitle "Shared Dog & Cat Dose Reminder".
- Its one job: answer "Did anyone give the dose?" for a household that shares
  a pet's medicine. It is not a social app, a vet records app, or a general
  pet tracker.
- Core loop: one shared Today list → tap "Log dose" → everyone in the house
  sees "Given by Sara · 8:02 AM". If someone tries to give the same dose
  again, a double-dose guard stops them and names who gave it.
- Proof points (all real, all visible in the attached screenshots):
  1. Double-dose guard that names who gave the dose
  2. Works offline, with no account before the first dose
  3. iPhone and Android in one household; sitters join with a browser link,
     no app install
  4. "Not sure if given" state for real-life mix-ups
  5. Low-supply alert before the medicine runs out (Pro)
  6. A vet report the owner can share in one tap (Pro)
  7. Free plan: 1 pet, unlimited medicines, the safety guard. Safety is never
     behind the paywall.
- Pro: $29.99/yr with a 7-day free trial, or $4.99/mo. Pro adds multiple pets,
  household invites, the vet export, and low-supply alerts.
- Brand: calm, trustworthy, warm. "Apple Health meets a quiet vet clinic."
  Colors: green #4A7C59, dark green #3D6A4B, soft green #E9F1EB, off-white
  #FBFBFA, ink #2C3531, amber #E7A959 (accent only). Font: Geist.
  Never use purple, neon, black backgrounds, emoji-style 3D, or stock-photo pets.

MARKET (US, pulled 2026-10-03)
- Search demand (Google Ads proxy): "medication reminder app" 3,600/mo,
  "pet care app" 1,300, "med tracker" 720, "pill tracker app" 390,
  "pet health tracker" 210, "pet medication tracker" 40, "dog medication
  tracker" 20. Exact pet-medication terms have little demand yet, so we
  win generic tokens (medication, reminder, tracker, pill) combined with
  pet, dog, and cat.
- Giants (Chewy, Rover, PetDesk) own "pet care app". Human pill apps
  (Medisafe, Hero) own "medication reminder". Don't fight them head-on.
- There are about 30 pet-medication apps and none is a leader; nearly all
  have 0–10 ratings. Direct "shared care" rivals: PetPill (iCloud only, so
  no Android partners), PawPact, MoaTails, Who Fed Henry.
- Highest-paying segment: owners of pets with diabetes (insulin twice a
  day), kidney disease, seizures, or arthritis. These are daily, high-stakes
  medicines where a missed or doubled dose hurts the pet.

WHAT WE KNOW ABOUT CONVERSION (use it, challenge it if you have better data)
- Apple shows up to 3 portrait screenshots in iPhone search results. The
  first 3 frames carry most of the conversion weight, and most people never
  swipe further.
- Frame jobs: 1 = hook (the outcome or the fear relieved), 2 = proof (the
  real UI delivering it), 3 = second benefit or differentiator.
- Custom product pages (CPPs) can now appear in organic search, with
  keywords assigned from the keyword field. You can have up to 70. Each CPP
  gets its own screenshots, promo text, and analytics.
- Test risky concepts on CPPs with Apple Ads traffic first, then promote
  the winner to a Product Page Optimization (PPO) test on the default page.

APPLE RULES (hard constraints, a rejection costs a week)
- Every frame shows the real app UI. No fake reviews, star ratings, "#1",
  "Best", or awards we have not won.
- No price claims unless they are exactly true. Don't show Apple hardware
  in ways that break Apple's marketing guidelines. No other brands' logos.
- No medical claims ("prevents overdose", "vet approved"). Say "helps
  your household avoid double doses", not "prevents".
- Headlines ≤ 5 words where possible, readable at search-result thumbnail
  size (~120 px wide). One idea per frame.

TASKS
1. Competitor teardown. For the top 10 listings shown for "pet medication
   tracker", "dog medication reminder", "cat insulin tracker", and "pet care
   app", record: frame-1 headline, visual style, what job each of the first 3
   frames does, and the one thing each does better than us. End with the 3
   patterns that win, plus 3 gaps nobody owns.
2. Default page (PPO control). Write 6 frames: headline (≤5 words),
   subline (≤9 words), which attached screenshot to use, what to crop or
   zoom into, and the emotion it should trigger. Frame 1 must work as a
   standalone ad.
3. Custom product pages. Design 3 CPPs, each for a different intent:
   A) Diabetic pet / insulin owners — keywords: insulin, diabetes, cat,
      dog, tracker, reminder
   B) Couples and families sharing care — keywords: shared, household,
      family, partner, sitter
   C) Multi-pet homes — keywords: multi pet, dogs, cats, schedule, refill
   For each CPP: 5 frames (same format as task 2), 170-character promo
   text, the keyword set to assign, and the Apple Ads ad group it should
   receive.
4. Test plan. Run PPO with up to 3 treatments against the control, one
   variable per treatment. Give a hypothesis for each, the metric
   (conversion rate, plus trial starts tracked in RevenueCat), the minimum
   detectable effect, and the run time to reach 90% confidence at our
   traffic. Assume about 1,500 page views a week at launch, and say if
   that is too low.
5. Revenue math. Estimate installs → trial → paid for each page using
   2026 subscription benchmarks (cite the source). State a realistic
   lift range. Don't promise a number. If someone asks for "65% ROI",
   explain what would have to be true for it.
6. Hand-off. Output one table per page:
   frame | headline | subline | source screenshot | crop/zoom | background
   | callout. A designer or a Pillow script must be able to build from it
   with no follow-up questions.

OUTPUT
Markdown, tables wherever possible. Skip generic ASO advice we did not ask
for. Finish with: "The single change most likely to lift conversion this
month is ___ because ___."
```

## How to use the answers

1. Run the prompt in Claude, ChatGPT, and Cowork. Keep the strongest
   headlines from each. Disagreements between them point to good A/B
   candidates.
2. Put the chosen copy into `marketing/screenshots/pages.json`, then run
   `python3 scripts/compose_store_screenshots.py` to render every page at
   1320×2868 (6.9") and 1290×2796 (6.7").
3. Upload in App Store Connect:
   - **Default page:** the `default` set
   - **Product Page Optimization:** add up to 3 treatments, 50/50 traffic,
     and run until it reaches 90% confidence
   - **Custom product pages:** create one CPP per set, assign its keywords,
     and point the matching Apple Ads ad group at it
4. Record results in `docs/ASO_KEYWORDS.md`. A winning CPP concept gets
   promoted to a PPO treatment on the default page.

## Ready-made sets (first version, 2026-10-03)

Rendered in `marketing/screenshots/out/<page>/{6.9,6.7}/`. Copy, keywords
and promo text live in `marketing/screenshots/pages.json`.

| Page | Who it's for | Frame 1 hook | Keywords to assign |
|------|--------------|--------------|--------------------|
| `default` (7 frames) | Everyone; PPO control | "Did anyone give the dose?" over the double-dose guard | pet, meds, dose, reminder, tracker, medication |
| `cpp-insulin` (5) | Diabetic cats/dogs | "Insulin given? Know for sure." | insulin, diabetes, diabetic, cat, dog |
| `cpp-household` (5) | Couples, families, sitters | "No more "did you give it?" texts" | shared, household, family, partner, sitter |
| `cpp-multipet` (5) | 2+ pets (Pro gate) | "Every pet's meds in one place" | multi, pets, dogs, cats, schedule, refill |

### First A/B tests (one variable each)

1. **PPO, frame 1 hook:** control = guard screen ("Did anyone give the
   dose?") vs. treatment = shared schedule ("No more "did you give it?"
   texts"). Tests fear relief vs. household convenience.
2. **PPO, frame 1 colour:** brand green vs. light background, with the same
   copy.
3. **CPP vs. default on Apple Ads:** send the `insulin`/`diabetes` ad group
   to `cpp-insulin` and a matched group to the default page. Compare
   conversion rate, and trial starts in RevenueCat.

At about 1,500 page views a week, a PPO test needs roughly 3–4 weeks to
detect a ~20% relative lift. Run one test at a time.

### Regenerate everything

```bash
scripts/store_screenshots.sh            # simulator → marketing/screenshots/raw (needs QA backend on :3100)
python3 scripts/compose_store_screenshots.py   # raw → store-ready frames
```
