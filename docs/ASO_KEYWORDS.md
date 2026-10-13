# App Store ASO — Name, Subtitle, Keywords

Data sources: DataForSEO Keywords Data API (Google Ads search volume, US,
proxy for demand), DataForSEO App Data API (live App Store listing search —
real competitor titles/subtitles/categories). Pulled 2026-10-03;
name check and volumes refreshed 2026-10-13 (see Rename).

## Market signal (US monthly search volume)

| Keyword | Volume/mo | Competition | Note |
|---|---|---|---|
| medication reminder app | 3,600 | LOW | huge human-health term, not pet-specific but token-shares with "medication","reminder" |
| med tracker | 720 | HIGH | broad, token-shares with "med","tracker" |
| pet care app | 1,300 | LOW | best high-volume pet umbrella term |
| pill tracker app | 390 | LOW | token-shares "pill","tracker" |
| pet health tracker | 210 | HIGH | competitive, mostly wellness/fitness apps |
| medicine schedule app | 50 | LOW | token "schedule" |
| pet medication tracker | 40 | LOW | exact-match term, low volume but near-zero competition |
| pet meds app | 40 | HIGH | |
| dog medication tracker | 20 | LOW | |
| pet reminder app | 10 | LOW | |
| pet planner app | 10 | LOW | |
| pet health log | 10 | HIGH | |
| cat medication tracker / household pet tracker / multi pet tracker / pet dose tracker / pet symptom tracker / vet med tracker / dog pill reminder / cat pill reminder / dose tracker app / shared pet care app / pet med log / vet visit tracker | ~0 (no data) | — | zero measurable demand today — don't anchor copy on these exact phrases, but still fine as keyword-field tokens since they cost nothing and may pick up long-tail traffic |

**Reading:** nobody is searching "pet medication tracker" at volume yet — the
category is pre-demand, consistent with the roadmap's "own did-anyone-give-
the-dose, not social, not vet EMR" positioning. The money is in capturing the
generic high-volume human-adjacent tokens (**medication, reminder, tracker,
pill, schedule, med**) combined with **pet/dog/cat/household** via Apple's
token-matching (Apple indexes individual words from Title + Subtitle +
Keywords and recombines them — it does not require exact phrase matches).

## Competitor scan (live App Store listings, Medical/Lifestyle categories)

Pulled real title/subtitle pairs to check naming conventions — all found
competitors have single-digit review counts, confirming the multi-pet/
household-dose niche is still open:

- **PetCareDiary** — "Dog/Cat health care diary" (Lifestyle, 2 reviews)
- **Veterian — Pet Health & Care** — "Your Pet's Health Companion" (Medical, 2 reviews)
- **PetNote — Pet Health Care** — "Simple and easy to use" (Medical, 5 reviews, discontinued)
- **PILL — Medication Reminder App** — "Vitamins & Birth Control Alarm" (Medical, human-only)
- **Take Pills® Pill Reminder** — "Medication Reminder" (Medical, human-only)
- **Medmento: Medication Reminder** — "Pill tracker & memory support" (Medical, human-only, offline/no-account — closest positioning match to PawsitiveSync's offline-first stance)

Pattern: `[Brand]: [Primary Function]` for name, `[Secondary benefit/feature]`
for subtitle. No competitor owns "household" or "multi-pet dose sync" — that's
the open wedge.

## Rename after the 4.3 rejection (2026-10-13)

Apple rejected 1.0 twice under 4.3 (spam) / 4.2.6 (app generation). The
"PawsitiveSync" pun, the stock paw icon and the sage-green look read as one
more lookalike in a category of ~30. The 1.1.0 build ships under a new name.

### Name check (live App Store search via Apple Search Ads, 2026-10-13)

| Candidate | Result |
|---|---|
| DoseCheck | Taken — "DoseCheck: Medication Tracker" (John Warda) |
| Dosed / Dose\_\_\_ | Crowded — DoseDash, DoseDay (×3), DoseDone, DoseDeck, Dosed AI |
| Pet Meds \_\_\_ | Crowded — "Pet Meds Reminder", "Pet Meds & Activity Log" |
| Given | Crowded — "GIVEN" (Taiwan Given), "Given - Gift Manager", "Given: Baby Names", "Given: Relationship Reminders" |
| Who Gave | Close — "Who Gave Me What" |
| **Gave It** | No app found — chosen ("Gave" alone only matches Gavel/Gaven/Gaveta) |
| Already Gave | No app found — backup |

An empty search is not a trademark clearance: run a USPTO search for
"Gave It" in class 9 before the build ships.

### Fresh volumes (Google Ads, US, 2026-10-13)

| Keyword | Volume/mo |
|---|---|
| pet medication tracker | 40 |
| dog medication reminder | 10 |
| pet medication reminder | 10 |
| pet pill reminder | 10 |
| cat medication reminder, pet/dog/cat insulin tracker, diabetic cat/dog app | no data |

Same reading as 2026-10-03: pet-specific phrases barely register, so the
brand can be distinctive while subtitle + keywords carry the high-volume
tokens (medication, reminder, tracker, pill).

### App Store search check (DataForSEO App Data, US, top 100, 2026-10-13)

- **"pet medication tracker"** is a field of lookalikes: PetMed, PipDose,
  PawDose, Pawzy, PetDose, PillPaw, Pawscriptions, TailCare, Muzzly, Arya.
  At least six have "Paw" in the name and nearly all have under 30 ratings.
  Paw icon + "Pet Med" name is the template Apple flagged under 4.3.
- **"cat insulin"** is thinner: Feline Diabetes, PetDose (Cat Insulin),
  CarePaws, Lumi, DiabiPets, Diabetes Tracker for Pets, Insulin Log, PillPaw.
  The rest is cat translators and games, so few results really serve the search.
- No ranked app leads with a shared household or "already given" claim.

### Condition volumes (Google Ads, US, 2026-10-13)

| Keyword | Volume/mo |
|---|---|
| cat insulin / feline insulin | 1,900 |
| insulin for cats with diabetes | 880 |
| pet medication reminder app | 20 |

Owners search for the condition (insulin, diabetes), not for "pet
medication tracker". The listing shows its purpose by naming the condition.

## Recommendation

**App Name** (25/30):
> `Gave It – Shared Pet Meds`

**Subtitle** (28/30):
> `Shared Insulin & Pet Med Log`

The previous subtitle, `Dog & Cat Medication Reminder`, matched dozens of
listings word for word. The new one names the highest-volume condition
(insulin) and the claim no competitor makes (shared). Name + subtitle seed:
gave, shared, pet, meds, insulin, med, log.

**Keywords field** (98/100, no spaces, no words already in Name/Subtitle):
> `dog,cat,medication,reminder,tracker,pill,medicine,dose,diabetic,feline,sitter,household,vet,refill`

`dog`, `cat`, `medication` and `reminder` moved here from the old subtitle,
so "medication reminder app" (3,600/mo) and "dog medication reminder" still
match. `diabetic` and `feline` cover the condition searches; `puppy`,
`kitten`, `schedule`, `family` and `diabetes` dropped for space (Apple
matches "diabetes" loosely from `diabetic`). No insulin brand names (e.g.
ProZinc): trademarked terms in the keyword field risk rejection.

**Note:** the home-screen label is a *separate* field
(`CFBundleDisplayName` in `ios/Runner/Info.plist`, `android:label` in
`AndroidManifest.xml`) — set it to `Gave It`. The bundle ID
`com.pawsitivesync.app` stays so RevenueCat products and subscriptions keep
working. The App Store Connect "Name" field takes the value above.

**Screenshot callouts** (first 3 carry the most weight; see
[REDESIGN_GAVE_IT.md](REDESIGN_GAVE_IT.md)):
1. "Sara already gave Miso's insulin" — the guard stamp, the one screen no
   ranked app shows; lead with it for the 4.3 resubmission
2. "Did someone already give it?" — the core search intent
3. "One tap. Logged for everyone." — works offline, no sign-in to start
4. "Sitters log without the app" — browser link, no account
5. "A clean log for your vet" — Pro report

## Notes / caveats

- Google Ads volume is a demand *proxy*, not true App Store search volume —
  Apple doesn't expose that via public API. Apple Search Ads Popularity
  scores (true App Store intent) require an active ASA campaign with
  adgroups/keywords already running; this account has none yet, so that data
  source isn't available until a campaign exists.
- Re-run this quarterly — "medication reminder app" and "pet care app" are
  the two highest-value volume anchors and worth tracking for drift.
