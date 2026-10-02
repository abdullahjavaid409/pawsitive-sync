import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/motion/app_motion.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/core/widgets/pet_mark.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_visuals.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Optional details stay editable without slowing down the first step.
class PetDetailsScreen extends StatelessWidget {
  const PetDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = model.petName.trim().isEmpty ? 'them' : model.petName.trim();

    return OnboardingStep(
      onBack: () => context.go(AppRoutes.pet),
      child: OnboardingShell(
        header: OnboardingHeader(
          step: 2,
          onBack: () => context.go(AppRoutes.pet),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnboardingTitle(
              'A little about $name',
              'Make their profile feel like them. You can update these details anytime.',
            ),
            const SizedBox(height: 28),
            Material(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                onTap: () => _choosePhoto(context, model),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          if (model.photoBytes == null)
                            ExcludeSemantics(
                              child: PetMark(
                                species: model.species,
                                size: 80,
                                artScale: 1,
                              ),
                            )
                          else
                            ClipOval(
                              child: Image.memory(
                                model.photoBytes!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.primaryContainer,
                                  width: 3,
                                ),
                              ),
                              child: StrokeIcon(
                                StrokeIconKind.camera,
                                size: 14,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model.photoBytes == null
                                  ? 'Add a photo'
                                  : 'Photo added',
                              style: text.titleLarge?.copyWith(
                                color: context.paws.brandDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              model.photoBytes == null
                                  ? 'A familiar face for everyone who helps.'
                                  : 'Tap to choose a different one.',
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            _AgeStepper(years: model.ageYears),
            const SizedBox(height: 24),
            _WeightField(weight: model.weight),
            const SizedBox(height: 24),
            const OnboardingNote(
              'Don’t know the details? You can add them later.',
            ),
          ],
        ),
        footer: FilledButton(
          onPressed: model.hasValidWeight
              ? () {
                  FocusScope.of(context).unfocus();
                  context.go(AppRoutes.conditions);
                }
              : null,
          child: const Text('Continue'),
        ),
      ),
    );
  }
}

Future<void> _choosePhoto(BuildContext context, OnboardingViewModel model) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AppMotion.sheet(context),
    constraints: AdaptiveLayout.sheetConstraints,
    backgroundColor: scheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pet photo',
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'People use this to know which pet they are looking at.',
                style: Theme.of(sheetContext).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    _pick(context, sheetContext, ImageSource.camera),
                child: const Text('Take a photo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    _pick(context, sheetContext, ImageSource.gallery),
                child: const Text('Choose from photos'),
              ),
              if (model.photoBytes != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    AppLog.event('pet.photo_removed');
                    model.setPhoto(null);
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Remove photo'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _pick(
  BuildContext context,
  BuildContext sheetContext,
  ImageSource source,
) async {
  Navigator.of(sheetContext).pop();
  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (file == null) {
      AppLog.event('pet.photo_cancelled', {'source': source.name});
      return;
    }
    if (!context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    context.read<OnboardingViewModel>().setPhoto(bytes);
    AppLog.event('pet.photo_set', {
      'source': source.name,
      'bytes': bytes.length,
    });
  } on PlatformException {
    AppLog.event('pet.photo_failed', {'source': source.name});
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the camera or photos. Try the other one.',
        ),
      ),
    );
  }
}

class _AgeStepper extends StatelessWidget {
  const _AgeStepper({required this.years});

  final int years;

  @override
  Widget build(BuildContext context) {
    final model = context.read<OnboardingViewModel>();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Age (years)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                IconButton(
                  tooltip: years <= 0 ? 'Youngest age is 0' : 'Decrease age',
                  onPressed: years <= 0 ? null : () => model.changeAge(-1),
                  icon: const Text('−', style: TextStyle(fontSize: 20)),
                ),
                Expanded(
                  child: Text(
                    years == 0
                        ? 'Under 1 year'
                        : '$years ${years == 1 ? 'year' : 'years'}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: years >= 30 ? 'Oldest age is 30' : 'Increase age',
                  onPressed: years >= 30 ? null : () => model.changeAge(1),
                  icon: const Text('+', style: TextStyle(fontSize: 20)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeightField extends StatelessWidget {
  const _WeightField({required this.weight});

  final String weight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weight (optional)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          onChanged: context.read<OnboardingViewModel>().setWeight,
          decoration: InputDecoration(
            hintText: 'e.g. 4.6',
            errorText: context.watch<OnboardingViewModel>().hasValidWeight
                ? null
                : 'Enter a weight like 4.6, or leave blank.',
            suffixText: 'kg',
            suffixStyle: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
