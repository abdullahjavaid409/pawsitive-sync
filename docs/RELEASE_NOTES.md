# PawsitiveSync — Release notes (1.0.0)

## App Store — What’s New (paste into App Store Connect)

**Never wonder if someone already gave the dose.**

**Free — one pet, full safety**
• **Did I already give it?** — one-tap logging and double-dose checks  
• **Not sure if given** — mark uncertain so the next person checks first  
• **What's due today** — morning, afternoon, and evening in one list  
• **Reminders** — local notifications when a dose is due  
• **Works offline** — log without Wi‑Fi; sync when connected  

**Pro — when care is shared or you have multiple pets**
• **More than one pet on meds** — track up to 10 pets in one household  
• **Did my partner or sitter dose?** — invite with a code; everyone sees who logged what  
• **Vet asked for a log** — export week-by-week reports for checkups  
• **Almost ran out** — low-supply alerts before the bottle is empty  

Also: course length for short-term meds, coming-up vet visits, and sitter join links.

---

## Google Play — Short description (80 chars max)

Shared pet med schedules — log doses, sync with sitters, never double-dose.

## Google Play — Full description (excerpt)

PawsitiveSync helps households stay on the same page for pet medicines.

**Pain: “Did someone already give the dose?”**
Free: log doses, double-dose checks, and “not sure if given” for one pet.  
Pro: invite partner, family, or sitter — everyone sees the same list and who logged what.

**Pain: “What's due today?”**
Today shows morning, afternoon, and evening doses, progress for the day, and local reminders.

**Pain: “We have multiple pets on meds” (Pro)**
Track up to 10 pets in one household.

**Pain: “The vet wants a clear log” (Pro)**
Export week-by-week reports. Free still lets you view dose history in the app.

**Pain: “We almost ran out” (Pro)**
Low-supply alerts before the bottle is empty.

Free: one pet, full dose tracking, safety, reminders, offline logging.  
Pro: every pet, household invites, vet export, refill warnings.

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
