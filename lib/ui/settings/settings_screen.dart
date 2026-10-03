import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/onboarding_state.dart';
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
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
    ReminderChoice.read().then((on) {
      if (mounted) setState(() => _remindersOn = on);
    });
  }

  Future<void> _open(Uri uri) async {
    AppLog.event('settings.link', {'uri': uri.toString()});
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.path}.')),
      );
    }
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
    setState(() => _remindersOn = on);
    await context.read<OnboardingViewModel>().saveReminders(on);
    final care = context.read<CareRepository>();
    if (on) {
      await DoseReminders.scheduleNext(care);
    } else {
      await DoseReminders.cancel();
    }
  }

  void _loadDemoData(CareRepository care) {
    AppLog.event('debug.demo_data.loaded');
    care.loadSampleData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Demo data loaded — 2 pets, meds, today\'s doses.')),
    );
  }

  Future<void> _clearDemoData(CareRepository care) async {
    AppLog.event('debug.demo_data.cleared');
    await care.reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared. Back to empty.')),
    );
  }

  Future<void> _deleteAccount() async {
    if (_busy) return;
    final care = context.read<CareRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account on this phone?'),
        content: Text(
          care.isConnected
              ? 'This removes your pets, medicines, and dose history from this phone and signs you out of the household. Other caregivers keep their access. This cannot be undone.'
              : 'This removes all pets, medicines, and dose history stored on this phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    AppLog.event('settings.account_deleted');
    await DoseReminders.cancel();
    await ReminderChoice.write(false);
    await care.reset();
    await OnboardingState.clear();
    if (!mounted) return;
    context.read<OnboardingViewModel>().resetForSignOut();
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
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.household),
                  icon: StrokeIcon(
                    StrokeIconKind.chevronLeft,
                    color: scheme.onSurface,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Settings',
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Text('Settings', style: text.displaySmall),
            Text(
              'Reminders, plan, and your data',
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text('YOUR PLAN', style: text.labelSmall),
            const SizedBox(height: 8),
            SurfaceCard(
              child: Column(
                children: [
                  ListTile(
                    title: Text(care.isPro ? 'Pro' : 'Free'),
                    subtitle: Text(
                      care.isPro
                          ? 'Every pet, invites, refill alerts, vet export'
                          : 'One pet with full dose tracking · Pro for shared care',
                    ),
                    trailing: care.isPro
                        ? null
                        : TextButton(
                            onPressed: () => context.push(AppRoutes.paywall),
                            child: const Text('Upgrade'),
                          ),
                  ),
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
                    onTap: () => _open(Uri.parse(AppLinks.manageAppleSubscriptions)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('NOTIFICATIONS', style: text.labelSmall),
            const SizedBox(height: 8),
            SurfaceCard(
              child: SwitchListTile(
                title: const Text('Dose reminders'),
                subtitle: const Text(
                  'A nudge when medicine is due. You can change this anytime.',
                ),
                value: _remindersOn ?? false,
                onChanged: _remindersOn == null
                    ? null
                    : (on) => _toggleReminders(on),
              ),
            ),
            const SizedBox(height: 24),
            Text('LEGAL', style: text.labelSmall),
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
                    onTap: () => _open(Uri.parse(AppLinks.support)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('ACCOUNT', style: text.labelSmall),
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
                    await DoseReminders.cancel();
                    await care.reset();
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
                  : const Text('Delete account on this phone'),
            ),
            const SizedBox(height: 8),
            Text(
              'Required by Apple and Google: delete removes all app data from this device.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 24),
              Text('DEBUG · SCREENSHOTS ONLY', style: text.labelSmall),
              const SizedBox(height: 8),
              SurfaceCard(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Load demo data'),
                      subtitle: const Text(
                        '2 pets, 4 meds, and today\'s doses — for App Store screenshots.',
                      ),
                      onTap: () => _loadDemoData(care),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    ListTile(
                      title: Text(
                        'Clear demo data',
                        style: TextStyle(color: scheme.error),
                      ),
                      subtitle: const Text('Wipes everything on this phone back to empty.'),
                      onTap: () => _clearDemoData(care),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: Text(
                'PawsitiveSync $version',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
