import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:provider/provider.dart';

/// Shows today's doses and who has already given them.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  String? _petId;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final doses = care.doses
        .where((dose) => _petId == null || dose.petId == _petId)
        .toList();
    final given = doses.where((dose) => dose.status == DoseStatus.given).length;
    Dose? next;
    for (final dose in doses) {
      if (dose.status == DoseStatus.due) {
        next = dose;
        break;
      }
    }
    final slots = doses.length;
    final low = care.lowSupply;
    final left = slots - given;
    final summary = doses.isEmpty
        ? 'Nothing to give today.'
        : left == 0
        ? 'Every medicine today is given.'
        : '$given given. $left still to give.';
    final faces = care.members.length >= 3
        ? [care.members[1], care.members[2], care.members[0]]
        : care.members;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: care.sync,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayLabel(),
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text('Today', style: text.displaySmall),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Household, ${care.members.length} people in sync',
                  child: InkWell(
                    onTap: () => context.go(AppRoutes.household),
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 74,
                      height: 30,
                      child: Stack(
                        children: [
                          for (var i = 0; i < faces.length && i < 3; i++)
                            Positioned(
                              left: i * 22.0,
                              child: _memberAvatar(context, faces[i], size: 30),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (care.syncing || care.syncError != null) ...[
              const SizedBox(height: 12),
              Text(
                care.syncError ?? 'Loading the household.',
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (care.syncError != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: care.sync,
                    child: const Text('Try again'),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (next != null)
              SoftEnter(
                child: _NowCard(
                  dose: next,
                  pet: care.petById(next.petId),
                  time: _dueTime(next),
                  onPressed: () => _openDose(context, next!),
                ),
              )
            else if (doses.isNotEmpty)
              const SoftEnter(child: _CalmCard()),
            if (doses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(summary, style: text.bodyLarge),
            ],
            if (slots > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < slots; i++) ...[
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: i < given
                              ? scheme.primary
                              : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    if (i != slots - 1) const SizedBox(width: 4),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'All pets',
                    selected: _petId == null,
                    onPressed: () => setState(() => _petId = null),
                  ),
                  for (final pet in care.pets) ...[
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: pet.name,
                      species: pet.species,
                      selected: _petId == pet.id,
                      onPressed: () => setState(() => _petId = pet.id),
                    ),
                  ],
                ],
              ),
            ),
            if (low != null) ...[
              const SizedBox(height: 16),
              Material(
                color: tokens.warningBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: tokens.warningBorder),
                ),
                child: InkWell(
                  onTap: () => context.push(AppRoutes.medication(low.id)),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        StrokeIcon(
                          StrokeIconKind.refresh,
                          size: 18,
                          color: tokens.warning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${low.name} is running low',
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${low.dosesLeft} doses left · lasts until ${low.lastsUntil.split(',').first}',
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Refill',
                          style: text.bodyMedium?.copyWith(
                            color: tokens.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (doses.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Text(
                  _petId == null
                      ? 'Nothing is scheduled today.'
                      : 'Nothing is scheduled for this pet today.',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final part in DayPart.values) ...[
                if (doses.any((dose) => dose.part == part)) ...[
                  SectionLabel(_partLabel(part)),
                  _DoseGroup(
                    doses: doses.where((dose) => dose.part == part).toList(),
                    onDose: (dose) => _openDose(context, dose),
                  ),
                ],
              ],
          ],
          ),
        ),
      ),
    );
  }

  String _partLabel(DayPart part) => switch (part) {
    DayPart.morning => 'Morning',
    DayPart.afternoon => 'Afternoon',
    DayPart.evening => 'Evening',
  };

  String _dueTime(Dose dose) {
    final match = RegExp(r'\d{1,2}:\d{2} [AP]M').firstMatch(dose.subtitle);
    return match?.group(0) ?? 'soon';
  }

  Future<void> _openDose(BuildContext context, Dose dose) async {
    if (dose.status == DoseStatus.given) {
      await showDoubleDoseGuard(context, dose);
      return;
    }
    await showLogDoseSheet(context, dose);
  }
}

Widget _memberAvatar(BuildContext context, Member member, {double size = 24}) {
  final scheme = Theme.of(context).colorScheme;
  final tokens = context.paws;
  final (background, foreground) = switch (member.avatarTone) {
    AvatarTone.brand => (scheme.primary, scheme.onPrimary),
    AvatarTone.soft => (tokens.brandSoft, tokens.brandDark),
    AvatarTone.neutral => (tokens.neutral, scheme.onSurface),
  };
  return InitialsAvatar(
    label: member.initials,
    size: size,
    fontSize: member.isYou ? 11 : 13,
    background: background,
    foreground: foreground,
    borderColor: scheme.surface,
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.species,
  });

  final String label;
  final Species? species;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondary : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.secondary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (species != null) ...[
                  PetMark(species: species!, size: 22),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? scheme.onSecondary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoseGroup extends StatelessWidget {
  const _DoseGroup({required this.doses, required this.onDose});

  final List<Dose> doses;
  final ValueChanged<Dose> onDose;

  @override
  Widget build(BuildContext context) {
    final due = doses.length == 1 && doses.first.status == DoseStatus.due;
    if (due) {
      return _DueRow(dose: doses.first, onPressed: () => onDose(doses.first));
    }
    return SurfaceCard(
      child: Column(
        children: [
          for (var i = 0; i < doses.length; i++)
            _DoseTile(
              dose: doses[i],
              showDivider: i != doses.length - 1,
              onPressed: doses[i].status == DoseStatus.given
                  ? () => onDose(doses[i])
                  : null,
            ),
        ],
      ),
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({
    required this.dose,
    required this.showDivider,
    required this.onPressed,
  });

  final Dose dose;
  final bool showDivider;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final care = context.read<CareRepository>();
    final given = dose.status == DoseStatus.given;
    final member = dose.givenById == null
        ? null
        : care.memberById(dose.givenById!);

    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: tokens.divider))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: given ? scheme.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: given
                    ? null
                    : Border.all(color: scheme.outline, width: 1.5),
              ),
              child: given
                  ? StrokeIcon(
                      StrokeIconKind.check,
                      size: 16,
                      color: scheme.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dose.title,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    dose.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (member != null) _memberAvatar(context, member),
          ],
        ),
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.dose, required this.onPressed});

  final Dose dose;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    return SurfaceCard(
      borderColor: scheme.primary,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.primary, width: 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  dose.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.brandDark),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: Theme.of(context).textTheme.labelLarge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('I gave this'),
          ),
        ],
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.dose,
    required this.pet,
    required this.time,
    required this.onPressed,
  });

  final Dose dose;
  final Pet pet;
  final String time;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      borderColor: scheme.primary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Give this now',
            style: text.titleSmall?.copyWith(
              color: context.paws.brandDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              PetMark(species: pet.species, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pet.name} · $time',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('I gave this'),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button after you give the medicine.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CalmCard extends StatelessWidget {
  const _CalmCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing to give right now', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'You can rest. Later medicines stay in the list below.',
            style: text.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
