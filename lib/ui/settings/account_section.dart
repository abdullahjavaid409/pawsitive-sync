import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/account_service.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/firebase_setup.dart';
import 'package:pawsitive_sync/ui/account/account_sheet.dart';
import 'package:provider/provider.dart';

/// Settings › Account: who is signed in, or how to save / restore the
/// household. Hidden entirely when sign-in can't start (no Firebase), so
/// Settings never shows a control that would only fail.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!FirebaseSetup.isReady) return const SizedBox.shrink();
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) => _Body(user: snapshot.data),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.user});

  final User? user;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _busy = false;

  Future<void> _signOut(CareRepository care) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your household stays on this phone. It just won’t come back on a '
          'new phone until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await care.forgetSignIn();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save(CareRepository care) async {
    // Saving needs the household on the server: shared households already
    // are; a solo phone only with Pro.
    if (!care.isConnected && !care.isPro) {
      AppLog.event('account.save_needs_pro');
      context.push(
        AppRoutes.paywallWith(reason: 'settings', from: 'settings_account'),
      );
      return;
    }
    await showAccountSheet(context, mode: AccountSheetMode.save);
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final user = widget.user;
    final rows = <Widget>[
      if (user != null)
        ListTile(
          title: const Text('Signed in'),
          subtitle: Text(
            user.email ??
                switch (AccountService.currentProvider) {
                  AccountProvider.apple => 'With Apple',
                  AccountProvider.google => 'With Google',
                  _ => 'With email',
                },
          ),
          trailing: TextButton(
            onPressed: _busy ? null : () => _signOut(care),
            child: const Text('Sign out'),
          ),
        )
      else
        ListTile(
          title: const Text('Save your household'),
          subtitle: const Text(
            'Sign in so it comes back if you lose or change your phone.',
          ),
          trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          onTap: () => _save(care),
        ),
      if (user == null && !care.isConnected) ...[
        Divider(height: 1, color: scheme.outlineVariant),
        ListTile(
          title: const Text('Restore a saved household'),
          subtitle: const Text('New phone? Sign in to bring it back.'),
          trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          onTap: () =>
              showAccountSheet(context, mode: AccountSheetMode.restore),
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CareSectionHeader('Account'),
        const SizedBox(height: 8),
        SurfaceCard(child: Column(children: rows)),
        const SizedBox(height: 24),
      ],
    );
  }
}
