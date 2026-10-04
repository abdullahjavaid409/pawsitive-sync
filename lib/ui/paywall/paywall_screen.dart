import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/legal/subscription_disclosure.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
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
  /// Pain → solution. Always free — never paywall safety.
  static const _freeFeatures = [
    (
      'Did I already give it?',
      'One-tap logging, double-dose checks, and “not sure if given” for one pet.',
    ),
    (
      'What\'s due today?',
      'Morning, afternoon, and evening doses in one Today list with reminders.',
    ),
    (
      'Works without Wi‑Fi',
      'Log doses offline. Sync when you connect — safety is never locked behind Pro.',
    ),
  ];

  /// Pain → solution. Pro gates only — multi-pet, household, export, supply.
  static const _proFeatures = [
    (
      'We have more than one pet on meds',
      'Track up to 10 pets — cats, dogs, rabbits, and more — in one household.',
    ),
    (
      'Did my partner or sitter already dose?',
      'Invite with a code. Everyone sees the same list and who logged each dose.',
    ),
    (
      'The vet asked for a clear log',
      'Export a week-by-week report to share at checkups or send ahead to the clinic.',
    ),
    (
      'We almost ran out without noticing',
      'Running-low alerts before the bottle is empty so refills do not slip by.',
    ),
  ];

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
    // household's billing plan on the server.
    if (!care.isPro && care.plan != BillingPlan.yearly) {
      AppLog.unawaitedLogged(
        care.setPlan(BillingPlan.yearly),
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

  /// The store's localized price, or a placeholder until RevenueCat answers.
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
    if (!_isUpgradeFlow && model.hasValidPetName) {
      care.applyOnboarding(model);
      await model.finish(reminders: model.remindersOn);
      if (!mounted) return;
      if (model.remindersOn) {
        AppLog.unawaitedLogged(
          DoseReminders.scheduleNext(care),
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
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
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
              Row(
                children: [
                  IconButton(
                    tooltip: upgradeFlow ? 'Close' : 'Continue free',
                    onPressed: locked
                        ? null
                        : () =>
                              upgradeFlow ? _dismissPaywall() : _continueFree(),
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
                      'Pick a plan — yearly saves the most.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _PlanTile(
                      selected: yearly,
                      title: 'Yearly',
                      subtitle: '${_price(BillingPlan.yearly)} per year',
                      price: '$_yearlyPerMonth/mo',
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
                    const SizedBox(height: 24),
                    Text('Always free', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'One pet · dose logging · double-dose safety · reminders',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FeatureCard(
                      hairline: tokens.hairline,
                      children: [
                        for (final (index, feature) in _freeFeatures.indexed)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: index == _freeFeatures.length - 1
                                  ? 0
                                  : 16,
                            ),
                            child: _FeatureRow(
                              title: feature.$1,
                              detail: feature.$2,
                              accent: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Pro unlocks', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'When care is shared or you have multiple pets',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FeatureCard(
                      hairline: scheme.primary.withValues(alpha: 0.35),
                      background: scheme.primaryContainer.withValues(
                        alpha: 0.25,
                      ),
                      children: [
                        for (final (index, feature) in _proFeatures.indexed)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: index == _proFeatures.length - 1 ? 0 : 16,
                            ),
                            child: _FeatureRow(
                              title: feature.$1,
                              detail: feature.$2,
                              accent: scheme.primary,
                            ),
                          ),
                      ],
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
                    FilledButton(
                      onPressed: locked || _loadingOffer ? null : _startTrial,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_ctaLabel(care.plan)),
                    ),
                    const SizedBox(height: 8),
                    // Apple 3.1.2 terms, only with the store's real price.
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

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.hairline,
    required this.children,
    this.background,
  });

  final Color hairline;
  final Color? background;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(children: children),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.title,
    required this.detail,
    required this.accent,
  });

  final String title;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: StrokeIcon(StrokeIconKind.check, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              const SizedBox(height: 2),
              Text(
                detail,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
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
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
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
