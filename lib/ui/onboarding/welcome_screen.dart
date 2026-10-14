import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/ledger.dart';

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
    final compact = MediaQuery.sizeOf(context).height < 740;

    return OnboardingShell(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppIconMark(size: 40),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Gave It',
                    style: text.headlineSmall?.copyWith(fontSize: 22),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 16 : 28),
          SoftEnter(child: _PhotoHero(compact: compact)),
          SizedBox(height: compact ? 20 : 28),
          Text('Did anyone give\nthe dose?', style: text.displaySmall),
          const SizedBox(height: 12),
          Text(
            'One shared log for everyone who cares for your pet. '
            'See who gave each dose, and get stopped before a second one.',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          // The first question a new user has, answered plainly. True by
          // design: nothing leaves the phone until a household is shared.
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              StrokeIcon(
                StrokeIconKind.lock,
                size: 14,
                color: scheme.onSurfaceVariant,
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
            child: const Text('I have an invite code'),
          ),
        ],
      ),
    );
  }
}

/// A real home at the moment the app is for, stamped the way a second
/// caregiver would see it: someone already gave the dose.
class _PhotoHero extends StatelessWidget {
  const _PhotoHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'A cat asleep at home while two people check its medicine. '
          'Stamped: already given by Sara at 8:02 AM.',
      excludeSemantics: true,
      child: AspectRatio(
        // Shorter on small phones so the pitch and buttons still fit.
        aspectRatio: compact ? 16 / 9 : 3 / 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PawsRadii.cardValue + 4),
            boxShadow: PawsElevation.hero(Theme.of(context).brightness),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PawsRadii.cardValue + 4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/photos/welcome-household.jpg',
                  fit: BoxFit.cover,
                  cacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                ),
                const Positioned(
                  left: 14,
                  bottom: 14,
                  child: GivenStamp(who: 'Sara', time: '8:02 AM'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
