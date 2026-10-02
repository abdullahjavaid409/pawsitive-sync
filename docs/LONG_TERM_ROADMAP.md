# PawsitiveSync — long-term roadmap

Strategic plan for scaling PawsitiveSync from v1 launch through multi-year growth. Complements [QA_WORKFLOW.md](./QA_WORKFLOW.md) (shipping quality) and [RELEASE_NOTES.md](./RELEASE_NOTES.md) (store copy).

---

## North star

**Local-first pet care ledger + optional household sync.**

Own the **“did anyone give the dose?”** problem for multi-caregiver pet homes — not a social network, not a vet EMR.

**3-year vision:** PawsitiveSync becomes the default shared medicine log for households with pets — like a shared Notes app for doses, with proof of who gave what and when.

---

## Decision lens (use on every change)

Three pillars: **long-term · cost · user quality**

### Long-term

1. **Still works offline?** Core dose flow must not depend on network.
2. **Minimal API?** Prefer outbox/batch over per-action requests.
3. **Sync-ready?** New entities need stable IDs and a path to household sync.
4. **Recoverable?** Solo = one device OK; connected owners need Apple Sign-In (Phase 2).
5. **Migration path?** Shortcuts OK if debt + fix are named (e.g. SharedPreferences → Drift).

### Cost (yours + users’)

6. **Cheapest path?** Local-first beats server; one Postgres beats microservices; no polling/WebSockets for doses.
7. **Free tier sustainable?** Free users should not drive disproportionate server cost.
8. **Safe to paywall?** Never gate logging or double-dose checks; gate multi-pet, invite, export.

### User quality

9. **Core flow instant?** Local dose log = no spinner; one tap where possible.
10. **Safety & clarity?** Double-dose guard free; honest paywall; big targets; keyboard dismiss.
11. **Tested?** Dose, onboarding, household paths — no regressions on touched flows.

Cursor enforces this via `.cursor/rules/long-term-thinking.mdc` (always on). See also [AGENTS.md](../AGENTS.md).

---

## Current baseline (v1)

| Area | Today |
|------|--------|
| **Data** | Phone is source of truth; SharedPreferences + in-memory repo |
| **Auth** | Device Bearer token; invite code to join household |
| **Sync** | On connect, write-through when connected, pull on refresh/resume; 45s throttle |
| **Billing** | RevenueCat + App Store / Play |
| **Backend** | Railway Postgres + REST (`backend/`) |
| **Care events** | Local only (`CareEventsStore`) |
| **Logging** | `AppLog` client-side; key events in QA doc |

---

## Phase 1 — Launch (now → 6 months)

**Goal:** Reliable solo + small household use, minimal ops cost.

| Area | Choice |
|------|--------|
| **Data** | Phone = source of truth until user connects |
| **Auth** | Device token + invite code (keep) |
| **Sync** | Write-through when connected; pull on refresh/resume |
| **Billing** | RevenueCat + App Store / Play |
| **Backend** | Single Railway Postgres + REST |
| **Care events** | Local only (acceptable for v1) |

### Success metrics

- D7 retention
- Doses logged per active user per day
- Invite conversion (Free → Pro when adding 2nd pet or inviting)
- Support tickets per 1k users (target: low — recovery is main risk)

### Near-term product gaps (pre–Phase 2)

1. Wire **What’s New** screen (`ReleaseFeatures` → one-time per version on Today)
2. Live **privacy policy + terms** on `pawsitivesync.app`
3. Manual QA on device using [QA_WORKFLOW.md](./QA_WORKFLOW.md)

---

## Phase 2 — Growth (6–18 months)

**Goal:** Retention, account recovery, less support pain, fewer API calls.

### 1. Sign in with Apple (household owner)

Link `apple_user_id` → `household_id` so owners can restore on a new phone without re-entering invite.

```
Solo user         → no login, local only
Household member  → invite code + device token
Owner recovery    → Sign in with Apple (Phase 2)
Payment           → RevenueCat (store identity)
```

- Device token remains the API credential — Apple ID is for **recovery**, not every request.
- Add Google on Android only; on iOS always offer Apple if Google is added (App Store requirement).

**Do not:** custom email/password, or require login before first dose.

### 2. Sync outbox (batch, fewer calls)

```
Local change → outbox queue → sync every N min OR on Wi‑Fi / foreground
```

- Batch writes instead of one API call per tap
- Better on spotty networks and for sitters
- Extend existing conflict handling (409 on double dose) for queue replay

### 3. Backend care events

Sync vet visits, vaccines, refills to household so **Coming up** is shared across caregivers.

### 4. Push notifications (server-triggered)

When a partner logs a dose, optionally notify others — requires FCM/APNs + backend events (not polling).

Local dose reminders stay on-device; push is for **household activity**.

### 5. Analytics (privacy-light)

Mirror key funnel events server-side in aggregate: onboarding → first dose → invite → Pro. Client already logs via `AppLog`; pick PostHog, Firebase, or similar with minimal PII.

---

## Phase 3 — Scale (18 months+)

**Goal:** 10k+ households, stronger offline reliability, revenue expansion.

### Target architecture

```
Mobile (local DB: Drift / SQLite)
    ↕ sync engine (outbox + conflict rules)
API (Node on Railway, or Workers at higher scale)
    ↕
Postgres (households, pets, meds, logs, care_events)
Redis (rate limits, session cache) — when needed
Object storage (future: vet PDF exports, pet photos)
```

### Technical decisions

| Decision | Long-scale pick |
|----------|-----------------|
| **Local DB** | Migrate SharedPreferences → **Drift/SQLite** for queries, migrations, offline reliability |
| **API** | REST is fine until ~50k DAU; revisit if mobile + web teams split |
| **Conflicts** | Last-write-wins for dose logs with server timestamp; surface “Sara logged at 8:02” in UI |
| **Multi-region** | Defer until international; US/EU first with GDPR export/delete |
| **Realtime** | **Avoid** full WebSocket sync — dose logging does not need it |

### Product expansion (priority order)

1. **Home screen widget + watch** — next dose at a glance
2. **Vet PDF export** — Pro; add email-to-clinic
3. **Refill reminders** — pharmacy integration (hard; year 3+)
4. **Clinic portal** — read-only link for vet (B2B, separate SKU)

### Monetization

| Tier | Price (indicative) | Unlock |
|------|-------------------|--------|
| **Free** | $0 | 1 pet, local logging, join household |
| **Pro** | $30–40/yr | Up to 10 pets, invite, reports, low-supply alerts |
| **Family** (later) | ~$50/yr | Unlimited caregivers, priority sync |
| **Lifetime** (optional) | ~$79 once | Launch promo only; cap ~10% of users |

**Principle:** Never paywall basic dose logging or double-dose safety. Paywall multi-pet, household, and export — aligned with Reddit/Mobbin research.

### RevenueCat at scale

- Server-side Pro status via **webhooks** (not client-only)
- Customer Center for self-serve billing (already integrated in app direction)

---

## Auth model (long-term)

```
┌─────────────────────────────────────────┐
│  Solo user        → no login, local only │
│  Household member → invite code + token  │
│  Owner recovery   → Sign in with Apple     │
│  Payment          → RevenueCat (store)     │
└─────────────────────────────────────────┘
```

Covers ~95% of pet-app use cases without friction on day one.

---

## Ops & compliance (before 10k users)

| Item | Action |
|------|--------|
| **Privacy / terms** | Live on marketing site |
| **Account delete** | Client delete exists; add server-side household leave for connected members |
| **GDPR / CCPA** | JSON export of pet + dose history (Pro goodwill feature) |
| **HIPAA** | Not required for consumer wellness tracker; avoid clinical claims in copy |
| **Uptime** | Railway today; add read replica or move provider if DB becomes bottleneck |
| **Rate limits** | Already in `backend/server.js`; tune with traffic |

---

## Infrastructure & cost (rough)

| Active households | Infra / mo | Engineering focus |
|-------------------|------------|---------------------|
| 0–1k | $20–50 | Product, ASO, community (Reddit, pet groups) |
| 1k–10k | $100–300 | Apple recovery, outbox sync, support playbooks |
| 10k–100k | $500–2k | Drift migration, push, dedicated backend capacity |

API today: `https://pawsitive-api-production.up.railway.app`

---

## What not to do

- Full realtime WebSocket sync for every field
- Google/Apple login **before** product–market fit
- Paywalling dose logging or “check before you give” safety
- Building for vet clinics before nailing households
- Storing medication data on server without encryption at rest
- Custom username/password auth

---

## Recommended build order (after v1 ship)

| Priority | Item | Why |
|----------|------|-----|
| P0 | What’s New + legal pages | Store trust, release communication |
| P1 | Sign in with Apple (owner) | #1 support issue: new phone / lost data |
| P2 | Sync outbox | Fewer API calls, better offline |
| P3 | Care events on backend | Shared “Coming up” for households |
| P4 | Drift local DB | When log volume or query needs grow |
| P5 | Push for household activity | Engagement without polling |

---

## Related docs

- [QA_WORKFLOW.md](./QA_WORKFLOW.md) — manual test steps and expected logs
- [RELEASE_NOTES.md](./RELEASE_NOTES.md) — App Store / Play copy
- [main-screens-design.md](./main-screens-design.md) — UI structure

---

*Last updated: October 2026 — revise after each major release or phase gate.*
