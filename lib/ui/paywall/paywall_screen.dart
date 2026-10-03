import 'package:flutter/foundation.dart' show kReleaseMode;
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
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Compares Free and Pro. Free solves solo care; Pro solves shared / multi-pet pain.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason});

  /// Query param from [AppRoutes.paywallWith] — contextual upgrade moment.
  final String? reason;

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
  List<Package> _packages = const [];
  late final PaywallReason? _moment = PaywallReasonQuery.fromQuery(widget.reason);

  bool get _isUpgradeFlow {
    final model = context.read<OnboardingViewModel>();
    final care = context.read<CareRepository>();
    return model.isComplete || care.hasHousehold;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLog.event('billing.paywall.opened', {
        'reason': widget.reason ?? 'default',
      });
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final care = context.read<CareRepository>();
    if (care.plan != BillingPlan.yearly) {
      care.setPlan(BillingPlan.yearly);
    }
    if (RevenueCatService.isReady) {
      AppLog.event('billing.paywall.rc_ready');
      final packages = await RevenueCatService.loadPackages();
      if (mounted) setState(() => _packages = packages);
    } else {
      AppLog.event('billing.paywall.rc_fallback', {'reason': 'not_configured'});
    }
  }

  String _priceFor(BillingPlan plan, String fallback) {
    final package = RevenueCatService.packageForPlan(plan, _packages);
    return package?.storeProduct.priceString ?? fallback;
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
    if (ok) {
      AppLog.event('billing.restore.paywall_success');
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
    AppLog.event('billing.trial.tap', {'plan': care.plan.name});

    if (RevenueCatService.isReady) {
      final result = await care.purchasePlan();
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
    } else if (!kReleaseMode) {
      AppLog.event('billing.trial.local_fallback');
      await care.startTrial();
    } else {
      AppLog.event('billing.trial.store_unavailable');
      setState(() {
        _busy = false;
        _error = 'Purchases are not available right now. '
            'Check your connection and try again.';
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
        DoseReminders.scheduleNext(care);
      } else {
        DoseReminders.cancel();
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
    final copy = (_moment ?? PaywallReason.onboarding).copy;

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
                        : () => upgradeFlow ? _dismissPaywall() : _continueFree(),
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
                      subtitle: _priceFor(BillingPlan.yearly, '\$29.99 per year'),
                      price: '\$2.50/mo',
                      badge: 'Save 50%',
                      onPressed: locked
                          ? null
                          : () => care.setPlan(BillingPlan.yearly),
                    ),
                    const SizedBox(height: 8),
                    _PlanTile(
                      selected: !yearly,
                      title: 'Monthly',
                      subtitle: _priceFor(BillingPlan.monthly, '\$4.99/mo'),
                      price: '\$4.99/mo',
                      onPressed: locked
                          ? null
                          : () => care.setPlan(BillingPlan.monthly),
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
                              bottom: index == _freeFeatures.length - 1 ? 0 : 16,
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
                      background: scheme.primaryContainer.withValues(alpha: 0.25),
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
                      onPressed: locked ? null : _startTrial,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              yearly
                                  ? 'Start 7-day free trial · Yearly'
                                  : 'Start 7-day free trial · Monthly',
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      SubscriptionDisclosure.compactLine(care.plan),
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
          child: StrokeIcon(
            StrokeIconKind.check,
            size: 18,
            color: accent,
          ),
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
