# Gave It — revenue plan

Goal: the most revenue per install without dark patterns. Hard limits from
AGENTS.md: dose logging and the double-dose guard stay free; the paywall
stays honest (price, period, trial terms, Restore, Terms/Privacy — App Review
3.1.2). Prices and trials come only from RevenueCat.

References (Mobbin, 2026-10-13), the largest subscription apps rather than
pet competitors:
[Headspace](https://mobbin.com/screens/17e4ce60-0851-40be-92af-336be1220857),
[Monarch](https://mobbin.com/screens/f4f97ca0-8e85-4609-8f21-c5c9902171d4),
[Quizlet](https://mobbin.com/screens/1c14274b-c9e0-4c46-bdb5-018567fa5f49),
[5 Minute Journal](https://mobbin.com/screens/2494e11b-8fbf-480c-8e33-4bb736f176c3),
[Pillow](https://mobbin.com/screens/73a2cafa-d97e-477b-9e00-1e276ef50151).
All lead with the same honest pattern: a trial timeline (today → reminder
before it ends → billing day), yearly preselected with its monthly price.

Today: $29.99/yr (7-day trial), $4.99/mo. Market: PawLog $39.99/yr,
DogLog $52.99/yr, EveryDose $69.99/yr (see COMPETITORS_AND_PRICING.md).

## Levers, ranked

| # | Lever | Where | Who does it |
|---|---|---|---|
| 1 | **Trial timeline on the paywall**: "Today: full access · Day 5: we remind you · Day 7: $X/year, cancel anytime before". Removes the main fear of starting a trial. | App (paywall) | Claude, in code |
| 2 | **Real trial-ending reminder**: a local notification 2 days before the trial ends, matching the promise in #1. Fewer refunds and 1-star "charged without warning" reviews. | App (reminders) | Claude, in code |
| 3 | **Price test**: yearly $29.99 vs $39.99, monthly $4.99 vs $7.99 (a higher monthly anchors yearly as the deal). Run as a RevenueCat Experiment, not a guess. | RevenueCat + App Store Connect | You (new products), then Claude wires the offering |
| 4 | **Lifetime option** (~$79.99 one-time, non-consumable). Diabetic and epileptic pets are on meds for years; subscription-averse owners buy once. 5 Minute Journal shows it beside annual. | App Store Connect + RevenueCat | You (product), Claude (paywall row) |
| 5 | **Household framing**: "One plan covers everyone who cares for your pet", so the price reads per household, not per person. | Paywall copy | Claude |
| 6 | **Paywall at peak intent** (already gated, keep): inviting a partner, adding a second pet, evening dose time. Add: after the guard stops a dose for a solo user, offer "Share the log so this never happens" once. | App | Claude |
| 7 | **Win-back**: Apple win-back offers for lapsed subscribers via RevenueCat; one-question cancel survey. | App Store Connect + RevenueCat | You (offer), Claude (copy) |

Not doing: fake countdown timers, hidden close buttons, pre-checked upsells,
paywalling dose logging or the guard, guessed prices.

## Order

1. #1 + #2 + #5 now: code only, no store changes, low risk, ships in 1.1.0.
2. #3 + #4 next: need new products in App Store Connect and RevenueCat
   (owner action), then a RevenueCat Experiment for 2–4 weeks.
3. #6 + #7 after data from the first 1.1.0 cohort.

Measure in RevenueCat: trial start rate, trial→paid, refund rate, and
revenue per install, split by experiment arm.
