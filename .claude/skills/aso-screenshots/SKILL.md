---
name: aso-screenshots
description: End-to-end App Store / Google Play screenshot pipeline for a mobile app — run the app in the iOS simulator with realistic hand-entered data, capture every key screen, write and run an ASO master prompt in Claude and ChatGPT (via Claude in Chrome), then render premium store-ready frames for the default page plus 2–3 custom product pages (CPPs) and an A/B test plan. Use when the user asks for App Store screenshots, ASO screenshots, custom product pages, PPO / A/B tests on the store listing, a "master prompt" for screenshots, or says "do the same screenshot process as PawsitiveSync" for a new app.
---

# ASO screenshot pipeline

Reference implementation: PawsitiveSync (`~/Desktop/pawsitive`). Its files are
the worked example of every step below: `integration_test/store_screenshots_test.dart`,
`scripts/store_screenshots.sh`, `scripts/compose_store_screenshots.py`,
`marketing/screenshots/pages.json`, `docs/ASO_SCREENSHOT_MASTER_PROMPT.md`.

## 0. Read the app first
- `AGENTS.md` / `CLAUDE.md`, brand colors and font (theme file, `assets/fonts`),
  ASO keyword doc, competitor/pricing doc. Every headline must be true to the UI.
- Never point captures at production. Run the local/QA backend.

## 1. Capture real screens (simulator, realistic data)
- Attach the iOS simulator panel first (`mcp__Claude_Code_iOS_Simulator__control attach`),
  prefer the largest iPhone (6.9", 1320×2868).
- Copy `templates/store_screenshots_test.dart.example` to
  `integration_test/store_screenshots_test.dart` and adapt it to the app: onboard
  by **typing like a real user** (no "load demo data" button), add 2 pets/items,
  a partner who logs something via the API so shared state shows real names
  and morning times (e.g. "Sara · 8:02 AM"), then `shot('name')` on each key
  screen. Use `toTop()` / `alignTop()` so screens aren't captured mid-scroll.
- Copy `scripts/store_screenshots.sh` into the project and run it. It sets
  Apple's marketing status bar (9:41, full battery), runs the test and saves
  `marketing/screenshots/raw/<name>.png` whenever the test prints `[shot] name`.
  Override with `TEST=...` and `DART_DEFINES=...`.
- If `flutter test` hangs on the launch screen, kill stale flutter processes
  and rerun once — the first attach can miss the VM service.
- Review a contact sheet of the raw shots. Exclude anything that leaks test
  data (localhost URLs, debug banners). Fix real UI bugs you spot (double drag
  handles, duplicated names) — they would ship in the hero frame.

## 2. Master prompt
- Fill `templates/master_prompt.md` with the app's facts, market data, rules
  and tasks. Save it in the project as `docs/ASO_SCREENSHOT_MASTER_PROMPT.md`.

## 3. Run it in Claude and ChatGPT (Claude in Chrome)
- Use the user's own Chrome profile ("Abdullah Javaid") and verify by account
  (Product Hunt `/my/profile` → `@abdullah_javaid3`) before acting. If the only
  connected browser is another profile, stop and ask; `switch_browser` /
  `select_browser` once they open the right one. Accounts signed in inside that
  verified profile are trusted.
- claude.ai/new and chatgpt.com (Chat mode): upload ≤10 images through the file
  input (`file_upload`, never click the picker), paste the prompt with a
  synthetic ClipboardEvent on the contenteditable, then click Send.
- If the model asks setup questions, pick live web search + in-chat markdown.
- Poll with `wait` batches; read the answer with `get_page_text`.

## 4. Render the frames
- Put the winning copy in `marketing/screenshots/pages.json` (see
  `templates/pages.example.json`): one entry per page (`default`, `cpp-*`),
  each frame = shot, theme, headline (≤5 words), subline, optional `pop`
  (crop box in raw px lifted out of the phone as a larger card — makes the
  proof legible at search-thumbnail size). Override `font_dir`,
  `font_prefix`, `themes` for the brand.
- `python3 scripts/compose_store_screenshots.py` → `marketing/screenshots/out/<page>/{6.9,6.7}/NN.png`
  plus `preview.png`. Check every preview: no orphan words, phones aligned.

## 5. Copy rules (Apple)
- Real UI only. No fake ratings, "#1", "Best", unearned awards, other brands.
- No medical/absolute safety claims ("prevents", "never double-dose") —
  say "know for sure", "get warned".
- Frame 1 = hook that works as a standalone ad; 2 = provable proof; 3 = the
  claim no competitor can make. First 3 frames carry most conversion.

## 6. Test plan
- Default page = PPO control; CPPs per intent with their own keywords + an
  Apple Ads ad group each. At low traffic (~1.5k views/week) run ONE PPO
  treatment at a time; validate bold ideas on CPPs with paid traffic first.
- Never promise ROI numbers; state what would have to be true.

## 7. iPad (required if TARGETED_DEVICE_FAMILY includes 2)
- Boot the 13" iPad simulator. In Settings → Multitasking & Gestures pick
  **Full-Screen Apps**: "Windowed Apps" captures a small window with black
  around it, which looks like a layout bug but isn't.
- The panel screenshot can be stale on iPad; verify with
  `xcrun simctl io <udid> screenshot`.
- Wide windows swap the bottom bar for a NavigationRail, so the test taps
  tabs through a `tab(label)` helper that checks for a rail first.
- Responsiveness check: full-screen routes must paint their side gutters
  (a centered max-width column with nothing behind it shows black), sheets
  stay a centered dialog width, and nothing overflows (grep the log for
  "overflow"/"RenderFlex").
- Capture into `marketing/screenshots/raw-ipad`; iPad screenshots need a
  longer pause than iPhone (2064×2752 PNGs are slower).
- Composer: add `ipad_box` (iPad pixel coords) to each `pop` so the iPad set
  gets readable cards too → `out/<page>/ipad-13/NN.png` (2064×2752).
