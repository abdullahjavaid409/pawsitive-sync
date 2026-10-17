import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/pro_prompts.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// The cards under Today's dose list: the week, the next dose and coming
/// care. Each hides itself when
/// it has nothing true to say.
class TodayMoreCards extends StatelessWidget {
  const TodayMoreCards({super.key, required this.care, this.petId});

  final CareRepository care;

  /// The pet picked on Today; null means every pet.
  final String? petId;

  @override
  Widget build(BuildContext context) {
    final next = care.nextAfterToday(petId: petId);
    final events = [
      for (final e in care.upcomingCareEvents(withinDays: 30))
        if (petId == null || e.petId == petId) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekCard(days: _week(care, petId)),
        if (next != null) ...[
          const SizedBox(height: 12),
          _UpNextCard(care: care, medication: next.medication, at: next.at),
        ],
        if (events.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ComingUpCard(care: care, events: events.take(2).toList()),
        ],
      ],
    );
  }

  /// The last seven days for one pet, or summed across every pet.
  static List<DayTally> _week(CareRepository care, String? petId) {
    final pets = [
      for (final p in care.pets)
        if (petId == null || p.id == petId) p,
    ];
    List<DayTally>? sum;
    for (final pet in pets) {
      final days = care.reportFor(pet.id, 7).days;
      sum = sum == null
          ? days
          : [
              for (final (i, d) in days.indexed)
                DayTally(
                  day: d.day,
                  expected: d.expected + sum[i].expected,
                  given: d.given + sum[i].given,
                ),
            ];
    }
    return sum ?? const [];
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: text.headlineSmall),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Seven circles: a check for a day with every dose given, warm for a
/// missed one, an outline before anything was scheduled; today ringed.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.days});

  final List<DayTally> days;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// Days in a row with every dose given, ending today (if done) or
  /// yesterday (today still open).
  int get _streak {
    var i = days.length - 1;
    if (i >= 0 && !days[i].allGiven) i--;
    var count = 0;
    while (i >= 0 && days[i].allGiven) {
      count++;
      i--;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    if (days.every((d) => d.isEmpty)) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final streak = _streak;
    final pastMissed = days
        .take(days.length - 1)
        .any((d) => !d.isEmpty && !d.allGiven);
    final note = pastMissed
        ? 'A few doses were missed this week.'
        : streak >= 2
        ? 'Every dose given $streak days in a row.'
        : 'Each check is a day with every dose given.';
    return _Card(
      title: 'This week',
      trailing: streak >= 2
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(StrokeIconKind.paw, size: 14, color: paws.brandDark),
                const SizedBox(width: 4),
                Text('$streak-day streak', style: text.labelLarge),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, d) in days.indexed)
                Expanded(
                  child: _DayDot(
                    letter: _letters[d.day.weekday - 1],
                    day: d,
                    today: i == days.length - 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            note,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.letter, required this.day, required this.today});

  final String letter;
  final DayTally day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final missed = !today && !day.isEmpty && !day.allGiven;
    final (fill, ink) = day.allGiven
        ? (paws.states.success, Colors.white)
        : missed
        ? (paws.warningBg, paws.warning)
        : day.isEmpty
        ? (Colors.transparent, scheme.onSurfaceVariant)
        : (paws.surfaces.subtle, scheme.onSurface);
    final state = day.allGiven
        ? 'every dose given'
        : missed
        ? 'a dose was missed'
        : day.isEmpty
        ? 'nothing scheduled'
        : 'doses still to give';
    return Semantics(
      label:
          '${today ? 'Today' : MaterialLocalizations.of(context).formatMediumDate(day.day)}: $state',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            letter,
            style: text.labelSmall?.copyWith(
              color: today ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: today ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: today
                  ? Border.all(color: scheme.onSurface, width: 2)
                  : day.isEmpty
                  ? Border.all(color: paws.hairline, width: 1.5)
                  : null,
            ),
            child: day.allGiven
                ? StrokeIcon(StrokeIconKind.check, size: 16, color: ink)
                : Text(
                    '${day.day.day}',
                    style: text.labelMedium?.copyWith(
                      color: ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The first dose after today, so a finished day still says what's next.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.care,
    required this.medication,
    required this.at,
  });

  final CareRepository care;
  final Medication medication;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pet = care.tryPetById(medication.petId);
    final tomorrow = DateTime(care.now.year, care.now.month, care.now.day + 1);
    final day = DateUtils.isSameDay(at, tomorrow)
        ? 'Tomorrow'
        : MaterialLocalizations.of(context).formatMediumDate(at);
    final time = ClockFormat.label(at.hour * 60 + at.minute);
    final amount = medication.doseLabel;
    return _Card(
      title: 'Up next',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.medication(medication.id)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.paws.surfaces.subtle,
                shape: BoxShape.circle,
              ),
              child: StrokeIcon(
                StrokeIconKind.clock,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$day · $time',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    [
                      pet == null
                          ? medication.name
                          : '${pet.name}’s ${medication.name}',
                      if (amount.isNotEmpty) amount,
                    ].join(' · '),
                    style: text.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to two care events in the next 30 days; the rest live on Pets.
class _ComingUpCard extends StatelessWidget {
  const _ComingUpCard({required this.care, required this.events});

  final CareRepository care;
  final List<CareEvent> events;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final local = MaterialLocalizations.of(context);
    return _Card(
      title: 'Coming up',
      trailing: TextButton(
        onPressed: () {
          AppLog.event('today.shortcut.events');
          context.go(AppRoutes.pets);
        },
        style: TextButton.styleFrom(
          foregroundColor: paws.brandDark,
          padding: const EdgeInsetsDirectional.only(start: 8),
          minimumSize: const Size(44, 36),
        ),
        child: const Text('See all'),
      ),
      child: Column(
        children: [
          for (final (i, event) in events.indexed) ...[
            if (i > 0) Divider(height: 20, color: paws.hairline),
            Builder(
              builder: (context) {
                final date = DateTime.tryParse(event.dueDay);
                final pet = care.tryPetById(event.petId);
                return Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: paws.surfaces.subtle,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            date == null
                                ? ''
                                : local
                                      .formatShortMonthDay(date)
                                      .split(' ')
                                      .first
                                      .toUpperCase(),
                            style: text.labelSmall?.copyWith(
                              fontSize: 10,
                              color: paws.brandDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            date == null ? '' : '${date.day}',
                            style: text.titleSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            [
                              if (date != null) local.formatMediumDate(date),
                              event.kindLabel,
                              ?pet?.name,
                            ].join(' · '),
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Free only: the problem Pro solves, what it adds and why it's a
/// subscription, said once. Closing it hides it for good; no countdowns,
/// no badges.
class TodayProCard extends StatefulWidget {
  const TodayProCard({super.key});

  @override
  State<TodayProCard> createState() => _TodayProCardState();
}

class _TodayProCardState extends State<TodayProCard> {
  /// Hidden until the saved choice is read, so it never flashes in.
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    ProPrompts.todayCardHidden().then((hidden) {
      if (!mounted) return;
      setState(() => _hidden = hidden);
      if (!hidden) AppLog.event('billing.today_pro_card.shown');
    });
  }

  void _hide() {
    setState(() => _hidden = true);
    ProPrompts.hideTodayCard();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    const gains = [
      (StrokeIconKind.people, 'Everyone sees each dose the moment it’s given'),
      (StrokeIconKind.clock, 'Afternoon and evening doses, reminded on time'),
      (StrokeIconKind.bell, 'A heads-up before the medicine runs out'),
      (StrokeIconKind.file, 'A vet-ready report of every dose'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PawsRadii.cardValue),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  // The handover itself: the moment a dose gets doubled.
                  Image.asset(
                    'assets/photos/caregivers-together.jpg',
                    width: double.infinity,
                    height: 132,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.2, -0.1),
                    excludeFromSemantics: true,
                  ),
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: IconButton(
                      tooltip: 'Hide Pro card',
                      onPressed: _hide,
                      style: IconButton.styleFrom(
                        backgroundColor: paws.surfaces.card.withValues(
                          alpha: 0.88,
                        ),
                        fixedSize: const Size(32, 32),
                        minimumSize: const Size(32, 32),
                      ),
                      icon: StrokeIcon(
                        StrokeIconKind.close,
                        size: 16,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'GAVE IT PRO',
                      style: text.labelSmall?.copyWith(
                        color: paws.brandDark,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      header: true,
                      child: Text(
                        'One log for everyone who gives the pills',
                        style: text.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Two people, one pill and no shared record: that’s how '
                      'doses get doubled or missed. Pro puts everyone on the '
                      'same log.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final (icon, line) in gains)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: paws.surfaces.selected,
                                shape: BoxShape.circle,
                              ),
                              child: StrokeIcon(
                                icon,
                                size: 16,
                                color: paws.brandDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(line, style: text.bodyMedium)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Why monthly, plainly: the paid parts run every day.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: paws.surfaces.subtle,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Why a subscription: Pro syncs your household and '
                          'sends reminders every day. Logging doses and the '
                          'double-dose check stay free, always.',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      // billing.paywall.opened from=today_pro_card.
                      onPressed: () => context.push(
                        AppRoutes.paywallWith(
                          reason: 'settings',
                          from: 'today_pro_card',
                        ),
                      ),
                      child: const Text('See Pro plans'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
