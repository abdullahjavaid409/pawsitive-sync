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
| 2.11 | Care shortcuts (Pets / Household / Reports) | `today.shortcut.*` |
| 2.12 | Settings gear | `nav.push to=/settings` |

---

## 3. Add medicine

| Step | Action | Expected log |
|------|--------|--------------|
| 3.1 | Name + times + course length + save | `medication.add.completed` |
| 3.2 | Empty name save | `medication.add_rejected` reason=missing_name |
| 3.3 | No time selected | validation error (UI) |

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
| 9.1 | Select plan on paywall | `billing.plan.changed` |
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
