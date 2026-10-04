import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/moment_art.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

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
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
  LogOutcome? _saved;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.dose.amount);
    _memberId = context.read<CareRepository>().you.id;
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
      setState(() => _error = 'Choose a time earlier today, or use Now.');
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
      setState(() => _error = 'Enter the amount that was given.');
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
    final saved = switch (outcome) {
      LogOutcome.given => await care.logDose(
        doseId: widget.dose.id,
        memberId: _memberId,
        amount: _amount.text.trim(),
        timeLabel: timeLabel,
        outcome: _outcome,
      ),
      LogOutcome.skipped => await care.skipDose(widget.dose.id),
      LogOutcome.uncertain => await care.markDoseUncertain(widget.dose.id),
    };
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
    if (_saved != null) {
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
                  _saved == LogOutcome.uncertain
                      ? StrokeIconKind.alert
                      : StrokeIconKind.check,
                  size: 28,
                  color: context.paws.brandDark,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                switch (_saved!) {
                  LogOutcome.given => 'Dose saved.',
                  LogOutcome.skipped => 'Skipped for today.',
                  LogOutcome.uncertain => 'Marked for a check.',
                },
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _saved == LogOutcome.uncertain
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
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
              child: Row(
                children: [
                  PetPortrait(pet, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Log ${widget.dose.name.toLowerCase()}',
                          style: text.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${pet.name} · ${widget.dose.timeLabel}',
                          style: text.bodyMedium,
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
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: AbsorbPointer(
                  absorbing: _busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                            style: text.bodyLarge,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text('Amount given', style: text.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
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
                      const SizedBox(height: 22),
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
                            label: _givenAt == null
                                ? 'Earlier today'
                                : _givenAt!.format(context),
                            selected: _givenAt != null,
                            onPressed: _pickTime,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
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
                              onPressed: () =>
                                  setState(() => _memberId = member.id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
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
                              onPressed: () =>
                                  setState(() => _outcome = outcome),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : () => _save(LogOutcome.given),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
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
                        : const Text('Log dose'),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _save(LogOutcome.uncertain),
                        child: const Text('Not sure if given'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _save(LogOutcome.skipped),
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
}

class _DoubleDoseSheet extends StatelessWidget {
  const _DoubleDoseSheet({required this.dose});

  final Dose dose;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final member = dose.givenById == null
        ? null
        : care.memberById(dose.givenById!);
    final pet = care.petById(dose.petId);
    final who = member?.name ?? 'Someone';

    final detail =
        '${pet.name}\'s ${dose.name.toLowerCase()} was already logged. Giving it again could be unsafe.';
    final when = [
      'Given by $who',
      pet.name,
      if (dose.givenAt.isNotEmpty) dose.givenAt,
    ].join(' · ');

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
          const SizedBox(height: 16),
          const MomentArt('dose.already', size: 120),
          const SizedBox(height: 16),
          Text('$who already gave this dose', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            detail,
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurface,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                InitialsAvatar(
                  label: member?.initials ?? '?',
                  size: 40,
                  fontSize: 16,
                  background: tokens.brandSoft,
                  foreground: tokens.brandDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dose.title, style: text.titleMedium),
                      const SizedBox(height: 1),
                      Text(when, style: text.bodyMedium),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: StrokeIcon(
                    StrokeIconKind.check,
                    size: 14,
                    color: scheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.secondary,
              foregroundColor: scheme.onSecondary,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Got it, don't log"),
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
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
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
