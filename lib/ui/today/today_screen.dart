import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/layout/app_art_size.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/moment_art.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/care/add_care_event_sheet.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:provider/provider.dart';

/// Daily care leads with progress and the next useful action.
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
    final text = Theme.of(context).textTheme;
    // A removed pet falls back immediately, including the selector and summary.
    final selectedId = care.tryPetById(_petId ?? '')?.id;
    final selectedPet = selectedId == null ? null : care.tryPetById(selectedId);
    final doses = care.doses
        .where((d) => selectedId == null || d.petId == selectedId)
        .toList();
    final given = doses.where((d) => d.status == DoseStatus.given).length;
    final due = doses.where((d) => d.status == DoseStatus.due).toList();
    final upcoming = doses
        .where((d) => d.status == DoseStatus.upcoming)
        .toList();
    final next = due.firstOrNull ?? upcoming.firstOrNull;
    final low = care.medications
        .where((m) => m.isLow && (selectedId == null || m.petId == selectedId))
        .firstOrNull;
    final hasPet = care.primaryPet != null;
    final upcomingCare = care
        .upcomingCareEvents(withinDays: 60)
        .where((e) => selectedId == null || e.petId == selectedId)
        .take(5)
        .toList();

    void addMedicine() {
      AppLog.event('medication.add_opened', {'petId': selectedId ?? 'default'});
      context.push(
        selectedId == null
            ? AppRoutes.schedule
            : '${AppRoutes.schedule}?pet=$selectedId',
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: care.isConnected
              ? () => care.sync(force: true)
              : () async {},
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: carePagePaddingOf(context),
            children: [
              CarePageHeader(
                title: 'Today',
                subtitle: '${greetingLabel(care.now)} · ${dayLabel(care.now)}',
                action: _TodayHeaderActions(
                  isPro: care.isPro,
                  onUpgrade: care.isPro
                      ? null
                      : () {
                          AppLog.event('today.pro_badge_tapped');
                          context.push(AppRoutes.paywall);
                        },
                  onSettings: () {
                    AppLog.event('settings.opened');
                    context.push(AppRoutes.settings);
                  },
                ),
              ),
              if (care.hasApi && (care.isConnected || care.syncError != null))
                _HouseholdSync(
                  syncing: care.syncing,
                  error: care.syncError,
                  onRetry: () {
                    AppLog.event('household.sync_retry');
                    return care.sync(force: true);
                  },
                ),
              const SizedBox(height: 24),
              if (care.pets.isNotEmpty) ...[
                CarePetPicker(
                  pets: care.pets,
                  selectedId: selectedId,
                  includeAll: true,
                  onSelected: (id) {
                    AppLog.event('pet.filter', {'petId': id ?? 'all'});
                    setState(() => _petId = id);
                  },
                ),
                const SizedBox(height: 20),
              ],
              if (doses.isNotEmpty) ...[
                _DayProgress(
                  given: given,
                  total: doses.length,
                  due: due.length,
                ),
                if (next != null) ...[
                  const SizedBox(height: 16),
                          _NextDose(
                            dose: next,
                            pet: care.tryPetById(next.petId),
                            onLog: () => _openDose(context, next),
                    onDetails: () =>
                        context.push(AppRoutes.medication(next.medicationId)),
                  ),
                ],
                if (care.canShowLowSupplyAlerts && low != null) ...[
                  const SizedBox(height: 16),
                  _LowSupply(
                    medication: low,
                    onTap: () {
                      AppLog.event('pro.low_supply.opened', {
                        'medicationId': low.id,
                      });
                      context.push(AppRoutes.medication(low.id));
                    },
                  ),
                ],
                if (due.isNotEmpty &&
                    (care.isConnected || care.members.length > 1)) ...[
                  const SizedBox(height: 16),
                  _DoubleDoseAlert(
                    onCheckHousehold: () {
                      AppLog.event('double_dose.check_household');
                      context.go(AppRoutes.household);
                    },
                  ),
                ],
                if (care.pets.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  CareSectionHeader(
                    'Coming up',
                    action: 'Add event',
                    onAction: () =>
                        showAddCareEventSheet(context, petId: selectedId),
                  ),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    radius: 20,
                    child: Column(
                      children: [
                        if (upcomingCare.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              'Keep vet visits, vaccines and refills in one place.',
                            ),
                          ),
                        for (final (index, event) in upcomingCare.indexed)
                          _CareEventTile(
                            event: event,
                            pet: care.tryPetById(event.petId),
                            showDivider: index < upcomingCare.length - 1,
                            onRemove: () {
                              AppLog.event('care_event.dismissed', {
                                'eventId': event.id,
                                'kind': event.kind.name,
                              });
                              care.removeCareEvent(event.id);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                CareSectionHeader(
                  'Today’s schedule',
                  action: 'Add',
                  onAction: addMedicine,
                ),
                const SizedBox(height: 4),
                for (final part in DayPart.values)
                  if (doses.any((d) => d.part == part)) ...[
                    _PartLabel(part),
                    SurfaceCard(
                      radius: 20,
                      child: Column(
                        children: [
                          for (final (index, dose)
                              in doses.where((d) => d.part == part).indexed)
                            _DoseTile(
                              dose: dose,
                              showDivider:
                                  index <
                                  doses.where((d) => d.part == part).length - 1,
                              onPressed: () =>
                                  dose.status == DoseStatus.upcoming
                                  ? context.push(
                                      AppRoutes.medication(dose.medicationId),
                                    )
                                  : _openDose(context, dose),
                            ),
                        ],
                      ),
                    ),
                  ],
                const SizedBox(height: 24),
                const CareSectionHeader('Care shortcuts'),
                const SizedBox(height: 16),
                const _QuickActions(),
                const _RemindersBanner(),
              ] else ...[
                _StartCare(
                  pet: selectedPet ?? care.primaryPet,
                  onStart: hasPet
                      ? addMedicine
                      : () {
                          if (!care.canAddPet) {
                            AppLog.event('pet.add.blocked', {
                              'source': 'today',
                            });
                            context.push(AppRoutes.paywall);
                            return;
                          }
                          context.push(AppRoutes.addPet);
                        },
                ),
                if (care.pets.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  CareSectionHeader(
                    'Coming up',
                    action: 'Add event',
                    onAction: () =>
                        showAddCareEventSheet(context, petId: selectedId),
                  ),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    radius: 20,
                    child: Column(
                      children: [
                        if (upcomingCare.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              'Keep vet visits, vaccines and refills in one place.',
                            ),
                          ),
                        for (final (index, event) in upcomingCare.indexed)
                          _CareEventTile(
                            event: event,
                            pet: care.tryPetById(event.petId),
                            showDivider: index < upcomingCare.length - 1,
                            onRemove: () {
                              AppLog.event('care_event.dismissed', {
                                'eventId': event.id,
                                'kind': event.kind.name,
                              });
                              care.removeCareEvent(event.id);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const _QuickActions(),
                const _RemindersBanner(),
                const SizedBox(height: 28),
                Text('How it works', style: text.headlineSmall),
                const SizedBox(height: 16),
                const _SetupGuide(),
                if (!care.isConnected) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.join),
                    child: const Text('I have a household invite code'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDose(BuildContext context, Dose dose) async {
    AppLog.event('dose.tapped', {
      'doseId': dose.id,
      'status': dose.status.name,
    });
    if (dose.status == DoseStatus.given) {
      await showDoubleDoseGuard(context, dose);
      return;
    }
    await showLogDoseSheet(context, dose);
  }
}

class _TodayHeaderActions extends StatelessWidget {
  const _TodayHeaderActions({
    required this.isPro,
    required this.onUpgrade,
    required this.onSettings,
  });

  final bool isPro;
  final VoidCallback? onUpgrade;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CarePlanBadge(isPro: isPro, onUpgrade: onUpgrade),
        SizedBox(width: tokens.spacing.sm),
        IconButton(
          tooltip: 'Settings',
          onPressed: onSettings,
          style: IconButton.styleFrom(
            backgroundColor: tokens.surfaces.card,
            side: BorderSide(color: tokens.borders.subtle),
            minimumSize: Size.square(tokens.controlHeights.icon),
          ),
          icon: StrokeIcon(
            StrokeIconKind.settings,
            size: 21,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _DayProgress extends StatelessWidget {
  const _DayProgress({
    required this.given,
    required this.total,
    required this.due,
  });
  final int given;
  final int total;
  final int due;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tokens = context.paws;
    final complete = given == total;
    final remaining = total - given;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.surfaces.selected,
        borderRadius: BorderRadius.circular(tokens.radii.xxl),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.2;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A little care, every day',
                style: text.bodyMedium?.copyWith(color: tokens.brandDark),
              ),
              const SizedBox(height: 8),
              Text(
                complete
                    ? 'All cared for.'
                    : '$remaining ${remaining == 1 ? 'dose' : 'doses'} left today',
                style: text.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                complete
                    ? 'Every scheduled dose is logged.'
                    : due == 0
                    ? '$given of $total given. The rest are later.'
                    : '$given of $total given. $due ${due == 1 ? 'is' : 'are'} due.',
                style: text.bodyMedium,
              ),
            ],
          );
          final progress = Semantics(
            label: 'Daily progress',
            value: '$given of $total doses given',
            child: ExcludeSemantics(
              child: SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: total == 0 ? 0 : given / total,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .outlineVariant,
                      ),
                    ),
                    if (complete)
                      StrokeIcon(
                        StrokeIconKind.check,
                        size: 30,
                        color: tokens.brandDark,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(9),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$given', style: text.headlineSmall),
                              Text('of $total', style: text.bodySmall),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: 18),
                Align(alignment: Alignment.center, child: progress),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 16),
              progress,
            ],
          );
        },
      ),
    );
  }
}

class _NextDose extends StatelessWidget {
  const _NextDose({
    required this.dose,
    required this.pet,
    required this.onLog,
    required this.onDetails,
  });
  final Dose dose;
  final Pet? pet;
  final VoidCallback onLog;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDue = dose.status == DoseStatus.due;
    final uncertain = isDue && dose.givenById != null;
    return SurfaceCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  uncertain
                      ? 'Needs a check'
                      : isDue
                      ? 'Next dose'
                      : 'Later today',
                  style: text.titleSmall,
                ),
              ),
              StrokeIcon(
                StrokeIconKind.clock,
                size: 15,
                color: context.paws.brandDark,
              ),
              const SizedBox(width: 6),
              Text(
                dose.part.timeLabel,
                style: text.bodyMedium?.copyWith(color: context.paws.brandDark),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pet != null)
                PetPortrait(pet!, size: 56)
              else
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: StrokeIcon(
                    StrokeIconKind.paw,
                    size: 24,
                    color: context.paws.brandDark,
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dose.name, style: text.headlineSmall),
                    const SizedBox(height: 5),
                    Text(
                      '${pet?.name ?? 'Pet removed'}${dose.amount.isEmpty ? '' : ' · ${dose.amount}'}',
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (uncertain) ...[
            Text(
              dose.subtitle,
              style: text.bodyMedium?.copyWith(color: context.paws.warning),
            ),
            const SizedBox(height: 12),
          ],
          if (isDue)
            FilledButton.icon(
              onPressed: onLog,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: StrokeIcon(
                StrokeIconKind.check,
                size: 18,
                color: scheme.onPrimary,
              ),
              label: Text(uncertain ? 'Review dose' : 'Log dose'),
            )
          else
            OutlinedButton(
              onPressed: onDetails,
              child: const Text('View medicine'),
            ),
          if (isDue) ...[
            const SizedBox(height: 9),
            Text(
              uncertain
                  ? 'Confirm what happened before recording this dose.'
                  : 'Log it after you’ve given the medicine.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _PartLabel extends StatelessWidget {
  const _PartLabel(this.part);
  final DayPart part;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
    child: Row(
      children: [
        MomentArt(part.name, size: appPartArtSize(context), announce: false),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            part.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Text(part.timeLabel, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({
    required this.dose,
    required this.showDivider,
    required this.onPressed,
  });
  final Dose dose;
  final bool showDivider;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final given = dose.status == DoseStatus.given;
    final due = dose.status == DoseStatus.due;
    final uncertain = due && dose.givenById != null;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(bottom: BorderSide(color: scheme.outlineVariant))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: given ? scheme.primaryContainer : scheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: due ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                child: StrokeIcon(
                  uncertain
                      ? StrokeIconKind.alert
                      : given
                      ? StrokeIconKind.check
                      : StrokeIconKind.clock,
                  size: 16,
                  color: given || due
                      ? context.paws.brandDark
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dose.title, style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(dose.subtitle, style: text.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (due)
                Text(
                  uncertain ? 'Check' : 'Log',
                  style: text.titleSmall?.copyWith(
                    color: context.paws.brandDark,
                  ),
                )
              else if (given)
                const SizedBox.shrink()
              else
                StrokeIcon(
                  StrokeIconKind.chevronRight,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LowSupply extends StatelessWidget {
  const _LowSupply({required this.medication, required this.onTap});
  final Medication medication;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.paws.warningBg,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            StrokeIcon(
              StrokeIconKind.alert,
              size: 20,
              color: context.paws.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${medication.name}: ${medication.dosesLeft} doses left',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.paws.warning),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Refill',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: context.paws.warning),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StartCare extends StatelessWidget {
  const _StartCare({required this.pet, required this.onStart});
  final Pet? pet;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.paws.brandSoft,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet == null
                          ? 'Good care starts here.'
                          : 'A fresh start for ${pet!.name}.',
                      style: text.headlineSmall?.copyWith(
                        fontSize: 24,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      pet == null ? 'Bring their daily care into one place.' : 'Add their first medicine. We’ll keep the routine together.',
                      style: text.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (pet != null) ...[
                const SizedBox(width: 12),
                PetPortrait(pet!, size: 80),
              ],
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: StrokeIcon(
              StrokeIconKind.plus,
              size: 18,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            label: Text(pet == null ? 'Add a pet' : 'Add first medicine'),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();
  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        StrokeIconKind.paw,
        'My pet',
        'today.shortcut.pets',
        () => context.go(AppRoutes.pets),
      ),
      (
        StrokeIconKind.people,
        'Family & helpers',
        'today.shortcut.household',
        () => context.go(AppRoutes.household),
      ),
      (
        StrokeIconKind.file,
        'Vet report',
        'today.shortcut.reports',
        () => context.go(AppRoutes.reports),
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final action in actions)
          Expanded(
            child: Semantics(
              button: true,
              label: action.$2,
              excludeSemantics: true,
              child: InkWell(
                onTap: () {
                  AppLog.event(action.$3);
                  action.$4();
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: StrokeIcon(
                          action.$1,
                          size: 23,
                          color: context.paws.brandDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        action.$2,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SetupGuide extends StatelessWidget {
  const _SetupGuide();
  @override
  Widget build(BuildContext context) {
    const steps = [
      (
        StrokeIconKind.plus,
        'Build their routine',
        'Add each medicine and when it’s needed.',
      ),
      (StrokeIconKind.check, 'Log each dose', 'Confirm after you’ve given it.'),
      (
        StrokeIconKind.people,
        'Keep everyone in sync',
        'Your household sees who gave what.',
      ),
    ];
    return Column(
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StrokeIcon(step.$1, size: 22, color: context.paws.brandDark),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.$2,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.$3,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
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
                MomentArt(
                  art,
                  size: appInlineArtSize(context),
                  announce: false,
                ),
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
    AppLog.event('reminders.banner_tap');
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

/// Reddit's #1 pet-med pain: "Did someone already give it?"
class _DoubleDoseAlert extends StatelessWidget {
  const _DoubleDoseAlert({required this.onCheckHousehold});

  final VoidCallback onCheckHousehold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tokens = context.paws;
    return Material(
      color: tokens.warningBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.warningBorder),
      ),
      child: InkWell(
        onTap: onCheckHousehold,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StrokeIcon(
                StrokeIconKind.people,
                size: 20,
                color: tokens.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check before you give',
                      style: text.titleSmall?.copyWith(color: tokens.warning),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Someone else may have logged this dose. '
                      'Open Household to see who gave what today.',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

String _careDueLabel(String dueDay, DateTime now) {
  final parsed = DateTime.tryParse(dueDay);
  if (parsed == null) return dueDay;
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(parsed.year, parsed.month, parsed.day);
  final diff = due.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff < 7) return 'In $diff days';
  return dayLabel(parsed);
}

class _CareEventTile extends StatelessWidget {
  const _CareEventTile({
    required this.event,
    required this.pet,
    required this.showDivider,
    required this.onRemove,
  });

  final CareEvent event;
  final Pet pet;
  final bool showDivider;
  final VoidCallback onRemove;

  Future<bool> _confirmRemove(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove care event?'),
          content: Text('“${event.title}” will be removed from Coming up.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep event'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final due = _careDueLabel(event.dueDay, care.now);

    return Column(
      children: [
        Dismissible(
          key: ValueKey(event.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmRemove(context),
          onDismissed: (_) => onRemove(),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: scheme.errorContainer,
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: StrokeIcon(
                    StrokeIconKind.calendar,
                    size: 20,
                    color: context.paws.brandDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        '${event.kindLabel} · $due · ${pet.name}',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (event.note.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(event.note, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ${event.title}',
                  onPressed: () async {
                    if (await _confirmRemove(context)) onRemove();
                  },
                  icon: const StrokeIcon(StrokeIconKind.close, size: 18),
                ),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}
