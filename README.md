# PawsitiveSync

A household medication schedule for pets. Everyone who cares for them sees who gave each dose, the moment it happens.

The screens follow the PawsitiveSync UI: welcome, onboarding, trial, today, dose logging, double-dose guard, household, invite, pet profile, and the vet report.

**Principles:** long-term scale, low cost, best user quality — local-first, minimal API — see [docs/LONG_TERM_ROADMAP.md](docs/LONG_TERM_ROADMAP.md). [AGENTS.md](AGENTS.md)

## Run

No keys or Apple Sign-In required — works offline on this phone.

```bash
flutter pub get
flutter run
```

Optional store billing and online sync: [docs/CONFIG.md](docs/CONFIG.md).

The schedule is stored in memory for this build. Completing onboarding, or choosing “I was invited,” opens the sample household (Miso and Juniper).

Geist Sans is included under the SIL Open Font License (`assets/fonts/OFL.txt`).
