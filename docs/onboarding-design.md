# Onboarding design

PawsitiveSync helps a household keep track of pet medication. The visual direction is a quiet, friendly care journal: pet illustrations carry the personality; forms stay clear and useful.

## Tokens

- Canvas: `#FBFBFA`; cards: `#FFFFFF`; ink: `#2C3531`.
- Forest: `#4A7C59`; pale sage: `#E9F1EB`; secondary text: `#6B726E`.
- Geist throughout: 34px welcome heading, 30px step headings, 16px body and actions, 13px supporting text.
- Spacing: 8 / 12 / 16 / 24 / 32. Page margins 24px; primary actions at least 56px high.
- Rounded fields and options: 16px. Illustration panels: 28px. No repeated card shadows.

## Layout

Welcome leads with the brand, a large original pet illustration, the core benefit, and a shared-dose example. Setup uses left-aligned titles, concise instructions, compact art and a pinned full-width action.

```text
Welcome                       Setup
brand                         back / step name / count
pet-care scene                segmented progress
benefit                       title + explanation
shared-dose example           illustration or profile
                              form / choices
primary action                primary action
invite link                   optional secondary action
```

The five-step progress indicator represents the actual sequence. Illustrations share the existing vector palette and rounded strokes. The welcome scene is the main visual accent; later steps use smaller assets to preserve space for decisions. This avoids giving every step a large, mostly empty hero.

## Reference

[Fi — setting up a profile, via Mobbin MCP](https://mobbin.com/flows/3a203fb4-5eef-407c-b16d-6e428223c95e): clear pet-centric hierarchy and direct form controls. Reference images are not incorporated into the app; all added vectors are original.

## Behavior

Preserve routing, validation, saved answers, photo selection, caregiver exclusivity and reminder permissions. Respect reduced motion, dark mode, larger text and small screens. The scaffold handles keyboard insets once; content scrolls independently above the action.
