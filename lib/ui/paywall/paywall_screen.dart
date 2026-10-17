import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/data/reminders/trial_reminder.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/legal/subscription_disclosure.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/post_frame.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/account_service.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:pawsitive_sync/ui/account/account_sheet.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Compares Free and Pro. Free solves solo care; Pro solves shared / multi-pet pain.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason, this.from});

  /// Query param from [AppRoutes.paywallWith] — contextual upgrade moment.
  final String? reason;

  /// The button that opened the paywall (e.g. `pro_badge`), for the log.
  final String? from;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _busy = false;
  bool _restoring = false;
  String? _error;
  PaywallOffer? _offer;

  /// True until RevenueCat answers. Prices and trials are never guessed:
  /// the paywall shows them only once the store has sent them.
  bool _loadingOffer = true;
  late final PaywallReason? _moment = PaywallReasonQuery.fromQuery(
    widget.reason,
  );

  /// RevenueCat placement id — one per upgrade moment, so Targeting can serve
  /// each moment its own offering (price or copy test) without a release.
  /// No reason: first-run setup is `onboarding`; anything after (e.g. the
  /// Today Pro badge) is a generic `upgrade`.
  String get _placement =>
      _moment?.queryValue ?? (_isUpgradeFlow ? 'upgrade' : 'onboarding');

  bool get _isUpgradeFlow {
    final model = context.read<OnboardingViewModel>();
    final care = context.read<CareRepository>();
    return model.isComplete || care.hasHousehold;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppLog.event('billing.paywall.opened', {
        'reason': widget.reason ?? 'default',
        'placement': _placement,
        'from': ?widget.from,
      });
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final care = context.read<CareRepository>();
    // Subscribers keep their real plan; resetting it would overwrite the
    // household’s billing plan on the server.
    if (!care.isPro && care.plan != BillingPlan.yearly) {
      AppLog.unawaitedLogged(
        care.setPlan(BillingPlan.yearly, source: 'paywall_default'),
        'billing.plan.failed',
      );
    }
    await _loadOffer();
  }

  Future<void> _loadOffer() async {
    setState(() {
      _loadingOffer = true;
      _error = null;
    });
    if (RevenueCatService.isReady) {
      AppLog.event('billing.paywall.rc_ready', {'placement': _placement});
      AppLog.unawaitedLogged(
        RevenueCatService.syncAttributes({'last_paywall': _placement}),
        'billing.rc.attributes_failed',
      );
    }
    final offer = await RevenueCatService.loadOffer(_placement);
    if (!mounted) return;
    setState(() {
      _offer = offer;
      _loadingOffer = false;
    });
    AppLog.event(
      offer == null
          ? 'billing.paywall.offer_unavailable'
          : 'billing.paywall.offer_shown',
      {
        'placement': _placement,
        'rcReady': RevenueCatService.isReady,
        if (offer != null) 'offering': offer.offeringId,
      },
    );
  }

  /// The store’s localized price, or a placeholder until RevenueCat answers.
  String _price(BillingPlan plan) =>
      _offer?.forPlan(plan)?.priceString ?? (_loadingOffer ? '…' : '—');

  /// Trial days RevenueCat says this user gets on [plan]; null = no trial.
  int? _trialDays(BillingPlan plan) => _offer?.forPlan(plan)?.trialDays;

  bool get _canBuy =>
      _offer?.forPlan(context.read<CareRepository>().plan) != null;

  String get _yearlyPerMonth =>
      _offer?.yearly?.perMonthString ?? _price(BillingPlan.yearly);

  String? get _yearlyBadge {
    final pct = _offer?.yearlySavingsPercent;
    return pct == null ? null : 'Save $pct%';
  }

  String _ctaLabel(BillingPlan plan) {
    if (_loadingOffer) return 'Loading prices…';
    if (_offer?.forPlan(plan) == null) return 'Try again';
    final name = plan == BillingPlan.yearly ? 'Yearly' : 'Monthly';
    final days = _trialDays(plan);
    if (days != null) return 'Start $days-day free trial · $name';
    return 'Subscribe · ${_price(plan)}/${SubscriptionDisclosure.period(plan)}';
  }

  Future<void> _restore() async {
    if (_busy || _restoring) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    final care = context.read<CareRepository>();
    final ok = await care.restoreBilling();
    if (!mounted) return;
    setState(() => _restoring = false);
    // billing.restore.completed / failed are logged by the repository.
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pro restored on this account.')),
      );
      return;
    }
    setState(() => _error = care.lastError);
  }

  Future<void> _startTrial() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final care = context.read<CareRepository>();
    if (!_canBuy) {
      AppLog.event('billing.paywall.offer_retry', {'placement': _placement});
      setState(() => _busy = false);
      await _loadOffer();
      if (mounted && _offer == null) {
        setState(
          () => _error =
              'Couldn’t load prices from the App Store. '
              'Check your connection and try again.',
        );
      }
      return;
    }
    AppLog.event('billing.trial.tap', {'plan': care.plan.name});

    if (RevenueCatService.isReady) {
      final result = await care.purchasePlan(
        package: _offer?.forPlan(care.plan)?.package,
      );
      if (!mounted) return;
      if (!result.success) {
        setState(() {
          _busy = false;
          if (result.kind != PurchaseErrorKind.cancelled) {
            _error = result.message ?? care.lastError;
          }
        });
        return;
      }
      // Pro is server-synced: offer to save it to an account now, while the
      // reason is fresh. "Not now" just continues; Settings offers it again.
      if (AccountService.currentUser == null && mounted) {
        await showAccountSheet(context, mode: AccountSheetMode.save);
        if (!mounted) return;
      }
    } else {
      AppLog.event('billing.trial.store_unavailable');
      setState(() {
        _busy = false;
        _error = 'Purchases aren’t available right now. Try again later.';
      });
      return;
    }

    await _finishSetup();
  }

  Future<void> _continueFree() async {
    if (_busy) return;
    AppLog.event('billing.continued_free', {
      'reason': widget.reason ?? 'default',
    });
    await _finishSetup();
  }

  void _dismissPaywall() {
    AppLog.event('billing.paywall.dismissed', {
      'reason': widget.reason ?? 'default',
    });
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.today);
    }
  }

  Future<void> _finishSetup() async {
    final care = context.read<CareRepository>();
    final model = context.read<OnboardingViewModel>();
    String? afterSetup;
    if (!_isUpgradeFlow && model.hasValidPetName) {
      care.applyOnboarding(model);
      afterSetup = await _saveFirstMedicine(care, model);
      await model.finish(reminders: model.remindersOn);
      if (!mounted) return;
      if (model.remindersOn) {
        AppLog.unawaitedLogged(
          DoseReminders.reschedule(care, reason: 'onboarding'),
          'reminders.schedule_failed',
        );
      } else {
        AppLog.unawaitedLogged(
          DoseReminders.cancel(),
          'reminders.cancel_failed',
        );
      }
    }
    if (!mounted) return;
    AppLog.event('billing.paywall.complete', {
      'isPro': care.isPro,
      'reason': widget.reason ?? 'default',
    });
    if (_isUpgradeFlow && context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.today);
    final messenger = ScaffoldMessenger.of(context);
    if (afterSetup != null) {
      messenger.showSnackBar(SnackBar(content: Text(afterSetup)));
    }
    // Setup asked to invite people: the invite flow (Pro) opens with the
    // first address, or a plain note on Free so nothing typed is lost.
    if (model.inviteAfterSetup) {
      model.inviteAfterSetup = false;
      if (care.canInviteHousehold) {
        final email = model.invites.firstOrNull;
        afterThisFrame(
          context,
          () => context.push(
            email == null
                ? AppRoutes.invite
                : Uri(
                    path: AppRoutes.invite,
                    queryParameters: {'email': email},
                  ).toString(),
          ),
        );
      } else if (model.invites.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Inviting ${model.invites.join(', ')} is part of Pro. '
              'You can do it from Household any time.',
            ),
          ),
        );
      }
    }
  }

  /// Setup's medicine step, saved now that the pet exists. Returns a note
  /// for the person when it couldn't be saved (never dropped silently).
  Future<String?> _saveFirstMedicine(
    CareRepository care,
    OnboardingViewModel model,
  ) async {
    final pet = care.pets.lastOrNull;
    if (!model.hasMedicine || pet == null || model.medName.trim().isEmpty) {
      return null;
    }
    final supply = int.tryParse(model.medSupply.trim()) ?? 0;
    final ok = await care.addMedication(
      petId: pet.id,
      name: model.medName,
      amount: model.medAmountText,
      parts: [
        for (final part in DayPart.values)
          if (model.medParts.contains(part)) part,
      ],
      supplyTotal: supply > 0 ? supply : 0,
      everyDays: model.medEveryDays,
      withFood: model.medWithFood,
      site: model.medSite,
      startDay: dayKey(care.now),
    );
    if (ok) return null;
    return '${model.medName.trim()} wasn’t added: '
        '${care.lastError ?? 'try again from Pets'}';
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final yearly = care.plan == BillingPlan.yearly;
    final locked = _busy || _restoring;
    final upgradeFlow = _isUpgradeFlow;
    final fallbackCopy = (_moment ?? PaywallReason.onboarding).copy;
    // Offering metadata wins so headline tests run from RevenueCat.
    final copy = (
      _offer?.text('headline') ?? fallbackCopy.$1,
      _offer?.text('subline') ?? fallbackCopy.$2,
    );

    return PopScope(
      canPop: !locked,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 12pt in, so the ✕ glyph and the "Restore" label sit on the
              // same 24pt edges as the copy below (buttons pad 12 inside).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: upgradeFlow ? 'Close' : 'Continue free',
                      onPressed: locked
                          ? null
                          : () => upgradeFlow
                                ? _dismissPaywall()
                                : _continueFree(),
                      icon: StrokeIcon(
                        StrokeIconKind.close,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: locked ? null : _restore,
                      child: Text(_restoring ? 'Restoring…' : 'Restore'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  children: [
                    Text(copy.$1, style: text.displaySmall),
                    if (copy.$2 != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        copy.$2!,
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Yearly saves the most. Cancel anytime in the App Store.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _PlanTile(
                      selected: yearly,
                      title: 'Yearly',
                      // Apple: the billed amount is the most prominent
                      // price; the per-month breakdown stays subordinate.
                      // developer.apple.com/app-store/subscriptions
                      subtitle: '$_yearlyPerMonth/mo · whole household',
                      price: '${_price(BillingPlan.yearly)}/yr',
                      badge: _yearlyBadge,
                      onPressed: locked
                          ? null
                          : () => AppLog.unawaitedLogged(
                              care.setPlan(BillingPlan.yearly),
                              'billing.plan.failed',
                            ),
                    ),
                    const SizedBox(height: 8),
                    _PlanTile(
                      selected: !yearly,
                      title: 'Monthly',
                      subtitle: '${_price(BillingPlan.monthly)} per month',
                      price: '${_price(BillingPlan.monthly)}/mo',
                      onPressed: locked
                          ? null
                          : () => AppLog.unawaitedLogged(
                              care.setPlan(BillingPlan.monthly),
                              'billing.plan.failed',
                            ),
                    ),
                    if (_trialDays(care.plan) case final days?) ...[
                      const SizedBox(height: 24),
                      _TrialTimeline(
                        days: days,
                        plan: care.plan,
                        price: _price(care.plan),
                        start: care.now,
                      ),
                    ],
                    const SizedBox(height: 24),
                    // v14: one Free vs Pro table, the row for this moment
                    // highlighted, then the promise that safety stays free.
                    _Comparison(highlight: _highlightFor(_moment)),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.verified_user_outlined,
                              size: 16,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        'Logging doses and the double-dose '
                                        'check stay free, always. ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const TextSpan(
                                    text:
                                        'One subscription covers your whole '
                                        'household.',
                                  ),
                                ],
                              ),
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Column(
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: locked || _loadingOffer ? null : _startTrial,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_ctaLabel(care.plan)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Apple 3.1.2 terms, only with the store’s real price.
                    if (_offer?.forPlan(care.plan) != null)
                      Text(
                        SubscriptionDisclosure.compactLine(
                          care.plan,
                          price: _price(care.plan),
                          trialDays: _trialDays(care.plan),
                        ),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    if (!upgradeFlow)
                      TextButton(
                        onPressed: locked ? null : _continueFree,
                        child: const Text('Continue free with 1 pet'),
                      ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      // The dot is shorter than the buttons: centre it.
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(AppLinks.terms),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('Terms'),
                        ),
                        Text(
                          '·',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(AppLinks.privacy),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('Privacy'),
                        ),
                      ],
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

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.selected,
    required this.title,
    required this.price,
    this.onPressed,
    this.subtitle,
    this.badge,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final String price;
  final String? badge;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: scheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PawsRadii.cardValue),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(PawsRadii.cardValue),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outline,
                        width: selected ? 6 : 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  Text(price, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -11,
            right: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  badge!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// How the free trial works, as lines in the log: what happens today, when
/// we remind, and when the plan starts. Mirrors [TrialReminder] so the
/// promise and the notification always agree.
class _TrialTimeline extends StatelessWidget {
  const _TrialTimeline({
    required this.days,
    required this.plan,
    required this.price,
    required this.start,
  });

  final int days;
  final BillingPlan plan;
  final String price;

  /// Today: the timeline shows real calendar dates ("Oct 19"), not trial
  /// day numbers, so people can see when they would pay.
  final DateTime start;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Oct 19" for [start] plus [offset] days.
  static String dateAfter(DateTime start, int offset) {
    final day = DateTime(start.year, start.month, start.day + offset);
    return '${_months[day.month - 1]} ${day.day}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reminder = TrialReminder.reminderDay(days);
    final period = SubscriptionDisclosure.period(plan);
    final steps = [
      (
        date: 'Today',
        title: 'Full Pro access',
        detail: 'Nothing to pay today.',
        icon: StrokeIconKind.check,
      ),
      if (reminder != null)
        (
          date: dateAfter(start, reminder),
          title: 'We remind you',
          detail: 'A notice before the trial ends, if notifications are on.',
          icon: StrokeIconKind.bell,
        ),
      (
        date: dateAfter(start, days),
        title: '$price per $period starts',
        detail: 'Cancel anytime before, in your store subscriptions.',
        icon: StrokeIconKind.calendar,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How your free trial works', style: text.titleMedium),
        const SizedBox(height: 12),
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                _TrialStep(
                  date: steps[i].date,
                  title: steps[i].title,
                  detail: steps[i].detail,
                  icon: steps[i].icon,
                  current: i == 0,
                  last: i == steps.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One stop on the trial timeline: a round marker on a vertical rail, then
/// the date, what happens and the detail. Today is filled; later stops are
/// quiet so the eye lands on "nothing to pay today".
class _TrialStep extends StatelessWidget {
  const _TrialStep({
    required this.date,
    required this.title,
    required this.detail,
    required this.icon,
    required this.current,
    required this.last,
  });

  final String date;
  final String title;
  final String detail;
  final StrokeIconKind icon;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$date: $title. $detail',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: current
                          ? scheme.primary
                          : scheme.surfaceContainerLow,
                      shape: BoxShape.circle,
                    ),
                    child: StrokeIcon(
                      icon,
                      size: 16,
                      color: current ? scheme.onPrimary : tokens.brandDark,
                    ),
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: text.labelLarge?.copyWith(
                        color: current
                            ? tokens.brandDark
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(title, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(detail, style: text.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The table row to highlight for the moment that opened the paywall.
String? _highlightFor(PaywallReason? reason) => switch (reason) {
  PaywallReason.secondPet => 'pets',
  PaywallReason.moreMeds => 'meds',
  PaywallReason.moreDoseTimes => 'times',
  PaywallReason.invite || PaywallReason.uncertain => 'share',
  PaywallReason.vetExport => 'report',
  PaywallReason.history => 'history',
  PaywallReason.refill => 'refill',
  PaywallReason.weeklySummary => 'summary',
  _ => null,
};

/// v14 comparison: feature, Free, Pro. Values mirror [PetLimits].
class _Comparison extends StatelessWidget {
  const _Comparison({required this.highlight});

  final String? highlight;

  static final _rows = <(String, String, Object, Object)>[
    ('logging', 'Dose logging & double-dose check', true, true),
    (
      'pets',
      'Pets',
      '${PetLimits.maxPetsFree}',
      'Up to ${PetLimits.maxPetsPerHousehold}',
    ),
    ('meds', 'Medicines per pet', '${PetLimits.maxMedsPerPetFree}', 'No limit'),
    ('times', 'Dose times a day', 'Morning', 'Any time'),
    ('share', 'Household & sitters', false, true),
    ('report', 'Vet-ready reports', false, true),
    ('history', 'History', '${PetLimits.freeHistoryDays} days', 'All of it'),
    ('refill', 'Refill reminders', false, true),
    ('summary', 'Weekly summary', false, true),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    Widget cell(Object value, {required bool pro}) {
      final words = value == true
          ? 'Included'
          : value == false
          ? 'Not included'
          : '$value';
      return Semantics(
        label: '${pro ? 'Pro' : 'Free'}: $words',
        excludeSemantics: true,
        child: Center(
          child: switch (value) {
            true => StrokeIcon(
              StrokeIconKind.check,
              size: 16,
              color: pro ? scheme.primary : scheme.onSurfaceVariant,
            ),
            false => Icon(
              Icons.remove,
              size: 16,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            _ => Text(
              '$value',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                fontSize: 13,
                fontWeight: pro ? FontWeight.w600 : FontWeight.w400,
                color: pro ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          },
        ),
      );
    }

    return SurfaceCard(
      child: Column(
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  SizedBox(
                    width: 64,
                    child: Text(
                      'Free',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      'Pro',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final (id, label, free, pro) in _rows)
            Semantics(
              container: true,
              label: label,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                decoration: BoxDecoration(
                  color: id == highlight ? paws.surfaces.background : null,
                  border: Border(top: BorderSide(color: paws.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          label,
                          style: text.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: scheme.onSurface,
                            fontWeight: id == highlight
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 64, child: cell(free, pro: false)),
                    SizedBox(width: 84, child: cell(pro, pro: true)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
