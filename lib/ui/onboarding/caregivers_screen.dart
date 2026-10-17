import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:provider/provider.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

/// v14 HouseholdStep: who else looks after the pet, by email. Nothing is
/// sent here — the household only goes online after setup — so the
/// addresses wait in the model and the invite flow opens with them once
/// setup is done. "Share an invite link instead" skips the emails.
class CaregiversScreen extends StatefulWidget {
  const CaregiversScreen({super.key});

  @override
  State<CaregiversScreen> createState() => _CaregiversScreenState();
}

class _CaregiversScreenState extends State<CaregiversScreen> {
  final _email = TextEditingController();
  String? _error;

  /// The most people setup collects; more can be invited later.
  static const _max = 5;
  static final _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _add(OnboardingViewModel model) {
    final value = _email.text.trim();
    if (value.isEmpty) return;
    if (!_pattern.hasMatch(value)) {
      setState(() => _error = 'Enter a full email, like sara@example.com');
      return;
    }
    if (model.invites.length >= _max) {
      setState(() => _error = 'Add more people after setup');
      return;
    }
    model.addInvite(value);
    _email.clear();
    setState(() => _error = null);
  }

  void _next(OnboardingViewModel model, {required String how}) {
    // A typed address that wasn't added yet still counts.
    if (_email.text.trim().isNotEmpty) _add(model);
    if (_error != null) return;
    model.householdDone = true;
    model.inviteAfterSetup = how == 'link' || model.invites.isNotEmpty;
    AppLog.event('onboarding.step', {
      'step': 'household',
      'how': how,
      'invites': model.invites.length,
    });
    FocusScope.of(context).unfocus();
    context.go(AppRoutes.notifications);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = model.petName.trim().isEmpty
        ? 'your pet'
        : model.petName.trim();
    final count = model.invites.length;

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.firstMedicine),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 3,
          onBack: () => context.go(AppRoutes.firstMedicine),
          onSkip: () {
            model.invites.clear();
            _email.clear();
            _error = null;
            _next(model, how: 'skip');
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTitle(
              'Who else looks after $name?',
              'Everyone sees the same log, so no dose gets doubled or missed.',
            ),
            const SizedBox(height: 28),
            const FieldLabel('Email'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    contextMenuBuilder: appContextMenuBuilder,
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(model),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: 'alex@example.com',
                      errorText: _error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 52,
                  child: TextButton(
                    onPressed: () => _add(model),
                    style: TextButton.styleFrom(
                      backgroundColor: context.paws.surfaces.subtle,
                      foregroundColor: scheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
            if (count > 0) ...[
              const SizedBox(height: 12),
              SurfaceCard(
                child: Column(
                  children: [
                    for (final (i, email) in model.invites.indexed) ...[
                      if (i > 0)
                        Divider(height: 1, color: context.paws.hairline),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(email, style: text.bodyLarge)),
                            IconButton(
                              tooltip: 'Remove $email',
                              onPressed: () => model.removeInvite(email),
                              icon: StrokeIcon(
                                StrokeIconKind.close,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'You’ll send ${count == 1 ? 'it' : 'them'} from Mail '
                  'once setup is done. Inviting is part of Pro.',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  model.invites.clear();
                  _email.clear();
                  _error = null;
                  _next(model, how: 'link');
                },
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                icon: StrokeIcon(
                  StrokeIconKind.link,
                  size: 16,
                  color: scheme.primary,
                ),
                label: const Text('Share an invite link instead'),
              ),
            ),
          ],
        ),
        footer: OnboardingCta(
          // Nothing is sent from this step (Mail, after setup, with Pro).
          label: 'Continue',
          onPressed: () => _next(model, how: count == 0 ? 'none' : 'email'),
        ),
      ),
    );
  }
}
