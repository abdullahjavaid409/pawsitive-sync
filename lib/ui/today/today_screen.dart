import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/day_label.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/celebration.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/pro_prompts.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/care/add_care_event_sheet.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:pawsitive_sync/ui/today/engagement_cards.dart';
import 'package:pawsitive_sync/ui/today/today_cards.dart';
import 'package:provider/provider.dart';

/// Daily care leads with progress and the next useful action.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  String? _petId;
  late final AppLifecycleListener _lifecycle;
  Timer? _idlePrompt;

  /// Quiet time on Today before a queued upgrade prompt may open.
  static const idleDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    DoseReminders.pendingOpen.addListener(_openFromNotification);
    // Queued upgrade prompts only ever open on a fresh visit (launch or
    // return to the app) — never right after a sheet closes.
    _lifecycle = AppLifecycleListener(onResume: _scheduleIdlePrompt);
    // A cold-start tap is already waiting before Today first builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openFromNotification();
      _scheduleIdlePrompt();
    });
  }

  @override
  void dispose() {
    DoseReminders.pendingOpen.removeListener(_openFromNotification);
    _lifecycle.dispose();
    _idlePrompt?.cancel();
    _celebrations.dispose();
    super.dispose();
  }

  /// Opens a queued upgrade prompt only when the person is idle on Today:
  /// nothing open on top, no notification tap waiting, and no dose to give
  /// right now (a due dose is a safety path — never covered by a paywall).
  /// Checked again after [idleDelay], so starting to use the app cancels it.
  void _scheduleIdlePrompt() {
    _idlePrompt?.cancel();
    if (!_idle()) return;
    _idlePrompt = Timer(idleDelay, () async {
      if (!_idle()) return;
      final care = context.read<CareRepository>();
      final trigger = await ProPrompts.takeIdle(now: care.now);
      if (trigger == null || !mounted || !_idle()) return;
      // billing.paywall.opened reason=<trigger> from=idle_prompt.
      unawaited(
        context.push(
          AppRoutes.paywallWith(reason: trigger, from: 'idle_prompt'),
        ),
      );
    });
  }

  bool _idle() {
    if (!mounted) return false;
    final care = context.read<CareRepository>();
    if (care.isPro) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    // Another tab is showing (Today kept alive offstage): not idle here.
    if (!TickerMode.valuesOf(context).enabled) return false;
    if (Navigator.of(context, rootNavigator: true).canPop()) return false;
    if (DoseReminders.pendingOpen.value != null) return false;
    // "Not sure" doses wait for a check, not a dose: they don’t block.
    return !care.doses.any(
      (d) => d.status == DoseStatus.due && d.givenById == null,
    );
  }

  /// A notification tap opens that dose’s log sheet (or the "already
  /// given" guard); a message (e.g. "Logged …") shows as a snackbar.
  void _openFromNotification() {
    final open = DoseReminders.pendingOpen.value;
    if (open == null || !mounted) return;
    DoseReminders.pendingOpen.value = null;
    final care = context.read<CareRepository>();
    final message = open.message;
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    final doseId = open.doseId;
    if (doseId == null) return;
    final dose = care.doseById(doseId);
    if (dose == null) {
      AppLog.event('reminders.open_missing', {'doseId': doseId});
      return;
    }
    AppLog.unawaitedLogged(_openDose(context, dose), 'reminders.open_failed');
  }

  /// Bumped after a dose is logged as given: confetti, toast and a haptic.
  final _celebrations = ValueNotifier<int>(0);

  /// The dose the toast is about, so its Undo takes back that one.
  String? _celebratedDoseId;

  /// "Sara gave the morning one at 8:02 AM": the same medicine given earlier
  /// today, so a second person doesn't give the next dose twice.
  String _lastGiven(CareRepository care, List<Dose> doses, Dose? next) {
    if (next == null) return '';
    for (final dose in doses.reversed) {
      if (dose.id == next.id ||
          dose.medicationId != next.medicationId ||
          dose.status != DoseStatus.given) {
        continue;
      }
      final id = dose.givenById;
      final giver = id == null ? null : care.memberById(id);
      final who = giver == null
          ? 'Someone'
          : (giver.isYou ? 'You' : giver.name);
      final when = dose.givenAt.isEmpty ? '' : ' at ${dose.givenAt}';
      return '$who gave the ${dose.part.label.toLowerCase()} one$when';
    }
    return '';
  }

  // Tab screen: rebuilds on data changes only while visible.
  @override
  Widget build(BuildContext context) => CareTabBuilder(builder: _build);

  Widget _build(BuildContext context, CareRepository care) {
    final text = Theme.of(context).textTheme;
    // A removed pet falls back immediately, including the selector and summary.
    final selectedId = care.tryPetById(_petId ?? '')?.id;
    final selectedPet = selectedId == null ? null : care.tryPetById(selectedId);
    final doses = care.doses
        .where((d) => selectedId == null || d.petId == selectedId)
        .toList();
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

    // Navigation is logged by AppRouteObserver.
    void openFromToday(Dose dose) => dose.status == DoseStatus.upcoming
        ? context.push(AppRoutes.medication(dose.medicationId))
        : _openDose(context, dose);

    // Logged as nav.push to=/schedule; the save logs the pet.
    void addMedicine() {
      context.push(
        selectedId == null
            ? AppRoutes.schedule
            : '${AppRoutes.schedule}?pet=$selectedId',
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              // One line: household.synced / sync_skipped / sync_failed with
              // source=pull_refresh.
              onRefresh: () => care.sync(force: true, source: 'pull_refresh'),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: carePagePaddingOf(context),
                children: [
                  CarePageHeader(
                    title: 'Today',
                    subtitle: dayLabel(care.now),
                    action: _TodayHeaderActions(
                      isPro: care.isPro,
                      onUpgrade: care.isPro
                          ? null
                          : () {
                              context.push(
                                AppRoutes.paywallWith(
                                  reason: 'settings',
                                  from: 'pro_badge',
                                ),
                              );
                            },
                      // Logged as nav.push to=/settings.
                      onSettings: () => context.push(AppRoutes.settings),
                    ),
                  ),
                  if (care.hasApi &&
                      (care.isConnected || care.syncError != null))
                    _HouseholdSync(
                      syncing: care.syncing,
                      error: care.syncError,
                      onRetry: () => care.sync(force: true, source: 'retry'),
                    ),
                  const SizedBox(height: 24),
                  // One pet: nothing to filter, so no picker.
                  if (care.pets.length > 1) ...[
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
                    // Hero first: the one answer and the one action.
                    TodayHero(
                      dose: next,
                      pet:
                          care.tryPetById(next?.petId ?? selectedId ?? '') ??
                          care.primaryPet,
                      lastGiven: _lastGiven(care, doses, next),
                      others: [
                        for (final d in due)
                          if (d.id != next?.id) d,
                      ],
                      petOf: (d) => care.tryPetById(d.petId),
                      onAddPhoto: () {
                        final pet = next == null
                            ? null
                            : care.tryPetById(next.petId);
                        if (pet != null) {
                          context.push(AppRoutes.editPet(pet.id));
                        }
                      },
                      onOpen: openFromToday,
                      onLog: () {
                        if (next != null) _openDose(context, next);
                      },
                      onDetails: () {
                        if (next != null) {
                          context.push(AppRoutes.medication(next.medicationId));
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // One dose: the hero already says it all.
                    if (doses.length > 1) ...[
                      const SizedBox(height: 16),
                      TodayRounds(doses: doses, onPressed: openFromToday),
                    ],
                    const CareDaysNote(),
                    TodayMoments(care: care),
                    if (care.lockedMedications.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _RemindersNeedPro(
                        medications: care.lockedMedications,
                        // billing.paywall.opened reason=more_dose_times from=today_locked.
                        onTap: () => context.push(
                          AppRoutes.paywallWith(
                            reason: 'more_dose_times',
                            from: 'today_locked',
                          ),
                        ),
                      ),
                    ],
                    if (care.canShowLowSupplyAlerts && low != null) ...[
                      const SizedBox(height: 16),
                      _LowSupply(
                        medication: low,
                        // Logged as nav.push to=/medication/:id.
                        onTap: () => context.push(AppRoutes.medication(low.id)),
                      ),
                    ],
                    // Free: the same moment, honestly framed as what Pro adds.
                    if (!care.canShowLowSupplyAlerts && low != null) ...[
                      _LowSupplyTeaser(
                        key: ValueKey('low-teaser-${low.id}'),
                        medication: low,
                      ),
                    ],
                    const SizedBox(height: 16),
                    TodayLog(
                      care: care,
                      doses: doses,
                      onAdd: addMedicine,
                      onPressed: openFromToday,
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
                      if (upcomingCare.isEmpty)
                        // Nothing to draw a box around: one quiet line instead.
                        Text(
                          'Vet visits, vaccines and refills show here.',
                          style: text.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        )
                      else
                        SurfaceCard(
                          child: Column(
                            children: [
                              for (final (index, event) in upcomingCare.indexed)
                                _CareEventTile(
                                  event: event,
                                  pet: care.tryPetById(event.petId),
                                  showDivider: index < upcomingCare.length - 1,
                                  // care_event.removed is logged by the repository.
                                  onRemove: () {
                                    AppLog.unawaitedLogged(
                                      care.removeCareEvent(event.id),
                                      'care_event.remove_failed',
                                      {'eventId': event.id},
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    const _RemindersBanner(),
                  ] else ...[
                    TodayStart(
                      pet: selectedPet ?? care.primaryPet,
                      onStart: hasPet
                          ? addMedicine
                          : () {
                              if (!care.canAddPet) {
                                // billing.paywall.opened from=add_pet_today.
                                context.push(
                                  AppRoutes.paywallWith(
                                    reason: 'second_pet',
                                    from: 'add_pet_today',
                                  ),
                                );
                                return;
                              }
                              context.push(AppRoutes.addPet);
                            },
                    ),
                    // A course that just ended may leave nothing scheduled today.
                    TodayMoments(care: care),
                    if (care.pets.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      CareSectionHeader(
                        'Coming up',
                        action: 'Add event',
                        onAction: () =>
                            showAddCareEventSheet(context, petId: selectedId),
                      ),
                      const SizedBox(height: 8),
                      if (upcomingCare.isEmpty)
                        // Nothing to draw a box around: one quiet line instead.
                        Text(
                          'Vet visits, vaccines and refills show here.',
                          style: text.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        )
                      else
                        SurfaceCard(
                          child: Column(
                            children: [
                              for (final (index, event) in upcomingCare.indexed)
                                _CareEventTile(
                                  event: event,
                                  pet: care.tryPetById(event.petId),
                                  showDivider: index < upcomingCare.length - 1,
                                  // care_event.removed is logged by the repository.
                                  onRemove: () {
                                    AppLog.unawaitedLogged(
                                      care.removeCareEvent(event.id),
                                      'care_event.remove_failed',
                                      {'eventId': event.id},
                                    );
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
          Positioned.fill(
            child: CelebrationLayer(
              trigger: _celebrations,
              message: care.isConnected
                  ? 'Logged for everyone.'
                  : 'Dose logged.',
              // Only while the dose is on this phone alone (see canUndoDose).
              onUndo: switch (_celebratedDoseId) {
                final id? when care.canUndoDose(id) => () => care.undoDose(id),
                _ => null,
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Logged as nav.push to the sheet it opens (log_dose / dose_already).
  Future<void> _openDose(BuildContext context, Dose dose) async {
    if (dose.status == DoseStatus.given) {
      await showDoubleDoseGuard(context, dose);
      return;
    }
    final care = context.read<CareRepository>();
    final wasUncertain =
        care.loggedDose(dose.id, dayKey(care.now))?.outcome ==
        LogOutcome.uncertain;
    await showLogDoseSheet(context, dose);
    if (!context.mounted) return;
    if (care.loggedDose(dose.id, dayKey(care.now))?.outcome ==
        LogOutcome.given) {
      _celebratedDoseId = dose.id;
      _celebrations.value++;
    }
    if (care.isPro || wasUncertain) return;
    // Just marked "not sure": the moment shared care answers — remembered
    // for the next idle visit to Today, once ever, capped.
    final nowUncertain =
        care.loggedDose(dose.id, dayKey(care.now))?.outcome ==
        LogOutcome.uncertain;
    if (!nowUncertain) return;
    // Never shown now (the person is mid-care); queued for an idle moment.
    await ProPrompts.queue(ProPrompts.uncertain);
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
      crossAxisAlignment: CrossAxisAlignment.center,
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

/// Free users: a medicine is running low. Says what Pro adds (a heads-up
/// before it runs out) and opens the refill paywall; dismissible per
/// low-supply episode, so it never nags.
class _LowSupplyTeaser extends StatefulWidget {
  const _LowSupplyTeaser({super.key, required this.medication});
  final Medication medication;

  @override
  State<_LowSupplyTeaser> createState() => _LowSupplyTeaserState();
}

class _LowSupplyTeaserState extends State<_LowSupplyTeaser> {
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    final care = context.read<CareRepository>();
    final lowNow = {
      for (final m in care.medications)
        if (m.isLow) m.id,
    };
    ProPrompts.lowDismissed(lowNow).then((dismissed) {
      if (!mounted) return;
      final hidden = dismissed.contains(widget.medication.id);
      setState(() => _hidden = hidden);
      if (!hidden) {
        AppLog.event('billing.low_supply_teaser.shown', {
          'medicationId': widget.medication.id,
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final m = widget.medication;
    final left = m.dosesLeft == 1 ? '1 dose left' : '${m.dosesLeft} doses left';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: context.paws.warningBg,
        borderRadius: BorderRadius.circular(PawsRadii.cardValue),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              StrokeIcon(
                StrokeIconKind.alert,
                size: 20,
                color: context.paws.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m.name} is running low · $left',
                      style: text.bodyMedium?.copyWith(
                        color: context.paws.warning,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pro sends a heads-up before it runs out.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                // billing.paywall.opened reason=refill from=low_supply_teaser.
                onPressed: () => context.push(
                  AppRoutes.paywallWith(
                    reason: 'refill',
                    from: 'low_supply_teaser',
                  ),
                ),
                child: const Text('See Pro'),
              ),
              IconButton(
                tooltip: 'Hide',
                icon: StrokeIcon(
                  StrokeIconKind.close,
                  size: 16,
                  color: context.paws.warning,
                ),
                onPressed: () {
                  setState(() => _hidden = true);
                  ProPrompts.dismissLow(m.id);
                },
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
    borderRadius: BorderRadius.circular(PawsRadii.cardValue),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PawsRadii.cardValue),
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

/// A medicine saved over Free’s limits (see [Medication.needsPro]): its
/// doses stay on Today and log as usual; only its reminders wait for Pro.
class _RemindersNeedPro extends StatelessWidget {
  const _RemindersNeedPro({required this.medications, required this.onTap});
  final List<Medication> medications;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final names = medications.length == 1
        ? medications.single.name
        : '${medications.length} medicines';
    return Material(
      color: context.paws.warningBg,
      borderRadius: BorderRadius.circular(PawsRadii.cardValue),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PawsRadii.cardValue),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              StrokeIcon(
                StrokeIconKind.lock,
                size: 20,
                color: context.paws.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$names: reminders paused on Free. Doses still log.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.paws.warning),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'See Pro',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: context.paws.warning),
              ),
            ],
          ),
        ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2;
        final columns = narrow ? 2 : actions.length;
        final gap = context.paws.spacing.sm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: Semantics(
                  button: true,
                  label: action.$2,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () {
                      AppLog.event(action.$3);
                      action.$4();
                    },
                    borderRadius: BorderRadius.circular(context.paws.radii.lg),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.paws.spacing.xs,
                        vertical: context.paws.spacing.sm,
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(context.paws.spacing.md),
                            decoration: BoxDecoration(
                              color: context.paws.surfaces.card,
                              borderRadius: context.paws.radii.optionShape,
                              border: Border.all(
                                color: context.paws.borders.subtle,
                              ),
                            ),
                            child: StrokeIcon(
                              action.$1,
                              size: 23,
                              color: context.paws.brandDark,
                            ),
                          ),
                          SizedBox(height: context.paws.spacing.sm + 2),
                          Text(
                            action.$2,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
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
      },
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
  Timer? _hideSynced;

  @override
  void didUpdateWidget(covariant _HouseholdSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncing) _started = true;
    if (_started &&
        oldWidget.syncing &&
        !widget.syncing &&
        widget.error == null) {
      // build() follows didUpdateWidget, so no setState needed here.
      _showSynced = true;
      _hideSynced?.cancel();
      _hideSynced = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _showSynced = false);
      });
    }
  }

  @override
  void dispose() {
    _hideSynced?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SyncNotice(
    syncing: widget.syncing,
    justSynced: _showSynced,
    failed: widget.error != null,
    onRetry: widget.onRetry,
  );
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
    if (allowed) await DoseReminders.reschedule(care, reason: 'toggled');
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
    if (on) return const ReminderPermissionNote(remindersOn: true);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: tokens.neutral,
        borderRadius: BorderRadius.circular(PawsRadii.cardValue),
        child: InkWell(
          onTap: _busy ? null : _turnOn,
          borderRadius: BorderRadius.circular(PawsRadii.cardValue),
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
  final Pet? pet;
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
    // The parent list rebuilds on data changes; the tile only needs the clock.
    final now = context.read<CareRepository>().now;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final due = _careDueLabel(event.dueDay, now);
    final petName = pet?.name ?? 'Pet removed';

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
                        '${event.kindLabel} · $due · $petName',
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
