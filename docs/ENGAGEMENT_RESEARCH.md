# Engagement Research — Reminders, Household, Tone

_Researched 2026-10-04. Scope: what we borrow, what we refuse. Every claim links to a source. If a source is vendor-reported, it says so._

## 1. Human medication-reminder apps

- **Medisafe**: notifications have **Take / Snooze / Skip** actions ([Medisafe FAQ](https://www.medisafe.com/faq/will-my-reminders-look-any-different)). A **Medfriend** (caregiver) is alerted only if no action is taken: a follow-up comes 30 min after the last reminder, so the caregiver hears about it **1 h after the scheduled time**. Users can't change that interval ([Medisafe help](https://help-center.medisafe.com/en/articles/8097801-what-is-a-medriend-and-how-does-the-feature-work)). Medfriends get missed-dose alerts, not "taken" confirmations, and have view-only access. Medisafe reports that 71% of users improved adherence after adding a Medfriend. That number is **vendor-reported and not peer-reviewed** ([Medisafe](https://www.medisafe.com/the-value-of-a-medfriend/)). It also offers weekly, monthly and yearly intake stats ([mHealth review](https://mhealth.amegroups.org/article/view/12186/html)).
- **MyTherapy**: a 30-min snooze. It **re-sends until the dose is marked taken or skipped** ([Healthify NZ](https://healthify.nz/apps/m/mytherapy-meds-pill-reminder-app)). That works but can nag.
- **Round Health**: uses a **reminder window** rather than one fixed time, with three nudges at the start, middle and end of the window ([iMedicalApps](https://www.imedicalapps.com/2016/11/round-health-app-personal-assistant-pill-taking/), [App Store](https://apps.apple.com/us/app/round-health/id1059591124)).
- **CareClinic**: reminders, a logbook of taken and skipped doses, refill notifications, "Care Teams" sharing and printable reports for clinicians ([App Store listing](https://apps.appfollow.io/ios/tracker-reminder-careclinic/1455648231?country=np)).
- **Takeaway:** the category standard is actionable buttons, **one or two follow-ups within about an hour**, then escalation to a caregiver. Reports are a utility, not a hook. We couldn't verify copy tone from public sources, so we make no claims about it.

## 2. Pet apps

- **11pets**: 50+ reminder categories (meds, deworming, vaccines) and record sharing with vets ([App Store](https://apps.apple.com/us/app/id1232470530)).
- **PetDesk**: clinic-driven reminders for vaccines, appointments and **medication refills** by push, SMS or email ([PetDesk](https://petdesk.com/blog/using-petdesk-to-remember-pet-medications)).
- **Pawprint (now Great Pet Care)**: vaccine-expiry reminders, plus logs and records shared with **co-owners and pet sitters** ([Great Pet Care](https://account.greatpetcare.com/app)).
- **Tractive**: Family Sharing with unlimited invitees who view for free. Only the owner edits the pet profile and fences ([Tractive help](https://help.tractive.com/hc/en-us/articles/211739365)). This matches our owner/member model.
- **Petcube**: med and treatment reminders in a pet journal, and family device sharing ([App Store](https://apps.apple.com/app/id720151500)).
- **Red Cross Pet First Aid**: profiles with medication lists, plus badges and quizzes rather than reminders ([Red Cross via Commons News](https://commonsnews.org/issue/239/American-Red-Cross-creates-new-Pet-First-Aid-app)).
- **Newer household apps** (Meal Time, Every Wag, Hound) sell **"everyone sees the dose instantly; prevents duplicate doses"** ([Meal Time](https://apps.apple.com/app/id1523239569), [Every Wag](https://apps.apple.com/us/app/id6747091313)). That's our north star, so it's table stakes, not a differentiator. We couldn't find any pet app with a public thank-you or acknowledgement loop.

## 3. Reminder efficacy, fatigue, timing

- **Reminders work, and two-way works better.** A meta-analysis of 16 RCTs (n=2,742) found that text reminders roughly doubled the odds of adherence (OR 2.11; ~50% → 67.8%). The authors caution that trials were short and adherence was self-reported ([Thakkar 2016, JAMA IM](https://georgeinstitute.org/publications/mobile-telephone-text-messaging-for-medication-adherence-in-chronic-disease-a-meta)). Two-way messaging beat one-way (RR 1.23 vs 1.04) ([em-consulte summary](https://www.em-consulte.com/es/article/1002951/tableaux/one-way-versus-two-way-text-messaging-on-improving)). **A "Given" button is our two-way channel.**
- **Repetition erodes response.** In clinical decision support, the likelihood of accepting a reminder fell about 30% with each additional reminder per encounter ([Ancker 2017](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5387195/)). This is a clinician setting, but the direction argues against nag loops.
- **Notification volume harms well-being.** Keeping alerts on raised inattention ([Kushlev CHI '16](https://www.interruptions.net/literature/Kushlev-CHI16.pdf)). Batching notifications three times a day lowered stress ([Georgia Tech summary](https://work21.gatech.edu/?p=402)).
- **Timing.** In a micro-randomized trial (n=1,255), non-urgent prompts had the most effect at **12:30 on weekends** (+11.8% engagement) ([Bidargaddi 2018, JMIR mHealth](https://mhealth.jmir.org/2018/11/e10123)). The app studied was a workplace well-being app, so this is indicative only.
- **Apple guidance.** Apple defines interruption levels: **Passive** (view at leisure), **Active**, **Time Sensitive** (directly impacts the user and needs immediate attention; breaks through Focus) and **Critical** (needs an Apple entitlement) ([WWDC21 10091](https://developer.apple.com/videos/play/wwdc2021/10091/)). Promotional push requires explicit opt-in ([HIG: Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)). The page returned no content when fetched; the opt-in rule is confirmed by secondary summaries. **Dose reminders = Time Sensitive. Summaries and celebrations = Passive.**

## 4. Attachment and tone

- **Pets are family.** 97% of US pet owners say their pet is part of the family, and 51% say "as much as a human member" ([Pew 2023](https://www.pewresearch.org/short-reads/2023/07/07/about-half-us-of-pet-owners-say-their-pets-are-as-much-a-part-of-their-family-as-a-human-member/)). That makes our emotional leverage high, and so is the potential for harm.
- **Guilt has a small effect and backfires when it assigns blame.** A meta-analysis found g = 0.19. Guilt backfires when it explicitly holds the person responsible for another's suffering ([Frontiers 2023](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2023.1201631/full)). "Miso is waiting…" is exactly that framing.
- **Gratitude reinforces helping.** One "thank you" more than doubled repeat helping (25→55%, 32→66%), because helpers felt socially valued ([Grant & Gino 2010](https://www.psychologytoday.com/ca/blog/work-matters/201008/the-power-of-a-simple-thank-you-from-the-boss)).
- **Streaks cut both ways.** Showing a broken streak lowers further engagement compared with an intact one, and the drop is worse when people blame themselves ([Silverman & Barasch 2023, JCR](https://www.colorado.edu/business/faculty-research/2023/04/19/or-track-how-broken-streaks-affect-consumer-decisions)). A missed pet dose is self-attributed by default. **Never display a break.**

## 5. Ranked tactics we will implement

1. **Reliable multi-dose reminders with actionable "Given" / "Snooze 15 min" buttons.** Local and offline. "Given" runs the same double-dose check as the app (offline it goes to the outbox). Time Sensitive only once the entitlement is enabled (`IOS_TIME_SENSITIVE`). Strongest evidence: two-way reminders.
2. **Household thank-you moments in-app**, e.g. "Sam gave Miso's insulin — thanks, Sam". Shown on next open from the synced log, with no extra push or API call. It also answers the "did anyone give it?" question directly. Gratitude evidence.
3. **One gentle missed-dose follow-up about 30 min later** (opt-out), cancelled the moment anyone logs the dose. Just one: fatigue data shows each extra reminder costs response, and Medisafe stops at one.
4. **Warm, specific copy with pet name and dose**, e.g. "Time for Miso's insulin · 2 units". Never blame, never a "waiting/sad" framing.
5. **Refill heads-up** (existing Pro low-supply alert). PetDesk and CareClinic treat it as core. Passive level, one alert per supply threshold.
6. **Weekly summary as a local notification on Sunday** (opt-out, Passive). Ships at **6 PM** as the product brief asked. The evidence hints at **weekend midday**, so that's the first thing to test; the time isn't user-adjustable yet. Content: doses given per pet, with no score and nothing sent when nothing was logged.
7. **Course-completion celebration**: one in-app moment when a finite course ends. Low cost and no guilt.
8. **Gentle care count**, e.g. "42 days of every dose given". Cumulative (it only grows), **never shown as broken or reset**. Ranked last because streak evidence is double-edged.

**Quiet hours 22:00–07:00** apply to #5–#8. Dose reminders (#1, #3) fire at the time the user scheduled, because that's safety.

## Deliberately won't do

1. **Guilt copy or sad-pet imagery** ("Miso is waiting…"). Blame-assigning guilt backfires, and it's a dark pattern on a family member.
2. **Fake urgency or escalating nags**: no re-send-until-acknowledged loops (the MyTherapy style), no Time Sensitive or Critical level on non-dose pushes.
3. **Streak-loss punishment or paywalled safety**: no broken-streak displays, no paid "streak freezes", and never gating dose logging or double-dose checks.
