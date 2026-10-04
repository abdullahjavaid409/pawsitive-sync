import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Joins someone's household with the 6-letter code they shared.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late final _code = TextEditingController(
    text: (widget.initialCode ?? '').toUpperCase(),
  );
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_clear);
    _name.addListener(_clear);
  }

  void _clear() {
    if (_error != null) setState(() => _error = null);
    setState(() {});
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _ready =>
      _code.text.replaceAll(RegExp('[^A-Za-z0-9]'), '').length >= 6 &&
      _name.text.trim().isNotEmpty;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final match = RegExp(r'[A-Za-z0-9]{6}').firstMatch(data?.text ?? '');
    if (match == null) {
      AppLog.event('join.paste_failed');
      setState(() => _error = 'No invite code found on the clipboard.');
      return;
    }
    AppLog.event('join.paste_success');
    _code.text = match.group(0)!.toUpperCase();
  }

  Future<void> _join() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final care = context.read<CareRepository>();
    final onboarding = context.read<OnboardingViewModel>();
    final error = await care.join(code: _code.text, name: _name.text);
    if (!mounted) return;
    // household.joined / join_* are logged by the repository.
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    if (!onboarding.isComplete) await onboarding.finish(reminders: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          care.primaryPet == null
              ? 'You joined the household.'
              : 'You joined. You can now see ${care.primaryPet!.name}’s doses.',
        ),
      ),
    );
    context.go(AppRoutes.today);
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareRepository>();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.paws;
    final text = Theme.of(context).textTheme;
    final replacesLocal = care.pets.isNotEmpty && !care.isConnected;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.welcome),
                    icon: StrokeIcon(
                      StrokeIconKind.chevronLeft,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text('Join a household', style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-letter code from the person who invited you. You will see the same pets and doses they do.',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Invite code', style: text.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _code,
                    autofocus: widget.initialCode == null,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: text.headlineMedium?.copyWith(letterSpacing: 6),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(6),
                      TextInputFormatter.withFunction(
                        (old, next) =>
                            next.copyWith(text: next.text.toUpperCase()),
                      ),
                    ],
                    decoration: InputDecoration(
                      hintText: 'ABC123',
                      suffixIcon: IconButton(
                        tooltip: 'Paste code',
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Your name', style: text.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'So everyone sees who gave each dose.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _name,
                    autofocus: widget.initialCode != null,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    maxLength: 40,
                    onSubmitted: (_) {
                      if (_ready) _join();
                    },
                    decoration: const InputDecoration(
                      hintText: 'e.g. Sara',
                      counterText: '',
                    ),
                  ),
                  if (replacesLocal) ...[
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.warningBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.warningBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Joining swaps the pet set up on this phone for the shared household.',
                          style: text.bodyMedium?.copyWith(
                            color: tokens.warning,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    onPressed: _busy || !_ready ? null : _join,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Join household'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
