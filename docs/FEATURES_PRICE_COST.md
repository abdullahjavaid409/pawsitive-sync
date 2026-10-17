# Gave It — every feature: price and running cost

As of 2026-10-14. Limits read from the code (`lib/core/constants/pet_limits.dart`,
`CareRepository.can*`). Prices from the live paywall (RevenueCat): **$29.99/yr
with a 7-day trial, or $4.99/mo**. One Pro plan covers the whole household.

Design board with all 20 screens tagged Free/Pro:
[Magic Patterns — Gave It App Screens](https://www.magicpatterns.com/c/fx73k9pujesskigmc5zdb8). References: Mobbin deep searches per
screen (see docs/REDESIGN_GAVE_IT.md and the redesign doc).

## Price per feature and where it runs

| Feature | Free | Pro | Runs on | Our running cost |
|---|---|---|---|---|
| Welcome + onboarding, no account | Yes | — | Phone | $0 |
| Log a dose ("Gave it"), offline | Yes, always | — | Phone | $0 |
| Double-dose guard, "Not sure if given" | Yes, always | — | Phone | $0 |
| Dose reminders, lock-screen actions | Yes | — | Phone (local notifications) | $0 |
| Pets | 1 pet | Up to 10 | Phone + sync | ~$0 |
| Medicines per pet | 1 | Unlimited | Phone + sync | ~$0 |
| Dose times | Morning only | Afternoon + evening | Phone | $0 |
| Coming up (vet, vaccine, refill) | Yes | — | Phone + sync | ~$0 |
| Supply count + "I refilled it" | Yes | — | Phone + sync | ~$0 |
| Low-supply alerts | — | Yes | Phone | $0 |
| History on screen | 30 days | Full | Phone | $0 |
| Vet PDF export | — | Yes | Phone (PDF made on device, `pdf` package) | $0 |
| Weekly summary | — | Yes | Phone | $0 |
| Household view | Yes | — | Server | small API calls |
| Invite caregivers, roles | Joining is free | Owner needs Pro | Server | small API calls |
| Sitter browser link | — | Yes | Server (web page) | small API calls |
| Shared activity + push to others | — | Yes (needs a household) | Server + Apple push | push free; API calls |
| Pet photo sync | Yes | — | Railway S3 bucket (phone uploads direct) | storage per photo |

## What a subscriber is worth

- Yearly: $29.99 − Apple 15% (Small Business Program) = **$25.49** per
  household per year. RevenueCat is free under $2.5k monthly tracked revenue,
  then 1%.
- Monthly: $4.99 − 15% = **$4.24** per household per month ($50.88/yr).
- Server: roadmap estimate $20–50/mo up to 1k households, $100–300/mo for
  1k–10k (docs/LONG_TERM_ROADMAP.md). That is about **$0.01–0.05 per
  household per month**: one yearly subscriber pays for roughly 40–200
  households' hosting.

Assumptions: server figures are the roadmap estimate, not a Railway bill.
Apple's 15% needs the App Store Small Business Program; otherwise 30% in the
first year of a subscription.

## Open pricing bet

PawLog, Pawlo and DogLog share the household for free; PetPill charges. Option:
make one partner free, keep 3+ caregivers, sitter links and history in Pro.
Not changed in code — owner decision.

## UX check of the board (20 screens)

Every screen has one obvious primary action, and Pro is labelled before the
tap (lock tag on the control), never after. Logging, the double-dose guard
and "Not sure" carry no Pro tag anywhere.

| Screen | Easy? | Note |
|---|---|---|
| Welcome, pet basics, care needs, reminders | Yes | 3 steps + permission; care needs skippable; no account |
| Today, guard, not sure, lock screen | Yes | "Gave it" one tap; guard's primary is "Don't give" |
| Add medicine | Yes | Free limit stated inline ("1 medicine per pet at a morning time") |
| Medicine detail | Yes | "I refilled it" is the one action; low-supply alert is a Pro toggle |
| Pet profile, coming up | Yes | Matches the shipped Pets build |
| Household, invite, join | Mostly | Invite offers role, link (Copy), code and Share; see pricing note |
| Sitter web page | Yes | "I gave it" per row, no install |
| Reports, vet PDF | Yes | Locked ranges show a lock; "Share PDF with vet" carries the Pro tag |
| Paywall, settings | Yes | Real dates on the trial timeline; Restore, Terms, Privacy present |

Gaps to decide before building:

1. **Join is free, but only a Pro owner can invite.** A Free owner's partner
   can never get in. This is the sharing price bet above.
2. **"Check with Sara"** on the Not-sure sheet needs a defined action. The app
   has no chat, so it should open the share sheet / Messages with a prefilled
   text.
3. **Five Pro locks** are visible to a Free user (dose times, low-supply
   alert, report ranges, PDF, weekly summary). Each is honest, but they
   should all open the same paywall with a reason, which the app already
   supports (`PaywallReason`).
