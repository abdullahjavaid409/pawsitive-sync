import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:provider/provider.dart';

Future<void> showLogDoseSheet(BuildContext context, Dose dose) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _LogDoseSheet(dose: dose),
  );
}

Future<void> showDoubleDoseGuard(BuildContext context, Dose dose) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _DoubleDoseSheet(dose: dose),
  );
}

class _LogDoseSheet extends StatefulWidget {
  const _LogDoseSheet({required this.dose});

  final Dose dose;

  @override
  State<_LogDoseSheet> createState() => _LogDoseSheetState();
}

class _LogDoseSheetState extends State<_LogDoseSheet> {
  late int _amount;
  String _memberId = 'you';
  bool _now = true;
  DoseOutcome _outcome = DoseOutcome.smooth;

  @override
  void initState() {
    super.initState();
    _amount =
        int.tryParse(
          RegExp(r'\d+').firstMatch(widget.dose.amount)?.group(0) ?? '',
        ) ??
        1;
  }

  String get _unit {
    if (widget.dose.amount.contains('ml')) return 'ml';
    if (widget.dose.amount.contains('unit')) return 'units';
    if (widget.dose.amount.contains('mg')) return 'mg';
    if (widget.dose.amount.contains('drop')) return 'drop';
    return '';
  }

  int get _step => _unit == 'ml' ? 10 : 1;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final pet = care.petById(widget.dose.petId);
    final amountLabel = _unit.isEmpty ? '$_amount' : '$_amount $_unit';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Log ${widget.dose.name.toLowerCase()}',
                        style: text.headlineSmall,
                      ),
                      Text(
                        '${pet.name} · due ${_due(widget.dose)}',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: StrokeIcon(
                    StrokeIconKind.close,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Amount',
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                _StepButton(
                  label: 'Less',
                  icon: '−',
                  onPressed: () => setState(
                    () => _amount = (_amount - _step).clamp(_step, 500),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    amountLabel,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(fontSize: 20),
                  ),
                ),
                _StepButton(
                  label: 'More',
                  icon: '+',
                  onPressed: () => setState(
                    () => _amount = (_amount + _step).clamp(_step, 500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'When',
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.neutral,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: _WhenChip(
                        label: 'Now · 1:06 PM',
                        selected: _now,
                        onPressed: () => setState(() => _now = true),
                      ),
                    ),
                    Expanded(
                      child: _WhenChip(
                        label: 'Earlier…',
                        selected: !_now,
                        onPressed: () => setState(() => _now = false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Given by',
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final member in care.members.where(
                  (member) => member.role != MemberRole.sitter,
                ))
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _Giver(
                      member: member,
                      selected: _memberId == member.id,
                      onPressed: () => setState(() => _memberId = member.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text.rich(
              TextSpan(
                text: 'How did it go? ',
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                children: [
                  TextSpan(
                    text: 'Optional',
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final outcome in DoseOutcome.values)
                  _OutcomeChip(
                    label: _outcomeLabel(outcome),
                    selected: _outcome == outcome,
                    onPressed: () => setState(() => _outcome = outcome),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                care.logDose(
                  doseId: widget.dose.id,
                  memberId: _memberId,
                  amount: amountLabel,
                  timeLabel: _now ? '1:06 PM' : '12:40 PM',
                  outcome: _outcome,
                );
                Navigator.of(context).pop();
              },
              child: const Text('Log dose'),
            ),
            Center(
              child: TextButton(
                onPressed: () {
                  care.skipDose(widget.dose.id);
                  Navigator.of(context).pop();
                },
                child: const Text('Skip this dose'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _due(Dose dose) {
    final match = RegExp(r'\d{1,2}:\d{2} [AP]M').firstMatch(dose.subtitle);
    return match?.group(0) ?? 'now';
  }

  String _outcomeLabel(DoseOutcome outcome) => switch (outcome) {
    DoseOutcome.smooth => 'Went smoothly',
    DoseOutcome.partial => 'Partial dose',
    DoseOutcome.vomited => 'Vomited',
    DoseOutcome.lowAppetite => 'Low appetite',
  };
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.warningBg,
              shape: BoxShape.circle,
            ),
            child: StrokeIcon(StrokeIconKind.bell, color: tokens.warning),
          ),
          const SizedBox(height: 16),
          Text(
            '$who already gave this dose',
            style: text.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "${pet.name}'s dose was logged recently. Giving it again could be dangerous.",
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (member != null)
                  InitialsAvatar(
                    label: member.initials,
                    background: tokens.brandSoft,
                    foreground: tokens.brandDark,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dose.title, style: text.titleMedium),
                      Text(
                        'Given by $who · ${dose.subtitle}',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                StrokeIcon(
                  StrokeIconKind.check,
                  color: scheme.primary,
                  strokeWidth: 2.2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Got it, don't log"),
          ),
          TextButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              showLogDoseSheet(navigator.context, dose);
            },
            child: const Text('This is a separate dose'),
          ),
          Text(
            'Only log a second dose if your vet told you to.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Center(
            child: Text(icon, style: const TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }
}

class _WhenChip extends StatelessWidget {
  const _WhenChip({
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
    return Material(
      color: selected ? scheme.surfaceContainerLowest : Colors.transparent,
      elevation: selected ? 1 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Giver extends StatelessWidget {
  const _Giver({
    required this.member,
    required this.selected,
    required this.onPressed,
  });

  final Member member;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final (background, foreground) = switch (member.avatarTone) {
      AvatarTone.brand => (scheme.primary, scheme.onPrimary),
      AvatarTone.soft => (tokens.brandSoft, tokens.brandDark),
      AvatarTone.neutral => (tokens.neutral, scheme.onSurface),
    };
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(28),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: InitialsAvatar(
              label: member.initials,
              size: 48,
              fontSize: member.isYou ? 14 : 16,
              background: background,
              foreground: foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            member.name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
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
