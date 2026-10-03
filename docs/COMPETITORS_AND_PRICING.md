# PawsitiveSync — competitors, positioning, pricing

Data: US App Store search results pulled 2026-10-03 (DataForSEO App Data) for
"dog medication reminder", "pet care app", "cat medication"; competitor prices
from web search. Ratings counts are a snapshot — recheck before big decisions.

---

## 1. The market

### Giants — not head-to-head competitors
| App | Ratings | What it really is |
|-----|---------|-------------------|
| Chewy | 1.18M | Pharmacy + shop |
| Rover | 516k | Pet sitters |
| PetDesk | 506k | Vet clinic portal |
| Banfield | 122k | Vet hospital chain |
| myVCA | 41k | Vet hospital chain |

They own "pet care app"; reminders are a side feature tied to their clinic or
pharmacy. Do not fight them for that keyword.

### Human medication apps ranking for pet searches
Medisafe (101k), Pill Reminder All-in-One (28k), Hero (10.6k), Max (9.8k).
They rank on "medication reminder" volume. No pets, no household, no
"who already gave it" check.

### General pet trackers
| App | Ratings | Price |
|-----|---------|-------|
| Pet Care Tracker Dog Cat Log | 948 (4.83★) | — |
| Digitail (vet-linked) | 3.7k | — |
| DogLog | — | $5.49/mo, $52.99/yr |
| PawLog | — | $6.99/mo, $39.99/yr (7-day trial) |
| 11pets | — | freemium |

They track everything (food, walks, weight); medicine is one tab.

### Pet-medication niche — crowded, no leader
~30 small new apps (PipDose, Bean, PillPaw, DozePaw, Medpaw, Pawzy, Nuzzy,
TailyDose, PetMed, Pawmeds, MediTracker, …), almost all with 0–10 ratings.
Strongest: PillCat (155 ratings, cats only). Nobody is winning yet.

### Direct rivals — "shared household care"
| App | How sharing works | Free tier |
|-----|-------------------|-----------|
| PetPill | iCloud (iPhone-to-iPhone only) | 1 pet, 1 medicine |
| PawPact | shared household space | — |
| MoaTails: Shared Pet Care Log | shared log | — |
| Who Fed Henry | shared tracker (5 ratings) | — |
| Pill Reminder for Family | family (22 ratings) | — |

---

## 2. Where PawsitiveSync wins

| Our edge | Why rivals can't easily match it |
|----------|----------------------------------|
| iPhone + Android in one household | iCloud-based rivals (PetPill) exclude Android partners |
| Sitter browser link, no app install | No rival found offers it; sitters won't install apps |
| Double-dose guard names who gave it | Rivals log doses; we prevent the dangerous mistake |
| "Not sure if given" state | Real-life case nobody else handles |
| Free: 1 pet, unlimited medicines, safety guard | PetPill free = 1 medicine |
| Yearly $29.99 | Below PawLog $39.99 and DogLog $52.99 |

---

## 3. How to compete (priority order)

1. **Own one job: "Did anyone give the dose?"** Not another pet care app.
   Subtitle `Shared Dog & Cat Dose Reminder` does this; screenshots 1–2 must
   show the double-dose guard and partner sync.
2. **Win ratings fast.** Everyone in the niche has 0–10 ratings — 50 good
   ratings puts us on top. Ask for a review at a happy moment (3rd dose
   logged, first partner sync).
3. **Lead with "works with Android partners and sitters — no app needed."**
   It's the hole in PetPill and the iCloud apps.
4. **Target conditions:** diabetic cats/dogs (insulin twice daily), kidney
   disease (fluids), seizures, arthritis — daily, high-stakes meds where a
   missed or double dose hurts, so owners pay.
5. **Get vets recommending us.** The vet report export gives clinics a reason.
6. **Don't chase** "pet care app" (giants) or generic "medication reminder"
   (Medisafe) as primary positioning.

---

## 4. Pricing

| Plan | Price | Trial | Notes |
|------|-------|-------|-------|
| Free | $0 | — | 1 pet, logging, double-dose safety, reminders (safety stays free) |
| **Yearly** (pre-selected) | **$29.99/yr** (~$2.50/mo) | **7 days** | Main revenue plan |
| Monthly | $4.99/mo | none | Anchor: $59.88/yr — "Save 50%" badge is accurate |
| Lifetime (later) | $79.99 once | — | Needs a small code change |
| Win-back | $14.99 first year | — | Apple win-back offer for lapsed users |

- Launch at $29.99; after ~50 ratings A/B test **$39.99** in RevenueCat
  (badge becomes "Save 33%").
- Set USD prices; let App Store Connect / Play auto-equalize other countries.
- Turn on Family Sharing for yearly — fits a household app.
- Before launch: the paywall button says "Start 7-day free trial · Monthly";
  if monthly has no trial, change it to "Subscribe · $4.99/mo".

---

## 5. Product identifiers

App: `com.abdulmanan.pawsitivesync` (iOS + Android). Code requires entitlement `pro`
and product IDs containing `annual`/`year` or `month`.

### App Store Connect
| Item | Identifier |
|------|------------|
| Subscription group | `PawsitiveSync Pro` |
| Yearly (rank 1) | `com.abdulmanan.pawsitivesync.pro.annual` |
| Monthly (rank 2) | `com.abdulmanan.pawsitivesync.pro.monthly` |
| Price test (later) | `com.abdulmanan.pawsitivesync.pro.annual.3999` |
| Trial | Introductory offer, 7 days free, yearly only |

### Google Play Console
| Item | Identifier |
|------|------------|
| Subscription | `pawsitivesync_pro` |
| Base plans | `annual`, `monthly` |
| Trial offer (on annual) | `free-trial-7d` |

### RevenueCat
| Item | Identifier |
|------|------------|
| Entitlement | `pro` |
| Offering | `default` |
| Packages | `$rc_annual`, `$rc_monthly` |

---

## Sources
- PetPill — https://apps.apple.com/za/app/id6760020801
- Pet Care Reminder & Tracker — https://apps.apple.com/app/id6444908248
- PetMed: Medication Tracker — https://apps.apple.com/app/id6761286407
- DogLog — https://apps.apple.com/app/id1229529595
- 11pets — https://apps.apple.com/us/app/id1232470530
- PawLog — https://apps.apple.com/app/id6782466968
- PetDesk pricing — https://zoftwarehub.com/en-bh/products/petdesk/pricing
