import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/ledger.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// Named so the navigation log reads `nav.push to=log_dose`.
Future<void> showLogDoseSheet(BuildContext context, Dose dose) {
  return showModalBottomSheet<void>(
    context: context,
    routeSettings: const RouteSettings(name: 'log_dose'),
    sheetAnimationStyle: AppMotion.sheet(context),
    showDragHandle: false,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    constraints: AdaptiveLayout.sheetConstraints,
    // v14 confirm sheet: a cream card over a soft ink scrim.
    backgroundColor: context.paws.surfaces.card,
    barrierColor: Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.3),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PawsRadii.sheetValue),
      ),
    ),
    builder: (context) => _LogDoseSheet(dose: dose),
  );
}

Future<void> showDoubleDoseGuard(BuildContext context, Dose dose) {
  AppLog.event('dose.already', {'doseId': dose.id});
  return showModalBottomSheet<void>(
    context: context,
    routeSettings: const RouteSettings(name: 'dose_already'),
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: AppMotion.sheet(context),
    constraints: AdaptiveLayout.sheetConstraints,
    backgroundColor: context.paws.surfaces.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PawsRadii.sheetValue),
      ),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(child: _DoubleDoseSheet(dose: dose)),
    ),
  );
}

class _LogDoseSheet extends StatefulWidget {
  const _LogDoseSheet({required this.dose});
  final Dose dose;
  @override
  State<_LogDoseSheet> createState() => _LogDoseSheetState();
}

class _LogDoseSheetState extends State<_LogDoseSheet> {
  late final TextEditingController _amount;
  late String _memberId;
  TimeOfDay? _givenAt;
  DoseOutcome _outcome = DoseOutcome.smooth;

  /// v14 leads with a plain confirm; amount, time, giver and "how did it
  /// go" stay one tap away under "Change details".
  bool _details = false;
  LogOutcome? _saved;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final care = context.read<CareRepository>();
    _amount = TextEditingController(text: widget.dose.amount);
    _memberId = care.you.id;
    if (_recent(care) case final recent?) {
      AppLog.event('dose.recent_warning', {
        'doseId': widget.dose.id,
        'previousLogId': recent.log.id,
        'minutesAgo': recent.ago.inMinutes,
      });
    }
  }

  /// Only a dose still to give can be a second one.
  RecentDose? _recent(CareRepository care) =>
      widget.dose.status == DoseStatus.due
      ? care.recentlyGiven(widget.dose.medicationId)
      : null;

  /// "Sara gave Carprofen 14 min ago (yesterday at 11:51 PM)."
  String _recentText(CareRepository care, RecentDose recent) {
    final member = care.memberById(recent.log.memberId);
    final who = member.isYou ? 'You' : member.name;
    final minutes = recent.ago.inMinutes;
    final ago = switch (minutes) {
      < 1 => 'just now',
      < 60 => '$minutes min ago',
      _ when minutes % 60 == 0 => '${minutes ~/ 60} h ago',
      _ => '${minutes ~/ 60} h ${minutes % 60} min ago',
    };
    final when = recent.log.day == dayKey(care.now)
        ? 'at ${recent.log.timeLabel}'
        : 'yesterday at ${recent.log.timeLabel}';
    return '$who gave ${widget.dose.name} $ago ($when). Doses this close '
        'together can be unsafe. Check before giving another.';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.fromDateTime(context.read<CareRepository>().now);
    final chosen = await showTimePicker(
      context: context,
      initialTime: _givenAt ?? now,
    );
    if (chosen == null || !mounted) return;
    if (chosen.hour * 60 + chosen.minute > now.hour * 60 + now.minute) {
      setState(() {
        _error = 'Choose a time earlier today, or use Now.';
        _details = true;
      });
      return;
    }
    setState(() {
      _givenAt = chosen;
      _error = null;
    });
  }

  Future<void> _save(LogOutcome outcome) async {
    if (_busy) return;
    final care = context.read<CareRepository>();
    if (outcome == LogOutcome.given &&
        widget.dose.amount.isNotEmpty &&
        _amount.text.trim().isEmpty) {
      setState(() {
        _error = 'Enter the amount that was given.';
        // The field lives under "Change details": open it so it can be fixed.
        _details = true;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.lightImpact();
    final when = _givenAt ?? TimeOfDay.fromDateTime(care.now);
    final timeLabel = MaterialLocalizations.of(context)
        .formatTimeOfDay(when, alwaysUse24HourFormat: false);
    // A helper who left the household while the sheet was open can't be
    // credited: fall back to you rather than save a dangling member.
    final memberId = care.members.any((m) => m.id == _memberId && m.joined)
        ? _memberId
        : care.you.id;
    bool saved;
    try {
      saved = switch (outcome) {
        LogOutcome.given => await care.logDose(
          doseId: widget.dose.id,
          memberId: memberId,
          amount: _amount.text.trim(),
          timeLabel: timeLabel,
          outcome: _outcome,
        ),
        LogOutcome.skipped => await care.skipDose(widget.dose.id),
        LogOutcome.uncertain => await care.markDoseUncertain(widget.dose.id),
      };
    } on Object catch (error, stack) {
      // The repository reports expected failures as `false`; anything thrown
      // is a bug. Log it and give the buttons back instead of spinning forever.
      AppLog.error('dose.save_crashed', error, stack, {
        'doseId': widget.dose.id,
        'outcome': outcome.name,
      });
      saved = false;
    }
    if (!mounted) return;
    // The outcome (completed / rejected / failed) is logged by the repository.
    if (!saved) {
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    setState(() => _saved = outcome);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pet = care.petById(widget.dose.petId);
    final members = {
      care.you.id: care.you,
      for (final member in care.members.where((m) => m.joined))
        member.id: member,
    }.values.toList();
    if (_saved case final saved?) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: context.paws.brandSoft,
                child: StrokeIcon(
                  saved == LogOutcome.uncertain
                      ? StrokeIconKind.alert
                      : StrokeIconKind.check,
                  size: 28,
                  color: context.paws.brandDark,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                switch (saved) {
                  LogOutcome.given => 'Dose saved.',
                  LogOutcome.skipped => 'Skipped for today.',
                  LogOutcome.uncertain => 'Marked for a check.',
                },
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                saved == LogOutcome.uncertain
                    ? 'It stays on Today until someone confirms.'
                    : '${pet.name}’s care record is up to date.',
                style: text.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: PetPortraitSquare(pet: pet, size: 56),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Medicine names are proper nouns ("Apoquel"): never re-cased.
                          'Log ${pet.name}’s ${widget.dose.name}?',
                          style: text.headlineSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          care.isConnected
                              ? 'Everyone in the household will see this right away.'
                              : 'Saved on this phone, even with no signal.',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const StrokeIcon(StrokeIconKind.close, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: AbsorbPointer(
                  absorbing: _busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Safety first: these warnings always sit on top.
                      if (_recent(care) case final recent?) ...[
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.paws.warningBg,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _recentText(care, recent),
                              style: text.bodyMedium?.copyWith(
                                color: context.paws.warning,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.dose.status == DoseStatus.due &&
                          widget.dose.givenById != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.paws.warningBg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${widget.dose.subtitle}. Confirm with your household before logging.',
                            style: text.bodyMedium?.copyWith(
                              color: context.paws.warning,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _SummaryRows(
                        rows: [
                          (
                            StrokeIconKind.clock,
                            'Scheduled',
                            [
                              widget.dose.timeLabel,
                              if (widget.dose.amount.isNotEmpty)
                                widget.dose.amount,
                              ?_site(care),
                            ].join(' · '),
                          ),
                          // Said where it's acted on, not only in setup.
                          if (care
                                  .medicationById(widget.dose.medicationId)
                                  ?.withFood ??
                              false)
                            (
                              StrokeIconKind.alert,
                              'With food',
                              'Give it with a meal',
                            ),
                          (
                            StrokeIconKind.history,
                            'Last dose',
                            _lastDoseText(care),
                          ),
                          (
                            StrokeIconKind.userCheck,
                            'Logged as',
                            '${_memberLabel(care, members)} · '
                                '${(_givenAt ?? TimeOfDay.fromDateTime(care.now)).format(context)}',
                          ),
                        ],
                      ),
                      // The household note, at the moment it matters.
                      if (pet.careNote.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: _noteLead(care, pet),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                TextSpan(text: pet.careNote),
                              ],
                            ),
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _details = !_details),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          icon: AnimatedRotation(
                            turns: _details ? 0.25 : 0,
                            duration: context.paws.motion.micro,
                            child: StrokeIcon(
                              StrokeIconKind.chevronRight,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ),
                          label: Text(
                            _details ? 'Hide details' : 'Change details',
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: context.paws.motion.enter,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: !_details
                            ? const SizedBox(width: double.infinity)
                            : _detailsForm(context, care, members),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error case final error?) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // One full-width primary; the ✕ above closes the sheet.
                  FilledButton(
                    autofocus: true,
                    onPressed: _busy ? null : () => _save(LogOutcome.given),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      textStyle: text.titleMedium,
                    ),
                    child: _busy
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                              semanticsLabel: 'Saving dose',
                            ),
                          )
                        : const Text('Confirm given'),
                  ),
                  const SizedBox(height: 4),
                  // Labels on the same edges as the button above; still
                  // 44pt tall to tap.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _save(LogOutcome.uncertain),
                        style: _edgeLink(scheme),
                        child: const Text('Not sure if given'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _save(LogOutcome.skipped),
                        style: _edgeLink(scheme),
                        child: const Text('Skip today'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ButtonStyle _edgeLink(ColorScheme scheme) => TextButton.styleFrom(
    foregroundColor: scheme.onSurfaceVariant,
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: 4),
  );

  /// "8:04 AM today by Sam": the same medicine given earlier today, else
  /// the most recent log within the safety window, else a plain "none".
  String _lastDoseText(CareRepository care) {
    Dose? earlier;
    for (final d in care.doses) {
      if (d.id != widget.dose.id &&
          d.medicationId == widget.dose.medicationId &&
          d.status == DoseStatus.given) {
        earlier = d;
      }
    }
    if (earlier != null) {
      final id = earlier.givenById;
      final giver = id == null ? null : care.memberById(id);
      final who = giver == null
          ? ''
          : giver.isYou
          ? ' by you'
          : ' by ${giver.name}';
      return '${earlier.givenAt} today$who';
    }
    if (care.recentlyGiven(widget.dose.medicationId) case final recent?) {
      final member = care.memberById(recent.log.memberId);
      final who = member.isYou ? 'you' : member.name;
      final today = recent.log.day == dayKey(care.now);
      return '${recent.log.timeLabel} ${today ? 'today' : 'yesterday'} by $who';
    }
    return 'None yet today';
  }

  /// "Reminder from Sam: " — who wrote the household note.
  String _noteLead(CareRepository care, Pet pet) {
    if (pet.careNoteBy.isEmpty) return 'Household note: ';
    final by = care.memberById(pet.careNoteBy);
    return 'Reminder from ${by.isYou ? 'you' : by.name}: ';
  }

  /// "Left eye" for drops and topicals; null when it has no site.
  String? _site(CareRepository care) {
    final site = care.medicationById(widget.dose.medicationId)?.site ?? '';
    return site.isEmpty ? null : site;
  }

  String _memberLabel(CareRepository care, List<Member> members) {
    final member = members.where((m) => m.id == _memberId).firstOrNull;
    if (member == null || member.isYou) {
      final name = care.you.name;
      return name.isEmpty || name == 'You' ? 'You' : '$name (you)';
    }
    return member.name;
  }

  /// Amount, time, giver and how it went: the full log, one tap away.
  Widget _detailsForm(
    BuildContext context,
    CareRepository care,
    List<Member> members,
  ) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Amount given', style: text.titleSmall),
        const SizedBox(height: 8),
        TextField(
          contextMenuBuilder: appContextMenuBuilder,
          controller: _amount,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'e.g. ½ tablet or 0.5 ml',
            counterText: '',
            helperText: 'Record the amount actually given.',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 18),
        Text('When was it given?', style: text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _OutcomeChip(
              label:
                  'Now · ${TimeOfDay.fromDateTime(care.now).format(context)}',
              selected: _givenAt == null,
              onPressed: () => setState(() => _givenAt = null),
            ),
            _OutcomeChip(
              label: switch (_givenAt) {
                final at? => at.format(context),
                null => 'Earlier today',
              },
              selected: _givenAt != null,
              onPressed: _pickTime,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Given by', style: text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final member in members)
              _OutcomeChip(
                label: member.isYou ? 'You' : member.name,
                selected: _memberId == member.id,
                onPressed: () => setState(() => _memberId = member.id),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text('How did it go? · optional', style: text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final outcome in DoseOutcome.values)
              _OutcomeChip(
                label: switch (outcome) {
                  DoseOutcome.smooth => 'Went smoothly',
                  DoseOutcome.partial => 'Partial dose',
                  DoseOutcome.vomited => 'Vomited',
                  DoseOutcome.lowAppetite => 'Low appetite',
                },
                selected: _outcome == outcome,
                onPressed: () => setState(() => _outcome = outcome),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// v14 summary: icon, label and value per row, on oat paper, hairlines
/// between.
class _SummaryRows extends StatelessWidget {
  const _SummaryRows({required this.rows});

  final List<(StrokeIconKind, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: paws.surfaces.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final (i, (icon, label, value)) in rows.indexed)
            Semantics(
              label: '$label: $value',
              excludeSemantics: true,
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i < rows.length - 1
                      ? Border(bottom: BorderSide(color: paws.hairline))
                      : null,
                ),
                child: Row(
                  children: [
                    StrokeIcon(icon, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 84,
                      child: Text(
                        label,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: text.bodyMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The guard: a second caregiver is stopped by a stamp naming who already
/// gave the dose and when. Logging is blocked; there is no "log anyway".
class _DoubleDoseSheet extends StatelessWidget {
  const _DoubleDoseSheet({required this.dose});

  final Dose dose;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final member = switch (dose.givenById) {
      final id? => care.memberById(id),
      null => null,
    };
    final pet = care.petById(dose.petId);
    final who = member?.name ?? 'Someone';
    final heading = dose.givenAt.isEmpty
        ? '$who already gave this dose'
        : '$who gave it at ${dose.givenAt}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: GivenStamp(
              who: who,
              time: dose.givenAt.isEmpty ? 'TODAY' : dose.givenAt,
            ),
          ),
          const SizedBox(height: 28),
          Text(heading, style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${pet.name}’s ${dose.name} is already in the log. '
            'Giving it again could be unsafe.',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          LedgerSheet(
            children: [
              LedgerLine(
                time: dose.givenAt.isEmpty ? '—' : dose.givenAt,
                title: dose.title,
                detail: '${pet.name} · $who',
                mark: LedgerMark.given,
                last: true,
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onSurface,
                foregroundColor: scheme.surface,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Don’t give it'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PawsRadii.cardValue),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PawsRadii.cardValue),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: selected ? tokens.brandDark : scheme.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
