import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:provider/provider.dart';

/// v14 ReadyStep: the pet's photo or initial with a green check, "*Miso* is
/// all set", and the medicine that was added. "Go to Today" goes through
/// the plan choice, which saves everything.
class ReadyScreen extends StatelessWidget {
  const ReadyScreen({super.key});

  /// "8:00 AM and 8:00 PM", "every 2 days at 8:00 AM".
  static String scheduleText(OnboardingViewModel model) {
    final times = [
      for (final part in DayPart.values)
        if (model.medParts.contains(part))
          ClockFormat.label(part.defaultMinute),
    ];
    final at = times.length <= 1
        ? times.join()
        : '${times.sublist(0, times.length - 1).join(', ')} and ${times.last}';
    return switch (model.medEveryDays) {
      2 => 'Every 2 days · $at',
      7 => 'Once a week · $at',
      _ => at,
    };
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final isPro = context.watch<CareRepository>().isPro;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final paws = context.paws;
    final name = model.petName.trim();
    final photo = model.photoBytes;

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.notifications),
      child: OnboardingShell(
        body: Column(
          children: [
            const SizedBox(height: 24),
            SizedBox.square(
              dimension: 100,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: paws.surfaces.card,
                      shape: BoxShape.circle,
                      boxShadow: PawsElevation.card(
                        Theme.of(context).brightness,
                      ),
                    ),
                    child: photo != null
                        ? Image.memory(
                            photo,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            cacheWidth:
                                (100 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          )
                        : ExcludeSemantics(
                            child: Text(
                              name.isEmpty ? '' : name.characters.first,
                              // v14: the initial in the serif, display size.
                              style: text.displaySmall,
                            ),
                          ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 4,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: paws.states.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: paws.surfaces.card, width: 2),
                      ),
                      child: StrokeIcon(
                        StrokeIconKind.check,
                        size: 13,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: name,
                      style: const TextStyle(
                        fontFamily: PawsTypeStyle.displayFamily,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const TextSpan(text: ' is all set'),
                  ],
                ),
                textAlign: TextAlign.center,
                style: text.headlineMedium,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              // Only Pro shares the log with the household.
              isPro
                  ? 'Log each dose with one tap. Everyone at home will see '
                        'it right away.'
                  : 'Log each dose with one tap. It’s saved on this phone, '
                        'even with no signal.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(
                fontSize: 16,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (model.hasMedicine) ...[
              const SizedBox(height: 28),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.medName, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (model.medAmountText.isNotEmpty)
                            model.medAmountText,
                          scheduleText(model),
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        footer: OnboardingCta(
          label: 'Go to Today',
          onPressed: () {
            AppLog.event('onboarding.step', {
              'step': 'ready',
              'medicine': model.hasMedicine,
            });
            // The plan choice finishes setup (applyOnboarding) either way.
            context.go(AppRoutes.paywall);
          },
        ),
      ),
    );
  }
}
