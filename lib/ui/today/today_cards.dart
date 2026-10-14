import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/ledger.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/press_scale.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Small uppercase label above a title or inside a card ("TODAY'S ROUNDS").
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color ?? Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

/// The day at a glance: "3/6 doses given" and one pocket per dose, in time
/// order. Calm colours: green given, blue due, amber to check, quiet later.
class TodayRounds extends StatelessWidget {
  const TodayRounds({super.key, required this.doses, required this.onPressed});

  final List<Dose> doses;
  final void Function(Dose dose) onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final given = doses.where((d) => d.status == DoseStatus.given).length;
    final ordered = [...doses]
      ..sort((a, b) => a.minuteOrDefault - b.minuteOrDefault);
    return _Card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Today’s rounds'),
          const SizedBox(height: 6),
          Semantics(
            label: '$given of ${doses.length} doses given',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$given',
                  style: text.displaySmall?.copyWith(
                    fontFamily: PawsTypeStyle.numberFamily,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  '/${doses.length}',
                  style: text.titleLarge?.copyWith(
                    fontFamily: PawsTypeStyle.numberFamily,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Text('doses given', style: text.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              for (final dose in ordered)
                _Pocket(dose: dose, onPressed: () => onPressed(dose)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pocket extends StatelessWidget {
  const _Pocket({required this.dose, required this.onPressed});

  final Dose dose;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final states = context.paws.states;
    final unsure = dose.status == DoseStatus.due && dose.givenById != null;
    final (fill, edge, mark) = switch (dose.status) {
      DoseStatus.given => (states.success, states.success, states.onSuccess),
      _ when unsure => (
        states.warningContainer,
        context.paws.amber,
        states.onWarning,
      ),
      DoseStatus.due => (
        scheme.primaryContainer,
        scheme.primary,
        scheme.primary,
      ),
      _ => (scheme.surfaceContainer, scheme.surfaceContainer, scheme.outline),
    };
    final words = switch (dose.status) {
      DoseStatus.given => 'given',
      _ when unsure => 'needs a check',
      DoseStatus.due => 'due now',
      _ => 'later',
    };
    return Semantics(
      button: true,
      label: '${dose.name}, ${dose.timeLabel}, $words',
      excludeSemantics: true,
      onTap: onPressed,
      child: PressScale(
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: edge, width: 1.5),
                  ),
                  child: dose.status == DoseStatus.given
                      ? StrokeIcon(StrokeIconKind.check, size: 20, color: mark)
                      : Container(
                          width: 18,
                          height: 8,
                          decoration: BoxDecoration(
                            color: mark.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                Text(
                  dose.shortTime,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What needs doing now, answered in one sentence, with the one action.
/// Shows the pet's own photo when there is one; never drawn art.
class TodayHero extends StatelessWidget {
  const TodayHero({
    super.key,
    required this.dose,
    required this.pet,
    required this.lastGiven,
    required this.onLog,
    required this.onDetails,
  });

  /// Null when everything today is logged.
  final Dose? dose;
  final Pet? pet;

  /// Who already gave this medicine earlier today, e.g. "Sara gave the
  /// morning one at 8:02 AM". Empty when nobody has.
  final String lastGiven;
  final VoidCallback onLog;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final dose = this.dose;
    final pet = this.pet;
    final photo = pet?.photoPath;
    final petName = pet?.name ?? 'Your pet';

    final isDue = dose?.status == DoseStatus.due;
    final unsure = isDue && dose?.givenById != null;
    final (chip, chipColor) = switch (dose) {
      null => ('All cared for', context.paws.states.success),
      _ when unsure => ('Needs a check', context.paws.warning),
      _ when isDue => ('Due now', scheme.primary),
      _ => ('Later today', scheme.onSurfaceVariant),
    };
    final headline = switch (dose) {
      null => 'All cared for.',
      final d when unsure => '$petName’s ${d.name} needs a check.',
      final d when isDue => '$petName’s ${d.name} hasn’t been given yet.',
      final d => '$petName’s ${d.name} is next.',
    };
    final details = [
      if (dose != null && dose.amount.isNotEmpty) dose.amount,
      if (unsure) dose!.subtitle else if (lastGiven.isNotEmpty) lastGiven,
      if (dose == null) 'Every dose today is in the log.',
    ].join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PawsRadii.cardValue + 4),
        boxShadow: PawsElevation.hero(Theme.of(context).brightness),
      ),
      child: Material(
        color: context.paws.surfaces.card,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(PawsRadii.cardValue + 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photo != null)
              SizedBox(
                height: 176,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: ResizeImage(
                        FileImage(File(photo)),
                        width:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      semanticLabel: 'Photo of $petName',
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: scheme.primaryContainer),
                    ),
                    if (dose != null)
                      Positioned(
                        left: 14,
                        top: 14,
                        child: _StatusChip(
                          label: chip,
                          time: dose.timeLabel,
                          color: chipColor,
                          onPhoto: true,
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (photo == null && dose != null) ...[
                    Row(
                      children: [
                        if (pet != null) PetPortrait(pet, size: 44),
                        if (pet != null) const SizedBox(width: 12),
                        Flexible(
                          child: _StatusChip(
                            label: chip,
                            time: dose.timeLabel,
                            color: chipColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(headline, style: text.headlineMedium),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(details, style: text.bodyMedium),
                  ],
                  if (dose != null) ...[
                    const SizedBox(height: 18),
                    if (isDue)
                      GaveItButton(
                        onPressed: onLog,
                        label: unsure ? 'Review dose' : 'Gave it',
                      )
                    else
                      OutlinedButton(
                        onPressed: onDetails,
                        child: const Text('View medicine'),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.time,
    required this.color,
    this.onPhoto = false,
  });

  final String label;
  final String? time;
  final Color color;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: onPhoto
            ? scheme.surface.withValues(alpha: 0.88)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: text.labelLarge?.copyWith(
                color: onPhoto ? scheme.onSurface : color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (time != null) ...[
            Text(
              ' · ',
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Text(
              time!,
              style: text.labelLarge?.copyWith(
                color: onPhoto ? scheme.onSurface : color,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Every dose today, grouped by time: what it is, for whom, and who gave it.
class TodayLog extends StatelessWidget {
  const TodayLog({
    super.key,
    required this.care,
    required this.doses,
    required this.onPressed,
    required this.onAdd,
  });

  final CareRepository care;
  final List<Dose> doses;
  final void Function(Dose dose) onPressed;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ordered = [...doses]
      ..sort((a, b) => a.minuteOrDefault - b.minuteOrDefault);
    final left = doses.where((d) => d.status != DoseStatus.given).length;
    final groups = <String, List<Dose>>{};
    for (final dose in ordered) {
      groups.putIfAbsent(dose.timeLabel, () => []).add(dose);
    }
    return _Card(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Today’s log', style: text.headlineSmall)),
                Text(
                  left == 0
                      ? 'All given'
                      : '$left ${left == 1 ? 'dose' : 'doses'} left today',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          for (final MapEntry(key: time, value: items) in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 2),
              child: Text(
                time,
                style: text.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            for (final dose in items)
              _LogRow(
                key: ValueKey(dose.id),
                care: care,
                dose: dose,
                onPressed: () => onPressed(dose),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: PressScale(
              child: TextButton.icon(
                onPressed: onAdd,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const StrokeIcon(StrokeIconKind.plus, size: 18),
                label: const Text('Add medicine'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    super.key,
    required this.care,
    required this.dose,
    required this.onPressed,
  });

  final CareRepository care;
  final Dose dose;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pet = care.tryPetById(dose.petId)?.name ?? '';
    final given = dose.status == DoseStatus.given;
    final due = dose.status == DoseStatus.due;
    final unsure = due && dose.givenById != null;
    final giver = switch (dose.givenById) {
      final id? => care.memberById(id),
      null => null,
    };
    final who = giver == null ? '' : (giver.isYou ? 'You' : giver.name);
    final detail = switch ((given, unsure)) {
      (true, _) when who.isNotEmpty => '$pet · $who, ${dose.givenAt}',
      (_, true) => dose.subtitle,
      _ => pet,
    };
    final words = given
        ? 'given by $who at ${dose.givenAt}'
        : unsure
        ? 'needs a check'
        : due
        ? 'due now'
        : 'later';
    return Semantics(
      button: true,
      label: '${dose.title}, $detail, ${dose.timeLabel}, $words',
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                _MedicineTile(dose: dose),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dose.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: (given ? text.bodyLarge : text.titleMedium)
                            ?.copyWith(
                              color: given ? scheme.onSurfaceVariant : null,
                            ),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (given && giver != null)
                  _GiverBadge(member: giver)
                else
                  _StatePill(
                    label: unsure
                        ? 'Check'
                        : due
                        ? 'Due'
                        : 'Later',
                    tone: unsure
                        ? _PillTone.warning
                        : due
                        ? _PillTone.brand
                        : _PillTone.quiet,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A recognisable shape per medicine kind, read from the dose unit:
/// a syringe for units, a drop for millilitres, a pill otherwise.
class _MedicineTile extends StatelessWidget {
  const _MedicineTile({required this.dose});

  final Dose dose;

  @override
  Widget build(BuildContext context) {
    final amount = dose.amount.toLowerCase();
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final (icon, tint, ink) = amount.contains('unit')
        ? (
            PhosphorIconsDuotone.syringe,
            scheme.primaryContainer,
            scheme.primary,
          )
        : amount.contains('ml')
        ? (
            PhosphorIconsDuotone.drop,
            paws.states.unsureContainer,
            paws.states.unsure,
          )
        : (PhosphorIconsDuotone.pill, paws.warningBg, paws.warningIcon);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExcludeSemantics(child: PhosphorIcon(icon, size: 22, color: ink)),
    );
  }
}

class _GiverBadge extends StatelessWidget {
  const _GiverBadge({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final (bg, fg) = switch (member.avatarTone) {
      AvatarTone.brand => (scheme.primary, scheme.onPrimary),
      AvatarTone.soft => (tokens.brandSoft, tokens.brandDark),
      AvatarTone.neutral => (tokens.neutral, scheme.onSurface),
    };
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(
              // "You" or "SM" don't fit 32 pt; one letter reads cleanly.
              member.isYou
                  ? 'Y'
                  : member.initials.characters.take(1).toString(),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.states.success,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.surfaces.card, width: 2),
              ),
              child: StrokeIcon(
                StrokeIconKind.check,
                size: 9,
                color: tokens.states.onSuccess,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PillTone { brand, warning, quiet }

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.tone});

  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final (bg, fg) = switch (tone) {
      _PillTone.brand => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _PillTone.warning => (paws.warningBg, paws.warning),
      _PillTone.quiet => (Colors.transparent, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      SurfaceCard(padding: padding, child: child);
}

extension on Dose {
  int get minuteOrDefault => minute < 0 ? part.defaultMinute : minute;

  /// "8 AM" / "1:30 PM" for a pocket label; 24 h clocks keep "08:00".
  String get shortTime => timeLabel.replaceFirst(':00 ', ' ');
}
