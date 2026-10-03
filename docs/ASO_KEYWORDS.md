# App Store ASO — Name, Subtitle, Keywords

Data sources: DataForSEO Keywords Data API (Google Ads search volume, US,
proxy for demand), DataForSEO App Data API (live App Store listing search —
real competitor titles/subtitles/categories). Pulled 2026-10-03.

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

## Recommendation

**App Name** (23/30 chars — kept well under the 30-char cap on purpose:
maxing it out risks mid-word truncation on narrower App Store search rows;
23 chars reads cleanly on every device):
> `PawsitiveSync: Pet Meds`

**Subtitle** (30/30 chars):
> `Shared Dog & Cat Dose Reminder`

Together these seed the tokens: pawsitivesync, pet, meds, shared, dog, cat,
dose, reminder — all for free, no keyword-field budget spent. "Shared" is the
differentiator no competitor claims.

**Keywords field** (97/100 chars, no spaces, no repeats of words already in
Name/Subtitle, singular forms only — Apple's algorithm already matches
plurals and recombines individual words from Name + Subtitle + Keywords):
> `tracker,pill,medication,medicine,schedule,log,household,family,vet,refill,insulin,diabetes,kitten`

Covers: "medication reminder app" (3,600/mo), "pill tracker app" (390/mo),
"pet medication tracker" / "dog medication tracker" (exact-match niche),
"medicine schedule app" (50/mo), insulin/diabetes (the most common daily-med
pets), household/family shared care, and vet/refill intent.

Full-30 alternative name if truncation stops mattering:
`PawsitiveSync: Pet Med Tracker` (30/30) — then swap `tracker` out of the
keywords for `puppy,sync`.

**Note:** the device home-screen icon label is a *separate* field
(`CFBundleDisplayName` in `ios/Runner/Info.plist`, `android:label` in
`AndroidManifest.xml`) — already set to the short `PawsitiveSync` and
untouched by this ASO work. Only the App Store Connect "Name" metadata field
(entered in App Store Connect, not in this repo) needs the value above.

**Screenshot keyword callouts** (first 3 screenshots carry the most weight —
these don't affect indexing but drive tap-through/conversion, so lead with
the highest-intent phrase a searcher just typed):
1. "Did anyone give the dose today?" — mirrors the core search intent, no login wall
2. "One tap. Offline. No account needed." — addresses the #1 differentiator vs. human pill-tracker apps
3. "Share with your whole household" — the Pro-gate hook (multi-pet/household invite)
4. "Vet export in one tap" — Pro feature, secondary search intent ("vet visit tracker")
5. "Never run out — low-supply alerts" — Pro feature, ties to "refill"/"supply" keyword tokens

## Notes / caveats

- Google Ads volume is a demand *proxy*, not true App Store search volume —
  Apple doesn't expose that via public API. Apple Search Ads Popularity
  scores (true App Store intent) require an active ASA campaign with
  adgroups/keywords already running; this account has none yet, so that data
  source isn't available until a campaign exists.
- Re-run this quarterly — "medication reminder app" and "pet care app" are
  the two highest-value volume anchors and worth tracking for drift.
