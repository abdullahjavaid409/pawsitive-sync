import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/layout/app_art_size.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/moment_art.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
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
    final primaryPet = care.primaryPet;
    final selectedPet = _petId == null ? null : care.tryPetById(_petId!);
    if (_petId != null && selectedPet == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _petId = null);
      });
    }
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
        ? null
        : left == 0
        ? 'All done for today.'
        : '$given of $slots given · $left left';
    final showHousehold = care.members.length > 1;
    final faces = care.members.length >= 3
        ? [care.members[1], care.members[2], care.members[0]]
        : care.members;
    final petLabel = selectedPet?.name ?? primaryPet?.name;
    final isEmpty = doses.isEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: care.hasApi ? care.sync : () async {},
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _TodayHeader(
                      petName: petLabel,
                      isEmpty: isEmpty,
                    ),
                  ),
                  if (showHousehold)
                    Semantics(
                      button: true,
                      label:
                          'Household, ${care.members.length} people helping',
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
                                  child: _memberAvatar(
                                    context,
                                    faces[i],
                                    size: 30,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (care.hasApi && (care.isConnected || care.syncError != null))
                _HouseholdSync(
                  syncing: care.syncing,
                  error: care.syncError,
                  onRetry: care.sync,
                ),
              const SizedBox(height: 20),
              _QuickActions(hasPet: primaryPet != null),
              const _RemindersBanner(),
              const SizedBox(height: 16),
              if (next != null)
                SoftEnter(
                  child: _NowCard(
                    dose: next,
                    pet: care.tryPetById(next.petId) ?? primaryPet!,
                    time: _dueTime(next),
                    onPressed: () => _openDose(context, next!),
                  ),
                )
              else if (doses.isNotEmpty)
                const SoftEnter(child: _CalmCard()),
              if (summary != null) ...[
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
              if (care.pets.length > 1) ...[
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
                          onPressed: () {
                            setState(() => _petId = pet.id);
                            if (!care.doses.any(
                              (dose) => dose.petId == pet.id,
                            )) {
                              AppLog.event('dose.empty', {'petId': pet.id});
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (low != null) ...[
                const SizedBox(height: 16),
                Material(
                  color: tokens.warningBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: tokens.warningBorder),
                  ),
                  child: InkWell(
                    onTap: () {
                      AppLog.event('medication.low_opened', {
                        'medicationId': low.id,
                        'dosesLeft': low.dosesLeft,
                      });
                      context.push(AppRoutes.medication(low.id));
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          MomentArt(
                            'medication.low',
                            size: appInlineArtSize(context),
                            announce: false,
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
                                  low.dosesLeft == 0
                                      ? 'None left · refill soon'
                                      : '${low.dosesLeft} ${low.dosesLeft == 1 ? 'dose' : 'doses'} left · until ${low.lastsUntil(care.now)}',
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
              if (isEmpty) ...[
                const SizedBox(height: 8),
                const SoftEnter(child: _HowItWorks()),
                SoftEnter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
                    child: _EmptyToday(
                      petName: selectedPet?.name ?? primaryPet?.name,
                      hasPet: primaryPet != null,
                      onAddMedicine: () {
                        AppLog.event('today.add_medicine');
                        context.push(AppRoutes.schedule);
                      },
                      onViewPet: () => context.go(AppRoutes.pets),
                      onInvite: () => care.isConnected
                          ? context.go(AppRoutes.household)
                          : context.push(AppRoutes.join),
                    ),
                  ),
                ),
              ]
              else ...[
                for (final part in DayPart.values) ...[
                  if (doses.any((dose) => dose.part == part)) ...[
                    _PartLabel(part),
                    _DoseGroup(
                      doses: doses.where((dose) => dose.part == part).toList(),
                      onDose: (dose) => _openDose(context, dose),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.schedule),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: StrokeIcon(
                    StrokeIconKind.plus,
                    size: 18,
                    color: scheme.primary,
                  ),
                  label: const Text('Add another medicine'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

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

class _PartLabel extends StatelessWidget {
  const _PartLabel(this.part);

  final DayPart part;

  @override
  Widget build(BuildContext context) {
    final name = switch (part) {
      DayPart.morning => 'morning',
      DayPart.afternoon => 'afternoon',
      DayPart.evening => 'evening',
    };
    final label = switch (part) {
      DayPart.morning => 'Morning',
      DayPart.afternoon => 'Afternoon',
      DayPart.evening => 'Evening',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          MomentArt(name, size: appPartArtSize(context), announce: false),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _HouseholdSync extends StatefulWidget {
  const _HouseholdSync({
    required this.syncing,
    required this.error,
    required this.onRetry,
  });

  final bool syncing;
  final String? error;
  final Future<void> Function() onRetry;

  @override
  State<_HouseholdSync> createState() => _HouseholdSyncState();
}

class _HouseholdSyncState extends State<_HouseholdSync> {
  var _started = false;
  var _showSynced = false;

  @override
  void didUpdateWidget(covariant _HouseholdSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncing) _started = true;
    if (_started &&
        oldWidget.syncing &&
        !widget.syncing &&
        widget.error == null) {
      setState(() => _showSynced = true);
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _showSynced = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final failed = widget.error != null;
    if (!widget.syncing && !failed && !_showSynced) {
      return const SizedBox.shrink();
    }
    final message = failed
        ? widget.error!
        : widget.syncing
        ? 'Loading the household.'
        : 'Household is up to date.';
    final art = failed
        ? 'household.sync_failed'
        : _showSynced
        ? 'household.synced'
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (art != null) ...[
                MomentArt(art, size: appInlineArtSize(context), announce: false),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  message,
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (failed)
            TextButton(
              onPressed: widget.onRetry,
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
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
              PetMark(
                species: pet.species,
                size: appPetMarkSize(context, compact: 56),
              ),
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
          Text('Nothing due right now', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Later doses stay in the list below.',
            style: text.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.isEmpty, this.petName});

  final bool isEmpty;
  final String? petName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = petName?.trim();
    final title = isEmpty
        ? 'Pet medicine, shared'
        : name == null || name.isEmpty
        ? 'Today\'s medicines'
        : '$name\'s medicines today';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greetingLabel(),
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(title, style: text.displaySmall),
        const SizedBox(height: 6),
        Text(dayLabel(), style: text.bodyMedium),
        const SizedBox(height: 10),
        Text(
          'See what\'s due today and who already gave it — so the same dose is never given twice.',
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Every main feature, one tap from home.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.hasPet});

  final bool hasPet;

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (hasPet)
        (
          StrokeIconKind.plus,
          'Add\nmedicine',
          () => context.push(AppRoutes.schedule),
        ),
      (StrokeIconKind.paw, 'My\npet', () => context.go(AppRoutes.pets)),
      (
        StrokeIconKind.people,
        'Family &\nhelpers',
        () => context.go(AppRoutes.household),
      ),
      (
        StrokeIconKind.file,
        'Vet\nreport',
        () => context.go(AppRoutes.reports),
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          Expanded(
            child: _QuickAction(
              icon: actions[i].$1,
              label: actions[i].$2,
              onPressed: () {
                AppLog.event('today.quick_action', {
                  'action': actions[i].$2.replaceAll('\n', ' '),
                });
                actions[i].$3();
              },
            ),
          ),
          if (i != actions.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final StrokeIconKind icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label.replaceAll('\n', ' '),
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.brandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: StrokeIcon(icon, size: 20, color: tokens.brandDark),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets people turn reminders on from home with one tap.
class _RemindersBanner extends StatefulWidget {
  const _RemindersBanner();

  @override
  State<_RemindersBanner> createState() => _RemindersBannerState();
}

class _RemindersBannerState extends State<_RemindersBanner> {
  bool _busy = false;

  Future<void> _turnOn() async {
    if (_busy) return;
    setState(() => _busy = true);
    final onboarding = context.read<OnboardingViewModel>();
    final care = context.read<CareRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final allowed = await DoseReminders.ask();
    await onboarding.saveReminders(allowed);
    if (allowed) await DoseReminders.scheduleNext(care);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          allowed
              ? 'Reminders are on.'
              : 'Reminders stay off. You can allow them in phone Settings.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final on = context.watch<OnboardingViewModel>().remindersOn;
    if (on) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: tokens.neutral,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _busy ? null : _turnOn,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                StrokeIcon(
                  StrokeIconKind.bell,
                  size: 20,
                  color: tokens.brandDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Get a reminder when a dose is due',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  _busy ? '…' : 'Turn on',
                  style: text.bodyMedium?.copyWith(
                    color: tokens.brandDark,
                    fontWeight: FontWeight.w600,
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

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    ('1', 'Add your pet\'s medicines'),
    ('2', 'Tap “I gave this” after each dose'),
    ('3', 'Everyone in your home sees the same list'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tokens = context.paws;

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works', style: text.titleMedium),
          const SizedBox(height: 12),
          for (final step in _steps) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.brandSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    step.$1,
                    style: text.titleSmall?.copyWith(color: tokens.brandDark),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      step.$2,
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (step != _steps.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _EmptyToday extends StatelessWidget {
  const _EmptyToday({
    required this.hasPet,
    required this.onAddMedicine,
    required this.onViewPet,
    required this.onInvite,
    this.petName,
  });

  final bool hasPet;
  final String? petName;
  final VoidCallback onAddMedicine;
  final VoidCallback onViewPet;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = petName?.trim();
    final title = !hasPet
        ? 'Waiting for your household'
        : name == null || name.isEmpty
        ? 'Nothing scheduled yet'
        : 'Nothing scheduled for $name yet';
    final body = !hasPet
        ? 'Ask whoever invited you to share the pet\'s medicine list. It will show up here.'
        : 'Add the medicines $name takes. They\'ll appear here each day.';

    return Column(
      children: [
        MomentArt('dose.empty', size: appEmptyStateArtSize(context)),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (hasPet) ...[
          FilledButton(
            onPressed: onAddMedicine,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Add first medicine'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onViewPet, child: const Text('View pet profile')),
        ] else
          OutlinedButton(
            onPressed: onInvite,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Open household'),
          ),
      ],
    );
  }
}
