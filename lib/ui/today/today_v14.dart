import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/press_scale.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';

// Today, as drawn in the Magic Patterns v14 prototype
// (magicpatterns.com/c/3uevscvjssummpalbf68t8, pages/TodayPage.tsx):
// date + serif greeting, one progress card with the next dose, the day's
// doses grouped by time of day, then supplies.

/// Minute of day a dose is scheduled for, falling back to its part's default.
int doseMinute(Dose dose) =>
    dose.minute < 0 ? dose.part.defaultMinute : dose.minute;

/// "Due now" until the late reminder would have fired, then "Late": an
/// 8:00 AM dose at 2 PM is not "now", and the word tells the household
/// which doses to deal with first. Never "Late" for a dose that was logged.
String dueWord(Dose dose, DateTime now) {
  if (dose.status != DoseStatus.due) return 'Later today';
  final minutesPast = now.hour * 60 + now.minute - doseMinute(dose);
  return minutesPast >= ReminderSettings.followUpDelay.inMinutes
      ? 'Late'
      : 'Due now';
}

/// "Wednesday, October 14", then "Good morning, *Sara*" in the serif, then a
/// quiet sync line when the household is shared.
class TodayGreeting extends StatelessWidget {
  const TodayGreeting({super.key, required this.care, this.trailing});

  final CareRepository care;

  /// Header controls (Pro badge, settings), top-right.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = care.now;
    // The local placeholder member is literally named "You": greet without
    // a name rather than "Good morning, You".
    final name = care.you.name.trim();
    final firstName = name.isEmpty || name == 'You'
        ? ''
        : name.split(' ').first;
    final greeting = greetingLabel(now);
    final others = care.members.where((m) => !m.isYou && m.active).length;
    final synced = care.lastSyncedAt;
    final syncLine = !care.isConnected || synced == null
        ? null
        : [
            others == 0
                ? 'Household synced'
                : 'In sync with $others ${others == 1 ? 'other' : 'others'}',
            // An absolute time never goes stale the way "just now" would.
            'updated ${ClockFormat.label(synced.hour * 60 + synced.minute)}',
          ].join(' · ');
    final serif = text.displaySmall;
    // Large text or a narrow phone: controls get their own row so the
    // greeting keeps the full width and never breaks mid-word.
    final stack =
        MediaQuery.textScalerOf(context).scale(1) > 1.2 ||
        MediaQuery.sizeOf(context).width < 360;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dayLabel(now),
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: firstName.isEmpty ? greeting : '$greeting, '),
                if (firstName.isNotEmpty)
                  // Italic serif on the one warm word, as in v14.
                  TextSpan(
                    text: firstName,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            style: serif,
          ),
        ),
        if (syncLine != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              StrokeIcon(
                StrokeIconKind.refresh,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  syncLine,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 16),
      child: stack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (trailing != null) ...[
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: trailing,
                  ),
                  const SizedBox(height: 8),
                ],
                title,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
    );
  }
}

/// "3 of 5 doses given today", a segment per dose, and the next dose with
/// one "Mark given" button. All given: "Everyone is covered for today".
class TodayProgressCard extends StatelessWidget {
  const TodayProgressCard({
    super.key,
    required this.care,
    required this.doses,
    required this.next,
    required this.onMarkGiven,
    required this.onDetails,
    this.lastGiven = '',
  });

  final CareRepository care;

  /// Every dose on Today (already filtered to the selected pet).
  final List<Dose> doses;

  /// The dose to give next: the first one due, else the first upcoming.
  final Dose? next;

  /// Logs the next dose: only offered once it is due (or needs a check).
  final VoidCallback onMarkGiven;

  /// Opens the next dose's medicine. An upcoming dose offers this instead of
  /// a give-now action, so nobody gives a dose hours early by mistake.
  final VoidCallback onDetails;

  /// "Sara gave the morning one at 8:02 AM": the same medicine given earlier
  /// today, so a second person doesn't double up. Empty when there is none.
  final String lastGiven;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final ordered = [...doses]..sort((a, b) => doseMinute(a) - doseMinute(b));
    final done = doses.where((d) => d.status == DoseStatus.given).length;
    final next = this.next;
    final pet = next == null ? null : care.tryPetById(next.petId);
    final number = text.displaySmall?.copyWith(
      fontSize: 46,
      height: 1,
      letterSpacing: -0.7,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            // Its own node: VoiceOver reads the count, then the next dose.
            container: true,
            label: '$done of ${doses.length} doses given today',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$done'),
                      TextSpan(
                        text: '  of  ',
                        style: TextStyle(
                          fontSize: 26,
                          letterSpacing: 0,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(text: '${doses.length}'),
                    ],
                  ),
                  style: number,
                ),
                const SizedBox(height: 6),
                Text(
                  'doses given today',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // One segment per dose, in time order: the day at a glance.
          ExcludeSemantics(
            child: Row(
              children: [
                for (final (i, dose) in ordered.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: paws.motion.enter,
                      curve: Curves.easeOut,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dose.status == DoseStatus.given
                            ? paws.states.success
                            : paws.surfaces.subtle,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: paws.divider),
          const SizedBox(height: 16),
          if (next == null)
            Row(
              children: [
                StrokeIcon(
                  StrokeIconKind.check,
                  size: 16,
                  color: paws.states.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Everyone is covered for today',
                    style: text.bodyLarge?.copyWith(
                      color: paws.states.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final label = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _upNextLabel(next),
                      style: text.bodySmall?.copyWith(
                        color:
                            next.status == DoseStatus.due &&
                                next.givenById != null
                            ? paws.warning
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pet == null ? next.name : '${pet.name}’s ${next.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    if (lastGiven.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        lastGiven,
                        style: text.bodySmall?.copyWith(
                          color: paws.states.success,
                        ),
                      ),
                    ],
                  ],
                );
                final unsure =
                    next.status == DoseStatus.due && next.givenById != null;
                final Widget button;
                if (next.status == DoseStatus.upcoming) {
                  // Not due yet: details, never a give-now action.
                  button = TextButton(
                    onPressed: onDetails,
                    style: TextButton.styleFrom(
                      backgroundColor: paws.surfaces.subtle,
                      foregroundColor: scheme.onSurface,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: const StadiumBorder(),
                      textStyle: text.labelLarge?.copyWith(fontSize: 15),
                    ),
                    child: const Text('View medicine'),
                  );
                } else {
                  button = PressScale(
                    child: FilledButton(
                      onPressed: onMarkGiven,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        textStyle: text.labelLarge?.copyWith(fontSize: 15),
                      ),
                      child: Text(unsure ? 'Review dose' : 'Mark given'),
                    ),
                  );
                }
                // Large text on a narrow phone: stack instead of squeezing.
                final stack =
                    constraints.maxWidth < 300 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, const SizedBox(height: 12), button],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 12),
                    button,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  String _upNextLabel(Dose next) {
    // "Not sure" doses need a check before anyone gives them.
    if (next.status == DoseStatus.due && next.givenById != null) {
      return 'Needs a check · ${next.timeLabel}';
    }
    return '${dueWord(next, care.now)} · ${next.timeLabel}';
  }
}

/// The day's doses under "Morning", "Afternoon" and "Evening": pet photo,
/// medicine, "Miso · 2 units · 8:00 AM", then "Give" or who gave it.
class TodayDayGroups extends StatelessWidget {
  const TodayDayGroups({
    super.key,
    required this.care,
    required this.doses,
    required this.onGive,
    required this.onOpen,
  });

  final CareRepository care;
  final List<Dose> doses;

  /// Opens the log sheet for a dose that isn't given yet.
  final void Function(Dose dose) onGive;

  /// Row tap: details for an upcoming dose, the guard for a given one.
  final void Function(Dose dose) onOpen;

  @override
  Widget build(BuildContext context) {
    final ordered = [...doses]..sort((a, b) => doseMinute(a) - doseMinute(b));
    final groups = <(String, List<Dose>)>[
      (
        'Morning',
        [
          for (final d in ordered)
            if (doseMinute(d) < 12 * 60) d,
        ],
      ),
      (
        'Afternoon',
        [
          for (final d in ordered)
            if (doseMinute(d) >= 12 * 60 && doseMinute(d) < 17 * 60) d,
        ],
      ),
      (
        'Evening',
        [
          for (final d in ordered)
            if (doseMinute(d) >= 17 * 60) d,
        ],
      ),
    ];
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, items) in groups)
          if (items.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Semantics(
                header: true,
                child: Text(label, style: text.headlineSmall),
              ),
            ),
            SurfaceCard(
              child: Column(
                children: [
                  for (final (i, dose) in items.indexed)
                    _DoseRow(
                      key: ValueKey(dose.id),
                      care: care,
                      dose: dose,
                      divider: i < items.length - 1,
                      onGive: () => onGive(dose),
                      onOpen: () => onOpen(dose),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({
    super.key,
    required this.care,
    required this.dose,
    required this.divider,
    required this.onGive,
    required this.onOpen,
  });

  final CareRepository care;
  final Dose dose;
  final bool divider;
  final VoidCallback onGive;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final pet = care.tryPetById(dose.petId);
    final given = dose.status == DoseStatus.given;
    // Logged "not sure": still due, but someone has to check first.
    final unsure = dose.status == DoseStatus.due && dose.givenById != null;
    final giver = switch (dose.givenById) {
      final id? => care.memberById(id),
      null => null,
    };
    final who = giver == null ? '' : (giver.isYou ? 'You' : giver.name);
    final upcoming = dose.status == DoseStatus.upcoming;
    final medication = care.medicationById(dose.medicationId);
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    // "Not sure" keeps its full warning on the line ("Sara is not sure —
    // check first"); every other row reads pet · amount · time.
    final detail = unsure && dose.subtitle.isNotEmpty
        ? dose.subtitle
        : [
            ?pet?.name,
            if (dose.amount.isNotEmpty) dose.amount,
            if (medication?.site.isNotEmpty ?? false) medication!.site,
            dose.timeLabel,
            if (medication?.withFood ?? false) 'with food',
          ].join(' · ');
    final state = given
        ? 'given by $who at ${dose.givenAt}'
        : unsure
        ? 'not sure if given, needs a check'
        : dose.status == DoseStatus.due
        ? 'due now'
        : 'later';

    final Widget trailing;
    if (given) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(
            StrokeIconKind.check,
            size: 14,
            color: paws.states.success,
          ),
          const SizedBox(width: 4),
          Text(
            who.isEmpty ? dose.givenAt : '$who · ${dose.givenAt}',
            style: text.bodySmall?.copyWith(
              color: paws.states.success,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    } else if (upcoming) {
      // Not due yet: no give-now action; the row opens the medicine.
      trailing = Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          'Later',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    } else {
      trailing = TextButton(
        onPressed: onGive,
        style: TextButton.styleFrom(
          foregroundColor: unsure ? paws.warning : scheme.primary,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: text.labelLarge,
        ),
        child: Text(unsure ? 'Check' : 'Give'),
      );
    }

    return Semantics(
      container: true,
      label: '${pet?.name ?? ''} ${dose.name}, ${dose.timeLabel}, $state',
      child: InkWell(
        onTap: onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: divider
                ? Border(bottom: BorderSide(color: paws.divider))
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  // Decorative: the row label already names the pet.
                  if (pet != null)
                    ExcludeSemantics(
                      child: PetAvatar(
                        species: pet.species,
                        photoPath: pet.photoPath,
                        photoVersion: pet.photoVersion,
                        size: 40,
                      ),
                    )
                  else
                    const SizedBox.square(dimension: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            dose.name,
                            maxLines: big ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelLarge,
                          ),
                        ),
                        ExcludeSemantics(
                          child: Text(
                            detail,
                            maxLines: big ? 4 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: unsure
                                  ? paws.warning
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        // Large text: the status drops under the name so
                        // neither gets cut off.
                        if (big) ...[
                          const SizedBox(height: 4),
                          if (given || upcoming)
                            ExcludeSemantics(child: trailing)
                          else
                            trailing,
                        ],
                      ],
                    ),
                  ),
                  if (!big) ...[
                    const SizedBox(width: 8),
                    // The trailing label is read as part of the row's label.
                    if (given || upcoming)
                      ExcludeSemantics(child: trailing)
                    else
                      trailing,
                    if (given) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Supplies": a medicine running low, with roughly how many days are left.
class TodaySupplyRow extends StatelessWidget {
  const TodaySupplyRow({
    super.key,
    required this.medication,
    required this.pet,
    required this.onReorder,
  });

  final Medication medication;
  final Pet? pet;

  /// Opens the medicine, where supply is updated after a refill.
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final perDay = medication.parts.isEmpty ? 1 : medication.parts.length;
    final days = medication.dosesLeft ~/ perDay;
    final left = medication.dosesLeft;
    final detail = [
      '$left ${left == 1 ? 'dose' : 'doses'} left'
          '${pet == null ? '' : ' for ${pet!.name}'}',
      if (days <= 0)
        'runs out today'
      else
        'about $days ${days == 1 ? 'day' : 'days'}',
    ].join(' · ');
    return SurfaceCard(
      child: InkWell(
        onTap: onReorder,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: paws.amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${medication.name} is running low',
                      style: text.labelLarge,
                    ),
                    Text(
                      detail,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onReorder,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  minimumSize: const Size(44, 44),
                  textStyle: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: const Text('Refill'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
