import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:provider/provider.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/account/account_sheet.dart';
import 'package:pawsitive_sync/data/firebase_setup.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    AppLog.event('welcome');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final height = MediaQuery.sizeOf(context).height;

    // v14 welcome: one big photo with the name on it, then the promise.
    return OnboardingShell(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoftEnter(
            // Most of the screen on a tall phone, still leaving room for the
            // pitch and buttons on a small one or at large text.
            child: _PhotoHero(height: (height * 0.44).clamp(220.0, 460.0)),
          ),
          const SizedBox(height: 28),
          // On the photo's edge, like the button below it.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text.rich(
                  const TextSpan(
                    children: [
                      TextSpan(text: 'Every dose, '),
                      TextSpan(
                        text: 'accounted for.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                  style: text.displaySmall?.copyWith(
                    fontSize: 46,
                    height: 1,
                    letterSpacing: -0.7,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'One shared log for your pet’s medicines, so everyone at '
                'home knows what’s been given.',
                style: text.bodyLarge?.copyWith(
                  fontSize: 16,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // The first question a new user has, answered plainly. True
              // by design: nothing leaves the phone until a household is
              // shared.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: StrokeIcon(
                      StrokeIconKind.lock,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Your pet’s log stays on this phone until you invite someone.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () {
              AppLog.event('welcome.continued');
              context.go(AppRoutes.pet);
            },
            child: const Text('Get started'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () {
              AppLog.event('welcome.invited');
              context.push(AppRoutes.join);
            },
            style: TextButton.styleFrom(foregroundColor: scheme.primary),
            child: const Text('I have an invite code'),
          ),
          // A new phone: bring a saved household back instead of starting over.
          TextButton(
            onPressed: () async {
              AppLog.event('welcome.restore');
              if (!await FirebaseSetup.initialize() || !context.mounted) return;
              final restored = await showAccountSheet(
                context,
                mode: AccountSheetMode.restore,
              );
              if (restored && context.mounted) {
                await context.read<OnboardingViewModel>().finish(
                  reminders: false,
                );
                if (context.mounted) context.go(AppRoutes.today);
              }
            },
            child: const Text('Restore with your account'),
          ),
        ],
      ),
    );
  }
}

/// A dose being given at home, with the app's name on the photo (v14).
class _PhotoHero extends StatelessWidget {
  const _PhotoHero({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A tabby cat being given medicine at home.',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PawsRadii.cardValue),
            boxShadow: PawsElevation.card(Theme.of(context).brightness),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PawsRadii.cardValue),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/photos/welcome-cat.jpg',
                  fit: BoxFit.cover,
                  cacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                ),
                // Bottom half fades to dark so the name always reads.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 160,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x8C14120E), Color(0x0014120E)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 18,
                  child: Text(
                    'Gave It',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontSize: 22, color: Colors.white),
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
