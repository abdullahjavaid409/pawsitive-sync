# PawsitiveSync — Release notes (1.0.0)

## App Store — What’s New (paste into App Store Connect)

**Never wonder if someone already gave the dose.**

• **Check before you give** — see when doses are due and confirm with your household before logging  
• **“Not sure if given”** — mark a dose as uncertain so sitters and partners double-check first  
• **Shared household** — invite family or a sitter; everyone sees the same schedule and who logged what  
• **Sitter link** — share a join link with the invite code filled in  

**Smarter medicine schedules**

• **Course length** — set 7, 14, or 30 days for short-term meds; ongoing for daily medicines  
• **Coming up** — vet visits, vaccines, and refills on your Today list  
• **Low-supply alerts** (Pro) — know before the bottle runs out  

**Pro unlocks the whole household**

• Up to 10 pets  
• Invite caregivers  
• Vet report export  
• Running-low alerts  

Free includes one pet and full dose tracking for that pet.

---

## Google Play — Short description (80 chars max)

Shared pet med schedules — log doses, sync with sitters, never double-dose.

## Google Play — Full description (excerpt)

PawsitiveSync helps households stay on the same page for pet medicines.

**Built for real caregiver pain**
- Log each dose with one tap  
- See who already gave it — avoid double dosing  
- Mark “not sure if given” when someone may have already done it  
- Invite a partner, family member, or sitter with a code or link  

**Daily care on Today**
- Progress for the day at a glance  
- Schedule grouped by morning, afternoon, and evening  
- Reminders when a dose is due  
- Upcoming vet visits, vaccines, and refills  

**Every pet, one place (Pro)**
- Track up to 10 pets  
- Export vet reports for checkups  
- Low-supply warnings before you run out  

Free: one pet, full dose tracking. Pro: multi-pet households and sharing.

---

## Internal changelog

### Care & safety
- Double-dose alert banner on Today when household is connected  
- Uncertain dose outcome (`LogOutcome.uncertain`) with household activity feed  
- Lock screen dose logging, snooze, and double-dose guard  
- Dose sheet: Log / Not sure if given / Skip  

### Household
- Invite code + share message  
- Sitter web link (`/join?code=`) with copy button  
- Join flow with clipboard paste  
- Pull-to-refresh and sync status on Today  
- Household activity: who gave, skipped, or is unsure  

### Medications
- Add medicine form with validation and optional supply tracking  
- Course length chips (7 / 14 / 30 / Ongoing) → `endDay` on medication  
- Medication detail: 7-day history, refill, stop medicine  
- Doses respect medication end date  

### Care events
- Local care reminders: vaccine, vet visit, refill, other  
- “Coming up” card on Today  
- Add care reminder bottom sheet  
- Swipe to dismiss upcoming items  

### Pets
- Pets tab with profile, metrics, conditions, medicine list  
- Vertical pet picker when 3+ pets  
- Add / edit pet with species, age, weight, conditions  

### Pro & billing
- Free: 1 pet; Pro: up to 10 pets  
- Gates: add pet, invite, low supply, vet report share  
- RevenueCat purchase, restore, resume sync  
- Paywall with optimistic plan selection  

### Reports
- Vet report by pet and date range  
- Share export (Pro)  
- Show caregiver name on each line  

### Observability
- Structured `AppLog` events for doses, meds, pets, billing, nav, onboarding  

### Backend
- `end_day` on medications  
- `uncertain` dose log outcome  

---

## Review notes for Apple / Google (optional)

- Subscriptions: Pro via RevenueCat; restore purchases in Settings and Paywall  
- Account deletion: Settings → Delete account on this phone  
- Privacy: https://pawsitivesync.app/privacy  
- Terms: https://pawsitivesync.app/terms  
- No medical advice; medication tracking tool for pet caregivers  
