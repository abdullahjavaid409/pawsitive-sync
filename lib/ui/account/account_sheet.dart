import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/account_service.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart' show AccountConflict;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// What the sheet does once someone is signed in.
enum AccountSheetMode {
  /// Pro: tie the sign-in to this household so it can come back later.
  save,

  /// New phone: bring a saved household back.
  restore,
}

/// Opens the sign-in sheet. Resolves to true when the household was saved
/// or restored, false when the person chose "Not now" or closed it.
///
/// References: Vocabulary "Keep your data safe", Slopes sign-up sheet,
/// Crouton (Mobbin, 2026-10-14).
Future<bool> showAccountSheet(
  BuildContext context, {
  required AccountSheetMode mode,
}) async {
  AppLog.event('account.sheet_opened', {'mode': mode.name});
  final done = await showModalBottomSheet<bool>(
    context: context,
    routeSettings: RouteSettings(name: 'account_${mode.name}'),
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: AdaptiveLayout.sheetConstraints,
    // v14: the sign-in sheet is a cream card.
    backgroundColor: context.paws.surfaces.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PawsRadii.sheetValue),
      ),
    ),
    builder: (_) => _AccountSheet(mode: mode),
  );
  return done ?? false;
}

enum _Step { choose, email, done }

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.mode});

  final AccountSheetMode mode;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  _Step _step = _Step.choose;
  bool _creating = false;
  bool _showPassword = false;

  /// Which button is working, so only that one shows a spinner and the
  /// rest are disabled (no second sign-in sheet on a double tap).
  String? _busy;
  String? _error;
  String? _notice;
  String? _savedEmail;

  bool get _isBusy => _busy != null;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _run(String key, Future<AccountResult> Function() signIn) async {
    if (_isBusy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _busy = key;
      _error = null;
      _notice = null;
    });
    final result = await signIn();
    if (!mounted) return;
    switch (result) {
      case AccountCancelled():
        setState(() => _busy = null);
      case AccountFailed(:final message):
        setState(() {
          _busy = null;
          _error = message;
        });
      case AccountSignedIn(:final idToken, :final email):
        await _useSignIn(idToken, email);
    }
  }

  Future<void> _useSignIn(String idToken, String? email) async {
    final care = context.read<CareRepository>();
    String? error;
    if (widget.mode == AccountSheetMode.save) {
      var result = await care.saveSignIn(idToken);
      if (result case SignInSaveConflict(:final conflict)) {
        if (!mounted) return;
        final replace = await _confirmReplaceSaved(conflict);
        AppLog.event('account.link_conflict_choice', {
          'choice': replace ? 'replace' : 'keep',
        });
        if (!replace) {
          // Nothing changed on the server; don't stay signed in to an
          // account that saves a different household on this phone.
          await AccountService.signOut();
          if (!mounted) return;
          setState(() {
            _busy = null;
            _error =
                'Nothing changed. That household stays saved to this '
                'account. To use it here, choose “Restore a saved '
                'household” in Settings.';
          });
          return;
        }
        result = await care.saveSignIn(idToken, replace: true);
      }
      error = switch (result) {
        SignInSaved() => null,
        SignInSaveFailed(:final message) => message,
        // Only if the server reports another conflict right after replace.
        SignInSaveConflict() =>
          'That account changed while saving. Try again in a moment.',
      };
    } else {
      // Restoring replaces whatever this phone holds; ask first if that's
      // anything at all.
      if (care.pets.isNotEmpty && !await _confirmReplace(care)) {
        await AccountService.signOut();
        if (mounted) setState(() => _busy = null);
        return;
      }
      error = await care.recoverWithSignIn(idToken);
    }
    if (!mounted) return;
    if (error != null) {
      // The household didn't save or come back, so don't stay signed in to
      // an account that isn't tied to anything.
      await AccountService.signOut();
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = error;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = null;
      _savedEmail = email;
      _step = _Step.done;
    });
  }

  /// The sign-in already saves another household. Saving here would stop
  /// that one coming back with this account, so it's the person's choice,
  /// with Cancel (keep it) as the safe default (HIG Alerts).
  Future<bool> _confirmReplaceSaved(AccountConflict conflict) async {
    final answer = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'account_in_use'),
      builder: (dialog) => AlertDialog(
        title: const Text('This account already saves a household'),
        content: Text(
          '${conflict.summary}.\n\nSave this phone instead and that '
          'household won’t come back with this account any more. Nothing '
          'is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Save this phone'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<bool> _confirmReplace(CareRepository care) async {
    // Says exactly what goes, so nobody loses a log by surprise.
    final pets = care.pets;
    final names = pets.length == 1 ? pets.first.name : '${pets.length} pets';
    final answer = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'restore_replace'),
      builder: (dialog) => AlertDialog(
        title: const Text('Replace what’s on this phone?'),
        content: Text(
          // No dose count: memory holds only recent history.
          'Your saved household replaces $names and '
          '${pets.length == 1 ? 'its' : 'their'} dose log on this phone. '
          'They can’t be brought back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    final replace = answer ?? false;
    AppLog.event('account.restore_replace_choice', {
      'choice': replace ? 'replace' : 'keep',
      'pets': pets.length,
    });
    return replace;
  }

  Future<void> _submitEmail() async {
    FocusScope.of(context).unfocus();
    await _run(
      'email',
      () => _creating
          ? AccountService.createWithEmail(
              email: _email.text,
              password: _password.text,
            )
          : AccountService.signInWithEmail(
              email: _email.text,
              password: _password.text,
            ),
    );
  }

  Future<void> _resetPassword() async {
    if (_isBusy) return;
    setState(() {
      _busy = 'reset';
      _error = null;
      _notice = null;
    });
    final result = await AccountService.sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (result case AccountFailed(:final message)) {
        _error = message;
      } else {
        _notice = 'If that email has an account, a reset link is on its way.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      // Never close mid sign-in: the result would land on nothing.
      canPop: !_isBusy,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottom),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: switch (_step) {
              _Step.choose => _choose(context),
              _Step.email => _emailForm(context),
              _Step.done => _done(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _choose(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final save = widget.mode == AccountSheetMode.save;
    final petName = context.select<CareRepository, String?>(
      (care) => care.pets.isEmpty ? null : care.pets.first.name,
    );
    final who = petName == null ? 'Your pets’' : '$petName’s';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(PawsRadii.cardValue),
          child: AspectRatio(
            aspectRatio: 3 / 2,
            child: Image.asset(
              'assets/photos/caregivers-together.jpg',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          save ? 'Keep your household safe' : 'Welcome back',
          style: text.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          save
              ? 'Sign in so $who log comes back if you lose or change your '
                    'phone. Free stays on this phone only.'
              : 'Sign in with the account you saved your household to.',
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (AccountService.offersApple) ...[
          _ProviderButton(
            label: 'Continue with Apple',
            icon: Icons.apple,
            dark: true,
            busy: _busy == 'apple',
            enabled: !_isBusy,
            onPressed: () => _run('apple', AccountService.signInWithApple),
          ),
          const SizedBox(height: 10),
        ],
        _ProviderButton(
          label: 'Continue with Google',
          logo: SvgPicture.asset(
            'assets/icons/google-g.svg',
            width: 18,
            height: 18,
          ),
          busy: _busy == 'google',
          enabled: !_isBusy,
          onPressed: () => _run('google', AccountService.signInWithGoogle),
        ),
        const SizedBox(height: 10),
        _ProviderButton(
          label: 'Continue with email',
          icon: Icons.mail_outline_rounded,
          enabled: !_isBusy,
          onPressed: () => setState(() {
            _step = _Step.email;
            _error = null;
          }),
        ),
        _ErrorLine(_error),
        const SizedBox(height: 6),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          onPressed: _isBusy
              ? null
              : () {
                  AppLog.event('account.sheet_skipped', {
                    'mode': widget.mode.name,
                  });
                  Navigator.of(context).pop(false);
                },
          child: const Text('Not now'),
        ),
        const _LegalLine(),
      ],
    );
  }

  Widget _emailForm(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: _isBusy
                    ? null
                    : () => setState(() {
                        _step = _Step.choose;
                        _error = null;
                        _notice = null;
                      }),
                icon: const StrokeIcon(StrokeIconKind.chevronLeft, size: 22),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _creating ? 'Create your account' : 'Sign in with email',
                  style: text.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            contextMenuBuilder: appContextMenuBuilder,
            controller: _email,
            enabled: !_isBusy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          TextField(
            contextMenuBuilder: appContextMenuBuilder,
            controller: _password,
            focusNode: _passwordFocus,
            enabled: !_isBusy,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: [
              _creating ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _creating ? 'At least 8 characters.' : null,
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            onSubmitted: (_) => _submitEmail(),
          ),
          if (!_creating)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _isBusy ? null : _resetPassword,
                child: const Text('Forgot password?'),
              ),
            ),
          _ErrorLine(_error),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _notice!,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isBusy ? null : _submitEmail,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _busy == 'email'
                ? const _Spinner(onDark: true)
                : Text(_creating ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _isBusy
                ? null
                : () => setState(() {
                    _creating = !_creating;
                    _error = null;
                    _notice = null;
                  }),
            child: Text(
              _creating
                  ? 'Already have an account? Sign in'
                  : 'New here? Create an account',
            ),
          ),
          const _LegalLine(),
        ],
      ),
    );
  }

  Widget _done(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final save = widget.mode == AccountSheetMode.save;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: context.paws.states.success,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 32,
              color: context.paws.states.onSuccess,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          switch ((save, _savedEmail)) {
            (true, final email?) => 'Saved to $email',
            (true, null) => 'Your household is saved',
            (false, _) => 'Your household is back',
          },
          textAlign: TextAlign.center,
          style: text.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          save
              ? 'Your household comes back when you sign in on a new phone.'
              : 'Everything is up to date on this phone.',
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.onPressed,
    required this.enabled,
    this.icon,
    this.logo,
    this.busy = false,
    this.dark = false,
  });

  final String label;

  /// A glyph tinted to the button, or [logo] for a brand mark that keeps
  /// its own colours (Google's G must not be recoloured).
  final IconData? icon;
  final Widget? logo;
  final VoidCallback onPressed;
  final bool enabled;
  final bool busy;

  /// Apple's button is black (HIG: Sign in with Apple).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightDark = Theme.of(context).brightness == Brightness.dark;
    // In dark mode Apple's style flips to a white button.
    final fill = dark ? (brightDark ? Colors.white : Colors.black) : null;
    final ink = dark
        ? (brightDark ? Colors.black : Colors.white)
        : scheme.onSurface;
    final child = busy
        ? _Spinner(onDark: dark && !brightDark)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              logo ?? Icon(icon, size: 22, color: ink),
              const SizedBox(width: 10),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final style = (dark ? FilledButton.styleFrom : OutlinedButton.styleFrom)(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: fill,
      foregroundColor: ink,
      shape: const StadiumBorder(),
    );
    return dark
        ? FilledButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          )
        : OutlinedButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2.4,
      color: onDark ? Colors.white : Theme.of(context).colorScheme.primary,
      semanticsLabel: 'Signing in',
    ),
  );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

class _LegalLine extends StatelessWidget {
  const _LegalLine();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Future<void> open(Uri url) async {
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } on Object catch (error, stack) {
        AppLog.error('account.legal_open_failed', error, stack);
      }
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By continuing you agree to the ', style: style),
        GestureDetector(
          onTap: () => open(Uri.parse(AppLinks.terms)),
          child: Text(
            'Terms',
            style: style?.copyWith(decoration: TextDecoration.underline),
          ),
        ),
        Text(' and ', style: style),
        GestureDetector(
          onTap: () => open(Uri.parse(AppLinks.privacy)),
          child: Text(
            'Privacy Policy',
            style: style?.copyWith(decoration: TextDecoration.underline),
          ),
        ),
        Text('.', style: style),
      ],
    );
  }
}
