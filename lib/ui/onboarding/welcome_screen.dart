import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';

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
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: context.paws.brandSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: StrokeIcon(
                  StrokeIconKind.paw,
                  size: 22,
                  color: context.paws.brandDark,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Pawsitive',
                    style: text.headlineSmall?.copyWith(
                      fontSize: 22,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 16 : 24),
          Center(
            child: SoftEnter(
              child: OnboardingArtwork('welcome', height: compact ? 200 : 246),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'A little less worry.\nA lot more care.',
            style: text.displaySmall?.copyWith(
              fontSize: 34,
              height: 1.12,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Their medicines, reminders, and the people who love them. All in sync.',
            style: text.bodyLarge?.copyWith(
              fontSize: 16,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: context.paws.brandSoft,
                    shape: BoxShape.circle,
                  ),
                  child: StrokeIcon(
                    StrokeIconKind.check,
                    size: 20,
                    color: context.paws.brandDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('See who already gave it.', style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'One shared list. Everyone up to date.',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
