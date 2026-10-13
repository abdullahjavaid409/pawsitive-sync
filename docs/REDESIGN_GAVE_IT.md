# Gave It — identity redesign (4.3 resubmission)

Source: Claude (claude.ai) brief, 2026-10-13. Replaces the paw icon,
sage-green palette and Geist look that Apple read as a lookalike.

## Idea

"The Ledger": the shared logbook on the fridge, made digital. One line per
dose, a check, a name, a time. Ink blue + ruled paper, not soft green.

## Icon

Full-bleed ink blue #2638C4; cream #F5F1E8 check landing on a cream ledger
rule; fainter second rule below; amber #F2B04C dot (the timestamp) at the end
of the top rule. Optional purpose hint: make the lower rule a dose mark
(dropper or syringe scale), never a paw.

Follows Apple's HIG "App icons" (Liquid Glass revision, June 2026):
layered, square and unmasked, no baked highlights or glows (the system adds
them), default/dark/clear/tinted variants, sRGB or Display P3.

Built the Flutter way (docs.flutter.dev/deployment/ios and /android): PNGs
in `Runner/Assets.xcassets` with light, dark and tinted variants, and
`flutter_launcher_icons` for the Android adaptive icon. No SVG.

| File | Role |
|---|---|
| `marketing/icon/source-chatgpt.png` | ChatGPT render (1254px), the master art. Style refs from Mobbin: Outlook, Wabi |
| `marketing/icon/gave-it-icon-1024.png` | 1024px opaque RGB: App Store icon, iOS default, Android legacy |
| `marketing/icon/gave-it-foreground.png` | Symbol on transparency: iOS dark, iOS tinted (desaturated), Android adaptive foreground |
| `marketing/icon/gave-it-monochrome.png` | White silhouette: Android 13+ themed icon |

Regenerate with `dart run flutter_launcher_icons` (config in
`flutter_launcher_icons.yaml`). After every run:
- Revert `ios/Runner.xcodeproj/project.pbxproj` if the tool changed
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` to `AppIcon`
  (it must stay `YES`).
- Revert any CocoaPods `#include?` lines it adds to `ios/Flutter/*.xcconfig`.
- Delete icon PNGs that `Contents.json` no longer lists.

## Color tokens (all text pairs AA)

| Token | Light | Dark |
|---|---|---|
| background | #F5F1E8 | #121318 |
| surface/card | #FFFDF8 | #1B1D24 |
| ink | #1A1C24 | #EDEAE3 |
| muted | #5E5A52 | #A39E94 |
| hairline | #D9D2C3 | #2C2F38 |
| primary | #2638C4 | #8F9CFF |
| on-primary | #FFFFFF | #0E1240 |
| primary-soft (text) | #E4E7FB (#2638C4) | #232A5C (#B8C0FF) |
| given (on) | #17663A (#FFFFFF) | #5CC98A (#0B2416) |
| already given bg / text / stamp | #FBEBCF / #7A4A00 / #F2B04C | #2E2410 / #F2B04C |
| not sure bg / text (dashed border) | #E9ECF1 / #3F4A5C | #232833 / #B4BDCC |
| error | #B42318 | #FF8A80 |

Green is a status color only, never the brand.

## Type (all OFL)

| Role | Font | Size/LH | Weight |
|---|---|---|---|
| Page title | Bricolage Grotesque | 34/38 | 700, -0.02em |
| Section | Bricolage Grotesque | 20/26 | 600, -0.01em |
| Body | Atkinson Hyperlegible | 17/24 | 400 (700 names) |
| Caption | Atkinson Hyperlegible | 13/18 | 400, +0.01em |
| Stamp (times, doses) | JetBrains Mono | 15/20 | 500, tabular |

## Shape

- Radii: 4 rows/stamps, 10 cards, 16 sheet tops, pill only for "Gave it".
- Hairline borders, no shadows, except a hard 0 3px 0 #16227A under the
  primary button.
- Dose row = ledger line: mono time in a 72px gutter, vertical margin rule,
  med + pet, status at right. Given = pine check + "Sara · 8:02 AM" (mono);
  pending = empty 28px box; not sure = dashed box with "?".
- "Gave it" button: 56px, full width, ink blue, check stroke animates
  (~220ms) and lands in the row's box; long-press offers "Not sure if given".
- Guard sheet = a stamp: ruled cream sheet, amber stamp rotated -3°
  reading ALREADY GIVEN / SARA · 8:02 AM. Heading "Sara gave it at 8:02 AM."
  Primary "Don't give"; secondary "Log anyway, I'm sure" (hold to confirm).
- Today header: a ledger strip of the day's slots instead of the ring.

## Screenshot headlines

Listing copy (name, subtitle, keywords) and the search data behind it are in
[ASO_KEYWORDS.md](ASO_KEYWORDS.md).

1. Sara already gave Miso's insulin (lead: the guard stamp)
2. Did someone already give it?
3. One tap. Logged for everyone.
4. Sitters log without the app
5. A clean log for your vet
