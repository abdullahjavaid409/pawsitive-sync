# PawsitiveSync — Asset & Motion Brief (paste into ChatGPT / image gen)

Use this entire document as the system prompt when generating **Lottie JSON**, **SVG stills**, or **illustrations** for the PawsitiveSync Flutter app. Every asset must match these colors, style, and file names exactly.

---

## 1. What the app is

**PawsitiveSync** is a calm, premium pet-medication app for households. One shared Today list so nobody double-doses. Tone: **trustworthy, warm, simple** — like Apple Health meets a vet clinic waiting room, **not** TikTok/Reels energy.

- Audience: pet owners, partners, sitters
- Platform: Flutter mobile (iOS + Android)
- Font: **Geist** (400 / 500 / 600)
- Motion: subtle, 200ms ease-out; celebrations play **once** then hold

---

## 2. Color palette — USE ONLY THESE

| Role | Hex | Use |
|------|-----|-----|
| **Brand green** | `#4A7C59` | Primary actions, checkmarks, pet accents |
| **Brand dark** | `#3D6A4B` | Selected chips, emphasis text on soft green |
| **Brand soft** | `#E9F1EB` | Preview cards, highlights, primary container |
| **Background** | `#FBFBFA` | App background, pill fills |
| **Ink** | `#2C3531` | Headlines, stroke outlines |
| **Body** | `#4F5A54` | Secondary text |
| **Muted** | `#6B726E` | Captions, hints |
| **Stroke** | `#C9CCC6` | Icon strokes, borders |
| **Hairline** | `#E4E5E1` | Card borders |
| **Neutral fill** | `#F2F2EF` | Segmented controls |
| **White** | `#FFFFFF` | Cards, surfaces |
| **Warning bg** | `#FBF0DF` | Low-supply banners |
| **Warning border** | `#EBCB97` | Low-supply borders |
| **Warning text** | `#7A4E0E` | Low-supply copy |
| **Amber accent** | `#E7A959` | Sun / afternoon only |
| **Error** | `#B42318` | Rare; sync failed only |

**Do NOT use:** purple, pink gradients, neon, black backgrounds, Material default blue, emoji-style 3D, photoreal pets.

---

## 3. Illustration style

- **Format:** flat vector, **rounded stroke** (2–2.25px), stroke color `#2C3531`
- **Fills:** brand green `#4A7C59`, soft green `#E9F1EB`, off-white `#FBFBFA` only
- **Canvas:** 160×160 or 240×240, centered, generous padding
- **Characters:** simple circles + minimal features (existing cats/dogs are geometric, not cute-cartoon)
- **Medicine:** bottle + clock/check — no pill photos
- **People:** abstract circles with initials feel, not detailed faces
- **Mood:** calm relief (“done”, “shared”, “on track”) — never frantic or comic

Reference existing SVGs in repo: `assets/art/*.svg`, `assets/marks/*.svg`

---

## 4. Lottie technical spec

| Property | Value |
|----------|-------|
| Size | 240×240 px artboard |
| Frame rate | 30 or 60 fps |
| Duration | 0.8–1.5 s for moments; 2–3 s max for welcome |
| Loop | **false** (play once, hold last frame) except `morning`/`afternoon`/`evening` icons (may loop subtly) |
| File name | `{moment.name}.json` — see catalog below |
| Still fallback | Matching `{moment.name}.svg` for Reduce Motion |
| Colors | Recolor all layers to palette above before export |
| Export | Lottie JSON (Bodymovin), optimized, no embedded bitmaps |

**Flutter usage:**
```dart
Lottie.asset('assets/lottie/welcome.json', width: 200, height: 200, repeat: false)
```

---

## 5. Moment catalog (existing — keep consistent)

| File name | Screen | What it should show |
|-----------|--------|---------------------|
| `welcome.json` | Welcome | Two people + pet + shared check — “household care” |
| `morning.json` | Today header | Soft sun rising, green tones |
| `afternoon.json` | Today header | Sun higher, slight amber `#E7A959` |
| `evening.json` | Today header | Moon + soft green, calm |
| `dose.logged.json` | Log sheet success | Green check + medicine bottle, brief scale pop |
| `dose.skipped.json` | Skip success | Gentle dash or “later” arc, not sad |
| `dose.already.json` | Double-dose warning | Two checkmarks or hand stop, amber hint |
| `dose.empty.json` | Empty Today | Empty calendar + paw, inviting not lonely |
| `medication.low.json` | Low supply | Bottle nearly empty + small alert |
| `medication.refilled.json` | Refill success | Full bottle + check |
| `reminders.on.json` | Notifications onboarding | Bell with soft pulse |
| `reminders.off.json` | Reminders declined | Bell with slash, muted gray |
| `household.synced.json` | Sync banner | Two dots connected + check |
| `household.sync_failed.json` | Sync error | Cloud with gentle X, not aggressive red |

---

## 6. Moments to CREATE (missing today)

Generate these next, same style + palette:

| File name | Screen | Brief |
|-----------|--------|-------|
| `pet.setup.json` | Pet basics onboarding | Single pet face (cat/dog neutral) + heart or paw |
| `medicine.add.json` | Add medicine | Bottle appearing on Today list preview |
| `pet.add.json` | Add pet | Plus + paw in soft green circle |
| `invite.share.json` | Invite | Two people + link/code dots |
| `join.code.json` | Join household | Keypad / 6 boxes filling in green |
| `report.empty.json` | Vet report empty | Clipboard + paw, “building report” |
| `report.ready.json` | Vet report filled | Clipboard with check + small chart bars |

Also replace static `StoryArt` on: conditions, pet details, vet report empty → use `MomentArt` names above.

---

## 7. Static art (`assets/art/`)

| File | Use |
|------|-----|
| `welcome.svg` | Fallback / marketing |
| `pet.svg` | Generic pet (two face silhouettes) |
| `medicine.svg` | Bottle + clock |
| `empty.svg` | Empty state |
| `people.svg` | Household |
| `together.svg` | Sync / family |
| `reminder.svg` | Notifications |
| `conditions.svg` | Health tags |
| `low.svg` | Running low |

**Species marks** (`assets/marks/`): `cat.svg`, `dog.svg`, `rabbit.svg`, `paw.svg` — 64–88px on screen.

---

## 8. Size on screen (Flutter)

| Context | dp size |
|---------|---------|
| Welcome hero | 208–256 |
| Onboarding step | 200–240 |
| Empty state | 180–220 |
| Sheet celebration | 140 |
| Part label (morning…) | 44–52 |
| Inline banner | 48–56 |
| Medicine detail low | 72 |

---

## 9. LottieFiles — how to pick & adapt

1. Search: [lottiefiles.com/free-animations/pet](https://lottiefiles.com/free-animations/pet) or “checkmark minimal”, “medicine bottle line”
2. Filter: **Free**, **Lottie Simple License**, flat/line style
3. **Recolor** in LottieFiles editor or After Effects to `#4A7C59` / `#2C3531` / `#FBFBFA` only
4. Remove background layers
5. Trim to ≤1.5s, disable loop
6. Export JSON → rename to catalog name → add matching SVG still

**Good keywords:** pet care, checklist, medicine, family, sync, bell, sun, moon, bottle, paw, line icon

**Avoid:** 3D dogs, rainbow, confetti explosions, loading spinners, brand logos

---

## 10. ChatGPT prompt template (copy below)

```
You are generating assets for PawsitiveSync, a calm pet medication app.

STYLE: Flat vector, 2.25px rounded strokes #2C3531, fills only #4A7C59 #3D6A4B #E9F1EB #FBFBFA #E7A959 (afternoon only). 240×240. No purple, neon, or 3D.

TASK: Create [MOMENT NAME] as Lottie JSON description + SVG still.

MOMENT: [e.g. dose.logged — green check appears over medicine bottle, 1.2s, ease-out, hold last frame]

Output:
1. Layer-by-layer Lottie composition notes (shapes, colors, keyframes)
2. SVG path description for still fallback
3. Suggested LottieFiles search terms if sourcing instead of drawing
```

---

## 11. File drop checklist

After generation, place files in repo:

```
assets/lottie/{name}.json
assets/lottie/{name}.svg
```

Register label in `lib/core/widgets/moment_art.dart` → `labels` map.

Run: `flutter test` + hot restart on device.

---

*PawsitiveSync v1.0 — household pet medication, Flutter + lottie 3.3.1*
