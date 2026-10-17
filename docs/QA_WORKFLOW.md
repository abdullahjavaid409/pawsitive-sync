# PawsitiveSync — full QA workflow

Use this after a **Delete account** (Settings) or on a fresh install. Filter DevTools → Logging by `pawsitive`.

## Data model (local-first)

| Mode | Behavior |
|------|----------|
| **No API / not connected** | All pets, meds, doses, care events saved **on this phone** (`offline: true` in logs) |
| **Connected household** | Writes sync to server; pull-to-refresh fetches latest |
| **API calls** | Only on: Invite (connect), Join, dose/med writes when connected, manual refresh, billing resume — **not** on every app open |

Logs: `store.opened ms=…` + `data.restored` on launch (last 14 days), then `data.history_loaded logs=… ms=…` (rest of the 100 days) right after the first frame (first launch after the SQLite update also `store.migrated pets=… logs=… ms=…`, or `store.migrate_failed` — the app then keeps using the old data and retries next launch; if the database can't open on a later launch: `store.open_retry`, `store.open_failed`, changes saved aside and merged back next launch as `store.recovered`) · `household.sync_skipped` when no unnecessary fetch · a failed save logs `store.write_failed table=…`

One line per action: the repository logs the outcome (`*.completed` / `*.rejected` / `*.failed`); screens don't add a second "saved" line. Opening a screen, sheet or dialog is one `nav.push to=…` (sheets and dialogs are named: `log_dose`, `add_care_event`, `stop_medicine`, `delete_account`, `sitter_label`).

---

## 0. Fresh start

| Step | Action | Expected log |
|------|--------|--------------|
| 0.1 | Settings → **Delete account on this phone** → confirm | `household.reset`, `account.deleted` |
| 0.2 | Land on **Welcome** | `welcome` |
| 0.3 | Automated test | `test/full_workflow_test.dart` (63+ tests) |

---

## 1. Onboarding

| Step | Action | Expected log |
|------|--------|--------------|
| 1.1 | Get started → enter pet name → Continue | `onboarding.step` step=pet_basics |
| 1.2 | Age/weight → Continue | `onboarding.step` step=pet_details |
| 1.3 | Pick conditions → Continue | `onboarding.step` step=conditions |
| 1.3a | First medicine: Continue with fields missing | `onboarding.medicine_blocked` missing=name,amount,… — red message under each field, “Still needed: …” under the button, scrolls to the first |
| 1.3b | Tap − / + on an amount or supply | `stepper.step` field= dir= value=; at a limit `stepper.limit`; hold → one `stepper.held` steps= |
| 1.4 | Pick caregivers → Continue | `onboarding.step` step=caregivers |
| 1.5 | Reminders on/off | `onboarding.step`, `reminders.on` or `reminders.off` |
| 1.6 | Finish paywall / continue free | `billing.continued_free` or purchase logs |
| 1.7 | Complete setup | `household.created_from_onboarding` (with `reminders=`) |

---

## 2. Today (daily care)

| Step | Action | Expected log |
|------|--------|--------------|
| 2.1 | Open app | `app.started` |
| 2.2 | Tap pet filter | `pet.filter` |
| 2.3 | Tap a due dose | `nav.push to=log_dose` |
| 2.4 | **Log dose** | `dose.log.completed` |
| 2.5 | **Not sure if given** | `dose.uncertain.completed` |
| 2.6 | **Skip dose** | `dose.skip.completed` |
| 2.7 | Tap given dose | `dose.already` |
| 2.8 | Household banner → retry | `household.synced source=retry` |
| 2.9 | Due + connected → **Check before you give** | `nav.tab to=household` |
| 2.10 | Add medicine shortcut | `nav.push to=/schedule` |
| 2.11 | Care shortcuts (Pets / Household / Reports) — only before the first medicine; after that the tab bar covers them | `today.shortcut.*` |
| 2.14 | Open a due dose within half its interval of the last given one (half the shortest gap between its scheduled times: 12 h once a day, 6 h at 8:00/20:00, 2.5 h at 8:00/13:00/20:00, 1 h for custom 8:00/10:00 — e.g. 11:51 PM then 12:05 AM) | amber note "Sara gave … 14 min ago (yesterday at 11:51 PM)…", still loggable; `dose.recent_warning minutesAgo=…` · a log whose time can't be read is skipped: `dose.recent_unreadable` |
| 2.15 | Log a dose (household not shared) → tap **Undo** on the "Dose logged" toast within ~4 s | dose back to due, supply restored; `dose.undo.completed offline=true` · shared household: no Undo shown (`dose.undo.rejected reason=shared` if forced) |
| 2.13 | A save that throws (bug, not a network/conflict failure) | sheet shows the error, buttons work again, `dose.save_crashed` (error) |
| 2.12 | Settings gear | `nav.push to=/settings` |
| 2.16 | Today shortcut tiles (My pet · Household · Vet report) | one-line name, a caption saying what's there, chevron; VoiceOver reads "Household. Who gives doses"; `today.shortcut.pets` / `.household` / `.reports` |
| 2.17 | Free, with a medicine: Pro card under the shortcuts | photo, "One log for everyone who gives the pills", four gains, why it's a subscription, **See Pro plans**; `billing.today_pro_card.shown` (not shown before the first medicine, never on Pro) |
| 2.18 | **See Pro plans** → close the paywall → **×** on the card | `billing.paywall.opened from=today_pro_card`, then `billing.today_pro_card.dismissed`; the card stays hidden after a restart |
| 2.19 | This week · Up next cards | seven days with today ringed; tomorrow's first dose once today's are done; each card hides when it has nothing true to say |
| 2.20 | Free, idle on Today (nothing due, nothing open) | first 7 days after install: no upgrade page opens by itself · after that, at most once a week: `billing.prompt.shown trigger=weekly`, `billing.paywall.opened reason=weekly from=idle_prompt` |
| 2.21 | A due dose more than 30 min past its time (Today card, Pets next-dose card, Pets dose rows) | "Late · 8:00 AM" instead of "Due now"; "Due now" within the first 30 min; "Later today" before the time |
| 2.22 | Household with nobody else joined (Free or Pro) | "How sharing works" card (invite → they join → who gave what); Free plan card says Pro lets partners and sitters log on their own phones |
| 2.23 | Reports, Free | "Share report with vet · PRO" and "Pro makes a PDF of the last 90 days…"; tap → `billing.paywall.opened reason=vet_export from=report_share` |
| 2.24 | Debug build: Settings → "Debug: switch to Pro" | `debug.pro_toggled pro=true`; Today Pro card gone, Invite has no PRO badge, Add medicine opens without a paywall, afternoon/evening unlocked, Reports share has no lock. Switch back → Free again. Never sent to RevenueCat |
| 2.25 | Pets, every dose given | "All given today · Next dose tomorrow · 8:00 AM" (v14); a course that just ended says "Every dose for Miso is logged." |

---

## 3. Add medicine

| Step | Action | Expected log |
|------|--------|--------------|
| 3.1 | Name + times + course length + save | `medication.add.completed` |
| 3.2 | Empty name save | field error + `medication.form_invalid fields=true missingParts=false` (the form stops it before the repository; `medication.add_rejected reason=missing_name` only if a save bypasses the form) |
| 3.3 | No time selected | validation error (UI) + `medication.form_invalid missingParts=true` |
| 3.4 | Type a name the phone knows (e.g. "Brave") — Add medicine or setup | matches instantly, no spinner, no network; one `medicine.search.local results=… length=…` after typing pauses |
| 3.5 | Type a name the phone doesn't know (e.g. "Pregab") | "Searching more medicines…" row, then matches; `api.ok path=/v1/medicines/search`, `medicine.search.online results=… ms=…`, `medicine.search.learned added=…` |
| 3.6 | Same search again (any pet, even after a restart) | answered on the phone: `medicine.search.local`, no API call |
| 3.7 | Unknown name while offline | no matches, "Use “…”" still works; `api.failed`, `medicine.search.online_failed` — nothing saved, next search retries |
| 3.8 | Server side | `medicine.search source=groq` on the first ask of a query, `source=cache` for everyone after (one Groq call per query, ever); typed text is never logged |

---

## 4. Coming up (care events)

| Step | Action | Expected log |
|------|--------|--------------|
| 4.1 | Today → Coming up → **Add** | `nav.push to=add_care_event` |
| 4.2 | Save vet/vaccine reminder | `care_event.added` |
| 4.3 | Swipe to dismiss | `care_event.removed` |

---

## 5. Pets tab

| Step | Action | Expected log |
|------|--------|--------------|
| 5.1 | Add pet (Free, already 1 pet) | `billing.paywall.opened from=add_pet_…` |
| 5.2 | Add pet (Pro) | `pet.add.completed` |
| 5.3 | Edit pet → save | `pet.update.completed` |
| 5.4 | 3+ pets → vertical list | (UI only) |

---

## 6. Household

| Step | Action | Expected log |
|------|--------|--------------|
| 6.1 | Invite (Pro) | `nav.push to=/invite`, `household.connected` |
| 6.2 | Copy browser sitter link | `invite.web_link_copied`, `sitter.link_ready` |
| 6.2b | Copy app invite link | `invite.copied`, `invite.link_copied` |
| 6.2c | Open browser link on phone (no app) | Server: `dose.logged` source=sitter |
| 6.2d | Partner logs dose → your phone | `push.partner_detected`, `push.partner_logged` |
| 6.3 | Share | `invite.share_tapped` |
| 6.4 | Invite (Free) | `billing.paywall.opened reason=invite from=invite` |
| 6.5 | Join with code | `household.joined` |
| 6.6 | Bad code | `household.join_rejected` or `household.join_failed` |

---

## 7. Medication detail

| Step | Action | Expected log |
|------|--------|--------------|
| 7.1 | Open from Today | `nav.push` |
| 7.2 | **I refilled it** (Pro, low supply) | `medication.refill.completed` |
| 7.3 | **Stop medicine** | `nav.push to=stop_medicine`, `medication.remove.completed` |

---

## 8. Reports (Pro share)

| Step | Action | Expected log |
|------|--------|--------------|
| 8.1 | Change pet filter | `report.pet_filter` |
| 8.2 | Share (Pro) | `report.shared` |
| 8.3 | Share (Free) | `billing.paywall.opened from=report_share` |

---

## 9. Pro / billing

| Step | Action | Expected log |
|------|--------|--------------|
| 9.1 | Select plan on paywall | `billing.plan.completed source=user` (opening the paywall may log `source=paywall_default`) |
| 9.2 | Start trial / purchase | `billing.purchase.*` or `billing.trial.*` |
| 9.3 | Restore (Settings) | `billing.restore.settings`, `billing.restore.completed` |
| 9.4 | App resume | `app.resumed`, `billing.sync.*` |

---

## 10. UX polish

| Step | Action | Expected |
|------|--------|----------|
| 10.1 | Tap outside text field | Keyboard dismisses (`DismissKeyboard`) |
| 10.2 | Morning/afternoon/evening icons | Larger on Today (44px) and schedule (32px) |
| 10.3 | Pull to refresh Today | `household.synced` |

---

## 10b. Reminders & engagement (local only — no API calls)

Use the iOS simulator with real, hand-entered data; local backend only.

| Do | Expect | Log |
|----|--------|-----|
| Turn reminders on, add a med (AM + PM) | Notifications pending for every dose of the next days (≤ 52 + engagement) | `reminders.scheduled trigger=data doses=… followUps=…` |
| Wait for a reminder (set the clock just before 8:00) | "Miso's Insulin · 8:00 AM" with **Given** / **Snooze 15 min** | — |
| Tap **Given** | App opens on Today, dose logged, snackbar "Logged …"; other phones' reminders clear (silent push) | `reminders.given`, `dose.log.completed` |
| Tap **Given** on a dose Sam already logged | No second log; notification "Already given — Sam gave … at 8:02 AM" | `reminders.given_rejected reason=already_logged` |
| Tap **Snooze 15 min** (app killed) | One reminder 15 min later; no 30-min follow-up on top | `reminders.snoozed` |
| Ignore a reminder | One "Still due: …" 30 min later, never more | — |
| Tap a reminder | Today opens that dose's log sheet (cold start too) | `reminders.opened action=tap coldStart=…` |
| Change the time zone in Settings, reopen | Doses re-aimed to 8:00 / 1:00 / 8:00 local (or each dose's custom time) | `reminders.timezone_changed`, `trigger=timezone_changed` |
| Add medicine → tap **Morning reminder** → pick 7:00 | Tile, Today, lock screen, widget and notification say 7:00 AM (07:00 on a 24-hour phone) | `medication.time_picked`, `medication.add.completed customTimes=1` |
| Medicine screen → **Evening reminder** → pick 7:00 PM | Snackbar "Evening reminder set to 7:00 PM."; partner's phone shows it after sync | `medication.times.completed`, `reminders.scheduled trigger=data` |
| Two+ medicines at the same minute | One notification "3 doses due · 8:00 AM", body per pet; **Open** / **Snooze 15 min**; log one → it lists the rest | `reminders.scheduled grouped=…` |
| Set the phone clock forward/back with the app open | Re-planned; no past or duplicate reminders | `reminders.clock_changed`, `trigger=clock_changed` |
| Don't open the app for 6+ days | Background refresh extends reminders; if it never runs, a quiet "Open Pawsitive to keep Miso's reminders going" at the last dose | `reminders.background_run`, `reminders.scheduled upkeep=true` |
| Deny notifications in phone Settings, reopen | No scheduling; honest note on Today (Not now hides 14 days) and in Settings | `reminders.schedule_skipped reason=permission_denied` |
| Settings → each engagement switch | Takes effect at once; summary/refill respect quiet hours | `settings.engagement_changed` |
| Partner logs a dose (connected) | Today: "Sam gave Miso's Insulin — thanks, Sam" (dismissible) | `engagement.thanks_dismissed` on ✕ |
| Reopen within 15 min (connected, nothing queued) | No network call | `household.sync_skipped reason=fresh` |

## 11. Final delete

Repeat **§0** — confirm empty Today, Welcome screen, no pets/meds in logs after `household.reset`.

---

## Automated coverage

```bash
flutter test                                      # all tests (131+)
flutter test test/live_features_coverage_test.dart  # every live feature + log
flutter test test/all_features_logs_test.dart     # per-feature log assertions
flutter test test/full_workflow_test.dart         # delete → full journey → delete

# Live app on the simulator against the local backend (never production).
# Pro comes only from RevenueCat; the test fakes its entitlement callback.
flutter test integration_test/app_test.dart -d <sim> \
  --dart-define=API_BASE_URL=http://127.0.0.1:3100

# Real RevenueCat on a device (sandbox), server off:
flutter run --dart-define-from-file=config/dev.json

# Agent-driven manual QA: the real app plus the Flutter Driver extension, so
# taps/typing can be sent through the Dart MCP server (flutter_driver_command).
# Send driver commands one at a time; native iOS alerts (notification
# permission) can't be tapped without the Simulator GUI.
flutter run -t integration_test/support/driver_main.dart -d <sim> \
  --dart-define-from-file=config/dev.json
node scripts/smoke_backend.mjs                    # backend API (needs v4 deploy)
```

`full_workflow_test.dart` asserts logs for: reset, onboarding, medication, doses (log/uncertain/skip), care events, Pro, pets, refill, remove.
