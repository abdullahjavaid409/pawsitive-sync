import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
          const SoftEnter(child: _LedgerHero()),
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

/// An example page of the shared log, stamped the way a second caregiver
/// would see it. Illustration only: nothing here is stored.
class _LedgerHero extends StatelessWidget {
  const _LedgerHero();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Example log: Sara gave Miso’s insulin at 8:02 AM, '
          'so a second dose is stopped.',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const LedgerSheet(
            children: [
              LedgerLine(
                time: '8:02 AM',
                title: 'Insulin · 2 units',
                detail: 'Miso · Sara',
                mark: LedgerMark.given,
              ),
              LedgerLine(
                time: '8:15 AM',
                title: 'Apoquel · 1 tablet',
                detail: 'Biscuit · not sure if given',
                mark: LedgerMark.unsure,
              ),
              LedgerLine(
                time: '8:00 PM',
                title: 'Insulin · 2 units',
                detail: 'Miso · due tonight',
                mark: LedgerMark.due,
                last: true,
              ),
            ],
          ),
          // Stamped over the first entry only, the one already given.
          Positioned(
            right: 6,
            top: 8,
            child: const GivenStamp(who: 'Sara', time: '8:02 AM'),
          ),
        ],
      ),
    );
  }
}
