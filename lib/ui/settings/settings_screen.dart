import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/format/pet_names.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/settings/account_section.dart';
import 'package:pawsitive_sync/ui/settings/notification_settings.dart';
import 'package:pawsitive_sync/ui/today/engagement_cards.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// App settings, legal links, and account deletion (App Store / Play requirement).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _remindersOn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // ReminderChoice.read logs and swallows its own failures.
    ReminderChoice.read().then((on) {
      if (mounted) setState(() => _remindersOn = on);
    });
  }

  Future<void> _open(Uri uri) async {
    // Scheme + host only: the support link is a mailto with an address.
    final fields = {'scheme': uri.scheme, 'host': uri.host};
    AppLog.event('settings.link', fields);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stack) {
      AppLog.error('settings.link_failed', error, stack, fields);
    }
    if (!ok) AppLog.event('settings.link_unavailable', fields);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open ${uri.path}.')));
    }
  }

  /// Customer Center keeps cancel, refund and retention offers in-app;
  /// Apple’s subscriptions page is the fallback when billing is off.
  Future<void> _manageSubscription() async {
    final shown = await RevenueCatService.presentCustomerCenter();
    if (!shown) await _open(Uri.parse(AppLinks.manageAppleSubscriptions));
  }

  Future<void> _restorePurchases(CareRepository care) async {
    setState(() => _busy = true);
    AppLog.event('billing.restore.settings');
    final ok = await care.restoreBilling();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Pro restored on this account.'
              : care.lastError ?? 'No subscription found.',
        ),
      ),
    );
  }

  Future<void> _toggleReminders(bool on) async {
    AppLog.event('settings.reminders_toggled', {'on': on});
    final onboarding = context.read<OnboardingViewModel>();
    final care = context.read<CareRepository>();
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      setState(() => _remindersOn = false);
      await onboarding.saveReminders(false);
      await DoseReminders.cancel();
      return;
    }
    final allowed = await DoseReminders.ask();
    await onboarding.saveReminders(allowed);
    if (allowed) await DoseReminders.reschedule(care, reason: 'toggled');
    if (!mounted) return;
    setState(() => _remindersOn = allowed);
    if (!allowed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Reminders stay off. You can allow them in phone Settings.',
          ),
        ),
      );
    }
  }

  /// Confirm → server delete (if shared) → local wipe → welcome. The
  /// dialog owns the busy/slow/error states so a failed delete is explained
  /// in place and nothing has been removed.
  Future<void> _deleteAccount() async {
    if (_busy) return;
    final care = context.read<CareRepository>();
    // Logged as nav.push to=delete_account; the scope is logged by
    // account.delete_requested.
    final deleted = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'delete_account'),
      // Never dismissed by a stray tap while the request is running.
      barrierDismissible: false,
      builder: (_) => _DeleteAccountDialog(care: care),
    );
    if (deleted != true || !mounted) return;
    context.read<OnboardingViewModel>().resetForSignOut();
    maybeEngagement(context, listen: false)?.clear();
    context.go(AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const version = '1.0.0';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // Shared back button: its caret lines up with the title.
            // The page title below is the only "Settings" on screen.
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: CareBackButton(fallbackRoute: AppRoutes.household),
            ),
            const SizedBox(height: 8),
            const CarePageHeader(
              title: 'Settings',
              subtitle: 'Reminders, plan, and your data',
            ),
            const SizedBox(height: 24),
            CareSectionHeader('Your plan'),
            const SizedBox(height: 8),
            SurfaceCard(
              child: Column(
                children: [
                  if (care.isPro)
                    const ListTile(
                      title: Text('Pro'),
                      subtitle: Text(
                        'Every pet, your whole household, vet export and '
                        'refill alerts. Synced to everyone’s phone.',
                      ),
                    )
                  else
                    // What Free keeps, and what it can lose, in plain words.
                    CareActionTile(
                      title: 'Free',
                      subtitle:
                          'Just you and one pet, saved only on this phone. '
                          'Delete the app or lose the phone and the log is '
                          'gone. Pro syncs it for your household.',
                      action: 'See Pro',
                      onAction: () => context.push(
                        AppRoutes.paywallWith(
                          reason: 'settings',
                          from: 'settings_plan',
                        ),
                      ),
                    ),
                  // Hidden unless a debug build runs with DEBUG_TOOLS=true.
                  if (kDebugMode && AppConfig.debugTools) ...[
                    Divider(height: 1, color: scheme.outlineVariant),
                    ListTile(
                      title: Text(
                        care.isPro
                            ? 'Debug: switch to Free'
                            : 'Debug: switch to Pro',
                      ),
                      subtitle: const Text(
                        'Debug build only. Resets to RevenueCat on restart.',
                      ),
                      trailing: Switch(
                        value: care.isPro,
                        onChanged: (_) => care.debugTogglePro(),
                      ),
                      onTap: care.debugTogglePro,
                    ),
                  ],
                  Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    title: const Text('Restore purchases'),
                    subtitle: const Text(
                      'Already subscribed? Restore Pro on this phone.',
                    ),
                    onTap: _busy ? null : () => _restorePurchases(care),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    title: const Text('Manage subscription'),
                    trailing: Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: _manageSubscription,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const AccountSection(),
            CareSectionHeader('Notifications'),
            const SizedBox(height: 8),
            NotificationSettings(
              remindersOn: _remindersOn,
              onToggleReminders: _toggleReminders,
              care: care,
            ),
            const SizedBox(height: 24),
            CareSectionHeader('Legal'),
            const SizedBox(height: 8),
            SurfaceCard(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Privacy Policy'),
                    trailing: Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => _open(Uri.parse(AppLinks.privacy)),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    title: const Text('Terms of Service'),
                    trailing: Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => _open(Uri.parse(AppLinks.terms)),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    title: const Text('Contact support'),
                    // Opens outside the app, like the two links above.
                    trailing: Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    onTap: () => _open(Uri.parse(AppLinks.support)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // "Account" is already the sign-in section above.
            CareSectionHeader('Your data'),
            const SizedBox(height: 8),
            if (care.isConnected)
              SurfaceCard(
                child: ListTile(
                  title: const Text('Leave household'),
                  subtitle: const Text(
                    'Stay on this phone but remove shared data. Use Join to come back.',
                  ),
                  onTap: () async {
                    final leave = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Leave this household?'),
                        content: const Text(
                          'Your dose history on this phone will be cleared. You can rejoin with an invite code.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Leave'),
                          ),
                        ],
                      ),
                    );
                    if (leave != true || !context.mounted) return;
                    final error = await care.leaveHousehold();
                    if (!context.mounted) return;
                    // household.left / leave_failed: logged by the repository.
                    if (error != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error)));
                      return;
                    }
                    // Pets and medicines stay on this phone, so do their
                    // reminders; doses from the old household drop out.
                    await DoseReminders.reschedule(
                      care,
                      reason: 'left_household',
                    );
                    if (!context.mounted) return;
                    context.go(AppRoutes.today);
                  },
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy ? null : _deleteAccount,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      care.isConnected
                          ? 'Delete account'
                          : 'Delete account on this phone',
                    ),
            ),
            const SizedBox(height: 8),
            // Same 4pt inset as the section title above.
            Padding(
              padding: CareSectionHeader.inset,
              child: Text(
                care.isConnected
                    ? 'Deletes your account on our server and all app data on this phone.'
                    : 'Removes every pet, dose and setting from this phone. '
                          'This can’t be undone.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Gave It $version',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Delete confirmation with the exact consequence for this person’s role,
/// a busy state, a "slow connection" note after 5 s, and inline errors.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.care});

  final CareRepository care;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _slowAfter = Duration(seconds: 5);

  bool _busy = false;
  bool _slow = false;
  String? _error;
  Timer? _slowTimer;

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return; // double tap: the first request is still running
    setState(() {
      _busy = true;
      _slow = false;
      _error = null;
    });
    _slowTimer = Timer(_slowAfter, () {
      if (mounted) setState(() => _slow = true);
      AppLog.event('account.delete_slow');
    });
    final error = await widget.care.deleteAccount();
    _slowTimer?.cancel();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _slow = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final care = widget.care;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (title, body) = switch (care.accountDeleteScope) {
      AccountDeleteScope.household => (
        'Delete your account and household?',
        'This permanently deletes ${petNameList(care.pets)} and all medicines, doses and notes for everyone in this household. Other caregivers will lose access. This can’t be undone.',
      ),
      AccountDeleteScope.member => (
        'Delete your account?',
        'You’ll leave this household and your account is deleted. Doses you logged stay in the household’s history.',
      ),
      AccountDeleteScope.local => (
        'Delete everything on this phone?',
        'This removes all pets, medicines, and dose history stored on this phone. This cannot be undone.',
      ),
    };
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            if (_busy && _slow) ...[
              const SizedBox(height: 16),
              Text(
                'Still working — slow connection. Keep this open; it finishes as soon as the server answers.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: text.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              disabledBackgroundColor: scheme.error.withValues(alpha: 0.7),
              disabledForegroundColor: scheme.onError,
            ),
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onError,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('Deleting…'),
                    ],
                  )
                : Text(_error == null ? 'Delete' : 'Try again'),
          ),
        ],
      ),
    );
  }
}
