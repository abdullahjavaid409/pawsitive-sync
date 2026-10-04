# Agent guidelines — PawsitiveSync

Every change must pass **three checks**:

1. **Long-term** — still works at 10k+ households?
2. **Cost** — cheapest path that doesn’t hurt users?
3. **User quality** — fast, safe, clear; no dark patterns?

Roadmap: [docs/LONG_TERM_ROADMAP.md](docs/LONG_TERM_ROADMAP.md)

## North star

Local-first pet care ledger + optional household sync. Own **“did anyone give the dose?”** — not social, not vet EMR.

## Non-negotiables

- **Offline-first** — dose logging works with no network; log `offline: true` when applicable
- **Minimal API** — batch/outbox over per-tap calls; sync only when connected or user refreshes
- **Low infra cost** — no polling, no extra services until traffic requires them
- **No login wall** — first dose before any sign-in; Apple Sign-In is Phase 2 for owner recovery only
- **Safety is free** — never paywall dose logging or double-dose checks
- **Best UX on core paths** — one-tap dose log, clear errors, dismiss keyboard, honest paywall
- **Pro gates** — multi-pet (2+), 3+ active medicines per pet, history older than 30 days, household invite, vet export, low-supply alerts, weekly summary

## Before you ship

1. Offline path + `AppLog` event?
2. API cost same or lower (batched/throttled)?
3. New data has stable IDs and a sync story?
4. User-facing flow tested — no regression on dose/onboarding/household?
5. Shortcut? Name debt + fix + any cost/UX tradeoff.

## Key docs

| Doc | Purpose |
|-----|---------|
| [CONFIG.md](docs/CONFIG.md) | Human setup — no Apple Sign-In or keys required to run |
| [LONG_TERM_ROADMAP.md](docs/LONG_TERM_ROADMAP.md) | Scale, phases, architecture |
| [QA_WORKFLOW.md](docs/QA_WORKFLOW.md) | Manual QA + expected logs |
| [RELEASE_NOTES.md](docs/RELEASE_NOTES.md) | Store copy |

Config lives in `lib/core/config/app_config.dart` — one place for `--dart-define` values.
