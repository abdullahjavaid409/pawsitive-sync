# PawsitiveSync — full QA workflow

Use this after a **Delete account** (Settings) or on a fresh install. Filter DevTools → Logging by `pawsitive`.

## Data model (local-first)

| Mode | Behavior |
|------|----------|
| **No API / not connected** | All pets, meds, doses, care events saved **on this phone** (`offline: true` in logs) |
| **Connected household** | Writes sync to server; pull-to-refresh fetches latest |
| **API calls** | Only on: Invite (connect), Join, dose/med writes when connected, manual refresh, billing resume — **not** on every app open |

Logs: `data.restored` on launch · `household.sync_skipped` when no unnecessary fetch

---

## 0. Fresh start

| Step | Action | Expected log |
|------|--------|--------------|
| 0.1 | Settings → **Delete account on this phone** → confirm | `settings.account_deleted`, `household.reset` |
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
| 1.7 | Complete setup | `onboarding.finished`, `household.created_from_onboarding` |

---

## 2. Today (daily care)

| Step | Action | Expected log |
|------|--------|--------------|
| 2.1 | Open app | `app.started` |
| 2.2 | Tap pet filter | `pet.filter` |
| 2.3 | Tap a due dose | `dose.tapped`, `dose.opened` |
| 2.4 | **Log dose** | `dose.log.completed` |
| 2.5 | **Not sure if given** | `dose.uncertain.completed` |
| 2.6 | **Skip dose** | `dose.skip.completed` |
| 2.7 | Tap given dose | `dose.already` |
| 2.8 | Household banner → retry | `household.sync_retry`, `household.synced` |
| 2.9 | Due + connected → **Check before you give** | `double_dose.check_household` |
| 2.10 | Add medicine shortcut | `medication.add_opened` |
| 2.11 | Care shortcuts (Pets / Household / Reports) | `today.shortcut.*` |
| 2.12 | Settings gear | `settings.opened` |

---

## 3. Add medicine

| Step | Action | Expected log |
|------|--------|--------------|
| 3.1 | Name + times + course length + save | `medication.add.completed`, `medication.saved` |
| 3.2 | Empty name save | `medication.add_rejected` reason=missing_name |
| 3.3 | No time selected | validation error (UI) |

---

## 4. Coming up (care events)

| Step | Action | Expected log |
|------|--------|--------------|
| 4.1 | Today → Coming up → **Add** | `care_event.sheet_opened` |
| 4.2 | Save vet/vaccine reminder | `care_event.saved`, `care_event.added` |
| 4.3 | Swipe to dismiss | `care_event.dismissed`, `care_event.removed` |

---

## 5. Pets tab

| Step | Action | Expected log |
|------|--------|--------------|
| 5.1 | Add pet (Free, already 1 pet) | `pet.add.blocked` → paywall |
| 5.2 | Add pet (Pro) | `pet.add.completed`, `pet.add.ui_success` |
| 5.3 | Edit pet → save | `pet.update.completed` |
| 5.4 | 3+ pets → vertical list | (UI only) |

---

## 6. Household

| Step | Action | Expected log |
|------|--------|--------------|
| 6.1 | Invite (Pro) | `invite.opened`, `invite.connect_ready` |
| 6.2 | Copy code / sitter link | `invite.copied`, `invite.link_copied` |
| 6.3 | Share | `invite.share_tapped` |
| 6.4 | Invite (Free) | `invite.blocked` |
| 6.5 | Join with code | `join.started`, `household.joined`, `join.completed` |
| 6.6 | Bad code | `household.join_rejected` or `join.ui_failed` |

---

## 7. Medication detail

| Step | Action | Expected log |
|------|--------|--------------|
| 7.1 | Open from Today | `nav.push` |
| 7.2 | **I refilled it** (Pro, low supply) | `medication.refill_tapped`, `medication.refill.completed` |
| 7.3 | **Stop medicine** | `medication.stop_tapped`, `medication.stop_confirmed`, `medication.remove.completed` |

---

## 8. Reports (Pro share)

| Step | Action | Expected log |
|------|--------|--------------|
| 8.1 | Change pet filter | `report.pet_filter` |
| 8.2 | Share (Pro) | `report.shared` |
| 8.3 | Share (Free) | `report.share.blocked` |

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

## 11. Final delete

Repeat **§0** — confirm empty Today, Welcome screen, no pets/meds in logs after `household.reset`.

---

## Automated coverage

```bash
flutter test                    # all tests
flutter test test/full_workflow_test.dart   # delete → full journey → delete
flutter test test/features_edge_cases_test.dart  # edge cases
```

`full_workflow_test.dart` asserts logs for: reset, onboarding, medication, doses (log/uncertain/skip), care events, Pro, pets, refill, remove.
