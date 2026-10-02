# Daily care design

Extend the onboarding identity into Today, Pets, Household, Reports and navigation. Keep the existing forest green (#4A7C59), pale sage (#E9F1EB), white (#FFFFFF), soft canvas (#FBFBFA), ink (#2C3531) and muted text (#6B726E). Geist remains the only typeface: 30px page titles, 20px section headings, 15–16px body and 13px supporting text. Page margins are 24px, with 24px between major sections and 12px between related controls.

## Direction

The pet and the next useful action lead. Use one sage summary panel, quiet white task rows and restrained progress indicators based on real data. Pet portraits create continuity between the selector, next dose and profile. All other decoration supports a task. No streaks, fabricated health scores, or additional medication prompts.

```text
Today                         Other main tabs
Today / greeting / settings   page title / relevant action
pet selector                  shared pet selector when needed
daily progress                pet profile / household / report summary
next dose + log action        clearly grouped content
schedule by time of day        specific empty-state action
utilities                     secondary tools
```

Review: the former home put duplicate shortcuts and introductory copy before care tasks. The new layout puts daily progress and the next dose first. Empty Today uses one direct setup prompt and compact guidance. Given and upcoming doses keep distinct states; a progress count never treats an upcoming dose as immediately due.

## References

Use Mobbin MCP for UI references on this project, as requested by the user.

[Fi health dashboard, via Mobbin MCP](https://mobbin.com/screens/89958f60-b292-4cd5-8bca-69b2370f22f8): clear grouped health information and persistent pet identity. Reference images are not shipped as app assets.

[Apple Health medication screen](https://mobbin.com/screens/19cc770b-a386-48a5-9d6b-7a46a8c98685): scheduled doses and logged doses have distinct states, with direct logging actions. [GoodRx medicine cabinet](https://mobbin.com/screens/95f9bc43-c218-4b83-b008-5a451404b138): medicine identity and recording actions are visually grouped. These support the Today task hierarchy while keeping PawsitiveSync’s existing visual identity.

## Validation

Add Medicine uses the same pet selector, 24px margins and sage surfaces. [Apple Health’s schedule form on Mobbin](https://mobbin.com/screens/97e0cc8f-ce4a-4b2a-8ff3-086a35392556) informs the separation of medicine details and daily timing. [Zocdoc’s medication form](https://mobbin.com/screens/2338cd93-5969-4803-9363-f1ab157e564b) informs the short, directly labeled fields and persistent save action. Original sunrise, sun, moon and medicine SVGs carry the existing stroke-icon style into this form. Times remain the app’s existing daily slots, with no invented scheduling capabilities. Supply inputs appear only when enabled; the unit is a complete dose. Field errors scroll into view, and the form opens without forcing the keyboard. At narrow widths or larger text sizes, schedule choices stack vertically.

Review rendered screens in light and dark mode, phone and tablet widths, empty and populated accounts. Verify pet filtering updates progress and tasks together, logging remains a confirmation flow, reports retain export controls, and all navigation actions work.
