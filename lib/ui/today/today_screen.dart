import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/celebration.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/pro_prompts.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/today/today_more_cards.dart';
import 'package:pawsitive_sync/ui/today/dose_sheets.dart';
import 'package:pawsitive_sync/ui/today/engagement_cards.dart';
import 'package:pawsitive_sync/ui/today/today_cards.dart';
import 'package:pawsitive_sync/ui/today/today_v14.dart';
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
                  // v14 header: date, serif greeting, sync line.
                  TodayGreeting(
                    care: care,
                    // Always says which plan this phone is on; Free taps
                    // through to the paywall (logged as billing.paywall.opened).
                    trailing: CarePlanBadge(
                      isPro: care.isPro,
                      onUpgrade: care.isPro
                          ? null
                          : () => context.push(
                              AppRoutes.paywallWith(
                                reason: 'settings',
                                from: 'today_plan_badge',
                              ),
                            ),
                    ),
                  ),
                  if (care.hasApi &&
                      (care.isConnected || care.syncError != null))
                    _HouseholdSync(
                      syncing: care.syncing,
                      error: care.syncError,
                      onRetry: () => care.sync(force: true, source: 'retry'),
                    ),
                  const SizedBox(height: 8),
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
                    // v14: one progress card with the next dose and its
                    // one action, then the day's doses by time of day.
                    TodayProgressCard(
                      care: care,
                      doses: doses,
                      next: next,
                      lastGiven: _lastGiven(care, doses, next),
                      onMarkGiven: () {
                        if (next != null) _openDose(context, next);
                      },
                      // Logged as nav.push to=/medication/:id.
                      onDetails: () {
                        if (next != null) {
                          context.push(AppRoutes.medication(next.medicationId));
                        }
                      },
                    ),
                    TodayDayGroups(
                      care: care,
                      doses: doses,
                      onGive: (dose) => _openDose(context, dose),
                      onOpen: openFromToday,
                    ),
                    const SizedBox(height: 8),
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
                      const SizedBox(height: 24),
                      const CareSectionHeader('Supplies'),
                      const SizedBox(height: 10),
                      TodaySupplyRow(
                        medication: low,
                        pet: care.tryPetById(low.petId),
                        // Logged as nav.push to=/medication/:id.
                        onReorder: () =>
                            context.push(AppRoutes.medication(low.id)),
                      ),
                    ],
                    // Free: the same moment, honestly framed as what Pro adds.
                    if (!care.canShowLowSupplyAlerts && low != null) ...[
                      _LowSupplyTeaser(
                        key: ValueKey('low-teaser-${low.id}'),
                        medication: low,
                      ),
                    ],
                    const SizedBox(height: 24),
                    TodayMoreCards(care: care, petId: selectedId),
                    const SizedBox(height: 12),
                    const _QuickActions(),
                    if (!care.isPro) const TodayProCard(),
                    const _RemindersBanner(),
                  ] else ...[
                    TodayStart(
                      pet: selectedPet ?? care.primaryPet,
                      hasHistory: care.logs.isNotEmpty,
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
                    const SizedBox(height: 24),
                    const _QuickActions(),
                    const _RemindersBanner(),
                    const SizedBox(height: 28),
                    Text('How it works', style: text.headlineSmall),
                    const SizedBox(height: 16),
                    const _SetupGuide(),
                    if (!care.isConnected) ...[
                      const SizedBox(height: 12),
                      // A link, not a heading: brand colour and body size even
                      // when large text makes it wrap.
                      Center(
                        child: TextButton(
                          onPressed: () => context.push(AppRoutes.join),
                          style: TextButton.styleFrom(
                            foregroundColor: context.paws.brandDark,
                            textStyle: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text(
                            'I have a household invite code',
                            textAlign: TextAlign.center,
                          ),
                        ),
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
        'Profile & photo',
        'today.shortcut.pets',
        () => context.go(AppRoutes.pets),
      ),
      (
        StrokeIconKind.people,
        'Household',
        'Who gives doses',
        'today.shortcut.household',
        () => context.go(AppRoutes.household),
      ),
      (
        StrokeIconKind.file,
        'Vet report',
        'For the next visit',
        'today.shortcut.reports',
        () => context.go(AppRoutes.reports),
      ),
    ];
    // Always one row of three equal cards: an even set reads as one control,
    // where a 2 + 1 wrap leaves a tile looking orphaned.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, action) in actions.indexed) ...[
            if (index > 0) SizedBox(width: context.paws.spacing.sm),
            Expanded(
              child: _QuickActionCard(
                icon: action.$1,
                label: action.$2,
                caption: action.$3,
                onTap: () {
                  AppLog.event(action.$4);
                  action.$5();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One shortcut tile: icon, a one-line name and what you'll find there, so
/// nobody has to guess what a tap opens.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final StrokeIconKind icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paws;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(tokens.radii.lg);
    return Semantics(
      button: true,
      label: '$label. $caption',
      excludeSemantics: true,
      child: Material(
        color: tokens.surfaces.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tokens.borders.subtle),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            // A third of the width can't hold XXL text; cap the scale here
            // so the caption wraps instead of the name truncating.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.surfaces.selected,
                          shape: BoxShape.circle,
                        ),
                        child: StrokeIcon(
                          icon,
                          size: 18,
                          color: tokens.brandDark,
                        ),
                      ),
                      const Spacer(),
                      StrokeIcon(
                        StrokeIconKind.chevronRight,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                const SizedBox(width: 12),
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
